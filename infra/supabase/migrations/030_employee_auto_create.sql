-- ============================================================
-- Migration 030: Auto-Create Employee on Auth Signup
-- Fixes: Empty employees table causing all data sync to fail
-- Date: 2026-02-03
-- ============================================================

-- ============================================================
-- STEP 1: Function to create employee on auth signup
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Create employee record from auth user data
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
    COALESCE(NEW.raw_user_meta_data->>'role', 'employee')
  )
  ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    phone = COALESCE(EXCLUDED.phone, employees.phone),
    updated_at = NOW();
  
  -- Initialize employee state for real-time tracking
  INSERT INTO public.employee_states (employee_id)
  VALUES (NEW.id)
  ON CONFLICT (employee_id) DO NOTHING;
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Log error but don't fail auth
    RAISE WARNING 'Failed to create employee for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

-- ============================================================
-- STEP 2: Create trigger on auth.users
-- ============================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- STEP 3: Backfill existing auth users into employees
-- ============================================================

-- Insert missing employees from auth.users
INSERT INTO employees (id, name, phone, role)
SELECT 
  u.id,
  COALESCE(
    u.raw_user_meta_data->>'name',
    u.raw_user_meta_data->>'full_name',
    split_part(u.email, '@', 1),
    'Employee'
  ),
  COALESCE(u.phone, u.raw_user_meta_data->>'phone'),
  COALESCE(u.raw_user_meta_data->>'role', 'employee')
FROM auth.users u
WHERE u.id NOT IN (SELECT id FROM employees)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- STEP 4: Backfill employee_states for all employees
-- ============================================================

INSERT INTO employee_states (employee_id)
SELECT id FROM employees
WHERE id NOT IN (SELECT employee_id FROM employee_states)
ON CONFLICT (employee_id) DO NOTHING;

-- ============================================================
-- STEP 5: Grant execute permission on function
-- ============================================================

GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

-- ============================================================
-- SUCCESS
-- ============================================================

DO $$ 
DECLARE
  emp_count INTEGER;
  state_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO emp_count FROM employees;
  SELECT COUNT(*) INTO state_count FROM employee_states;
  RAISE NOTICE 'Migration 030 completed successfully.';
  RAISE NOTICE '   - Created trigger: on_auth_user_created';
  RAISE NOTICE '   - Employees now: % records', emp_count;
  RAISE NOTICE '   - Employee states: % records', state_count;
  RAISE NOTICE '';
  RAISE NOTICE 'Mobile app should now be able to sync data.';
END $$;
