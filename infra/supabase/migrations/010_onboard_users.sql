-- ============================================================
-- ONBOARDING BENZDESK USERS & ROLE ASSIGNMENT
-- ============================================================

-- 1. Update Role Constraint to allow 'super_admin'
ALTER TABLE employees DROP CONSTRAINT IF EXISTS employees_role_check;
ALTER TABLE employees ADD CONSTRAINT employees_role_check CHECK (role IN ('employee', 'admin', 'super_admin'));

-- 2. Onboard existing auth.users into employees table
-- This inserts all users from auth.users who are not yet in employees table.
-- It attempts to extract a name from metadata, or defaults to the email username.
INSERT INTO employees (id, name, role, is_active, created_at, updated_at)
SELECT 
    au.id,
    COALESCE(au.raw_user_meta_data->>'name', split_part(au.email, '@', 1)),
    'employee', -- Default role
    true,
    COALESCE(au.created_at, NOW()),
    NOW()
FROM auth.users au
WHERE NOT EXISTS (SELECT 1 FROM employees e WHERE e.id = au.id);

-- 3. Assign Roles (Based on User Inputs)
-- Replace the placeholders with actual emails if they differ slightly.

-- Directors / Super Admins
UPDATE employees SET role = 'super_admin' 
WHERE id IN (SELECT id FROM auth.users WHERE email IN ('chaitanya@benzpackaging.com', 'manan@benzpackaging.com')); -- Adjust emails if needed

-- Admins
UPDATE employees SET role = 'admin' 
WHERE id IN (SELECT id FROM auth.users WHERE email IN ('dinesh@benzpackaging.com', 'hr.support@benzpackaging.com')); -- Adjust emails if needed

-- Verification
SELECT e.name, e.role, au.email 
FROM employees e 
JOIN auth.users au ON e.id = au.id
WHERE e.role IN ('admin', 'super_admin');
