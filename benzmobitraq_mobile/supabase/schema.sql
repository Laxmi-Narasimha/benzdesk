-- ============================================================
-- BenzMobiTraq Supabase Database Schema
-- ============================================================
-- 
-- This file contains the complete database schema for the BenzMobiTraq
-- field-force tracking application.
--
-- Run this in your Supabase SQL Editor to set up the database.
-- 
-- IMPORTANT: Execute this script in order. Some tables have foreign key
-- dependencies on others.
-- ============================================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- ============================================================
-- EMPLOYEES TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    role TEXT NOT NULL DEFAULT 'employee' CHECK (role IN ('employee', 'admin')),
    device_token TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for quick role lookups
CREATE INDEX IF NOT EXISTS idx_employees_role ON employees(role);
CREATE INDEX IF NOT EXISTS idx_employees_active ON employees(is_active);

-- ============================================================
-- SHIFT SESSIONS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS shift_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    end_time TIMESTAMPTZ,
    start_latitude DOUBLE PRECISION,
    start_longitude DOUBLE PRECISION,
    end_latitude DOUBLE PRECISION,
    end_longitude DOUBLE PRECISION,
    total_km DOUBLE PRECISION NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Constraint: end_time must be after start_time when not null
    CONSTRAINT valid_time_range CHECK (end_time IS NULL OR end_time > start_time)
);

-- Indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_sessions_employee ON shift_sessions(employee_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON shift_sessions(status);
CREATE INDEX IF NOT EXISTS idx_sessions_start_time ON shift_sessions(start_time);
CREATE INDEX IF NOT EXISTS idx_sessions_employee_active ON shift_sessions(employee_id, status) WHERE status = 'active';

-- ============================================================
-- LOCATION POINTS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS location_points (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES shift_sessions(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    altitude DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    is_moving BOOLEAN DEFAULT true,
    recorded_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Constraint: valid coordinates
    CONSTRAINT valid_latitude CHECK (latitude >= -90 AND latitude <= 90),
    CONSTRAINT valid_longitude CHECK (longitude >= -180 AND longitude <= 180)
);

-- Indexes for faster queries (critical for performance)
CREATE INDEX IF NOT EXISTS idx_location_session ON location_points(session_id);
CREATE INDEX IF NOT EXISTS idx_location_employee ON location_points(employee_id);
CREATE INDEX IF NOT EXISTS idx_location_recorded_at ON location_points(recorded_at);
CREATE INDEX IF NOT EXISTS idx_location_session_time ON location_points(session_id, recorded_at);

-- ============================================================
-- EMPLOYEE STATES TABLE (for stuck detection)
-- ============================================================

CREATE TABLE IF NOT EXISTS employee_states (
    employee_id UUID PRIMARY KEY REFERENCES employees(id) ON DELETE CASCADE,
    current_session_id UUID REFERENCES shift_sessions(id) ON DELETE SET NULL,
    last_latitude DOUBLE PRECISION,
    last_longitude DOUBLE PRECISION,
    last_accuracy DOUBLE PRECISION,
    last_update TIMESTAMPTZ,
    today_km DOUBLE PRECISION DEFAULT 0,
    today_date DATE DEFAULT CURRENT_DATE,
    
    -- Stuck detection fields
    is_stuck BOOLEAN DEFAULT false,
    stuck_alert_sent BOOLEAN DEFAULT false,
    anchor_latitude DOUBLE PRECISION,
    anchor_longitude DOUBLE PRECISION,
    anchor_time TIMESTAMPTZ,
    
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- NOTIFICATIONS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type TEXT NOT NULL CHECK (type IN ('stuck_alert', 'expense_submitted', 'expense_approved', 'expense_rejected', 'session_started', 'session_ended')),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    recipient_id UUID REFERENCES employees(id) ON DELETE CASCADE,
    recipient_role TEXT,
    is_read BOOLEAN DEFAULT false,
    is_pushed BOOLEAN DEFAULT false,
    push_sent_at TIMESTAMPTZ,
    related_employee_id UUID REFERENCES employees(id) ON DELETE SET NULL,
    related_session_id UUID REFERENCES shift_sessions(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_notifications_recipient ON notifications(recipient_id);
CREATE INDEX IF NOT EXISTS idx_notifications_role ON notifications(recipient_role);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(recipient_id, is_read) WHERE is_read = false;
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);

-- ============================================================
-- EXPENSE CLAIMS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS expense_claims (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    claim_date DATE NOT NULL DEFAULT CURRENT_DATE,
    total_amount DECIMAL(10, 2) NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'approved', 'rejected')),
    notes TEXT,
    rejection_reason TEXT,
    submitted_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ,
    reviewed_by UUID REFERENCES employees(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_expense_claims_employee ON expense_claims(employee_id);
CREATE INDEX IF NOT EXISTS idx_expense_claims_status ON expense_claims(status);
CREATE INDEX IF NOT EXISTS idx_expense_claims_date ON expense_claims(claim_date);

-- ============================================================
-- EXPENSE ITEMS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS expense_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    claim_id UUID NOT NULL REFERENCES expense_claims(id) ON DELETE CASCADE,
    category TEXT NOT NULL CHECK (category IN ('fuel', 'food', 'travel', 'accommodation', 'parking', 'other')),
    amount DECIMAL(10, 2) NOT NULL CHECK (amount > 0),
    description TEXT,
    merchant TEXT,
    receipt_path TEXT,
    expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_expense_items_claim ON expense_items(claim_id);

-- ============================================================
-- APP SETTINGS TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by UUID REFERENCES employees(id) ON DELETE SET NULL
);

-- Insert default settings
INSERT INTO app_settings (key, value, description) VALUES
    ('stuck_radius_meters', '150', 'Radius in meters to consider as "same location" for stuck detection'),
    ('stuck_duration_minutes', '30', 'Duration in minutes before triggering stuck alert'),
    ('max_accuracy_threshold', '50', 'Maximum GPS accuracy threshold in meters'),
    ('min_distance_delta', '10', 'Minimum distance in meters to count as real movement')
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================

-- Enable RLS on all tables
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE employee_states ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

-- EMPLOYEES
-- Employees can read their own profile
CREATE POLICY "Users can view own profile" ON employees
    FOR SELECT USING (auth.uid() = id);

-- Employees can update their own profile
CREATE POLICY "Users can update own profile" ON employees
    FOR UPDATE USING (auth.uid() = id);

-- Admins can view all employees
CREATE POLICY "Admins can view all employees" ON employees
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- SHIFT SESSIONS
-- Employees can view their own sessions
CREATE POLICY "Users can view own sessions" ON shift_sessions
    FOR SELECT USING (employee_id = auth.uid());

-- Employees can create their own sessions
CREATE POLICY "Users can create own sessions" ON shift_sessions
    FOR INSERT WITH CHECK (employee_id = auth.uid());

-- Employees can update their own sessions
CREATE POLICY "Users can update own sessions" ON shift_sessions
    FOR UPDATE USING (employee_id = auth.uid());

-- Admins can view all sessions
CREATE POLICY "Admins can view all sessions" ON shift_sessions
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- LOCATION POINTS
-- Employees can insert their own location points
CREATE POLICY "Users can insert own locations" ON location_points
    FOR INSERT WITH CHECK (employee_id = auth.uid());

-- Employees can view their own location points
CREATE POLICY "Users can view own locations" ON location_points
    FOR SELECT USING (employee_id = auth.uid());

-- Admins can view all location points
CREATE POLICY "Admins can view all locations" ON location_points
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- EMPLOYEE STATES
-- Employees can view and update their own state
CREATE POLICY "Users can view own state" ON employee_states
    FOR SELECT USING (employee_id = auth.uid());

CREATE POLICY "Users can update own state" ON employee_states
    FOR UPDATE USING (employee_id = auth.uid());

CREATE POLICY "Users can insert own state" ON employee_states
    FOR INSERT WITH CHECK (employee_id = auth.uid());

-- Admins can view all states
CREATE POLICY "Admins can view all states" ON employee_states
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- NOTIFICATIONS
-- Users can view their own notifications or admin-role notifications if admin
CREATE POLICY "Users can view own notifications" ON notifications
    FOR SELECT USING (
        recipient_id = auth.uid() 
        OR (
            recipient_role = 'admin' 
            AND EXISTS (
                SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
            )
        )
    );

-- Users can update read status on their notifications
CREATE POLICY "Users can mark own notifications as read" ON notifications
    FOR UPDATE USING (recipient_id = auth.uid() OR recipient_role = 'admin');

-- EXPENSE CLAIMS
-- Employees can manage their own expense claims
CREATE POLICY "Users can view own expenses" ON expense_claims
    FOR SELECT USING (employee_id = auth.uid());

CREATE POLICY "Users can create own expenses" ON expense_claims
    FOR INSERT WITH CHECK (employee_id = auth.uid());

CREATE POLICY "Users can update own expenses" ON expense_claims
    FOR UPDATE USING (employee_id = auth.uid() AND status = 'draft');

CREATE POLICY "Users can delete own draft expenses" ON expense_claims
    FOR DELETE USING (employee_id = auth.uid() AND status = 'draft');

-- Admins can view and update all expenses
CREATE POLICY "Admins can view all expenses" ON expense_claims
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
        )
    );

CREATE POLICY "Admins can update expenses" ON expense_claims
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- EXPENSE ITEMS
-- Employees can manage items on their draft claims
CREATE POLICY "Users can view own expense items" ON expense_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM expense_claims 
            WHERE id = claim_id AND employee_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert own expense items" ON expense_items
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM expense_claims 
            WHERE id = claim_id AND employee_id = auth.uid() AND status = 'draft'
        )
    );

CREATE POLICY "Users can delete own expense items" ON expense_items
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM expense_claims 
            WHERE id = claim_id AND employee_id = auth.uid() AND status = 'draft'
        )
    );

-- Admins can view all expense items
CREATE POLICY "Admins can view all expense items" ON expense_items
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- APP SETTINGS
-- Anyone can read settings
CREATE POLICY "Anyone can read settings" ON app_settings
    FOR SELECT USING (true);

-- Only admins can update settings
CREATE POLICY "Admins can update settings" ON app_settings
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
        )
    );

-- ============================================================
-- STUCK DETECTION FUNCTION (for cron job)
-- ============================================================

CREATE OR REPLACE FUNCTION check_stuck_employees()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    stuck_radius DOUBLE PRECISION;
    stuck_duration INTERVAL;
    employee_record RECORD;
BEGIN
    -- Get settings
    SELECT (value::TEXT)::DOUBLE PRECISION INTO stuck_radius 
    FROM app_settings WHERE key = 'stuck_radius_meters';
    
    SELECT ((value::TEXT)::INTEGER * INTERVAL '1 minute') INTO stuck_duration 
    FROM app_settings WHERE key = 'stuck_duration_minutes';
    
    -- Default values if not set
    stuck_radius := COALESCE(stuck_radius, 150);
    stuck_duration := COALESCE(stuck_duration, INTERVAL '30 minutes');
    
    -- Check each active employee
    FOR employee_record IN 
        SELECT es.employee_id, es.last_latitude, es.last_longitude, 
               es.anchor_latitude, es.anchor_longitude, es.anchor_time,
               es.is_stuck, es.stuck_alert_sent, e.name
        FROM employee_states es
        JOIN employees e ON e.id = es.employee_id
        WHERE es.current_session_id IS NOT NULL
          AND es.last_latitude IS NOT NULL
          AND es.last_longitude IS NOT NULL
    LOOP
        -- Calculate distance from anchor point
        IF employee_record.anchor_latitude IS NOT NULL THEN
            -- Check if still within radius
            IF (
                earth_distance(
                    ll_to_earth(employee_record.last_latitude, employee_record.last_longitude),
                    ll_to_earth(employee_record.anchor_latitude, employee_record.anchor_longitude)
                ) <= stuck_radius
            ) THEN
                -- Still in same area, check duration
                IF (NOW() - employee_record.anchor_time >= stuck_duration) 
                   AND NOT employee_record.stuck_alert_sent THEN
                    -- Send stuck alert
                    INSERT INTO notifications (
                        type, title, body, recipient_role, related_employee_id, data
                    ) VALUES (
                        'stuck_alert',
                        'Employee Stuck Alert',
                        employee_record.name || ' has been stationary for ' || 
                        EXTRACT(MINUTES FROM (NOW() - employee_record.anchor_time))::TEXT || ' minutes',
                        'admin',
                        employee_record.employee_id,
                        jsonb_build_object(
                            'employee_id', employee_record.employee_id,
                            'latitude', employee_record.last_latitude,
                            'longitude', employee_record.last_longitude,
                            'duration_minutes', EXTRACT(MINUTES FROM (NOW() - employee_record.anchor_time))
                        )
                    );
                    
                    -- Mark as stuck and alert sent
                    UPDATE employee_states 
                    SET is_stuck = true, stuck_alert_sent = true, updated_at = NOW()
                    WHERE employee_id = employee_record.employee_id;
                END IF;
            ELSE
                -- Moved outside radius, reset anchor
                UPDATE employee_states 
                SET anchor_latitude = last_latitude,
                    anchor_longitude = last_longitude,
                    anchor_time = NOW(),
                    is_stuck = false,
                    stuck_alert_sent = false,
                    updated_at = NOW()
                WHERE employee_id = employee_record.employee_id;
            END IF;
        ELSE
            -- No anchor set, initialize it
            UPDATE employee_states 
            SET anchor_latitude = last_latitude,
                anchor_longitude = last_longitude,
                anchor_time = NOW(),
                updated_at = NOW()
            WHERE employee_id = employee_record.employee_id;
        END IF;
    END LOOP;
END;
$$;

-- ============================================================
-- SET UP CRON JOB FOR STUCK DETECTION
-- ============================================================

-- Schedule the stuck detection to run every 5 minutes
SELECT cron.schedule(
    'check-stuck-employees',
    '*/5 * * * *',
    'SELECT check_stuck_employees()'
);

-- ============================================================
-- TRIGGERS FOR updated_at
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_employees_updated_at
    BEFORE UPDATE ON employees
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_sessions_updated_at
    BEFORE UPDATE ON shift_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_expense_claims_updated_at
    BEFORE UPDATE ON expense_claims
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_employee_states_updated_at
    BEFORE UPDATE ON employee_states
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_app_settings_updated_at
    BEFORE UPDATE ON app_settings
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================
-- END OF SCHEMA
-- ============================================================
