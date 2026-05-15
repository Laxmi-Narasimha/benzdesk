-- Replace is_admin_or_super_admin to cover both MobiTraq Employees and BenzDesk User Roles
-- This ensures BenzDesk sysadmins (like Laxmi) can manage MobiTraq Employees even if they aren't drivers.

CREATE OR REPLACE FUNCTION public.is_admin_or_super_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM user_roles 
    WHERE user_id = auth.uid() 
    AND role IN ('super_admin', 'admin', 'director')
  ) OR EXISTS (
    SELECT 1 FROM employees 
    WHERE id = auth.uid() 
    AND role IN ('admin', 'super_admin', 'director')
  );
END;
$function$;
