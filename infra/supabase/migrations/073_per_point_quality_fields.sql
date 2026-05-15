-- Migration 073: per-point quality fields (Stage 2)
--
-- Adds columns that let the server-side finalization pipeline (Stage 3)
-- make informed decisions before calling Google Roads API:
--
--   elapsed_realtime_nanos  monotonic timestamp (Android), clock-jump safe
--   is_mock                 mock-location detection
--   speed_accuracy_mps      reliability of the speed reading
--   bearing_accuracy_deg    reliability of the bearing reading
--   activity_type           ActivityRecognition: in_vehicle | still | walking | on_bicycle | unknown
--   activity_confidence     0..100 from ActivityRecognition API
--
-- All are nullable: existing rows from before this migration have NULLs,
-- which the scoring/finalization code treats as "unknown".
--
-- See docs/DISTANCE_TRACKING_METHODOLOGY.md §3.2.

ALTER TABLE location_points ADD COLUMN IF NOT EXISTS elapsed_realtime_nanos BIGINT;
ALTER TABLE location_points ADD COLUMN IF NOT EXISTS is_mock BOOLEAN DEFAULT FALSE;
ALTER TABLE location_points ADD COLUMN IF NOT EXISTS speed_accuracy_mps REAL;
ALTER TABLE location_points ADD COLUMN IF NOT EXISTS bearing_accuracy_deg REAL;
ALTER TABLE location_points ADD COLUMN IF NOT EXISTS activity_type TEXT;
ALTER TABLE location_points ADD COLUMN IF NOT EXISTS activity_confidence INTEGER;

ALTER TABLE location_points DROP CONSTRAINT IF EXISTS location_points_activity_type_check;
ALTER TABLE location_points ADD CONSTRAINT location_points_activity_type_check
  CHECK (activity_type IS NULL OR activity_type IN (
    'in_vehicle', 'still', 'walking', 'on_bicycle', 'on_foot', 'running', 'tilting', 'unknown'
  ));

ALTER TABLE location_points DROP CONSTRAINT IF EXISTS location_points_activity_confidence_check;
ALTER TABLE location_points ADD CONSTRAINT location_points_activity_confidence_check
  CHECK (activity_confidence IS NULL OR (activity_confidence BETWEEN 0 AND 100));

-- Index used by the finalization Edge Function when fetching points for a session.
-- We already have (session_id, recorded_at) elsewhere; this adds the filter
-- columns the Edge Function checks before calling Roads API.
CREATE INDEX IF NOT EXISTS idx_location_points_session_quality
  ON location_points (session_id, recorded_at)
  WHERE is_mock = FALSE OR is_mock IS NULL;
