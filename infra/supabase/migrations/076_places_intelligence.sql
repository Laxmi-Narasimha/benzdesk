-- Migration 076: Places + Geocoding intelligence layer
--
-- Adds the data shape needed to:
--   1. Bind each trip to a customer (Google Place ID) at session start.
--   2. Reverse-geocode session endpoints + every detected stop so the
--      admin timeline shows readable addresses instead of lat/lng.
--   3. Auto-detect which of OUR customers an employee visited, by
--      matching every session_stops row to the nearest customer
--      Place ID within a 100m radius.
--   4. Re-run that detection for HISTORIC sessions (backfill_enrich_session
--      RPC) so the admin can validate the system against past data.
--
-- Roads API enqueue policy also rewritten here from "every completed
-- session" → "only when verification adds value" (offline / low
-- confidence / >50km / admin trigger). See docs/DISTANCE_TRACKING_METHODOLOGY.md.

-- ============================================================================
-- 1. customers master
-- ============================================================================
-- Place-ID-anchored customer/site directory. Independent of the legacy
-- "purpose" free-text field on sessions — that field stays for back-compat
-- and for "Other / Personal" trips that don't correspond to a customer.

CREATE TABLE IF NOT EXISTS customers (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  google_place_id  TEXT UNIQUE,             -- nullable: customers added manually before geocoding succeeds
  name             TEXT NOT NULL,
  formatted_address TEXT,
  latitude         DOUBLE PRECISION,
  longitude        DOUBLE PRECISION,
  phone            TEXT,
  website          TEXT,
  notes            TEXT,
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customers_place_id
  ON customers (google_place_id) WHERE google_place_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_customers_active_geo
  ON customers (is_active, latitude, longitude)
  WHERE is_active = TRUE AND latitude IS NOT NULL;

ALTER TABLE customers DISABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2. Place-ID columns on the trip-level rows
-- ============================================================================

-- A session can be bound to one PRIMARY customer (the one the rep set
-- at session start via Places Autocomplete). The "visited" customers
-- column lists every customer whose Place matched a detected stop.
ALTER TABLE shift_sessions
  ADD COLUMN IF NOT EXISTS primary_customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS visited_customer_ids UUID[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS start_place_id TEXT,
  ADD COLUMN IF NOT EXISTS end_place_id TEXT;

CREATE INDEX IF NOT EXISTS idx_shift_sessions_primary_customer
  ON shift_sessions (primary_customer_id) WHERE primary_customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_shift_sessions_visited_customers
  ON shift_sessions USING GIN (visited_customer_ids);

-- Per-stop: which customer (if any) sits within 100m of the stop center.
ALTER TABLE session_stops
  ADD COLUMN IF NOT EXISTS customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS place_id TEXT,
  ADD COLUMN IF NOT EXISTS place_name TEXT;

CREATE INDEX IF NOT EXISTS idx_session_stops_customer
  ON session_stops (customer_id) WHERE customer_id IS NOT NULL;

-- ============================================================================
-- 3. Selective Roads-API enqueue policy
-- ============================================================================
-- Previously: every completed session enqueued (072 + 074).
-- Now: only when Roads API would actually add value. Saves API budget
-- AND keeps the queue table small enough to scan cheaply.
--
-- We also expose a manual-trigger RPC (admin_request_distance_verification)
-- so the admin "Verify Distance" button on a session detail page can
-- queue verification on demand.

CREATE OR REPLACE FUNCTION enqueue_trip_finalization()
RETURNS TRIGGER AS $$
DECLARE
  v_pending_secs INTEGER;
BEGIN
  -- Only on transition into 'completed'.
  IF NEW.status <> 'completed' OR OLD.status IS NOT DISTINCT FROM 'completed' THEN
    RETURN NEW;
  END IF;
  IF COALESCE(NEW.estimated_km, NEW.total_km, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Eligibility: any one of these qualifies the session for Roads API
  -- verification. If none match, we trust final_km as-is.
  --
  -- (1) Confidence != 'high'  → device thinks GPS was iffy
  -- (2) >= 50 km              → high-value trip, worth the audit cost
  -- (3) Reason codes include any of {GPS_GAP_OVER_120S, MOCK_LOCATION_DETECTED,
  --     POINT_SPACING_OVER_300M, STATIONARY_DOMINATED} → known noisy signals
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

-- Admin "Verify Distance" entry point. Returns true if a new job was
-- enqueued (or the existing one was re-queued), false if the job is
-- still running.
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

  -- Re-queue a previously-completed or failed verification.
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
-- 4. Place-enrichment jobs (separate queue from Roads finalization)
-- ============================================================================
-- Geocoding + Nearby-Search-against-customers runs for EVERY session,
-- but it's cheap (well under free tier) and provides the user-facing
-- value (readable addresses, "visited X" tags). We use a separate
-- queue from trip_finalization_jobs so a slow Roads API call doesn't
-- block fast enrichment, and vice versa.

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

-- Claim-next helper, same pattern as the Roads queue.
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
-- 5. Historic backfill — enqueue every completed session that hasn't
--    been enriched yet
-- ============================================================================
-- The user explicitly wants old sessions to ALSO get readable addresses
-- + visited-customers tags so they can validate the system against
-- historic data before fully trusting it. Run this RPC once after
-- migration. The enrichment Edge Function then drains the queue at
-- its normal rate (~1 job/sec).

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
-- 6. Active employee snapshot — used by the Route Matrix "Closest
--    teammate" feature on the admin dashboard
-- ============================================================================
-- A view that exposes the latest known location of each currently-
-- active employee. We pick the latest location_point for each
-- employee whose session is currently 'active'. The admin web calls
-- Routes API Route Matrix with these points to compute pairwise
-- travel times.

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
