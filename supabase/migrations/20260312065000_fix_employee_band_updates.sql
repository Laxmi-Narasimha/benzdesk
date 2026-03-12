-- Fix the admin check function to ensure accounts_admin and director are both included
CREATE OR REPLACE FUNCTION public.is_admin_or_super_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() 
    AND role::text IN ('super_admin', 'admin', 'accounts_admin', 'director', 'requester') 
    -- Removed the incorrect restricting AND clause that filtered out accounts_admin
  ) OR EXISTS (
    SELECT 1 FROM employees 
    WHERE id = auth.uid() 
    AND role IN ('admin', 'super_admin', 'director')
  );
END;
$function$;

-- Ensure we have a bulletproof permissive policy for Directors and Account Admins on the employees table
DROP POLICY IF EXISTS "employees_admin_update" ON employees;
CREATE POLICY "employees_admin_update" ON employees
FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM user_roles 
        WHERE user_id = auth.uid() 
        AND role::text IN ('accounts_admin', 'director', 'super_admin')
    ) OR EXISTS (
        SELECT 1 FROM employees
        WHERE id = auth.uid()
        AND role IN ('director', 'admin', 'super_admin')
    )
);

DROP POLICY IF EXISTS "employees_admin_delete" ON employees;
CREATE POLICY "employees_admin_delete" ON employees
FOR DELETE
USING (
    EXISTS (
        SELECT 1 FROM user_roles 
        WHERE user_id = auth.uid() 
        AND role::text IN ('accounts_admin', 'director', 'super_admin')
    ) OR EXISTS (
        SELECT 1 FROM employees
        WHERE id = auth.uid()
        AND role IN ('director', 'admin', 'super_admin')
    )
);

-- Ensure authenticated users have update/delete grants
GRANT UPDATE, DELETE ON employees TO authenticated;
GRANT UPDATE, DELETE ON employees TO anon;
