-- Migration 074: trip_finalization_jobs queue + polyline storage (Stage 3)
--
-- After every session is marked 'completed', a row is inserted into
-- trip_finalization_jobs. The Supabase Edge Function ('finalize-trip')
-- picks up pending jobs, waits for all GPS points to finish syncing,
-- calls Google Roads API to snap the trail, computes the final road-
-- matched distance, and updates shift_sessions.final_km.
--
-- ToS compliance: the snapped polyline geometry is stored ONLY for
-- diagnostics and must be purged within 30 calendar days
-- (Google Maps Platform Service Specific Terms). A nightly cron nulls
-- out snapped_polyline + polyline_expires_at for any row past expiry.
-- final_km (a derived number) is kept forever as a business record.
--
-- See docs/DISTANCE_TRACKING_METHODOLOGY.md §3.2 and §3.8.

-- ============================================================================
-- 1. Polyline storage columns on shift_sessions
-- ============================================================================

ALTER TABLE shift_sessions ADD COLUMN IF NOT EXISTS snapped_polyline TEXT;
ALTER TABLE shift_sessions ADD COLUMN IF NOT EXISTS polyline_expires_at TIMESTAMPTZ;

-- ============================================================================
-- 2. trip_finalization_jobs queue table
-- ============================================================================

CREATE TABLE IF NOT EXISTS trip_finalization_jobs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      UUID NOT NULL REFERENCES shift_sessions(id) ON DELETE CASCADE,
  reason          TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pending',
  attempts        INTEGER NOT NULL DEFAULT 0,
  max_attempts    INTEGER NOT NULL DEFAULT 5,
  error           TEXT,
  provider        TEXT NOT NULL DEFAULT 'google_roads',
  enqueued_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (session_id)
);

ALTER TABLE trip_finalization_jobs DROP CONSTRAINT IF EXISTS trip_finalization_jobs_status_check;
ALTER TABLE trip_finalization_jobs ADD CONSTRAINT trip_finalization_jobs_status_check
  CHECK (status IN ('pending', 'in_progress', 'done', 'failed', 'skipped'));

ALTER TABLE trip_finalization_jobs DROP CONSTRAINT IF EXISTS trip_finalization_jobs_provider_check;
ALTER TABLE trip_finalization_jobs ADD CONSTRAINT trip_finalization_jobs_provider_check
  CHECK (provider IN ('google_roads', 'osrm', 'valhalla'));

CREATE INDEX IF NOT EXISTS idx_trip_finalization_jobs_status_next
  ON trip_finalization_jobs (status, next_attempt_at)
  WHERE status IN ('pending', 'failed');

CREATE INDEX IF NOT EXISTS idx_trip_finalization_jobs_session
  ON trip_finalization_jobs (session_id);

-- ============================================================================
-- 3. Auto-enqueue: a row is inserted whenever a session transitions to
--    'completed'. The Edge Function picks it up on its next tick.
-- ============================================================================

CREATE OR REPLACE FUNCTION enqueue_trip_finalization()
RETURNS TRIGGER AS $$
BEGIN
  -- Only enqueue on transition into 'completed', and only if the session
  -- actually has a non-zero estimated_km (no point snapping a 0 km row).
  IF NEW.status = 'completed'
     AND (OLD.status IS DISTINCT FROM 'completed')
     AND COALESCE(NEW.estimated_km, NEW.total_km, 0) > 0 THEN
    INSERT INTO trip_finalization_jobs (session_id, reason)
    VALUES (NEW.id, 'session_completed')
    ON CONFLICT (session_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_enqueue_trip_finalization ON shift_sessions;
CREATE TRIGGER trg_enqueue_trip_finalization
  AFTER UPDATE OF status ON shift_sessions
  FOR EACH ROW
  EXECUTE FUNCTION enqueue_trip_finalization();

-- ============================================================================
-- 4. Helper: claim the next pending job (FOR UPDATE SKIP LOCKED)
-- ============================================================================
-- The Edge Function calls this to atomically grab one job at a time.
-- Idempotent on session_id; safe to run concurrently across regions.

CREATE OR REPLACE FUNCTION claim_next_finalization_job()
RETURNS SETOF trip_finalization_jobs AS $$
DECLARE
  v_job trip_finalization_jobs%ROWTYPE;
BEGIN
  SELECT *
  INTO v_job
  FROM trip_finalization_jobs
  WHERE status IN ('pending', 'failed')
    AND next_attempt_at <= NOW()
    AND attempts < max_attempts
  ORDER BY enqueued_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  UPDATE trip_finalization_jobs
  SET status     = 'in_progress',
      started_at = NOW(),
      attempts   = attempts + 1,
      error      = NULL
  WHERE id = v_job.id
  RETURNING * INTO v_job;

  RETURN NEXT v_job;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 5. Nightly polyline purge (ToS compliance)
-- ============================================================================
-- Run via pg_cron or a scheduled Edge Function. Keeps final_km forever;
-- only the geometry is purged. 25-day cutoff = 5-day safety margin under
-- the 30-day Google ToS limit.

CREATE OR REPLACE FUNCTION purge_expired_snapped_polylines()
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  WITH purged AS (
    UPDATE shift_sessions
    SET snapped_polyline   = NULL,
        polyline_expires_at = NULL
    WHERE polyline_expires_at IS NOT NULL
      AND polyline_expires_at < NOW()
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_count FROM purged;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Schedule the purge daily if pg_cron is available. Wrap in a DO block so the
-- migration succeeds on instances without pg_cron (purge can be triggered
-- from the Edge Function itself as a fallback).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('purge_expired_snapped_polylines');
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- unschedule fails if the job doesn't exist; that's fine.
  NULL;
END$$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'purge_expired_snapped_polylines',
      '15 3 * * *', -- daily at 03:15 IST-ish UTC
      $cron$SELECT public.purge_expired_snapped_polylines();$cron$
    );
  END IF;
END$$;
