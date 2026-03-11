-- ============================================================================
-- Migration 045: Session-Expense Linking & Unified System
-- 
-- Adds session_id to trip_expenses so fuel expenses can be linked back to
-- the GPS session for admin audit. Also ensures request_comments has correct
-- RLS for mobile app access.
-- ============================================================================

-- 1. Add session_id column to trip_expenses for session-expense linking
ALTER TABLE trip_expenses ADD COLUMN IF NOT EXISTS session_id UUID REFERENCES shift_sessions(id);
CREATE INDEX IF NOT EXISTS idx_trip_expenses_session ON trip_expenses(session_id);

-- 2. Ensure request_comments table exists and has proper access
-- (It should already exist from the requests module, but ensure RLS allows mobile insert)
DO $$
BEGIN
  -- Grant insert permissions on request_comments for authenticated users (mobile app)
  GRANT SELECT, INSERT ON request_comments TO authenticated;
  GRANT SELECT, INSERT ON request_events TO authenticated;
  GRANT SELECT ON request_attachments TO authenticated;
  
  RAISE NOTICE '✅ Migration 045 complete:';
  RAISE NOTICE '   - Added session_id column to trip_expenses';
  RAISE NOTICE '   - Ensured request_comments/events/attachments accessible to authenticated users';
END $$;
