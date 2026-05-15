-- Migration 077: Repair + complete migration 076.
--
-- 076 assumed the `customers` table didn't exist and tried to
-- CREATE TABLE IF NOT EXISTS it with all the columns we need. In
-- production a `customers` table DOES exist (created earlier outside
-- of this migration chain), so the CREATE was a no-op and the
-- subsequent CREATE INDEX ON customers (google_place_id) failed
-- because the column wasn't there.
--
-- This migration is **defensive**: it adds every column we need with
-- ADD COLUMN IF NOT EXISTS, then re-runs all of 076 from that point
-- forward. Everything is idempotent (IF NOT EXISTS, CREATE OR REPLACE,
-- DROP CONSTRAINT IF EXISTS) so safe to run even on databases where
-- 076 ran cleanly.
--
-- Run this AFTER 076. If 076 hasn't been run at all, this still
-- works — every step is independently safe.

-- ============================================================================
-- 1. Patch customers table to match the shape our code expects
-- ============================================================================
-- Make sure the table exists at minimum. If it already exists with
-- different columns, ADD COLUMN IF NOT EXISTS below handles each
-- missing field individually.

CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid()
);

ALTER TABLE customers ADD COLUMN IF NOT EXISTS google_place_id   TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS name              TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS formatted_address TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS latitude          DOUBLE PRECISION;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS longitude         DOUBLE PRECISION;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS phone             TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS website           TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS notes             TEXT;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS is_active         BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE customers ADD COLUMN IF NOT EXISTS created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE customers ADD COLUMN IF NOT EXISTS updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Unique constraint on google_place_id (only when non-null) so the
-- admin "Add customer" modal can rely on ON CONFLICT to detect dupes.
-- We do this with a partial unique INDEX rather than a CONSTRAINT
-- because partial unique constraints require Postgres 15+ and we want
-- this to run on any Supabase project. The downside is the admin code
-- can't use ON CONFLICT (google_place_id) — it has to SELECT first.
-- Re-checked the admin/customers/page.tsx code: it uses a plain
-- INSERT and surfaces error code 23505 for the duplicate case, which
-- the unique INDEX raises just like a CONSTRAINT would.
CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_place_id
  ON customers (google_place_id) WHERE google_place_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customers_active_geo
  ON customers (is_active, latitude, longitude)
  WHERE is_active = TRUE AND latitude IS NOT NULL;

ALTER TABLE customers DISABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. Place-ID columns on the trip-level rows
-- ============================================================================

ALTER TABLE shift_sessions
  ADD COLUMN IF NOT EXISTS primary_customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS visited_customer_ids UUID[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS start_place_id TEXT,
  ADD COLUMN IF NOT EXISTS end_place_id TEXT;

CREATE INDEX IF NOT EXISTS idx_shift_sessions_primary_customer
  ON shift_sessions (primary_customer_id) WHERE primary_customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_shift_sessions_visited_customers
  ON shift_sessions USING GIN (visited_customer_ids);

ALTER TABLE session_stops
  ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS place_id TEXT,
  ADD COLUMN IF NOT EXISTS place_name TEXT;

CREATE INDEX IF NOT EXISTS idx_session_stops_customer
  ON session_stops (customer_id) WHERE customer_id IS NOT NULL;

-- ============================================================================
-- 3. Selective Roads-API enqueue policy
-- ============================================================================

CREATE OR REPLACE FUNCTION enqueue_trip_finalization()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status <> 'completed' OR OLD.status IS NOT DISTINCT FROM 'completed' THEN
    RETURN NEW;
  END IF;
  IF COALESCE(NEW.estimated_km, NEW.total_km, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  IF NEW.confidence IS DISTINCT FROM 'high'
     OR NEW.final_km >= 50
     OR EXISTS (
       SELECT 1
       FROM jsonb_array_elements_text(COALESCE(NEW.reason_codes, '[]'::jsonb)) AS r(code)
       WHERE r.code IN (
         'GPS_GAP_OVER_120S',
         'MOCK_LOCATION_DETECTED',
         'POINT_SPACING_OVER_300M',
         'STATIONARY_DOMINATED'
       )
     )
  THEN
    INSERT INTO trip_finalization_jobs (session_id, reason)
    VALUES (NEW.id, 'auto_eligibility_match')
    ON CONFLICT (session_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_request_distance_verification(p_session_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  v_existing trip_finalization_jobs%ROWTYPE;
BEGIN
  SELECT * INTO v_existing FROM trip_finalization_jobs WHERE session_id = p_session_id;

  IF v_existing.id IS NULL THEN
    INSERT INTO trip_finalization_jobs (session_id, reason)
    VALUES (p_session_id, 'admin_verify');
    RETURN TRUE;
  END IF;

  IF v_existing.status = 'in_progress' THEN
    RETURN FALSE;
  END IF;

  UPDATE trip_finalization_jobs
  SET status          = 'pending',
      reason          = 'admin_verify',
      attempts        = 0,
      error           = NULL,
      next_attempt_at = NOW()
  WHERE id = v_existing.id;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 4. Trip-enrichment jobs queue
-- ============================================================================

CREATE TABLE IF NOT EXISTS trip_enrichment_jobs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      UUID NOT NULL REFERENCES shift_sessions(id) ON DELETE CASCADE,
  reason          TEXT NOT NULL DEFAULT 'session_completed',
  status          TEXT NOT NULL DEFAULT 'pending',
  attempts        INTEGER NOT NULL DEFAULT 0,
  max_attempts    INTEGER NOT NULL DEFAULT 3,
  error           TEXT,
  enqueued_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (session_id)
);

ALTER TABLE trip_enrichment_jobs DROP CONSTRAINT IF EXISTS trip_enrichment_jobs_status_check;
ALTER TABLE trip_enrichment_jobs ADD CONSTRAINT trip_enrichment_jobs_status_check
  CHECK (status IN ('pending', 'in_progress', 'done', 'failed', 'skipped'));

CREATE INDEX IF NOT EXISTS idx_trip_enrichment_jobs_status_next
  ON trip_enrichment_jobs (status, next_attempt_at)
  WHERE status IN ('pending', 'failed');

CREATE OR REPLACE FUNCTION enqueue_trip_enrichment()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status <> 'completed' OR OLD.status IS NOT DISTINCT FROM 'completed' THEN
    RETURN NEW;
  END IF;
  INSERT INTO trip_enrichment_jobs (session_id, reason)
  VALUES (NEW.id, 'session_completed')
  ON CONFLICT (session_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_enqueue_trip_enrichment ON shift_sessions;
CREATE TRIGGER trg_enqueue_trip_enrichment
  AFTER UPDATE OF status ON shift_sessions
  FOR EACH ROW
  EXECUTE FUNCTION enqueue_trip_enrichment();

CREATE OR REPLACE FUNCTION claim_next_enrichment_job()
RETURNS SETOF trip_enrichment_jobs AS $$
DECLARE
  v_job trip_enrichment_jobs%ROWTYPE;
BEGIN
  SELECT *
  INTO v_job
  FROM trip_enrichment_jobs
  WHERE status IN ('pending', 'failed')
    AND next_attempt_at <= NOW()
    AND attempts < max_attempts
  ORDER BY enqueued_at ASC
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  UPDATE trip_enrichment_jobs
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
-- 5. Historic backfill RPC
-- ============================================================================

CREATE OR REPLACE FUNCTION backfill_trip_enrichment(p_limit INTEGER DEFAULT 1000)
RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  WITH ins AS (
    INSERT INTO trip_enrichment_jobs (session_id, reason)
    SELECT s.id, 'backfill'
    FROM shift_sessions s
    WHERE s.status = 'completed'
      AND NOT EXISTS (
        SELECT 1 FROM trip_enrichment_jobs j WHERE j.session_id = s.id
      )
    ORDER BY s.end_time DESC NULLS LAST
    LIMIT p_limit
    ON CONFLICT (session_id) DO NOTHING
    RETURNING 1
  )
  SELECT COUNT(*) INTO v_count FROM ins;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 6. Active employee snapshot view (Route Matrix proximity panel)
-- ============================================================================

CREATE OR REPLACE VIEW active_employee_locations AS
WITH active_sessions AS (
  SELECT id AS session_id, employee_id
  FROM shift_sessions
  WHERE status = 'active'
), latest_point AS (
  SELECT DISTINCT ON (lp.session_id)
    lp.session_id,
    lp.latitude,
    lp.longitude,
    lp.recorded_at,
    lp.accuracy
  FROM location_points lp
  JOIN active_sessions s ON s.session_id = lp.session_id
  WHERE lp.recorded_at >= NOW() - INTERVAL '30 minutes'
    AND (lp.is_mock = FALSE OR lp.is_mock IS NULL)
  ORDER BY lp.session_id, lp.recorded_at DESC
)
SELECT
  s.session_id,
  s.employee_id,
  e.name AS employee_name,
  e.phone AS employee_phone,
  lp.latitude,
  lp.longitude,
  lp.recorded_at AS fix_at,
  lp.accuracy
FROM active_sessions s
JOIN employees e ON e.id = s.employee_id
JOIN latest_point lp ON lp.session_id = s.session_id;
