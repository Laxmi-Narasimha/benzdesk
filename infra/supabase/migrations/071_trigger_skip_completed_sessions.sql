-- Migration 071: Prevent GPS-point trigger from double-counting completed sessions
--
-- ROOT CAUSE: For offline sessions, GPS points sync to DB after the session is
-- already marked 'completed'. The update_session_rollup() trigger unconditionally
-- does:
--   UPDATE shift_sessions SET total_km = COALESCE(total_km, 0) + distance_delta
-- This fires for every GPS point INSERT, including batch-uploaded offline points
-- that arrive after endSession already set total_km to the verified value.
-- Result: total_km = verified_km + sum(all_gps_deltas) ≈ 2× the correct value.
--
-- FIX: Skip the shift_sessions.total_km update when the session is already
-- 'completed' or 'cancelled'. The session_rollups entry is still updated so
-- the rollup table stays consistent for historical queries.
--
-- NOTE: session_rollups.distance_km is allowed to accumulate from GPS triggers
-- even for completed sessions — it's used for cross-checking, not billing.

CREATE OR REPLACE FUNCTION update_session_rollup()
RETURNS TRIGGER AS $$
DECLARE
  prev_point RECORD;
  distance_delta REAL := 0;
  session_status TEXT;
BEGIN
  IF NEW.counts_for_distance = true
     AND NEW.distance_delta_m IS NOT NULL
     AND NEW.distance_delta_m > 0 THEN
    -- Device already calculated this with jitter-rejection and noise filtering.
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

  -- 1. Upsert session rollup (always — used for cross-checking, not billing)
  INSERT INTO session_rollups (session_id, distance_km, point_count, last_point_time, last_lat, last_lng, updated_at)
  VALUES (NEW.session_id, distance_delta, 1, NEW.recorded_at, NEW.latitude, NEW.longitude, NOW())
  ON CONFLICT (session_id) DO UPDATE SET
    distance_km    = session_rollups.distance_km + EXCLUDED.distance_km,
    point_count    = session_rollups.point_count + 1,
    last_point_time = EXCLUDED.last_point_time,
    last_lat       = EXCLUDED.last_lat,
    last_lng       = EXCLUDED.last_lng,
    updated_at     = NOW();

  -- 2. Update shift_sessions total_km ONLY for non-completed sessions.
  -- For completed sessions, endSession() already wrote the verified device total.
  -- Adding GPS-trigger deltas on top would double-count offline batch uploads.
  SELECT status INTO session_status
  FROM shift_sessions
  WHERE id = NEW.session_id;

  IF session_status IS NOT DISTINCT FROM 'active'
     OR session_status IS NOT DISTINCT FROM 'paused' THEN
    UPDATE shift_sessions
    SET total_km = COALESCE(total_km, 0) + distance_delta
    WHERE id = NEW.session_id;
  END IF;

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
