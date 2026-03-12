-- Restore UPDATE and DELETE privileges on employees table for Admins and Directors

-- 1. Restore Admin Update Permission
DROP POLICY IF EXISTS "employees_admin_update" ON employees;
CREATE POLICY "employees_admin_update" ON employees
FOR UPDATE
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- 2. Restore Admin Delete Permission
DROP POLICY IF EXISTS "employees_admin_delete" ON employees;
CREATE POLICY "employees_admin_delete" ON employees
FOR DELETE
USING (is_admin_or_super_admin() OR is_benzdesk_director());

-- 3. Ensure permissions are granted to the relevant roles
GRANT UPDATE, DELETE ON employees TO authenticated;
GRANT UPDATE, DELETE ON employees TO anon;
