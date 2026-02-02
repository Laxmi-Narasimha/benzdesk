-- ============================================================================
-- Fix Stuck Sessions - Migration 017
-- Closes any active sessions that are currently stuck in "active" state
-- ============================================================================

-- Close all active sessions with current timestamp
UPDATE work_sessions
SET 
  end_time = NOW(),
  status = 'completed',
  updated_at = NOW()
WHERE 
  end_time IS NULL 
  AND status != 'completed';

-- Log the fix
DO $$
DECLARE
  affected_count INTEGER;
BEGIN
  GET DIAGNOSTICS affected_count = ROW_COUNT;
  RAISE NOTICE 'Closed % stuck session(s)', affected_count;
END $$;
