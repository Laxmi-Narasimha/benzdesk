-- Add address column to timeline_events table if it doesn't exist
ALTER TABLE timeline_events ADD COLUMN IF NOT EXISTS address TEXT;

-- Verify the column exists (optional comment)
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'timeline_events' AND column_name = 'address';
