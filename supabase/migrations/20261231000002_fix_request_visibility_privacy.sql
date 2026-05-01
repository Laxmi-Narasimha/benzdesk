-- ============================================================================
-- BenzDesk Database Schema - Migration 050: Fix Request Visibility Privacy Leak
-- This migration fixes a critical privacy issue where all users could see all
-- requests due to an overly permissive admin bypass function and a view that
-- bypassed RLS by missing the security_invoker flag.
-- ============================================================================

-- Force PostgREST schema reload so we start fresh
NOTIFY pgrst, 'reload schema';

-------------------------------------------------------------------------------
-- 1. FIX THE ADMIN BYPASS FUNCTION
-------------------------------------------------------------------------------
-- The previous function in 20260312055040_global_admin_bypass.sql wrongly
-- checked the `employees` table for role='admin', which granted admin access
-- to mobile app users who shouldn't have BenzDesk admin access.
-- We restrict this strictly to `user_roles` now.

CREATE OR REPLACE FUNCTION public.is_admin_or_super_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() 
    AND role::text IN ('super_admin', 'admin', 'accounts_admin', 'director') 
  );
END;
$function$;

-------------------------------------------------------------------------------
-- 2. RESTORE STRICT RLS ON REQUESTS TABLE
-------------------------------------------------------------------------------
ALTER TABLE requests ENABLE ROW LEVEL SECURITY;

-- Drop any existing overly-permissive select policies that might have leaked in
DROP POLICY IF EXISTS "requests_read_all" ON requests;
DROP POLICY IF EXISTS "Requests are viewable by everyone" ON requests;
DROP POLICY IF EXISTS "requests_select" ON requests;

-- Recreate the correct access policies:
-- Requesters only see their own
DROP POLICY IF EXISTS "Requesters can read own requests" ON requests;
CREATE POLICY "Requesters can read own requests"
  ON requests
  FOR SELECT
  USING (created_by = auth.uid());

-- Admins/Directors see all
DROP POLICY IF EXISTS "Admins can read all requests" ON requests;
CREATE POLICY "Admins can read all requests"
  ON requests
  FOR SELECT
  USING (is_admin_or_super_admin());

-------------------------------------------------------------------------------
-- 3. FIX THE View Bypassing RLS
-------------------------------------------------------------------------------
-- The requests_with_creator view was missing `security_invoker = true`.
-- Without this, the view executes with the privileges of its creator (superuser),
-- completely bypassing the RLS policies on the underlying `requests` table.

DROP VIEW IF EXISTS requests_with_creator;

CREATE OR REPLACE VIEW requests_with_creator WITH (security_invoker = on) AS
  SELECT r.*,
         u.email AS creator_email,
         e.name AS creator_name
  FROM requests r
  LEFT JOIN auth.users u ON r.created_by = u.id
  LEFT JOIN employees e ON r.created_by = e.id;

-- Force postgrest reload again to apply security_invoker view
NOTIFY pgrst, 'reload schema';
