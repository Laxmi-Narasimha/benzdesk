-- ============================================================
-- Migration 032: Complete MobiTraq Schema Fix
-- Fixes missing columns, storage bucket, and RLS policies
-- ============================================================

-- ============================================================
-- 1. ADD MISSING COLUMNS TO location_points
-- ============================================================

-- Add hash column for idempotent upserts (mobile app uses this)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'location_points' AND column_name = 'hash'
    ) THEN
        ALTER TABLE location_points ADD COLUMN hash TEXT;
    END IF;
END $$;

-- Add address column (for reverse geocoded addresses)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'location_points' AND column_name = 'address'
    ) THEN
        ALTER TABLE location_points ADD COLUMN address TEXT;
    END IF;
END $$;

-- Add provider column (gps/network/fused)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'location_points' AND column_name = 'provider'
    ) THEN
        ALTER TABLE location_points ADD COLUMN provider TEXT;
    END IF;
END $$;

-- Create unique index on hash for upsert operations
DROP INDEX IF EXISTS idx_location_points_hash;
CREATE UNIQUE INDEX idx_location_points_hash ON location_points(hash) WHERE hash IS NOT NULL;

-- ============================================================
-- 2. ADD MISSING COLUMNS TO employees
-- ============================================================

-- Add email column
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'employees' AND column_name = 'email'
    ) THEN
        ALTER TABLE employees ADD COLUMN email TEXT;
    END IF;
END $$;

-- Update employees with email from auth.users
UPDATE employees e
SET email = u.email
FROM auth.users u
WHERE e.id = u.id AND e.email IS NULL;

-- ============================================================
-- 3. ADD MISSING COLUMNS TO shift_sessions
-- ============================================================

-- Add session_name column for named sessions
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'shift_sessions' AND column_name = 'session_name'
    ) THEN
        ALTER TABLE shift_sessions ADD COLUMN session_name TEXT;
    END IF;
END $$;

-- Add start_address and end_address columns
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'shift_sessions' AND column_name = 'start_address'
    ) THEN
        ALTER TABLE shift_sessions ADD COLUMN start_address TEXT;
    END IF;
    
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'shift_sessions' AND column_name = 'end_address'
    ) THEN
        ALTER TABLE shift_sessions ADD COLUMN end_address TEXT;
    END IF;
END $$;

-- ============================================================
-- 4. CREATE/UPDATE STORAGE BUCKET FOR RECEIPTS
-- ============================================================

-- Create bucket if not exists
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'benzmobitraq-receipts',
    'benzmobitraq-receipts',
    false,
    10485760, -- 10MB max file size
    ARRAY[
        'image/jpeg',
        'image/png',
        'image/gif',
        'image/webp',
        'image/heic',
        'image/heif',
        'application/pdf',
        'application/vnd.ms-excel',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ]
)
ON CONFLICT (id) DO UPDATE SET
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================================
-- 5. FIX STORAGE RLS POLICIES
-- ============================================================

-- Drop existing policies to recreate them properly
DROP POLICY IF EXISTS "Users can upload own receipts" ON storage.objects;
DROP POLICY IF EXISTS "Users can view own receipts" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own receipts" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own receipts" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated can upload receipts" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated can view receipts" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated can delete receipts" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated can update receipts" ON storage.objects;

-- Create proper storage policies
CREATE POLICY "Authenticated can upload receipts"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'benzmobitraq-receipts'
);

CREATE POLICY "Authenticated can view receipts"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'benzmobitraq-receipts'
);

CREATE POLICY "Authenticated can delete receipts"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'benzmobitraq-receipts'
);

CREATE POLICY "Authenticated can update receipts"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'benzmobitraq-receipts')
WITH CHECK (bucket_id = 'benzmobitraq-receipts');

-- ============================================================
-- 6. FIX location_points INSERT RLS
-- Allow upsert by having proper INSERT policy
-- ============================================================

-- Drop existing insert policy
DROP POLICY IF EXISTS "Users can insert own locations" ON location_points;
DROP POLICY IF EXISTS "Employees can insert own locations" ON location_points;

-- Create proper insert policy that allows upsert
CREATE POLICY "Employees can insert own locations" ON location_points
    FOR INSERT WITH CHECK (employee_id = auth.uid());

-- Allow UPDATE for upsert on conflict
DROP POLICY IF EXISTS "Employees can update own locations" ON location_points;
CREATE POLICY "Employees can update own locations" ON location_points
    FOR UPDATE USING (employee_id = auth.uid());

-- ============================================================
-- 7. ADD TRIGGER TO SET server_received_at TIMESTAMP
-- ============================================================

-- Add server_received_at column if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'location_points' AND column_name = 'server_received_at'
    ) THEN
        ALTER TABLE location_points ADD COLUMN server_received_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- Create trigger to set server_received_at on insert
CREATE OR REPLACE FUNCTION set_server_received_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.server_received_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_location_server_received ON location_points;
CREATE TRIGGER set_location_server_received
    BEFORE INSERT ON location_points
    FOR EACH ROW
    EXECUTE FUNCTION set_server_received_at();

-- ============================================================
-- 8. ADD session_rollups TABLE IF NOT EXISTS
-- ============================================================

CREATE TABLE IF NOT EXISTS session_rollups (
    session_id UUID PRIMARY KEY REFERENCES shift_sessions(id) ON DELETE CASCADE,
    distance_km DOUBLE PRECISION DEFAULT 0,
    point_count INTEGER DEFAULT 0,
    duration_minutes INTEGER DEFAULT 0,
    avg_speed_kmh DOUBLE PRECISION,
    max_speed_kmh DOUBLE PRECISION,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE session_rollups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own session rollups" ON session_rollups;
CREATE POLICY "Users can view own session rollups" ON session_rollups
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM shift_sessions s 
            WHERE s.id = session_rollups.session_id 
            AND s.employee_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Directors can view all session rollups" ON session_rollups;
CREATE POLICY "Directors can view all session rollups" ON session_rollups
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM user_roles WHERE user_id = auth.uid() AND role = 'director')
        OR EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin')
    );

DROP POLICY IF EXISTS "Authenticated can view session rollups" ON session_rollups;
CREATE POLICY "Authenticated can view session rollups" ON session_rollups
    FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 9. ADD daily_rollups TABLE IF NOT EXISTS
-- ============================================================

CREATE TABLE IF NOT EXISTS daily_rollups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    day DATE NOT NULL,
    distance_km DOUBLE PRECISION DEFAULT 0,
    session_count INTEGER DEFAULT 0,
    point_count INTEGER DEFAULT 0,
    total_duration_minutes INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(employee_id, day)
);

CREATE INDEX IF NOT EXISTS idx_daily_rollups_employee ON daily_rollups(employee_id);
CREATE INDEX IF NOT EXISTS idx_daily_rollups_day ON daily_rollups(day);

ALTER TABLE daily_rollups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own daily rollups" ON daily_rollups;
CREATE POLICY "Users can view own daily rollups" ON daily_rollups
    FOR SELECT USING (employee_id = auth.uid());

DROP POLICY IF EXISTS "Authenticated can view daily rollups" ON daily_rollups;
CREATE POLICY "Authenticated can view daily rollups" ON daily_rollups
    FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 10. ADD timeline_events TABLE IF NOT EXISTS
-- ============================================================

CREATE TABLE IF NOT EXISTS timeline_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES shift_sessions(id) ON DELETE CASCADE,
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN ('stop', 'move', 'start', 'end')),
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    duration_min DOUBLE PRECISION,
    distance_km DOUBLE PRECISION,
    center_lat DOUBLE PRECISION,
    center_lng DOUBLE PRECISION,
    address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_timeline_events_session ON timeline_events(session_id);
CREATE INDEX IF NOT EXISTS idx_timeline_events_employee ON timeline_events(employee_id);
CREATE INDEX IF NOT EXISTS idx_timeline_events_type ON timeline_events(event_type);

ALTER TABLE timeline_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own timeline events" ON timeline_events;
CREATE POLICY "Users can view own timeline events" ON timeline_events
    FOR SELECT USING (employee_id = auth.uid());

DROP POLICY IF EXISTS "Authenticated can view timeline events" ON timeline_events;
CREATE POLICY "Authenticated can view timeline events" ON timeline_events
    FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 11. ADD mobitraq_alerts TABLE IF NOT EXISTS
-- ============================================================

CREATE TABLE IF NOT EXISTS mobitraq_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    alert_type TEXT NOT NULL CHECK (alert_type IN ('stuck', 'low_battery', 'gps_lost', 'session_timeout', 'geofence_exit')),
    message TEXT NOT NULL,
    severity TEXT NOT NULL DEFAULT 'warning' CHECK (severity IN ('info', 'warning', 'critical')),
    is_read BOOLEAN DEFAULT false,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mobitraq_alerts_employee ON mobitraq_alerts(employee_id);
CREATE INDEX IF NOT EXISTS idx_mobitraq_alerts_type ON mobitraq_alerts(alert_type);
CREATE INDEX IF NOT EXISTS idx_mobitraq_alerts_unread ON mobitraq_alerts(is_read) WHERE is_read = false;

ALTER TABLE mobitraq_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own alerts" ON mobitraq_alerts;
CREATE POLICY "Users can view own alerts" ON mobitraq_alerts
    FOR SELECT USING (employee_id = auth.uid());

DROP POLICY IF EXISTS "Authenticated can view alerts" ON mobitraq_alerts;
CREATE POLICY "Authenticated can view alerts" ON mobitraq_alerts
    FOR SELECT TO authenticated USING (true);

-- ============================================================
-- 12. CREATE FUNCTION TO CALCULATE SESSION DISTANCE
-- ============================================================

CREATE OR REPLACE FUNCTION calculate_session_distance(p_session_id UUID)
RETURNS DOUBLE PRECISION
LANGUAGE plpgsql
AS $$
DECLARE
    total_distance DOUBLE PRECISION := 0;
    prev_lat DOUBLE PRECISION;
    prev_lng DOUBLE PRECISION;
    point_record RECORD;
BEGIN
    FOR point_record IN 
        SELECT latitude, longitude 
        FROM location_points 
        WHERE session_id = p_session_id 
        ORDER BY recorded_at
    LOOP
        IF prev_lat IS NOT NULL AND prev_lng IS NOT NULL THEN
            -- Haversine formula for distance in km
            total_distance := total_distance + (
                6371 * acos(
                    cos(radians(prev_lat)) * cos(radians(point_record.latitude)) * 
                    cos(radians(point_record.longitude) - radians(prev_lng)) + 
                    sin(radians(prev_lat)) * sin(radians(point_record.latitude))
                )
            );
        END IF;
        prev_lat := point_record.latitude;
        prev_lng := point_record.longitude;
    END LOOP;
    
    RETURN COALESCE(total_distance, 0);
END;
$$;

-- ============================================================
-- 13. CREATE TRIGGER TO UPDATE session_rollups ON LOCATION INSERT
-- ============================================================

CREATE OR REPLACE FUNCTION update_session_rollup_on_location()
RETURNS TRIGGER AS $$
DECLARE
    point_ct INTEGER;
    dist_km DOUBLE PRECISION;
BEGIN
    -- Count points for this session
    SELECT COUNT(*) INTO point_ct FROM location_points WHERE session_id = NEW.session_id;
    
    -- Calculate distance
    dist_km := calculate_session_distance(NEW.session_id);
    
    -- Upsert rollup
    INSERT INTO session_rollups (session_id, point_count, distance_km, updated_at)
    VALUES (NEW.session_id, point_ct, dist_km, NOW())
    ON CONFLICT (session_id) DO UPDATE SET
        point_count = EXCLUDED.point_count,
        distance_km = EXCLUDED.distance_km,
        updated_at = NOW();
    
    -- Also update shift_sessions total_km
    UPDATE shift_sessions 
    SET total_km = dist_km, updated_at = NOW()
    WHERE id = NEW.session_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_rollup_on_location_insert ON location_points;
CREATE TRIGGER update_rollup_on_location_insert
    AFTER INSERT ON location_points
    FOR EACH ROW
    EXECUTE FUNCTION update_session_rollup_on_location();

-- ============================================================
-- 14. GRANT NECESSARY PERMISSIONS
-- ============================================================

-- Grant usage on schema to authenticated users (if not already done)
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA storage TO authenticated;

-- Grant table permissions
GRANT ALL ON location_points TO authenticated;
GRANT ALL ON shift_sessions TO authenticated;
GRANT ALL ON employees TO authenticated;
GRANT ALL ON employee_states TO authenticated;
GRANT ALL ON expense_claims TO authenticated;
GRANT ALL ON expense_items TO authenticated;
GRANT ALL ON session_rollups TO authenticated;
GRANT ALL ON daily_rollups TO authenticated;
GRANT ALL ON timeline_events TO authenticated;
GRANT ALL ON mobitraq_alerts TO authenticated;
GRANT ALL ON mobile_notifications TO authenticated;
GRANT ALL ON mobile_app_settings TO authenticated;

-- ============================================================
-- DONE: Run this migration in Supabase SQL Editor
-- ============================================================
