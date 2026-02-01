-- ============================================================================
-- Migration 020: Industry-Grade Location Timeline System
-- Per specification: industry_grade_location_timeline_app_prompt_FREE_ONLY.md
-- ============================================================================

-- ============================================================================
-- STEP 1: Enhance location_points table
-- Add hash for idempotency, server_received_at, and provider
-- ============================================================================

-- Add hash column for idempotency (unique constraint)
ALTER TABLE location_points 
  ADD COLUMN IF NOT EXISTS hash TEXT,
  ADD COLUMN IF NOT EXISTS server_received_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS provider TEXT;

-- Create unique index for hash idempotency
CREATE UNIQUE INDEX IF NOT EXISTS idx_location_points_hash 
  ON location_points(hash) WHERE hash IS NOT NULL;

-- ============================================================================
-- STEP 2: Create session_rollups table
-- Real-time session distance and last position tracking
-- ============================================================================

CREATE TABLE IF NOT EXISTS session_rollups (
  session_id UUID PRIMARY KEY REFERENCES shift_sessions(id) ON DELETE CASCADE,
  distance_km REAL NOT NULL DEFAULT 0,
  point_count INTEGER NOT NULL DEFAULT 0,
  last_point_time TIMESTAMPTZ,
  last_lat DOUBLE PRECISION,
  last_lng DOUBLE PRECISION,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- STEP 3: Create daily_rollups table
-- Daily distance aggregation per employee (IST timezone)
-- ============================================================================

CREATE TABLE IF NOT EXISTS daily_rollups (
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  distance_km REAL NOT NULL DEFAULT 0,
  session_count INTEGER NOT NULL DEFAULT 0,
  point_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  PRIMARY KEY (employee_id, day)
);

CREATE INDEX IF NOT EXISTS idx_daily_rollups_day ON daily_rollups(day);
CREATE INDEX IF NOT EXISTS idx_daily_rollups_employee_day ON daily_rollups(employee_id, day DESC);

-- ============================================================================
-- STEP 4: Create timeline_events table
-- Stops and move segments for admin timeline view
-- ============================================================================

CREATE TABLE IF NOT EXISTS timeline_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES shift_sessions(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('stop', 'move')),
  
  -- Timing
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  duration_sec INTEGER NOT NULL,
  
  -- For move segments
  distance_km REAL,
  start_lat DOUBLE PRECISION,
  start_lng DOUBLE PRECISION,
  end_lat DOUBLE PRECISION,
  end_lng DOUBLE PRECISION,
  
  -- For stop events (cluster center)
  center_lat DOUBLE PRECISION,
  center_lng DOUBLE PRECISION,
  
  -- Metadata
  point_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT valid_event_duration CHECK (duration_sec >= 0),
  CONSTRAINT valid_event_time_range CHECK (end_time >= start_time)
);

CREATE INDEX IF NOT EXISTS idx_timeline_events_employee_day 
  ON timeline_events(employee_id, day);
CREATE INDEX IF NOT EXISTS idx_timeline_events_session 
  ON timeline_events(session_id, start_time);
CREATE INDEX IF NOT EXISTS idx_timeline_events_type 
  ON timeline_events(event_type, day);

-- ============================================================================
-- STEP 5: Create alerts table
-- stuck, no_signal, mock_location, clock_drift alerts
-- ============================================================================

CREATE TABLE IF NOT EXISTS mobitraq_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  session_id UUID REFERENCES shift_sessions(id) ON DELETE SET NULL,
  
  alert_type TEXT NOT NULL CHECK (alert_type IN (
    'stuck',
    'no_signal', 
    'mock_location',
    'clock_drift',
    'force_stop',
    'low_battery',
    'other'
  )),
  severity TEXT NOT NULL DEFAULT 'warn' CHECK (severity IN ('info', 'warn', 'critical')),
  
  message TEXT NOT NULL,
  start_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_time TIMESTAMPTZ,
  
  -- Location context
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  
  -- State
  is_open BOOLEAN NOT NULL DEFAULT true,
  acknowledged_by UUID REFERENCES employees(id) ON DELETE SET NULL,
  acknowledged_at TIMESTAMPTZ,
  
  -- Metadata
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_alerts_employee ON mobitraq_alerts(employee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_session ON mobitraq_alerts(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_alerts_open ON mobitraq_alerts(is_open, created_at DESC) WHERE is_open = true;
CREATE INDEX IF NOT EXISTS idx_alerts_type ON mobitraq_alerts(alert_type, created_at DESC);

-- ============================================================================
-- STEP 6: Create app_config table for tunable constants
-- ============================================================================

CREATE TABLE IF NOT EXISTS mobitraq_config (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_by UUID REFERENCES employees(id) ON DELETE SET NULL
);

-- Insert default configuration values (per specification)
INSERT INTO mobitraq_config (key, value, description) VALUES
  ('STOP_RADIUS_M', '120', 'Radius in meters for stop cluster detection'),
  ('STOP_MIN_DURATION_SEC', '600', 'Minimum duration in seconds for a stop (10 min)'),
  ('STUCK_RADIUS_M', '150', 'Radius in meters to consider as stuck'),
  ('STUCK_MIN_DURATION_MIN', '30', 'Duration in minutes before triggering stuck alert'),
  ('NO_SIGNAL_TIMEOUT_MIN', '20', 'Minutes without location before no_signal alert'),
  ('MAX_ACCURACY_M', '50', 'Maximum accuracy threshold for accepting points'),
  ('TELEPORT_SPEED_KMH', '160', 'Speed threshold for teleport detection'),
  ('RETENTION_DAYS', '35', 'Days to keep location history'),
  ('BIKE_SPEED_MPS', '8', 'Speed threshold for bike vs car mode'),
  ('BIKE_DISTANCE_M', '30', 'Distance threshold for bike mode'),
  ('CAR_DISTANCE_M', '60', 'Distance threshold for car mode'),
  ('MIN_POINT_INTERVAL_SEC', '5', 'Minimum seconds between accepted points'),
  ('STATIONARY_CHECK_INTERVAL_SEC', '120', 'Interval for stationary mode checks (2 min)'),
  ('CLOCK_DRIFT_THRESHOLD_MIN', '10', 'Minutes of clock drift before alert')
ON CONFLICT (key) DO NOTHING;

-- ============================================================================
-- STEP 7: Enable RLS on new tables
-- ============================================================================

ALTER TABLE session_rollups ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_rollups ENABLE ROW LEVEL SECURITY;
ALTER TABLE timeline_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobitraq_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE mobitraq_config ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 8: RLS Policies for session_rollups
-- ============================================================================

-- Employees can view their own session rollups
CREATE POLICY "Employees view own session rollups" ON session_rollups
FOR SELECT USING (
  session_id IN (
    SELECT id FROM shift_sessions WHERE employee_id = auth.uid()
  )
);

-- Admins can view all session rollups
CREATE POLICY "Admins view all session rollups" ON session_rollups
FOR SELECT USING (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

-- System can insert/update rollups (via service role)
CREATE POLICY "System can manage session rollups" ON session_rollups
FOR ALL USING (auth.role() = 'service_role');

-- ============================================================================
-- STEP 9: RLS Policies for daily_rollups
-- ============================================================================

-- Employees can view their own daily rollups
CREATE POLICY "Employees view own daily rollups" ON daily_rollups
FOR SELECT USING (employee_id = auth.uid());

-- Admins can view all daily rollups
CREATE POLICY "Admins view all daily rollups" ON daily_rollups
FOR SELECT USING (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

-- System can insert/update rollups
CREATE POLICY "System can manage daily rollups" ON daily_rollups
FOR ALL USING (auth.role() = 'service_role');

-- ============================================================================
-- STEP 10: RLS Policies for timeline_events
-- ============================================================================

-- Employees can view their own timeline
CREATE POLICY "Employees view own timeline" ON timeline_events
FOR SELECT USING (employee_id = auth.uid());

-- Admins can view all timelines
CREATE POLICY "Admins view all timelines" ON timeline_events
FOR SELECT USING (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

-- System can manage timeline events
CREATE POLICY "System can manage timeline events" ON timeline_events
FOR ALL USING (auth.role() = 'service_role');

-- ============================================================================
-- STEP 11: RLS Policies for mobitraq_alerts
-- ============================================================================

-- Employees can view their own alerts
CREATE POLICY "Employees view own alerts" ON mobitraq_alerts
FOR SELECT USING (employee_id = auth.uid());

-- Admins can view all alerts
CREATE POLICY "Admins view all alerts" ON mobitraq_alerts
FOR SELECT USING (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

-- Admins can acknowledge alerts
CREATE POLICY "Admins can acknowledge alerts" ON mobitraq_alerts
FOR UPDATE USING (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

-- System can manage alerts
CREATE POLICY "System can manage alerts" ON mobitraq_alerts
FOR ALL USING (auth.role() = 'service_role');

-- ============================================================================
-- STEP 12: RLS Policies for mobitraq_config
-- ============================================================================

-- Everyone can read config
CREATE POLICY "Everyone can read config" ON mobitraq_config
FOR SELECT USING (true);

-- Only admins can update config
CREATE POLICY "Admins can update config" ON mobitraq_config
FOR UPDATE USING (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

-- ============================================================================
-- STEP 13: Trigger for automatic rollup updates
-- ============================================================================

-- Function to update session rollups on new location point
CREATE OR REPLACE FUNCTION update_session_rollup()
RETURNS TRIGGER AS $$
DECLARE
  prev_point RECORD;
  distance_delta REAL := 0;
BEGIN
  -- Get previous point in this session
  SELECT latitude, longitude, recorded_at INTO prev_point
  FROM location_points
  WHERE session_id = NEW.session_id
    AND recorded_at < NEW.recorded_at
  ORDER BY recorded_at DESC
  LIMIT 1;

  -- Calculate distance if previous point exists
  IF FOUND THEN
    -- Haversine formula (simplified for trigger)
    distance_delta := (
      6371 * acos(
        LEAST(1.0, GREATEST(-1.0,
          cos(radians(prev_point.latitude)) * cos(radians(NEW.latitude)) *
          cos(radians(NEW.longitude) - radians(prev_point.longitude)) +
          sin(radians(prev_point.latitude)) * sin(radians(NEW.latitude))
        ))
      )
    );
  END IF;

  -- Upsert session rollup
  INSERT INTO session_rollups (session_id, distance_km, point_count, last_point_time, last_lat, last_lng, updated_at)
  VALUES (NEW.session_id, distance_delta, 1, NEW.recorded_at, NEW.latitude, NEW.longitude, NOW())
  ON CONFLICT (session_id) DO UPDATE SET
    distance_km = session_rollups.distance_km + EXCLUDED.distance_km,
    point_count = session_rollups.point_count + 1,
    last_point_time = EXCLUDED.last_point_time,
    last_lat = EXCLUDED.last_lat,
    last_lng = EXCLUDED.last_lng,
    updated_at = NOW();

  -- Update daily rollup (IST timezone: UTC+5:30)
  INSERT INTO daily_rollups (employee_id, day, distance_km, session_count, point_count, updated_at)
  VALUES (
    NEW.employee_id,
    (NEW.recorded_at AT TIME ZONE 'Asia/Kolkata')::DATE,
    distance_delta,
    1,
    1,
    NOW()
  )
  ON CONFLICT (employee_id, day) DO UPDATE SET
    distance_km = daily_rollups.distance_km + EXCLUDED.distance_km,
    point_count = daily_rollups.point_count + 1,
    updated_at = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger
DROP TRIGGER IF EXISTS location_point_rollup_trigger ON location_points;
CREATE TRIGGER location_point_rollup_trigger
  AFTER INSERT ON location_points
  FOR EACH ROW
  EXECUTE FUNCTION update_session_rollup();

-- ============================================================================
-- STEP 14: Function for retention cleanup
-- ============================================================================

CREATE OR REPLACE FUNCTION cleanup_old_mobitraq_data()
RETURNS void AS $$
DECLARE
  retention_days INTEGER;
  cutoff_date TIMESTAMPTZ;
  deleted_points INTEGER;
  deleted_events INTEGER;
  deleted_alerts INTEGER;
BEGIN
  -- Get retention config
  SELECT (value::TEXT)::INTEGER INTO retention_days 
  FROM mobitraq_config WHERE key = 'RETENTION_DAYS';
  
  IF retention_days IS NULL THEN
    retention_days := 35; -- Default
  END IF;
  
  cutoff_date := NOW() - (retention_days || ' days')::INTERVAL;
  
  -- Delete old location points
  DELETE FROM location_points WHERE recorded_at < cutoff_date;
  GET DIAGNOSTICS deleted_points = ROW_COUNT;
  
  -- Delete old timeline events
  DELETE FROM timeline_events WHERE start_time < cutoff_date;
  GET DIAGNOSTICS deleted_events = ROW_COUNT;
  
  -- Delete old alerts (90 days for alerts)
  DELETE FROM mobitraq_alerts WHERE created_at < NOW() - INTERVAL '90 days';
  GET DIAGNOSTICS deleted_alerts = ROW_COUNT;
  
  RAISE NOTICE 'Cleanup complete: % points, % events, % alerts deleted', 
    deleted_points, deleted_events, deleted_alerts;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- SUCCESS
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Migration 020 completed successfully!';
  RAISE NOTICE '   Added: hash, server_received_at, provider to location_points';
  RAISE NOTICE '   Created: session_rollups table';
  RAISE NOTICE '   Created: daily_rollups table';
  RAISE NOTICE '   Created: timeline_events table';
  RAISE NOTICE '   Created: mobitraq_alerts table';
  RAISE NOTICE '   Created: mobitraq_config table with defaults';
  RAISE NOTICE '   Created: RLS policies for all tables';
  RAISE NOTICE '   Created: Auto-update rollup trigger';
  RAISE NOTICE '   Created: Retention cleanup function';
END $$;
