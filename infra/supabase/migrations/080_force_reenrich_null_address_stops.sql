-- Migration 080: Force re-enrichment of sessions whose stops still
-- have NULL address / place_name.
--
-- User SQL on 2026-05-15 showed every stop row from yesterday's
-- sessions had address=NULL, place_name=NULL, customer_id=NULL.
-- The enrich-trip Edge Function exists and would fill those fields,
-- but the jobs queue may not have entries for those sessions OR
-- the cron isn't draining them. This migration re-enqueues a job
-- for every session that has at least one NULL-address stop.
--
-- The enrich-trip function is idempotent on session_id, so re-running
-- it on an already-enriched session is a cheap no-op for the
-- already-filled stops and a real fix for the NULL ones.

INSERT INTO trip_enrichment_jobs (session_id, reason)
SELECT DISTINCT s.id, 'force_reenrich_null_stops'
FROM shift_sessions s
WHERE s.status = 'completed'
  AND EXISTS (
    SELECT 1 FROM session_stops st
    WHERE st.session_id = s.id
      AND (st.address IS NULL OR st.place_name IS NULL)
  )
ON CONFLICT (session_id) DO UPDATE SET
  status = 'pending',
  reason = 'force_reenrich_null_stops',
  attempts = 0,
  error = NULL,
  next_attempt_at = NOW();

DO $$
DECLARE
  v_pending INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_pending
  FROM trip_enrichment_jobs
  WHERE status = 'pending';
  RAISE NOTICE 'Re-enrich queued: % pending jobs (drains at ~10/tick via enrich-trip cron)',
    v_pending;
END $$;
