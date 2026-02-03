-- ============================================================
-- Migration 031: Comprehensive Director RLS Access
-- Ensures BenzDesk directors can view ALL MobiTraq data
-- Date: 2026-02-03
-- ============================================================

-- The is_benzdesk_director() function checks the user_roles table
-- Directors may be logged in via BenzDesk but NOT be in the employees table
-- We need to ensure they can still see all MobiTraq data

-- First, verify the is_benzdesk_director function exists and works
CREATE OR REPLACE FUNCTION is_benzdesk_director()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() 
    AND role = 'director'
  );
EXCEPTION
  WHEN undefined_table THEN
    -- user_roles table doesn't exist, check benzdesk_users
    RETURN EXISTS (
      SELECT 1 FROM benzdesk_users 
      WHERE user_id = auth.uid() 
      AND role = 'director'
    );
  WHEN OTHERS THEN
    RETURN false;
END;
$$;

-- Grant execute to everyone so RLS can call it
GRANT EXECUTE ON FUNCTION is_benzdesk_director() TO authenticated;
GRANT EXECUTE ON FUNCTION is_benzdesk_director() TO anon;

-- ============================================================
-- employees table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all employees" ON employees;
CREATE POLICY "Directors can view all employees" ON employees
    FOR SELECT USING (is_benzdesk_director());

-- Allow authenticated users to see employees list (needed for dropdown)
DROP POLICY IF EXISTS "Authenticated users can view employees" ON employees;
CREATE POLICY "Authenticated users can view employees" ON employees
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- shift_sessions table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all sessions" ON shift_sessions;
CREATE POLICY "Directors can view all sessions" ON shift_sessions
    FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Authenticated users can view all sessions" ON shift_sessions;
CREATE POLICY "Authenticated users can view all sessions" ON shift_sessions
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- location_points table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all locations" ON location_points;
CREATE POLICY "Directors can view all locations" ON location_points
    FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Authenticated users can view all locations" ON location_points;
CREATE POLICY "Authenticated users can view all locations" ON location_points
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- expense_claims table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all expenses" ON expense_claims;
CREATE POLICY "Directors can view all expenses" ON expense_claims
    FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Authenticated users can view all expenses" ON expense_claims;
CREATE POLICY "Authenticated users can view all expenses" ON expense_claims
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- expense_items table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all expense items" ON expense_items;
CREATE POLICY "Directors can view all expense items" ON expense_items
    FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Authenticated users can view all expense items" ON expense_items;
CREATE POLICY "Authenticated users can view all expense items" ON expense_items
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- employee_states table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all employee states" ON employee_states;
CREATE POLICY "Directors can view all employee states" ON employee_states
    FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Authenticated users can view employee states" ON employee_states;
CREATE POLICY "Authenticated users can view employee states" ON employee_states
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- session_rollups table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all session rollups" ON session_rollups;
CREATE POLICY "Directors can view all session rollups" ON session_rollups
    FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Authenticated users can view session rollups" ON session_rollups;
CREATE POLICY "Authenticated users can view session rollups" ON session_rollups
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- daily_rollups table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all daily rollups" ON daily_rollups;
CREATE POLICY "Directors can view all daily rollups" ON daily_rollups
    FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Authenticated users can view daily rollups" ON daily_rollups;
CREATE POLICY "Authenticated users can view daily rollups" ON daily_rollups
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- timeline_events table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all timeline events" ON timeline_events;
CREATE POLICY "Directors can view all timeline events" ON timeline_events
    FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Authenticated users can view timeline events" ON timeline_events;
CREATE POLICY "Authenticated users can view timeline events" ON timeline_events
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- mobitraq_alerts table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all alerts" ON mobitraq_alerts;
CREATE POLICY "Directors can view all alerts" ON mobitraq_alerts
    FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Authenticated users can view alerts" ON mobitraq_alerts;
CREATE POLICY "Authenticated users can view alerts" ON mobitraq_alerts
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ============================================================
-- mobile_notifications table - Directors view all
-- ============================================================
DROP POLICY IF EXISTS "Directors can view all notifications" ON mobile_notifications;
CREATE POLICY "Directors can view all notifications" ON mobile_notifications
    FOR SELECT USING (is_benzdesk_director());

-- ============================================================
-- Success message
-- ============================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Migration 031 completed successfully!';
    RAISE NOTICE '   - Added director RLS policies to all MobiTraq tables';
    RAISE NOTICE '   - Added authenticated user policies for dashboard access';
    RAISE NOTICE '   - Directors can now view all employees, sessions, locations, expenses';
END $$;
