-- ============================================================
-- Migration 028: Fix Admin Panel Data Access
-- Adds missing RLS policies for admin users to view all tables
-- ============================================================

-- Problem: Admin users cannot view employees table - only directors can
-- This causes 400 errors when admin tries to load MobiTraq dashboard

-- Step 1: Add admin SELECT policy for employees table
DROP POLICY IF EXISTS "Admins can view all employees" ON employees;
CREATE POLICY "Admins can view all employees" ON employees
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM employees e 
            WHERE e.id = auth.uid() AND e.role = 'admin'
        )
    );

-- Step 2: Add director SELECT policy for employees table (using BenzDesk director check)
DROP POLICY IF EXISTS "Directors can view all employees for mobitraq" ON employees;
CREATE POLICY "Directors can view all employees for mobitraq" ON employees
    FOR SELECT
    USING (
        is_benzdesk_director()
    );

-- Step 3: Ensure location_points has director access
DROP POLICY IF EXISTS "Directors can view all locations" ON location_points;
CREATE POLICY "Directors can view all locations" ON location_points
    FOR SELECT
    USING (
        is_benzdesk_director()
    );

-- Step 4: Ensure expense_claims has proper director access
DROP POLICY IF EXISTS "Directors can view all expenses" ON expense_claims;
CREATE POLICY "Directors can view all expenses" ON expense_claims
    FOR SELECT
    USING (
        is_benzdesk_director()
    );

-- Step 5: Ensure expense_items has director access
DROP POLICY IF EXISTS "Directors can view all expense items" ON expense_items;
CREATE POLICY "Directors can view all expense items" ON expense_items
    FOR SELECT
    USING (
        is_benzdesk_director()
    );

-- Output success message
DO $$
BEGIN
    RAISE NOTICE 'Migration 028 complete: Added admin/director RLS policies for all MobiTraq tables';
END $$;
