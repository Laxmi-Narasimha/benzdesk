-- ============================================================================
-- Migration 041: Fix Timeline KM Sync (Robust Batch Insert)
-- Purpose: Safely update shift_sessions.total_km and session_rollups
-- Problem: The old trigger relied on `recorded_at < NEW.recorded_at`. If batched
-- points had similar timestamps, it found no previous point, resulting in 0 km.
-- Fix: Read `last_lat` and `last_lng` directly from `session_rollups`.
-- ============================================================================

CREATE OR REPLACE FUNCTION update_session_rollup()
RETURNS TRIGGER AS $$
DECLARE
  v_last_lat DOUBLE PRECISION;
  v_last_lng DOUBLE PRECISION;
  distance_delta REAL := 0;
BEGIN
  -- 1. Get the CURRENT last point from session_rollups
  -- This accurately tracks distance progressively, even during batched inserts
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
    last_lat = EXCLUDED.last_lat,   -- Updates the 'last known point' for the next row in the batch
    last_lng = EXCLUDED.last_lng,
    updated_at = NOW();

  -- 4. Automatically increase the total_km in the main session table!
  UPDATE shift_sessions
  SET total_km = COALESCE(total_km, 0) + distance_delta
  WHERE id = NEW.session_id;

  -- 5. Update daily rollup map
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

-- Re-run the backfill just to ensure all active sessions are perfectly synced right now
DO $$
DECLARE
  session_rec RECORD;
  point_rec RECORD;
  prev_lat DOUBLE PRECISION;
  prev_lng DOUBLE PRECISION;
  total_dist DOUBLE PRECISION;
  dist_delta DOUBLE PRECISION;
BEGIN
  FOR session_rec IN SELECT DISTINCT session_id FROM location_points WHERE session_id IS NOT NULL LOOP
    total_dist := 0;
    prev_lat := NULL;
    prev_lng := NULL;
    FOR point_rec IN 
      SELECT latitude, longitude 
      FROM location_points 
      WHERE session_id = session_rec.session_id 
      ORDER BY recorded_at ASC 
    LOOP
      IF prev_lat IS NOT NULL THEN
        dist_delta := (6371 * acos(LEAST(1.0, GREATEST(-1.0, cos(radians(prev_lat)) * cos(radians(point_rec.latitude)) * cos(radians(point_rec.longitude) - radians(prev_lng)) + sin(radians(prev_lat)) * sin(radians(point_rec.latitude))))));
        IF dist_delta IS NOT NULL AND dist_delta > 0 THEN
            total_dist := total_dist + dist_delta;
        END IF;
      END IF;
      prev_lat := point_rec.latitude;
      prev_lng := point_rec.longitude;
    END LOOP;

    -- Update both tables reliably
    UPDATE session_rollups SET distance_km = total_dist WHERE session_id = session_rec.session_id;
    UPDATE shift_sessions SET total_km = total_dist WHERE id = session_rec.session_id;
  END LOOP;
END $$;
