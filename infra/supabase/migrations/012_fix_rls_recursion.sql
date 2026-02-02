-- Fix RLS infinite recursion on employees table
-- The problem: Policies on 'employees' table cannot query 'employees' table
-- The solution: Use a SECURITY DEFINER function that bypasses RLS

-- Step 1: Create a helper function to get current user's role (bypasses RLS)
CREATE OR REPLACE FUNCTION get_my_employee_role()
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role::text FROM employees WHERE id = auth.uid() LIMIT 1;
$$;

-- Step 2: Create a function to check if current user is admin/super_admin
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
    AND role IN ('admin', 'super_admin')
  );
$$;

-- Step 3: Drop all problematic policies that cause recursion
DROP POLICY IF EXISTS "Admins can view all employees" ON employees;
DROP POLICY IF EXISTS "Users can view own record" ON employees;
DROP POLICY IF EXISTS "Admins can update employees" ON employees;

-- Step 4: Recreate policies using the SECURITY DEFINER function
-- Employees can always read their own record
CREATE POLICY "Users can view own record" 
ON employees 
FOR SELECT 
USING (id = auth.uid());

-- Admins/Super Admins can view ALL employees (using helper function to avoid recursion)
CREATE POLICY "Admins can view all employees" 
ON employees 
FOR SELECT 
USING (is_admin_or_super_admin());

-- Admins can update employees
CREATE POLICY "Admins can update employees" 
ON employees 
FOR UPDATE 
USING (is_admin_or_super_admin());

-- Step 5: Fix the other tables that also might have this issue
-- (These don't cause recursion but let's use consistent approach)

-- Shift Sessions
DROP POLICY IF EXISTS "Admins can view all sessions" ON shift_sessions;
CREATE POLICY "Admins can view all sessions" ON shift_sessions 
FOR SELECT USING (is_admin_or_super_admin());

-- Location Points
DROP POLICY IF EXISTS "Admins can view all locations" ON location_points;
CREATE POLICY "Admins can view all locations" ON location_points 
FOR SELECT USING (is_admin_or_super_admin());

-- Employee States
DROP POLICY IF EXISTS "Admins can view all states" ON employee_states;
CREATE POLICY "Admins can view all states" ON employee_states 
FOR SELECT USING (is_admin_or_super_admin());

-- Expense Claims
DROP POLICY IF EXISTS "Admins can view all expenses" ON expense_claims;
CREATE POLICY "Admins can view all expenses" ON expense_claims 
FOR SELECT USING (is_admin_or_super_admin());

DROP POLICY IF EXISTS "Admins can update expenses" ON expense_claims;
CREATE POLICY "Admins can update expenses" ON expense_claims 
FOR UPDATE USING (is_admin_or_super_admin());

-- Expense Items
DROP POLICY IF EXISTS "Admins can view all expense items" ON expense_items;
CREATE POLICY "Admins can view all expense items" ON expense_items 
FOR SELECT USING (is_admin_or_super_admin());

-- Mobile App Settings
DROP POLICY IF EXISTS "Admins can update settings" ON mobile_app_settings;
CREATE POLICY "Admins can update settings" ON mobile_app_settings 
FOR UPDATE USING (is_admin_or_super_admin());

-- Mobile Notifications
DROP POLICY IF EXISTS "Users can view own notifications" ON mobile_notifications;
CREATE POLICY "Users can view own notifications" ON mobile_notifications
FOR SELECT USING (
    recipient_id = auth.uid() 
    OR (recipient_role IN ('admin', 'super_admin') AND is_admin_or_super_admin())
);

DROP POLICY IF EXISTS "Users can mark own notifications as read" ON mobile_notifications;
CREATE POLICY "Users can mark own notifications as read" ON mobile_notifications
FOR UPDATE USING (recipient_id = auth.uid() OR is_admin_or_super_admin());

-- Grant execute permission on the helper functions
GRANT EXECUTE ON FUNCTION get_my_employee_role() TO authenticated;
GRANT EXECUTE ON FUNCTION is_admin_or_super_admin() TO authenticated;
