-- Fix RLS to allow directors to view mobile app data
-- Directors in BenzDesk need to access shift_sessions, expense_claims, etc.

-- Update the is_admin_or_super_admin function to also include directors
CREATE OR REPLACE FUNCTION is_admin_or_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS(
    SELECT 1 FROM employees 
    WHERE id = auth.uid() 
    AND role IN ('admin', 'super_admin', 'director')
  );
$$;

-- Also check the user_roles table for role 'director'
-- This function checks if current user is a director in the benzdesk system
CREATE OR REPLACE FUNCTION is_benzdesk_director()
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS(
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() 
    AND role = 'director'
  );
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION is_benzdesk_director() TO authenticated;

-- Update policies to also allow BenzDesk directors
-- For shift_sessions
DROP POLICY IF EXISTS "Directors can view all sessions" ON shift_sessions;
CREATE POLICY "Directors can view all sessions" ON shift_sessions 
FOR SELECT USING (is_benzdesk_director());

-- For expense_claims
DROP POLICY IF EXISTS "Directors can view all expenses" ON expense_claims;
CREATE POLICY "Directors can view all expenses" ON expense_claims 
FOR SELECT USING (is_benzdesk_director());

DROP POLICY IF EXISTS "Directors can update expenses" ON expense_claims;
CREATE POLICY "Directors can update expenses" ON expense_claims 
FOR UPDATE USING (is_benzdesk_director());

-- For employees table (so directors can see employee names)
DROP POLICY IF EXISTS "Directors can view all employees" ON employees;
CREATE POLICY "Directors can view all employees" ON employees 
FOR SELECT USING (is_benzdesk_director());
