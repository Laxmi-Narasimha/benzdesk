-- ============================================================================
-- Migration 033: Fix MobiTraq Alerts/Rollups RLS for Admin + Director Panels
-- Fixes: director/admin UI pages failing to read/acknowledge alerts and read
-- rollups, even when data exists.
-- ============================================================================

-- mobitraq_alerts: allow admins/super_admins/directors (employee role) and
-- BenzDesk directors (user_roles) to read + acknowledge.

DROP POLICY IF EXISTS "Admins view all alerts" ON mobitraq_alerts;
CREATE POLICY "Admins view all alerts" ON mobitraq_alerts
FOR SELECT
USING (is_admin_or_super_admin() OR is_benzdesk_director());

DROP POLICY IF EXISTS "Admins can acknowledge alerts" ON mobitraq_alerts;
CREATE POLICY "Admins can acknowledge alerts" ON mobitraq_alerts
FOR UPDATE
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- daily_rollups: allow directors to read (optional, for future dashboard use)
DROP POLICY IF EXISTS "Directors can view all daily rollups" ON daily_rollups;
CREATE POLICY "Directors can view all daily rollups" ON daily_rollups
FOR SELECT
USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Admins can view all daily rollups" ON daily_rollups;
CREATE POLICY "Admins can view all daily rollups" ON daily_rollups
FOR SELECT
USING (is_admin_or_super_admin());

DO $$
BEGIN
  RAISE NOTICE 'Migration 033 complete: Updated RLS for mobitraq_alerts + daily_rollups.';
END $$;

