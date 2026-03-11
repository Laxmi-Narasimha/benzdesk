-- ============================================================================
-- Migration 035: Security Hardening (Employee Role Escalation)
-- Fixes two critical privilege-escalation vectors:
-- 1) Prevent users from self-assigning employee.role via auth.user_metadata on signup.
-- 2) Prevent users from updating their own employees.role to 'admin' via RLS.
-- ============================================================================

-- ============================================================================
-- STEP 1: Lock down handle_new_user() to always create employee with role=employee
-- NOTE: Admin/director roles must be assigned by a trusted admin process.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.employees (id, name, phone, role)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'name',
      NEW.raw_user_meta_data->>'full_name',
      split_part(NEW.email, '@', 1),
      'Employee'
    ),
    COALESCE(NEW.phone, NEW.raw_user_meta_data->>'phone'),
    'employee'
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    phone = COALESCE(EXCLUDED.phone, employees.phone),
    updated_at = NOW();

  INSERT INTO public.employee_states (employee_id)
  VALUES (NEW.id)
  ON CONFLICT (employee_id) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING 'Failed to create employee for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

-- Keep function executable by service_role (as before)
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

-- ============================================================================
-- STEP 2: Harden employees UPDATE policy to forbid role changes by normal users
-- Uses get_my_employee_role() (SECURITY DEFINER) to compare against current role.
-- ============================================================================

DROP POLICY IF EXISTS "Users can update own profile" ON employees;
CREATE POLICY "Users can update own profile" ON employees
FOR UPDATE
USING (id = auth.uid())
WITH CHECK (
  id = auth.uid()
  AND role = get_my_employee_role()
);

DO $$
BEGIN
  RAISE NOTICE 'Migration 035 complete: handle_new_user role locked to employee; users cannot self-promote via employees.role.';
  RAISE NOTICE 'Action: audit employees with elevated roles (admin) and confirm they are legitimate.';
END $$;

