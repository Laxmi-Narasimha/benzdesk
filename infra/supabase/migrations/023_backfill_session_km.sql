-- ============================================================================
-- Migration 023: Backfill Session KM
-- Purpose: Recalculate and update total_km for ALL existing sessions based on location_points.
-- This fixes the "zeroes" issue for historical data recorded before the triggers were active.
-- ============================================================================

DO $$
DECLARE
  session_rec RECORD;
  point_rec RECORD;
  prev_lat DOUBLE PRECISION;
  prev_lng DOUBLE PRECISION;
  total_dist DOUBLE PRECISION;
  dist_delta DOUBLE PRECISION;
BEGIN
  RAISE NOTICE 'Starting backfill of session kilometers...';

  -- Iterate through all sessions that have location points
  FOR session_rec IN SELECT DISTINCT session_id FROM location_points WHERE session_id IS NOT NULL LOOP
    
    total_dist := 0;
    prev_lat := NULL;
    prev_lng := NULL;
    
    -- Iterate through points for this session, ordered by time
    FOR point_rec IN 
      SELECT latitude, longitude 
      FROM location_points 
      WHERE session_id = session_rec.session_id 
      ORDER BY recorded_at ASC 
    LOOP
      
      IF prev_lat IS NOT NULL THEN
        -- Calculate Haversine distance
        dist_delta := (
          6371 * acos(
            LEAST(1.0, GREATEST(-1.0,
              cos(radians(prev_lat)) * cos(radians(point_rec.latitude)) *
              cos(radians(point_rec.longitude) - radians(prev_lng)) +
              sin(radians(prev_lat)) * sin(radians(point_rec.latitude))
            ))
          )
        );
        total_dist := total_dist + dist_delta;
      END IF;

      prev_lat := point_rec.latitude;
      prev_lng := point_rec.longitude;
    END LOOP;

    -- Update session_rollups
    INSERT INTO session_rollups (session_id, distance_km, point_count, updated_at)
    VALUES (session_rec.session_id, total_dist, 0, NOW()) -- point_count 0 placeholder, triggering update mostly
    ON CONFLICT (session_id) DO UPDATE SET
      distance_km = total_dist,
      updated_at = NOW();

    -- Update shift_sessions
    UPDATE shift_sessions
    SET total_km = total_dist
    WHERE id = session_rec.session_id;
    
    RAISE NOTICE 'Updated Session %: % km', session_rec.session_id, total_dist;
    
  END LOOP;
  
  RAISE NOTICE 'Backfill complete.';
END $$;
