-- Migration 078: Backfill final_km for historic sessions, MAX-based
--
-- Original 078 (which used `estimated_km` first) was based on a wrong
-- assumption: that the device-filtered total is always the truthful
-- number. A real-world session reported by the user (27e851f7…) had
-- estimated_km = 9.70 and rollup = 12.07 km. The rep verified the
-- trip independently on Google Maps and confirmed ~12 km. So the
-- filter pass UNDER-counted by ~20%, and the rollup raw haversine
-- was actually more accurate for that trip.
--
-- The fix here: lock final_km to the MAX of all defensible signals.
-- Never under-count what the rep actually drove.
--
-- Signals considered (highest priority first when they're available):
--
--   final_km                — already verified by Roads API or earlier
--                             backfill. Keep as-is. NEVER overwrite a
--                             higher one with a lower one in any
--                             subsequent migration.
--   total_km                — what endSession() wrote (device's
--                             running tally, what the rep saw on
--                             screen).
--   estimated_km            — same source as total_km in most cases,
--                             but the NEW mobile code stores it
--                             separately as a frozen-at-end snapshot.
--   sum(distance_delta_m)   — sum of per-point accepted deltas
--      where counts_for_distance.
--                             Tightest filter; usually matches
--                             estimated_km.
--   session_rollups.distance_km — raw haversine across all GPS
--                             points. OVER-counts on stationary
--                             jitter but on a real-world drive can
--                             be the closest to truth. Apply a small
--                             5% jitter discount when using this
--                             source.
--
-- The fallback chain below picks the MAX of the first four signals,
-- then if that's smaller than `rollup * 0.95`, bumps up to that. The
-- 5% discount on the rollup is the "stationary jitter" safety margin.
--
-- Idempotent: re-running does NOT clobber a final_km that's already
-- set (we filter WHERE final_km IS NULL).

UPDATE shift_sessions s
SET
  final_km = GREATEST(
    COALESCE(NULLIF(s.estimated_km, 0), 0),
    COALESCE(NULLIF(s.total_km, 0), 0),
    COALESCE((
      SELECT NULLIF(SUM(lp.distance_delta_m) / 1000.0, 0)
      FROM location_points lp
      WHERE lp.session_id = s.id
        AND lp.counts_for_distance = TRUE
        AND lp.distance_delta_m > 0
    ), 0),
    COALESCE((
      SELECT NULLIF(sr.distance_km, 0) * 0.95
      FROM session_rollups sr
      WHERE sr.session_id = s.id
    ), 0)
  ),
  estimated_km = COALESCE(
    s.estimated_km,
    NULLIF(s.total_km, 0),
    (
      SELECT NULLIF(SUM(lp.distance_delta_m) / 1000.0, 0)
      FROM location_points lp
      WHERE lp.session_id = s.id
        AND lp.counts_for_distance = TRUE
        AND lp.distance_delta_m > 0
    )
  ),
  distance_source = COALESCE(s.distance_source, 'device_gps_filtered'),
  confidence = COALESCE(s.confidence, CASE
    WHEN s.total_km IS NULL OR s.total_km = 0 THEN 'unverified_no_gps'
    ELSE 'medium'
  END),
  finalized_at = COALESCE(s.finalized_at, s.end_time, s.updated_at)
WHERE s.status = 'completed'
  AND (s.final_km IS NULL OR s.final_km = 0);

-- Special case: sessions where Roads API ran and wrote a final_km
-- that is LOWER than the rollup × 0.95 — Roads API under-counted a
-- curvy trip. Restore to the higher device/rollup value. We DO want
-- to write here even though final_km is non-null.
UPDATE shift_sessions s
SET
  final_km = sub.best_km,
  distance_source = 'device_gps_filtered',
  reason_codes = COALESCE(s.reason_codes, '[]'::jsonb)
                 || '["ROADS_API_LOWER_THAN_DEVICE_RESTORED"]'::jsonb
FROM (
  SELECT
    s.id AS session_id,
    GREATEST(
      COALESCE(NULLIF(s.estimated_km, 0), 0),
      COALESCE(NULLIF(s.total_km, 0), 0),
      COALESCE((
        SELECT NULLIF(SUM(lp.distance_delta_m) / 1000.0, 0)
        FROM location_points lp
        WHERE lp.session_id = s.id
          AND lp.counts_for_distance = TRUE
          AND lp.distance_delta_m > 0
      ), 0),
      COALESCE((
        SELECT NULLIF(sr.distance_km, 0) * 0.95
        FROM session_rollups sr
        WHERE sr.session_id = s.id
      ), 0)
    ) AS best_km
  FROM shift_sessions s
  WHERE s.status = 'completed'
    AND s.distance_source = 'roads_api_verified'
) AS sub
WHERE s.id = sub.session_id
  AND s.distance_source = 'roads_api_verified'
  AND s.final_km < sub.best_km
  AND sub.best_km > 0;

-- Visibility
DO $$
DECLARE
  v_locked INTEGER;
  v_restored INTEGER;
  v_null INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_locked
  FROM shift_sessions
  WHERE status = 'completed' AND final_km IS NOT NULL AND final_km > 0;
  SELECT COUNT(*) INTO v_restored
  FROM shift_sessions
  WHERE status = 'completed'
    AND reason_codes::jsonb @> '["ROADS_API_LOWER_THAN_DEVICE_RESTORED"]'::jsonb;
  SELECT COUNT(*) INTO v_null
  FROM shift_sessions
  WHERE status = 'completed' AND (final_km IS NULL OR final_km = 0);
  RAISE NOTICE
    'final_km backfill: locked=%, restored_from_roads_api=%, still_null_or_zero=%',
    v_locked, v_restored, v_null;
END $$;
