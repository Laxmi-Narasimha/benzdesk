-- Migration 070: Fix session_rollups to use device-filtered distance
--
-- ROOT CAUSE: The update_session_rollup() trigger (migration 022) recalculates
-- raw haversine for every GPS point regardless of counts_for_distance. This
-- inflates session_rollups.distance_km vs shift_sessions.total_km because it
-- counts GPS jitter that the device's DistanceEngine correctly rejected.
--
-- Example: Online session showed 11.92 km on screen → expense lodged 12.25 km.
-- The 0.33 km gap was pure GPS noise counted by the raw trigger.
--
-- FIX: Use distance_delta_m from the GPS point when counts_for_distance = true.
-- Fall back to haversine only for old points that pre-date these columns (NULL).

CREATE OR REPLACE FUNCTION update_session_rollup()
RETURNS TRIGGER AS $$
DECLARE
  prev_point RECORD;
  distance_delta REAL := 0;
BEGIN
  IF NEW.counts_for_distance = true
     AND NEW.distance_delta_m IS NOT NULL
     AND NEW.distance_delta_m > 0 THEN
    -- Device already calculated this with jitter-rejection and noise filtering.
    -- Trust it directly — no re-calculation needed.
    distance_delta := NEW.distance_delta_m / 1000.0;

  ELSIF NEW.counts_for_distance IS NULL AND NEW.distance_delta_m IS NULL THEN
    -- Legacy point (pre-counts_for_distance): fall back to haversine.
    SELECT latitude, longitude INTO prev_point
    FROM location_points
    WHERE session_id = NEW.session_id
      AND recorded_at < NEW.recorded_at
    ORDER BY recorded_at DESC
    LIMIT 1;

    IF FOUND THEN
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
  END IF;
  -- counts_for_distance = false → distance_delta stays 0 (jitter, correctly ignored).

  -- 1. Upsert session rollup
  INSERT INTO session_rollups (session_id, distance_km, point_count, last_point_time, last_lat, last_lng, updated_at)
  VALUES (NEW.session_id, distance_delta, 1, NEW.recorded_at, NEW.latitude, NEW.longitude, NOW())
  ON CONFLICT (session_id) DO UPDATE SET
    distance_km    = session_rollups.distance_km + EXCLUDED.distance_km,
    point_count    = session_rollups.point_count + 1,
    last_point_time = EXCLUDED.last_point_time,
    last_lat       = EXCLUDED.last_lat,
    last_lng       = EXCLUDED.last_lng,
    updated_at     = NOW();

  -- 2. Update shift_sessions total_km
  UPDATE shift_sessions
  SET total_km = COALESCE(total_km, 0) + distance_delta
  WHERE id = NEW.session_id;

  -- 3. Update daily rollup
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
    updated_at  = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recalculate existing rollups for sessions that have counts_for_distance data.
-- This corrects the already-inflated rollup for sessions like b0133d0d.
UPDATE session_rollups sr
SET distance_km = (
  SELECT COALESCE(SUM(lp.distance_delta_m) / 1000.0, sr.distance_km)
  FROM location_points lp
  WHERE lp.session_id = sr.session_id
    AND lp.counts_for_distance = true
    AND lp.distance_delta_m > 0
)
WHERE EXISTS (
  SELECT 1 FROM location_points lp
  WHERE lp.session_id = sr.session_id
    AND lp.counts_for_distance = true
    AND lp.distance_delta_m > 0
);
