-- ============================================================================
-- Migration 037: Timeline Start/End Events + Robust Stop Updates
-- Implements:
-- - Support event_type in ('start','end','stop','move')
-- - DB-enforced day calculation (Asia/Kolkata) + duration_sec calculation
-- - Allow employees to UPDATE their own timeline events (for in-progress stops)
-- - Update stop radius config to 200m (per requirement)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Expand timeline_events.event_type allowed values
-- ---------------------------------------------------------------------------

-- Default check constraint name for: CHECK (event_type IN (...))
ALTER TABLE timeline_events
  DROP CONSTRAINT IF EXISTS timeline_events_event_type_check;

ALTER TABLE timeline_events
  ADD CONSTRAINT timeline_events_event_type_check
  CHECK (event_type IN ('start', 'end', 'stop', 'move'));

-- ---------------------------------------------------------------------------
-- 2) Enforce canonical day + duration_sec inside DB (avoid client timezone bugs)
-- day is derived in Asia/Kolkata
-- duration_sec is derived from end_time - start_time
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.timeline_events_set_derived_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Ensure end_time is never null
  IF NEW.end_time IS NULL THEN
    NEW.end_time := NEW.start_time;
  END IF;

  -- Canonical day in IST
  NEW.day := (NEW.start_time AT TIME ZONE 'Asia/Kolkata')::date;

  -- Canonical duration
  NEW.duration_sec := GREATEST(
    0,
    COALESCE(EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time))::int, 0)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS timeline_events_set_derived_fields_trigger ON timeline_events;
CREATE TRIGGER timeline_events_set_derived_fields_trigger
BEFORE INSERT OR UPDATE ON timeline_events
FOR EACH ROW
EXECUTE FUNCTION public.timeline_events_set_derived_fields();

GRANT EXECUTE ON FUNCTION public.timeline_events_set_derived_fields() TO authenticated;

-- ---------------------------------------------------------------------------
-- 3) Allow employees to UPDATE their own timeline events for their own sessions
-- (used to extend an in-progress stop while the user remains within the stop radius)
-- ---------------------------------------------------------------------------

DROP POLICY IF EXISTS "Employees can update own timeline events" ON timeline_events;
CREATE POLICY "Employees can update own timeline events" ON timeline_events
FOR UPDATE
TO authenticated
USING (
  employee_id = auth.uid()
  AND session_id IN (SELECT id FROM shift_sessions WHERE employee_id = auth.uid())
)
WITH CHECK (
  employee_id = auth.uid()
  AND session_id IN (SELECT id FROM shift_sessions WHERE employee_id = auth.uid())
);

-- ---------------------------------------------------------------------------
-- 4) Align STOP_RADIUS_M with requirement (200m)
-- ---------------------------------------------------------------------------

UPDATE mobitraq_config
SET value = '200'::jsonb
WHERE key = 'STOP_RADIUS_M';

DO $$
BEGIN
  RAISE NOTICE 'Migration 037 complete: timeline_events supports start/end; derived day+duration enforced; employee UPDATE policy added; STOP_RADIUS_M set to 200m.';
END $$;
