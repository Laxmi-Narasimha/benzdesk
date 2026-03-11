-- ============================================================================
-- Migration 034: Privileged SELECT Policies for MobiTraq Data
-- Fixes: missing data in admin/director panels due to inconsistent RLS across
-- tables (admin vs super_admin vs director/user_roles).
--
-- Rule: privileged users (admin/super_admin/director in employees OR BenzDesk
-- director in user_roles) can SELECT across key MobiTraq tables.
-- ============================================================================

-- Ensure helper functions exist (created in earlier migrations):
-- - is_admin_or_super_admin()
-- - is_benzdesk_director()

-- employees (needed for employee pickers)
DROP POLICY IF EXISTS "Privileged can view all employees" ON employees;
CREATE POLICY "Privileged can view all employees" ON employees
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- shift_sessions
DROP POLICY IF EXISTS "Privileged can view all sessions" ON shift_sessions;
CREATE POLICY "Privileged can view all sessions" ON shift_sessions
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- location_points
DROP POLICY IF EXISTS "Privileged can view all location points" ON location_points;
CREATE POLICY "Privileged can view all location points" ON location_points
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- timeline_events
DROP POLICY IF EXISTS "Privileged can view all timeline events" ON timeline_events;
CREATE POLICY "Privileged can view all timeline events" ON timeline_events
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- session_rollups
DROP POLICY IF EXISTS "Privileged can view all session rollups" ON session_rollups;
CREATE POLICY "Privileged can view all session rollups" ON session_rollups
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- daily_rollups
DROP POLICY IF EXISTS "Privileged can view all daily rollups" ON daily_rollups;
CREATE POLICY "Privileged can view all daily rollups" ON daily_rollups
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- mobitraq_alerts
DROP POLICY IF EXISTS "Privileged can view all alerts" ON mobitraq_alerts;
CREATE POLICY "Privileged can view all alerts" ON mobitraq_alerts
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- expense_claims + expense_items (used by director/admin expense panel)
DROP POLICY IF EXISTS "Privileged can view all expense claims" ON expense_claims;
CREATE POLICY "Privileged can view all expense claims" ON expense_claims
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

DROP POLICY IF EXISTS "Privileged can view all expense items" ON expense_items;
CREATE POLICY "Privileged can view all expense items" ON expense_items
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

DO $$
BEGIN
  RAISE NOTICE 'Migration 034 complete: Added privileged SELECT policies for MobiTraq tables.';
END $$;

