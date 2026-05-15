-- Migration 072: Lock the billed distance number (Stage 1 of distance-tracking rewrite)
--
-- PROBLEM: We had two production incidents caused by the billed distance being
-- recomputed silently between what the user saw on screen and what the expense
-- dialog filed:
--
--   Incident A: Device showed 11.92 km; expense dialog read session_rollups
--               (raw haversine, ignored counts_for_distance) and filed 12.25 km.
--   Incident B: Offline sessions ended up with shift_sessions.total_km = 0 in
--               the admin panel because the pending-stop sync failed silently
--               and the rollup trigger summed up to ~0 for the few synced points.
--
-- FIX: Introduce explicit columns for the *estimated* device-calculated distance
-- (locked at session end) and the *final* billed distance (defaults to estimated,
-- may be overwritten by Roads API verification or admin correction). The expense
-- flow now reads ONLY final_km — no rollup fallback, no recalculation.
--
-- The update_session_rollup trigger continues to maintain session_rollups for
-- audit purposes but is forbidden from touching final_km or estimated_km.
--
-- See docs/DISTANCE_TRACKING_METHODOLOGY.md for the full architecture.

-- ============================================================================
-- 1. New columns on shift_sessions
-- ============================================================================

ALTER TABLE shift_sessions ADD COLUMN IF NOT EXISTS estimated_km REAL;
ALTER TABLE shift_sessions ADD COLUMN IF NOT EXISTS final_km REAL;
ALTER TABLE shift_sessions ADD COLUMN IF NOT EXISTS distance_source TEXT;
ALTER TABLE shift_sessions ADD COLUMN IF NOT EXISTS confidence TEXT;
ALTER TABLE shift_sessions ADD COLUMN IF NOT EXISTS reason_codes JSONB;
ALTER TABLE shift_sessions ADD COLUMN IF NOT EXISTS finalized_at TIMESTAMPTZ;

-- Discriminated enum-style CHECKs (nullable: an active session has no values yet)
ALTER TABLE shift_sessions DROP CONSTRAINT IF EXISTS shift_sessions_distance_source_check;
ALTER TABLE shift_sessions ADD CONSTRAINT shift_sessions_distance_source_check
  CHECK (distance_source IS NULL OR distance_source IN (
    'device_gps_filtered',
    'roads_api_verified',
    'admin_corrected'
  ));

ALTER TABLE shift_sessions DROP CONSTRAINT IF EXISTS shift_sessions_confidence_check;
ALTER TABLE shift_sessions ADD CONSTRAINT shift_sessions_confidence_check
  CHECK (confidence IS NULL OR confidence IN (
    'high',
    'medium',
    'low',
    'unverified_no_gps'
  ));

-- ============================================================================
-- 2. Backfill existing completed sessions
-- ============================================================================
-- For sessions that already completed before this migration, take total_km as
-- the authoritative estimate. We can't recover confidence retroactively, so we
-- mark them medium and leave reason_codes empty.

UPDATE shift_sessions
SET
  estimated_km    = COALESCE(estimated_km, total_km),
  final_km        = COALESCE(final_km, total_km),
  distance_source = COALESCE(distance_source, 'device_gps_filtered'),
  confidence      = COALESCE(confidence, CASE
    WHEN total_km IS NULL OR total_km = 0 THEN 'unverified_no_gps'
    ELSE 'medium'
  END),
  finalized_at    = COALESCE(finalized_at, end_time, updated_at)
WHERE end_time IS NOT NULL;

-- ============================================================================
-- 3. Trigger guard — block final_km / estimated_km mutations from triggers
-- ============================================================================
-- The update_session_rollup trigger is allowed to update session_rollups and
-- daily_rollups, but it must NEVER touch final_km or estimated_km. Those are
-- written exclusively by the application (endSession + Roads API finalization).
--
-- We can't easily express "trigger may not modify column" in PG without
-- statement-level distinction, so we rewrite the trigger function to use a
-- session_rollups-only update path. final_km/estimated_km are simply not in
-- the UPDATE SET list — same effect, enforced by code.
--
-- Note: we deliberately keep total_km being updated by the trigger for now to
-- preserve admin views still reading total_km until we migrate all readers.
-- After full reader migration, a follow-up migration will drop total_km
-- updates from this trigger.

CREATE OR REPLACE FUNCTION update_session_rollup()
RETURNS TRIGGER AS $$
DECLARE
  prev_point RECORD;
  distance_delta REAL := 0;
  session_status TEXT;
BEGIN
  IF NEW.counts_for_distance = true
     AND NEW.distance_delta_m IS NOT NULL
     AND NEW.distance_delta_m > 0 THEN
    distance_delta := NEW.distance_delta_m / 1000.0;
  ELSIF NEW.counts_for_distance IS NULL AND NEW.distance_delta_m IS NULL THEN
    -- legacy points (pre-counts_for_distance): fall back to haversine
    SELECT latitude, longitude INTO prev_point
    FROM location_points
    WHERE session_id = NEW.session_id
      AND recorded_at < NEW.recorded_at
    ORDER BY recorded_at DESC
    LIMIT 1;

    IF FOUND THEN
      distance_delta := (
        6371 * acos(
          LEAST(1.0, GREATEST(-1.0,
            cos(radians(prev_point.latitude)) * cos(radians(NEW.latitude)) *
            cos(radians(NEW.longitude) - radians(prev_point.longitude)) +
            sin(radians(prev_point.latitude)) * sin(radians(NEW.latitude))
          ))
        )
      );
    END IF;
  END IF;
  -- counts_for_distance = false → distance_delta stays 0

  -- session_rollups (audit only — never read for billing)
  INSERT INTO session_rollups (session_id, distance_km, point_count, last_point_time, last_lat, last_lng, updated_at)
  VALUES (NEW.session_id, distance_delta, 1, NEW.recorded_at, NEW.latitude, NEW.longitude, NOW())
  ON CONFLICT (session_id) DO UPDATE SET
    distance_km     = session_rollups.distance_km + EXCLUDED.distance_km,
    point_count     = session_rollups.point_count + 1,
    last_point_time = EXCLUDED.last_point_time,
    last_lat        = EXCLUDED.last_lat,
    last_lng        = EXCLUDED.last_lng,
    updated_at      = NOW();

  -- shift_sessions.total_km — kept for backwards compatibility with admin
  -- readers, but ONLY for non-completed sessions (migration 071 logic).
  -- final_km and estimated_km are NEVER touched here.
  SELECT status INTO session_status
  FROM shift_sessions
  WHERE id = NEW.session_id;

  IF session_status IS NOT DISTINCT FROM 'active'
     OR session_status IS NOT DISTINCT FROM 'paused' THEN
    UPDATE shift_sessions
    SET total_km = COALESCE(total_km, 0) + distance_delta
    WHERE id = NEW.session_id;
  END IF;

  -- daily_rollups (audit)
  INSERT INTO daily_rollups (employee_id, day, distance_km, session_count, point_count, updated_at)
  VALUES (
    NEW.employee_id,
    (NEW.recorded_at AT TIME ZONE 'Asia/Kolkata')::DATE,
    distance_delta,
    1,
    1,
    NOW()
  )
  ON CONFLICT (employee_id, day) DO UPDATE SET
    distance_km = daily_rollups.distance_km + EXCLUDED.distance_km,
    point_count = daily_rollups.point_count + 1,
    updated_at  = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 4. Index for the expense flow's hot read
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_shift_sessions_final_km
  ON shift_sessions (id) INCLUDE (final_km, confidence, distance_source);
