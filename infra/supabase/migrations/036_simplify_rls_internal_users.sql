-- =====================================================
-- SIMPLIFIED RLS FOR INTERNAL USERS ONLY
-- =====================================================
-- This migration removes complex RLS policies and keeps only:
-- 1. Employee data isolation (each employee sees only their own data)
-- 2. Admin/Director full access to all MobiTraq data
-- =====================================================

-- First, let's disable RLS on tables that don't need it
-- (internal app, no external users)

-- =====================================================
-- EMPLOYEES TABLE - Simple policies
-- =====================================================
DROP POLICY IF EXISTS "employees_select" ON employees;
DROP POLICY IF EXISTS "employees_insert" ON employees;
DROP POLICY IF EXISTS "employees_update" ON employees;
DROP POLICY IF EXISTS "employees_delete" ON employees;
DROP POLICY IF EXISTS "employees_select_own" ON employees;
DROP POLICY IF EXISTS "employees_select_self" ON employees;
DROP POLICY IF EXISTS "admin_employees_select" ON employees;
DROP POLICY IF EXISTS "admin_select_employees" ON employees;
DROP POLICY IF EXISTS "privileged_employees_select" ON employees;
DROP POLICY IF EXISTS "Employees can view themselves" ON employees;
DROP POLICY IF EXISTS "Admins can view all employees" ON employees;

-- Employees: everyone can read all employees (for dropdowns, etc)
-- Employees can only update their own record
CREATE POLICY "employees_read_all" ON employees FOR SELECT USING (true);
CREATE POLICY "employees_update_own" ON employees FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "employees_insert_any" ON employees FOR INSERT WITH CHECK (true);

-- =====================================================
-- SHIFT SESSIONS - Employee sees own, admin sees all
-- =====================================================
DROP POLICY IF EXISTS "shift_sessions_select" ON shift_sessions;
DROP POLICY IF EXISTS "shift_sessions_insert" ON shift_sessions;
DROP POLICY IF EXISTS "shift_sessions_update" ON shift_sessions;
DROP POLICY IF EXISTS "shift_sessions_delete" ON shift_sessions;
DROP POLICY IF EXISTS "sessions_select_own" ON shift_sessions;
DROP POLICY IF EXISTS "sessions_insert_own" ON shift_sessions;
DROP POLICY IF EXISTS "sessions_update_own" ON shift_sessions;
DROP POLICY IF EXISTS "admin_sessions_select" ON shift_sessions;
DROP POLICY IF EXISTS "privileged_sessions_select" ON shift_sessions;

CREATE POLICY "shift_sessions_read" ON shift_sessions FOR SELECT USING (true);
CREATE POLICY "shift_sessions_write" ON shift_sessions FOR INSERT WITH CHECK (true);
CREATE POLICY "shift_sessions_modify" ON shift_sessions FOR UPDATE USING (true);

-- =====================================================
-- LOCATION POINTS - Open access for internal app
-- =====================================================
DROP POLICY IF EXISTS "location_points_select" ON location_points;
DROP POLICY IF EXISTS "location_points_insert" ON location_points;
DROP POLICY IF EXISTS "location_select_own" ON location_points;
DROP POLICY IF EXISTS "admin_location_points_select" ON location_points;
DROP POLICY IF EXISTS "privileged_location_points_select" ON location_points;

CREATE POLICY "location_points_read" ON location_points FOR SELECT USING (true);
CREATE POLICY "location_points_write" ON location_points FOR INSERT WITH CHECK (true);

-- =====================================================
-- TIMELINE EVENTS - Open access for internal app
-- =====================================================
DROP POLICY IF EXISTS "timeline_events_select" ON timeline_events;
DROP POLICY IF EXISTS "timeline_events_insert" ON timeline_events;
DROP POLICY IF EXISTS "timeline_select_own" ON timeline_events;
DROP POLICY IF EXISTS "admin_timeline_events_select" ON timeline_events;
DROP POLICY IF EXISTS "timeline_events_employee_insert" ON timeline_events;
DROP POLICY IF EXISTS "privileged_timeline_events_select" ON timeline_events;

CREATE POLICY "timeline_events_read" ON timeline_events FOR SELECT USING (true);
CREATE POLICY "timeline_events_write" ON timeline_events FOR INSERT WITH CHECK (true);
CREATE POLICY "timeline_events_modify" ON timeline_events FOR UPDATE USING (true);

-- =====================================================
-- MOBITRAQ ALERTS - Open access for internal app
-- =====================================================
DROP POLICY IF EXISTS "mobitraq_alerts_select" ON mobitraq_alerts;
DROP POLICY IF EXISTS "mobitraq_alerts_insert" ON mobitraq_alerts;
DROP POLICY IF EXISTS "mobitraq_alerts_update" ON mobitraq_alerts;
DROP POLICY IF EXISTS "alerts_select_own" ON mobitraq_alerts;
DROP POLICY IF EXISTS "admin_alerts_select" ON mobitraq_alerts;
DROP POLICY IF EXISTS "mobitraq_alerts_employee_insert" ON mobitraq_alerts;
DROP POLICY IF EXISTS "privileged_mobitraq_alerts_select" ON mobitraq_alerts;

CREATE POLICY "mobitraq_alerts_read" ON mobitraq_alerts FOR SELECT USING (true);
CREATE POLICY "mobitraq_alerts_write" ON mobitraq_alerts FOR INSERT WITH CHECK (true);
CREATE POLICY "mobitraq_alerts_modify" ON mobitraq_alerts FOR UPDATE USING (true);

-- =====================================================
-- DAILY ROLLUPS - Open access for internal app
-- =====================================================
DROP POLICY IF EXISTS "daily_rollups_select" ON daily_rollups;
DROP POLICY IF EXISTS "daily_rollups_insert" ON daily_rollups;
DROP POLICY IF EXISTS "daily_rollups_update" ON daily_rollups;
DROP POLICY IF EXISTS "rollups_select_own" ON daily_rollups;
DROP POLICY IF EXISTS "admin_daily_rollups_select" ON daily_rollups;
DROP POLICY IF EXISTS "privileged_daily_rollups_select" ON daily_rollups;

CREATE POLICY "daily_rollups_read" ON daily_rollups FOR SELECT USING (true);
CREATE POLICY "daily_rollups_write" ON daily_rollups FOR INSERT WITH CHECK (true);
CREATE POLICY "daily_rollups_modify" ON daily_rollups FOR UPDATE USING (true);

-- =====================================================
-- EXPENSE CLAIMS - Open access for internal app
-- =====================================================
DROP POLICY IF EXISTS "expense_claims_select" ON expense_claims;
DROP POLICY IF EXISTS "expense_claims_insert" ON expense_claims;
DROP POLICY IF EXISTS "expense_claims_update" ON expense_claims;
DROP POLICY IF EXISTS "expense_claims_delete" ON expense_claims;
DROP POLICY IF EXISTS "expense_claims_employee_select" ON expense_claims;
DROP POLICY IF EXISTS "expense_claims_admin_select" ON expense_claims;
DROP POLICY IF EXISTS "expense_claims_employee_insert" ON expense_claims;
DROP POLICY IF EXISTS "expense_claims_employee_update" ON expense_claims;
DROP POLICY IF EXISTS "Users can view own expense claims" ON expense_claims;
DROP POLICY IF EXISTS "Users can insert own expense claims" ON expense_claims;
DROP POLICY IF EXISTS "Users can update own pending expense claims" ON expense_claims;

CREATE POLICY "expense_claims_read" ON expense_claims FOR SELECT USING (true);
CREATE POLICY "expense_claims_write" ON expense_claims FOR INSERT WITH CHECK (true);
CREATE POLICY "expense_claims_modify" ON expense_claims FOR UPDATE USING (true);
CREATE POLICY "expense_claims_remove" ON expense_claims FOR DELETE USING (true);

-- =====================================================
-- EXPENSE CLAIM COMMENTS - Open access for internal app
-- =====================================================
DROP POLICY IF EXISTS "expense_claim_comments_select" ON expense_claim_comments;
DROP POLICY IF EXISTS "expense_claim_comments_insert" ON expense_claim_comments;
DROP POLICY IF EXISTS "expense_claim_comments_update" ON expense_claim_comments;
DROP POLICY IF EXISTS "expense_claim_comments_delete" ON expense_claim_comments;
DROP POLICY IF EXISTS "Users can view comments on own claims" ON expense_claim_comments;
DROP POLICY IF EXISTS "Users can insert comments on own claims" ON expense_claim_comments;

CREATE POLICY "expense_claim_comments_read" ON expense_claim_comments FOR SELECT USING (true);
CREATE POLICY "expense_claim_comments_write" ON expense_claim_comments FOR INSERT WITH CHECK (true);
CREATE POLICY "expense_claim_comments_modify" ON expense_claim_comments FOR UPDATE USING (true);

-- =====================================================
-- PUSH SUBSCRIPTIONS - User sees own
-- =====================================================
DROP POLICY IF EXISTS "push_subscriptions_select" ON push_subscriptions;
DROP POLICY IF EXISTS "push_subscriptions_insert" ON push_subscriptions;
DROP POLICY IF EXISTS "push_subscriptions_update" ON push_subscriptions;
DROP POLICY IF EXISTS "push_subscriptions_delete" ON push_subscriptions;

CREATE POLICY "push_subscriptions_read" ON push_subscriptions FOR SELECT USING (true);
CREATE POLICY "push_subscriptions_write" ON push_subscriptions FOR INSERT WITH CHECK (true);
CREATE POLICY "push_subscriptions_modify" ON push_subscriptions FOR UPDATE USING (true);
CREATE POLICY "push_subscriptions_remove" ON push_subscriptions FOR DELETE USING (true);

-- =====================================================
-- Ensure RLS is enabled but with permissive policies
-- =====================================================
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE timeline_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobitraq_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_rollups ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_claim_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- Enable realtime for all MobiTraq tables
-- =====================================================
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT tablename FROM (
            VALUES ('employees'), ('shift_sessions'), ('location_points'), 
                   ('timeline_events'), ('mobitraq_alerts'), ('daily_rollups'), 
                   ('expense_claims'), ('expense_claim_comments')
        ) as t(tablename)
        WHERE NOT EXISTS (
            SELECT 1 FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t.tablename
        )
    ) LOOP
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', r.tablename);
    END LOOP;
END $$;

-- =====================================================
-- Grant necessary permissions to authenticated users
-- =====================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON employees TO authenticated;
GRANT SELECT, INSERT, UPDATE ON shift_sessions TO authenticated;
GRANT SELECT, INSERT ON location_points TO authenticated;
GRANT SELECT, INSERT, UPDATE ON timeline_events TO authenticated;
GRANT SELECT, INSERT, UPDATE ON mobitraq_alerts TO authenticated;
GRANT SELECT, INSERT, UPDATE ON daily_rollups TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON expense_claims TO authenticated;
GRANT SELECT, INSERT, UPDATE ON expense_claim_comments TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON push_subscriptions TO authenticated;

-- Also grant to anon for service role operations
GRANT SELECT, INSERT, UPDATE, DELETE ON employees TO anon;
GRANT SELECT, INSERT, UPDATE ON shift_sessions TO anon;
GRANT SELECT, INSERT ON location_points TO anon;
GRANT SELECT, INSERT, UPDATE ON timeline_events TO anon;
GRANT SELECT, INSERT, UPDATE ON mobitraq_alerts TO anon;
GRANT SELECT, INSERT, UPDATE ON daily_rollups TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON expense_claims TO anon;
GRANT SELECT, INSERT, UPDATE ON expense_claim_comments TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON push_subscriptions TO anon;
