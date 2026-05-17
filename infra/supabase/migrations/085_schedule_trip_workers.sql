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
-- ONE-TIME SETUP — RUN THESE TWO LINES MANUALLY (psql or Supabase SQL
-- editor) BEFORE THIS MIGRATION TAKES EFFECT. They store the function
-- base URL + service-role key as database GUCs so the cron job can read
-- them without us hardcoding secrets into the migration:
--
--   ALTER DATABASE postgres SET app.settings.functions_base_url =
--     'https://<your-project-ref>.supabase.co/functions/v1';
--   ALTER DATABASE postgres SET app.settings.service_role_key =
--     '<your service-role JWT>';
--
-- After running them you must reconnect (the cron job picks them up via
-- current_setting() on each invocation). The migration is idempotent and
-- safe to re-apply.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

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
          url := current_setting('app.settings.functions_base_url', true) || '/enrich-trip',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
          ),
          body := '{"trigger":"cron"}'::jsonb,
          timeout_milliseconds := 25000
        );
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
          url := current_setting('app.settings.functions_base_url', true) || '/finalize-trip',
          headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key', true)
          ),
          body := '{"trigger":"cron"}'::jsonb,
          timeout_milliseconds := 25000
        );
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

  -- Fire-and-forget: kick the function so the user doesn't wait 60s.
  -- Both GUCs are optional — if they're not set, this becomes a no-op
  -- and the user just waits for the next cron tick instead.
  v_url := current_setting('app.settings.functions_base_url', true);
  v_key := current_setting('app.settings.service_role_key', true);
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
  END IF;

  RETURN v_job_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_request_distance_verification_now(UUID)
  TO authenticated, service_role;
