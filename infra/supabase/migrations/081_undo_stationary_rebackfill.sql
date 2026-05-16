-- Migration 081: Undo the over-eager rollup rebackfill from migration 079
-- for sessions that show no actual movement signal.
--
-- Migration 079 bumped final_km to rollup*0.95 for every session
-- where final_km was meaningfully lower than the rollup. That fixed
-- the 357-km under-count case but ALSO inflated stationary
-- sessions where the rollup was just accumulated GPS jitter
-- (phone-on-desk for 20 minutes = ~1.5 km of phantom haversine).
--
-- This migration finds sessions that 079 touched (reason_codes
-- contains REBACKFILL_FROM_ROLLUP) but DON'T have any movement
-- signal — defined as:
--   * estimated_km < 1.0 km, AND
--   * no GPS point reported speed > 1.5 m/s (~5.4 km/h)
-- and reverts their final_km back to estimated_km (or sum-of-deltas
-- if that's higher).
--
-- This is safe: estimated_km comes from the device's locked
-- DistanceEngine output. It's an honest "I drove this much" number
-- even if conservative. Better to under-count phantom motion than
-- to pay for it.

UPDATE shift_sessions s
SET
  final_km = GREATEST(
    COALESCE(NULLIF(s.estimated_km, 0), 0),
    COALESCE((
      SELECT NULLIF(SUM(lp.distance_delta_m) / 1000.0, 0)
      FROM location_points lp
      WHERE lp.session_id = s.id
        AND lp.counts_for_distance = TRUE
        AND lp.distance_delta_m > 0
    ), 0)
  ),
  reason_codes = COALESCE(s.reason_codes, '[]'::jsonb)
                 || '["REVERTED_STATIONARY_REBACKFILL"]'::jsonb
WHERE s.status = 'completed'
  AND s.reason_codes::jsonb @> '["REBACKFILL_FROM_ROLLUP"]'::jsonb
  AND COALESCE(s.estimated_km, 0) < 1.0
  AND NOT EXISTS (
    SELECT 1 FROM location_points lp
    WHERE lp.session_id = s.id
      AND lp.speed IS NOT NULL
      AND lp.speed > 1.5  -- m/s; ~5.4 km/h, clearly above stationary jitter
  );

DO $$
DECLARE
  v_reverted INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_reverted
  FROM shift_sessions
  WHERE reason_codes::jsonb @> '["REVERTED_STATIONARY_REBACKFILL"]'::jsonb;
  RAISE NOTICE 'Reverted % stationary sessions that 079 had over-inflated', v_reverted;
END $$;
