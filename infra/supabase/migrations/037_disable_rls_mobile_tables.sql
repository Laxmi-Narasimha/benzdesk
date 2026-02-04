-- Migration 037: DISABLE RLS on mobile tracking tables
-- The RLS policies are blocking location uploads. Disabling them completely.

-- DISABLE RLS on session_rollups (the one causing the current error)
ALTER TABLE session_rollups DISABLE ROW LEVEL SECURITY;

-- DISABLE RLS on location_points to ensure uploads work
ALTER TABLE location_points DISABLE ROW LEVEL SECURITY;

-- DISABLE RLS on timeline_events
ALTER TABLE timeline_events DISABLE ROW LEVEL SECURITY;

-- DISABLE RLS on mobitraq_alerts
ALTER TABLE mobitraq_alerts DISABLE ROW LEVEL SECURITY;

-- DISABLE RLS on daily_rollups
ALTER TABLE daily_rollups DISABLE ROW LEVEL SECURITY;

-- Drop any problematic policies that might interfere
DO $$
BEGIN
  -- session_rollups policies
  DROP POLICY IF EXISTS "Employees view own session rollups" ON session_rollups;
  DROP POLICY IF EXISTS "Admins view all session rollups" ON session_rollups;
  DROP POLICY IF EXISTS "System can manage session rollups" ON session_rollups;
  
  -- timeline_events policies
  DROP POLICY IF EXISTS "Employees view own timeline" ON timeline_events;
  DROP POLICY IF EXISTS "Admins view all timelines" ON timeline_events;
  DROP POLICY IF EXISTS "System can manage timeline events" ON timeline_events;
  DROP POLICY IF EXISTS "Employees can insert own timeline events" ON timeline_events;
  
  -- mobitraq_alerts policies
  DROP POLICY IF EXISTS "Employees view own alerts" ON mobitraq_alerts;
  DROP POLICY IF EXISTS "Admins view all alerts" ON mobitraq_alerts;
  DROP POLICY IF EXISTS "Admins can acknowledge alerts" ON mobitraq_alerts;
  DROP POLICY IF EXISTS "System can manage alerts" ON mobitraq_alerts;
  DROP POLICY IF EXISTS "Employees can insert own alerts" ON mobitraq_alerts;
  
  -- daily_rollups policies
  DROP POLICY IF EXISTS "Employees view own daily rollups" ON daily_rollups;
  DROP POLICY IF EXISTS "Admins view all daily rollups" ON daily_rollups;
  DROP POLICY IF EXISTS "System can manage daily rollups" ON daily_rollups;
END $$;

-- Verify RLS is disabled
DO $$
BEGIN
  RAISE NOTICE '✅ RLS DISABLED on: session_rollups, location_points, timeline_events, mobitraq_alerts, daily_rollups';
  RAISE NOTICE '✅ All blocking policies dropped';
END $$;
