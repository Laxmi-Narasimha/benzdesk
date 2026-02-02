-- ============================================================================
-- Migration 027: Add Admin RLS Policies for Expenses
-- FIXES CRITICAL ISSUE: Admins cannot view expense claims in admin panel
-- ============================================================================

-- ============================================================================
-- STEP 1: Add Admin SELECT policy for expense_claims
-- ============================================================================

-- Drop if exists to prevent errors
DROP POLICY IF EXISTS "Admins can view all expenses" ON expense_claims;

-- Create policy allowing admins and super_admins to view ALL expense_claims
CREATE POLICY "Admins can view all expenses" ON expense_claims
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM employees 
    WHERE employees.id = auth.uid() 
    AND employees.role IN ('admin', 'super_admin', 'director')
  )
);

-- ============================================================================
-- STEP 2: Add Admin UPDATE policy for expense_claims (approve/reject)
-- ============================================================================

DROP POLICY IF EXISTS "Admins can update all expenses" ON expense_claims;

CREATE POLICY "Admins can update all expenses" ON expense_claims
FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM employees 
    WHERE employees.id = auth.uid() 
    AND employees.role IN ('admin', 'super_admin', 'director')
  )
) WITH CHECK (
  EXISTS (
    SELECT 1 FROM employees 
    WHERE employees.id = auth.uid() 
    AND employees.role IN ('admin', 'super_admin', 'director')
  )
);

-- ============================================================================
-- STEP 3: Add Admin SELECT policy for expense_items
-- ============================================================================

DROP POLICY IF EXISTS "Admins can view all expense items" ON expense_items;

CREATE POLICY "Admins can view all expense items" ON expense_items
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM employees 
    WHERE employees.id = auth.uid() 
    AND employees.role IN ('admin', 'super_admin', 'director')
  )
);

-- ============================================================================
-- STEP 4: Add Admin SELECT policy for shift_sessions (for field tracking)
-- ============================================================================

DROP POLICY IF EXISTS "Admins can view all sessions" ON shift_sessions;

CREATE POLICY "Admins can view all sessions" ON shift_sessions
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM employees 
    WHERE employees.id = auth.uid() 
    AND employees.role IN ('admin', 'super_admin', 'director')
  )
);

-- ============================================================================
-- STEP 5: Add Admin SELECT policy for location_points (for field tracking)
-- ============================================================================

DROP POLICY IF EXISTS "Admins can view all location points" ON location_points;

CREATE POLICY "Admins can view all location points" ON location_points
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM employees 
    WHERE employees.id = auth.uid() 
    AND employees.role IN ('admin', 'super_admin', 'director')
  )
);

-- ============================================================================
-- STEP 6: Add Admin SELECT policy for employees (needed for joins)
-- ============================================================================

DROP POLICY IF EXISTS "Admins can view all employees" ON employees;

CREATE POLICY "Admins can view all employees" ON employees
FOR SELECT USING (
  -- Either viewing own profile OR is an admin
  id = auth.uid() OR
  EXISTS (
    SELECT 1 FROM employees e 
    WHERE e.id = auth.uid() 
    AND e.role IN ('admin', 'super_admin', 'director')
  )
);

-- ============================================================================
-- SUCCESS
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Migration 027 completed successfully!';
  RAISE NOTICE '   - Added admin SELECT policy for expense_claims';
  RAISE NOTICE '   - Added admin UPDATE policy for expense_claims';
  RAISE NOTICE '   - Added admin SELECT policy for expense_items';
  RAISE NOTICE '   - Added admin SELECT policy for shift_sessions';
  RAISE NOTICE '   - Added admin SELECT policy for location_logs';
  RAISE NOTICE '   - Added admin SELECT policy for employees';
END $$;
