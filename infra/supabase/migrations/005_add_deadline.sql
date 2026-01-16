-- ============================================================================
-- Migration: Add deadline column and update categories
-- Run this in Supabase SQL Editor
-- ============================================================================

-- Add deadline column to requests table
ALTER TABLE requests ADD COLUMN IF NOT EXISTS deadline TIMESTAMPTZ NULL;

-- Create index for deadline queries (overdue requests)
CREATE INDEX IF NOT EXISTS idx_requests_deadline ON requests(deadline) WHERE deadline IS NOT NULL;

-- Update the request_category enum with new manufacturing categories
-- Note: PostgreSQL doesn't allow easy enum modification
-- We'll handle this at the application level for now

-- Grant necessary permissions
GRANT SELECT, INSERT, UPDATE ON requests TO authenticated;

-- Success message
SELECT 'Migration completed: deadline column added' as result;
