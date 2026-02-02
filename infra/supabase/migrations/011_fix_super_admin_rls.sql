-- Fix RLS policies to allow 'super_admin' to have the same access as 'admin'
-- This ensures Directors (Chaitanya, Manan) can view all data.

-- EMPLOYEES
DROP POLICY IF EXISTS "Admins can view all employees" ON employees;
CREATE POLICY "Admins can view all employees" ON employees FOR SELECT USING (EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin')));

-- SHIFT SESSIONS
DROP POLICY IF EXISTS "Admins can view all sessions" ON shift_sessions;
CREATE POLICY "Admins can view all sessions" ON shift_sessions FOR SELECT USING (EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin')));

-- LOCATION POINTS
DROP POLICY IF EXISTS "Admins can view all locations" ON location_points;
CREATE POLICY "Admins can view all locations" ON location_points FOR SELECT USING (EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin')));

-- EMPLOYEE STATES
DROP POLICY IF EXISTS "Admins can view all states" ON employee_states;
CREATE POLICY "Admins can view all states" ON employee_states FOR SELECT USING (EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin')));

-- MOBILE NOTIFICATIONS
DROP POLICY IF EXISTS "Users can view own notifications" ON mobile_notifications;
CREATE POLICY "Users can view own notifications" ON mobile_notifications
    FOR SELECT USING (
        recipient_id = auth.uid() 
        OR (
            recipient_role IN ('admin', 'super_admin')
            AND EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
        )
    );

DROP POLICY IF EXISTS "Users can mark own notifications as read" ON mobile_notifications;
CREATE POLICY "Users can mark own notifications as read" ON mobile_notifications
    FOR UPDATE USING (recipient_id = auth.uid() OR recipient_role IN ('admin', 'super_admin'));

-- EXPENSE CLAIMS
DROP POLICY IF EXISTS "Admins can view all expenses" ON expense_claims;
CREATE POLICY "Admins can view all expenses" ON expense_claims FOR SELECT USING (EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin')));

DROP POLICY IF EXISTS "Admins can update expenses" ON expense_claims;
CREATE POLICY "Admins can update expenses" ON expense_claims FOR UPDATE USING (EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin')));

-- EXPENSE ITEMS
DROP POLICY IF EXISTS "Admins can view all expense items" ON expense_items;
CREATE POLICY "Admins can view all expense items" ON expense_items FOR SELECT USING (EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin')));

-- MOBILE APP SETTINGS
DROP POLICY IF EXISTS "Admins can update settings" ON mobile_app_settings;
CREATE POLICY "Admins can update settings" ON mobile_app_settings
    FOR UPDATE USING (EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin')));
