-- 1. Fix the global admin bypass function to safely cast user_roles to text to avoid Enum crashes
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
    AND role::text IN ('super_admin', 'admin', 'director') -- ensuring we only match the privileged ones
  ) OR EXISTS (
    SELECT 1 FROM employees 
    WHERE id = auth.uid() 
    AND role IN ('admin', 'super_admin', 'director')
  );
END;
$function$;

-- 2. Fix the `requests` table RLS policy to allow `super_admin` to actually UPDATE the request and avoid a 404
DROP POLICY IF EXISTS "Admins can update requests" ON requests;

CREATE POLICY "Admins can update requests"
  ON requests
  FOR UPDATE
  USING (
    is_admin_or_super_admin() OR 
    has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
  )
  WITH CHECK (
    is_admin_or_super_admin() OR 
    has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
  );

-- 3. Just to be absolutely safe, let's also ensure `super_admin` can insert and select requests
DROP POLICY IF EXISTS "Admins can create requests" ON requests;
CREATE POLICY "Admins can create requests"
  ON requests
  FOR INSERT
  WITH CHECK (
    is_admin_or_super_admin() OR 
    has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
  );

DROP POLICY IF EXISTS "Admins can read all requests" ON requests;
CREATE POLICY "Admins can read all requests"
  ON requests
  FOR SELECT
  USING (
    is_admin_or_super_admin() OR 
    has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
  );
