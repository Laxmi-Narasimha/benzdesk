-- ============================================================================
-- 085_schedule_trip_workers.sql
--
-- ROOT-CAUSE FIX for two long-standing bugs:
--   (1) Stops in completed sessions display GPS coordinates instead of
--       place names — `enrich-trip` Edge Function exists, the DB trigger
--       fires correctly and inserts rows into `trip_enrichment_jobs`,
--       but NOTHING ever invokes the function so the queue sits forever
--       in `pending`.
--   (2) Admin "Verify distance" button stays "Queued ✓" forever — same
--       problem on `trip_finalization_jobs`. The finalize-trip function
--       (with full Google Roads Snap-to-Roads logic in
--       _shared/map_matcher.ts) is deployed and works, but nothing
--       invokes it on a schedule.
--
-- Both function source files even comment "invoked on a cron tick (1/min)"
-- — that cron was never created.
--
-- This migration schedules both functions every minute via pg_cron +
-- pg_net. Each tick POSTs to the function URL; the function itself
-- decides whether there's work to do and exits quickly if not.
--
-- ONE-TIME SETUP via Supabase Dashboard → Project Settings → Vault
-- (NOT via ALTER DATABASE — managed Supabase rejects that with 42501).
-- Create two Vault secrets exactly named:
--
--   app_functions_base_url  =  https://<your-project-ref>.supabase.co/functions/v1
--   app_service_role_key    =  <paste the service role JWT from
--                               Project Settings → API → service_role>
--
-- The cron jobs below resolve them at execution time via
-- vault.decrypted_secrets, so the JWT never lives in git history. To
-- rotate the key later, just update the Vault entry — no new migration
-- needed. If either secret is missing the cron tick becomes a silent
-- no-op (safe failure mode); we surface this in the helper RPC return
-- value so the admin UI can warn the operator.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
CREATE EXTENSION IF NOT EXISTS supabase_vault;

-- Small helpers so each cron tick is a one-liner. Both return NULL when
-- the vault secret is missing — pg_net.http_post on NULL url silently
-- skips, so missing setup never throws.
CREATE OR REPLACE FUNCTION public._functions_base_url() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, vault AS $$
  SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'app_functions_base_url' LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public._service_role_key() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, vault AS $$
  SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'app_service_role_key' LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION public._functions_base_url() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public._service_role_key()    FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public._functions_base_url() TO service_role;
GRANT  EXECUTE ON FUNCTION public._service_role_key()    TO service_role;

-- Drop prior schedules with the same names so re-running this migration
-- doesn't pile up duplicate jobs.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN PERFORM cron.unschedule('drain-enrich-trip');        EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN PERFORM cron.unschedule('drain-finalize-trip');      EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
END$$;

-- ----------------------------------------------------------------------------
-- enrich-trip: drains trip_enrichment_jobs.
-- Writes place_name / address back onto session_stops + shift_sessions.
-- Idempotent inside the function — re-invocation with no pending jobs
-- returns immediately.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'drain-enrich-trip',
      '* * * * *', -- every minute
      $cron$
        SELECT net.http_post(
          url := public._functions_base_url() || '/enrich-trip',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || public._service_role_key()
          ),
          body := '{"trigger":"cron"}'::jsonb,
          timeout_milliseconds := 25000
        ) WHERE public._functions_base_url() IS NOT NULL
            AND public._service_role_key() IS NOT NULL;
      $cron$
    );
  END IF;
END$$;

-- ----------------------------------------------------------------------------
-- finalize-trip: drains trip_finalization_jobs.
-- Calls Google Roads "Snap to Roads" on the raw GPS fixes and writes
-- final_km back onto shift_sessions. Honours job.reason ('session_completed'
-- or 'admin_verify' from the admin "Verify distance" button).
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'drain-finalize-trip',
      '* * * * *', -- every minute
      $cron$
        SELECT net.http_post(
          url := public._functions_base_url() || '/finalize-trip',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || public._service_role_key()
          ),
          body := '{"trigger":"cron"}'::jsonb,
          timeout_milliseconds := 25000
        ) WHERE public._functions_base_url() IS NOT NULL
            AND public._service_role_key() IS NOT NULL;
      $cron$
    );
  END IF;
END$$;

-- ----------------------------------------------------------------------------
-- Helper used by the admin UI: enqueue an admin-verify job AND ping the
-- finalize-trip function once immediately so the user sees a result in a
-- few seconds rather than waiting up to a full minute for the cron tick.
--
-- Returns the job id so the admin UI can poll trip_finalization_jobs by
-- id and render the result inline.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_request_distance_verification_now(
  p_session_id UUID
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_job_id  UUID;
  v_url     TEXT;
  v_key     TEXT;
BEGIN
  -- Upsert a pending verification job, resetting attempts so it runs now.
  INSERT INTO trip_finalization_jobs (session_id, reason, status, attempts, next_attempt_at)
  VALUES (p_session_id, 'admin_verify', 'pending', 0, NOW())
  ON CONFLICT (session_id) DO UPDATE
    SET reason = 'admin_verify',
        status = 'pending',
        attempts = 0,
        error = NULL,
        next_attempt_at = NOW()
  RETURNING id INTO v_job_id;

  -- Fire-and-forget: kick the function so the user doesn't wait 60s
  -- for the next cron tick. If the vault entries are missing we still
  -- return the job id (so the UI can poll), but raise a notice so the
  -- caller can surface a clear "vault not configured" message instead
  -- of a silent stall.
  v_url := public._functions_base_url();
  v_key := public._service_role_key();
  IF v_url IS NOT NULL AND v_key IS NOT NULL THEN
    PERFORM net.http_post(
      url := v_url || '/finalize-trip',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_key
      ),
      body := jsonb_build_object('trigger', 'admin', 'session_id', p_session_id),
      timeout_milliseconds := 25000
    );
  ELSE
    RAISE WARNING
      'admin_request_distance_verification_now: vault secrets app_functions_base_url and/or app_service_role_key are missing. The job is queued but no worker will run until the next cron tick (which will also no-op until vault is configured).';
  END IF;

  RETURN v_job_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_request_distance_verification_now(UUID)
  TO authenticated, service_role;

-- ----------------------------------------------------------------------------
-- One-shot backlog drainers — call once from the SQL editor after vault
-- is configured to immediately process every pending job from the
-- months when neither cron existed. Returns the HTTP status / id from
-- pg_net so you can sanity-check the call worked.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.kick_enrich_trip_once() RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
  -- Reset every non-done row so the function actually sees them.
  UPDATE trip_enrichment_jobs
     SET status = 'pending', attempts = 0, error = NULL, next_attempt_at = NOW()
   WHERE status IN ('pending', 'failed', 'in_progress');

  SELECT net.http_post(
    url := public._functions_base_url() || '/enrich-trip',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || public._service_role_key()
    ),
    body := '{"trigger":"manual_backlog"}'::jsonb,
    timeout_milliseconds := 30000
  ) INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.kick_finalize_trip_once() RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id BIGINT;
BEGIN
  UPDATE trip_finalization_jobs
     SET status = 'pending', attempts = 0, error = NULL, next_attempt_at = NOW()
   WHERE status IN ('pending', 'failed', 'in_progress');

  SELECT net.http_post(
    url := public._functions_base_url() || '/finalize-trip',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || public._service_role_key()
    ),
    body := '{"trigger":"manual_backlog"}'::jsonb,
    timeout_milliseconds := 30000
  ) INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.kick_enrich_trip_once()   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.kick_finalize_trip_once() FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.kick_enrich_trip_once()   TO service_role;
GRANT  EXECUTE ON FUNCTION public.kick_finalize_trip_once() TO service_role;
