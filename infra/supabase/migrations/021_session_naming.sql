-- ============================================================================
-- Migration 021: Session Naming and Timeline Enhancements
-- Adds session_name column for user-defined session labels
-- ============================================================================

-- Add session_name column to shift_sessions
ALTER TABLE shift_sessions 
ADD COLUMN IF NOT EXISTS session_name TEXT DEFAULT NULL;

-- Add comment for documentation
COMMENT ON COLUMN shift_sessions.session_name IS 'User-defined name for the session (e.g., "Field Visit - North Zone")';

-- Create index for faster lookups by session name
CREATE INDEX IF NOT EXISTS idx_shift_sessions_name ON shift_sessions(session_name) WHERE session_name IS NOT NULL;

-- ============================================================================
-- End of Migration 021
-- ============================================================================
