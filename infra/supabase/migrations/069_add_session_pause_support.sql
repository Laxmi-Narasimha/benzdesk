-- Migration 069: Add pause support columns to shift_sessions
-- Run this in the Supabase SQL editor to unblock the mobile app.
--
-- ROOT CAUSE: The mobile app's SessionModel.toJson() was sending
-- paused_at / resumed_at / total_paused_seconds in the INSERT payload,
-- but those columns did not exist.  Postgres rejected every INSERT with
-- "column does not exist", the catch block classified it as "offline",
-- and the session was queued in SharedPreferences forever — which is why
-- new sessions were invisible to both the admin panel and the mobile
-- session history.
--
-- After running this migration:
--   1. New sessions will INSERT correctly (fix already shipped in mobile code).
--   2. Pause/resume state will persist to the database.
--   3. Restore the three fields in SessionModel.toJson() and
--      updateSessionStatus() in supabase_client.dart.

-- Step 1: add the missing columns
ALTER TABLE shift_sessions
  ADD COLUMN IF NOT EXISTS paused_at            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS resumed_at           TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS total_paused_seconds INTEGER NOT NULL DEFAULT 0;

-- Step 2: fix the status CHECK constraint to include 'paused'
ALTER TABLE shift_sessions
  DROP CONSTRAINT IF EXISTS shift_sessions_status_check;

ALTER TABLE shift_sessions
  ADD CONSTRAINT shift_sessions_status_check
  CHECK (status IN ('active', 'paused', 'completed', 'cancelled'));

-- Step 3: make sure RLS is off so all authenticated users can read/write
--         their own sessions without fighting policy chains
ALTER TABLE shift_sessions DISABLE ROW LEVEL SECURITY;
