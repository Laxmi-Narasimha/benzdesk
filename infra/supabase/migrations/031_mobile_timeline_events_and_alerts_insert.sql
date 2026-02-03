-- ============================================================================
-- Migration 031: Allow Mobile App to Create Timeline Events & Alerts
-- Fixes: stop markers + alerts not appearing in admin panel because the mobile
-- app (authenticated user) could not INSERT into timeline_events/mobitraq_alerts.
-- ============================================================================

-- ============================================================================
-- STEP 1: Allow authenticated employees to INSERT their own timeline events
-- Guarded by both employee_id = auth.uid() AND session ownership.
-- ============================================================================

DROP POLICY IF EXISTS "Employees can insert own timeline events" ON timeline_events;
CREATE POLICY "Employees can insert own timeline events" ON timeline_events
FOR INSERT
TO authenticated
WITH CHECK (
  employee_id = auth.uid()
  AND session_id IN (
    SELECT id FROM shift_sessions WHERE employee_id = auth.uid()
  )
);

-- ============================================================================
-- STEP 2: Allow authenticated employees to INSERT their own alerts
-- ============================================================================

DROP POLICY IF EXISTS "Employees can insert own mobitraq alerts" ON mobitraq_alerts;
CREATE POLICY "Employees can insert own mobitraq alerts" ON mobitraq_alerts
FOR INSERT
TO authenticated
WITH CHECK (
  employee_id = auth.uid()
  AND (
    session_id IS NULL
    OR session_id IN (SELECT id FROM shift_sessions WHERE employee_id = auth.uid())
  )
);

-- ============================================================================
-- STEP 3: Align stop threshold with mobile app (5 minutes)
-- NOTE: mobitraq_config.value is JSONB.
-- ============================================================================

UPDATE mobitraq_config
SET value = '300'::jsonb
WHERE key = 'STOP_MIN_DURATION_SEC';

DO $$
BEGIN
  RAISE NOTICE 'Migration 031 complete: Mobile can insert timeline_events + mobitraq_alerts; STOP_MIN_DURATION_SEC set to 300s.';
END $$;

