-- ============================================================================
-- Migration 032: Fix Employees RLS for Admin/Director Panels
-- Fixes: admin/director pages cannot list employees, so timelines/sessions show
-- only current user and appear "missing" even when data exists.
-- ============================================================================

-- Ensure helper exists (created in earlier migrations). If missing, this will
-- fail loudly during migration so it can be corrected.
-- is_admin_or_super_admin() should be SECURITY DEFINER and include director.

DROP POLICY IF EXISTS "Admins can view all employees" ON employees;
CREATE POLICY "Admins can view all employees" ON employees
FOR SELECT
USING (is_admin_or_super_admin());

DO $$
BEGIN
  RAISE NOTICE 'Migration 032 complete: Admins/super_admins/directors can SELECT all employees.';
END $$;

