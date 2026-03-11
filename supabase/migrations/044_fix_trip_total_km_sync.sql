-- ============================================================================
-- Migration 044: Fix Trip Kilometer Sync
-- Purpose: Safely update trips.total_km when location points come in.
-- Previous migration 041 updated shift_sessions but failed to bubble the
-- distance up to the parent trip.
-- ============================================================================

CREATE OR REPLACE FUNCTION update_session_rollup()
RETURNS TRIGGER AS $$
DECLARE
  v_last_lat DOUBLE PRECISION;
  v_last_lng DOUBLE PRECISION;
  distance_delta REAL := 0;
  v_trip_id UUID;
BEGIN
  -- 1. Get the CURRENT last point from session_rollups
  SELECT last_lat, last_lng INTO v_last_lat, v_last_lng
  FROM session_rollups
  WHERE session_id = NEW.session_id;

  -- 2. Calculate distance if a previous point exists
  IF FOUND AND v_last_lat IS NOT NULL AND v_last_lng IS NOT NULL THEN
    distance_delta := (
      6371 * acos(
        LEAST(1.0, GREATEST(-1.0,
          cos(radians(v_last_lat)) * cos(radians(NEW.latitude)) *
          cos(radians(NEW.longitude) - radians(v_last_lng)) +
          sin(radians(v_last_lat)) * sin(radians(NEW.latitude))
        ))
      )
    );
  END IF;

  -- Protect against NaN or null weirdness
  IF distance_delta IS NULL OR distance_delta < 0 THEN
      distance_delta := 0;
  END IF;

  -- 3. Upsert session rollup
  INSERT INTO session_rollups (session_id, distance_km, point_count, last_point_time, last_lat, last_lng, updated_at)
  VALUES (NEW.session_id, distance_delta, 1, NEW.recorded_at, NEW.latitude, NEW.longitude, NOW())
  ON CONFLICT (session_id) DO UPDATE SET
    distance_km = session_rollups.distance_km + EXCLUDED.distance_km,
    point_count = session_rollups.point_count + 1,
    last_point_time = EXCLUDED.last_point_time,
    last_lat = EXCLUDED.last_lat,
    last_lng = EXCLUDED.last_lng,
    updated_at = NOW();

  -- 4. Automatically increase the total_km in the main session table AND return the trip_id
  UPDATE shift_sessions
  SET total_km = COALESCE(total_km, 0) + distance_delta
  WHERE id = NEW.session_id
  RETURNING trip_id INTO v_trip_id;

  -- 5. Automatically increase the total_km in the parent trips table
  IF v_trip_id IS NOT NULL THEN
    UPDATE trips
    SET total_km = COALESCE(total_km, 0) + distance_delta
    WHERE id = v_trip_id;
  END IF;

  -- 6. Update daily rollup map
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

-- Re-run the backfill just to ensure all active trips are perfectly synced
DO $$
BEGIN
  -- Re-calculate trips.total_km based on the sum of all its shift_sessions
  UPDATE trips t
  SET total_km = COALESCE((
    SELECT SUM(COALESCE(s.total_km, 0))
    FROM shift_sessions s
    WHERE s.trip_id = t.id
  ), 0);
END $$;
