-- Migration 079: Force re-backfill of sessions whose final_km is
-- LOWER than rollup * 0.95.
--
-- After migration 078 ran, we discovered a class of sessions where
-- final_km was set from `estimated_km` (because that was the highest
-- of the four signals), but `rollup_km` was much higher. The reason:
-- on those trips the per-fix `counts_for_distance` filter rejected
-- 80-90% of the GPS deltas as "jitter" (root cause being too-strict
-- jitter thresholds, fixed in mobile commit 16bdeab). All four
-- signals 078 considered were downstream of the broken filter.
--
-- Concrete example: a 357 km drive ended with final_km = 260.9 km
-- (the device's recalc), rollup_km = 357.375 km (raw haversine),
-- sum_accepted_km = 43.6 km (per-fix filter accepted 12%).
--
-- This migration:
--   - Targets completed sessions where final_km < rollup * 0.95
--     AND the gap is > 1 km (don't bother with sub-1km noise).
--   - Sets final_km = rollup * 0.95 (the same 5% jitter discount
--     migration 078 uses).
--   - Tags reason_codes with REBACKFILL_FROM_ROLLUP so admin can
--     audit which sessions got bumped.
--   - Idempotent: safe to re-run; only touches rows that still
--     match the under-count criteria.

UPDATE shift_sessions s
SET
  final_km = COALESCE((
    SELECT NULLIF(sr.distance_km, 0) * 0.95
    FROM session_rollups sr
    WHERE sr.session_id = s.id
  ), s.final_km),
  distance_source = 'device_gps_filtered',
  reason_codes = COALESCE(s.reason_codes, '[]'::jsonb)
                 || '["REBACKFILL_FROM_ROLLUP"]'::jsonb
WHERE s.status = 'completed'
  AND EXISTS (
    SELECT 1
    FROM session_rollups sr
    WHERE sr.session_id = s.id
      AND sr.distance_km IS NOT NULL
      AND sr.distance_km * 0.95 > COALESCE(s.final_km, 0) + 1.0
  );

DO $$
DECLARE
  v_touched INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_touched
  FROM shift_sessions
  WHERE reason_codes::jsonb @> '["REBACKFILL_FROM_ROLLUP"]'::jsonb;
  RAISE NOTICE 'force-rebackfill complete: % sessions had final_km bumped to rollup*0.95',
    v_touched;
END $$;
