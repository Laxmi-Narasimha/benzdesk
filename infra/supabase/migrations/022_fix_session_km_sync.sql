-- ============================================================================
-- Migration 022: Fix Session KM Sync
-- Purpose: Ensure shift_sessions.total_km is updated when location points are added
-- Problem: Web Admin queries shift_sessions, but previous trigger only updated session_rollups
-- ============================================================================

-- Redefine the trigger function from 020 to also update shift_sessions
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
    -- Haversine formula
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

  -- 1. Upsert session rollup (Existing logic)
  INSERT INTO session_rollups (session_id, distance_km, point_count, last_point_time, last_lat, last_lng, updated_at)
  VALUES (NEW.session_id, distance_delta, 1, NEW.recorded_at, NEW.latitude, NEW.longitude, NOW())
  ON CONFLICT (session_id) DO UPDATE SET
    distance_km = session_rollups.distance_km + EXCLUDED.distance_km,
    point_count = session_rollups.point_count + 1,
    last_point_time = EXCLUDED.last_point_time,
    last_lat = EXCLUDED.last_lat,
    last_lng = EXCLUDED.last_lng,
    updated_at = NOW();

  -- 2. Update shift_sessions total_km (NEW LOGIC)
  UPDATE shift_sessions
  SET total_km = COALESCE(total_km, 0) + distance_delta
  WHERE id = NEW.session_id;

  -- 3. Update daily rollup (Existing logic)
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

-- Note: Trigger 'location_point_rollup_trigger' already exists and points to this function name,
-- so replacing the function is sufficient to apply the logic.
