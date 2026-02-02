-- ============================================================
-- Migration 029: Fix Timeline Page Data Access
-- Ensures all timeline-related tables have proper RLS policies
-- for admin and director access
-- ============================================================

-- Problem: Timeline page queries fail due to missing RLS policies
-- Tables used by timeline: location_points, shift_sessions, session_rollups, timeline_events

-- Step 1: Ensure shift_sessions has director/admin access
DROP POLICY IF EXISTS "Directors can view all sessions" ON shift_sessions;
CREATE POLICY "Directors can view all sessions" ON shift_sessions
    FOR SELECT
    USING (
        is_benzdesk_director()
    );

DROP POLICY IF EXISTS "Admins can view all sessions" ON shift_sessions;
CREATE POLICY "Admins can view all sessions" ON shift_sessions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM employees e 
            WHERE e.id = auth.uid() AND e.role = 'admin'
        )
    );

-- Step 2: Ensure session_rollups has director/admin access
DROP POLICY IF EXISTS "Directors can view all session rollups" ON session_rollups;
CREATE POLICY "Directors can view all session rollups" ON session_rollups
    FOR SELECT
    USING (
        is_benzdesk_director()
    );

DROP POLICY IF EXISTS "Admins can view all session rollups" ON session_rollups;
CREATE POLICY "Admins can view all session rollups" ON session_rollups
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM employees e 
            WHERE e.id = auth.uid() AND e.role = 'admin'
        )
    );

-- Step 3: Ensure timeline_events has director/admin access
DROP POLICY IF EXISTS "Directors can view all timeline events" ON timeline_events;
CREATE POLICY "Directors can view all timeline events" ON timeline_events
    FOR SELECT
    USING (
        is_benzdesk_director()
    );

DROP POLICY IF EXISTS "Admins can view all timeline events" ON timeline_events;
CREATE POLICY "Admins can view all timeline events" ON timeline_events
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM employees e 
            WHERE e.id = auth.uid() AND e.role = 'admin'
        )
    );

-- Step 4: Ensure location_points has admin access (directors already have from 028)
DROP POLICY IF EXISTS "Admins can view all location points" ON location_points;
CREATE POLICY "Admins can view all location points" ON location_points
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM employees e 
            WHERE e.id = auth.uid() AND e.role = 'admin'
        )
    );

-- Step 5: Also ensure is_benzdesk_director() works for location_points
DROP POLICY IF EXISTS "BenzDesk Directors can view all locations" ON location_points;
CREATE POLICY "BenzDesk Directors can view all locations" ON location_points
    FOR SELECT
    USING (
        is_benzdesk_director()
    );

-- Output success message
DO $$
BEGIN
    RAISE NOTICE 'Migration 029 complete: Added comprehensive RLS policies for timeline page data access';
END $$;
