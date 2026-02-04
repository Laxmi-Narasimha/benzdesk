-- Migration 038: Fix timeline_events event_type constraint
-- The current constraint only allows 'stop' and 'move', but we need 'start' and 'end' too

-- Drop the old constraint
ALTER TABLE timeline_events DROP CONSTRAINT IF EXISTS timeline_events_event_type_check;

-- Add new constraint with all event types
ALTER TABLE timeline_events ADD CONSTRAINT timeline_events_event_type_check 
  CHECK (event_type IN ('start', 'end', 'stop', 'move'));

-- Verify
DO $$
BEGIN
  RAISE NOTICE '✅ timeline_events_event_type_check updated to allow: start, end, stop, move';
END $$;
