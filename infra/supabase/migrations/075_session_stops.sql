-- Migration 075: session_stops table for stop / indoor-walking events
--
-- A "stop" is when the employee stays within a small radius for an
-- extended period. We do NOT auto-pause the session — distance tracking
-- keeps running so we never lose km. We just record where + when so
-- admins can see "visited customer X from 11:05 to 11:38" on the
-- timeline, distinct from driving segments.
--
-- "Indoor walking" is a sub-type: when the employee is detected as
-- WALKING by Activity Recognition AND GPS accuracy degrades (indoor
-- multipath), we mark the period as `kind = 'indoor_walking'` so it's
-- visually different from a pure stationary stop.
--
-- Stops are computed on-device by StopDetector (lib/services/stop_detector.dart)
-- and synced via the same pattern as location_points.

CREATE TABLE IF NOT EXISTS session_stops (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      UUID NOT NULL REFERENCES shift_sessions(id) ON DELETE CASCADE,
  employee_id     UUID NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  kind            TEXT NOT NULL,             -- 'stop' | 'indoor_walking'
  started_at      TIMESTAMPTZ NOT NULL,
  ended_at        TIMESTAMPTZ NOT NULL,
  duration_sec    INTEGER NOT NULL,
  center_lat      DOUBLE PRECISION NOT NULL,
  center_lng      DOUBLE PRECISION NOT NULL,
  radius_m        REAL,                      -- approximate detection radius (50m default)
  address         TEXT,                      -- best-effort reverse geocode
  point_count     INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE session_stops DROP CONSTRAINT IF EXISTS session_stops_kind_check;
ALTER TABLE session_stops ADD CONSTRAINT session_stops_kind_check
  CHECK (kind IN ('stop', 'indoor_walking'));

ALTER TABLE session_stops DROP CONSTRAINT IF EXISTS session_stops_duration_check;
ALTER TABLE session_stops ADD CONSTRAINT session_stops_duration_check
  CHECK (duration_sec >= 0);

CREATE INDEX IF NOT EXISTS idx_session_stops_session
  ON session_stops (session_id, started_at);

CREATE INDEX IF NOT EXISTS idx_session_stops_employee_day
  ON session_stops (employee_id, started_at DESC);

-- RLS: same posture as shift_sessions — RLS off here, scoped via app code.
ALTER TABLE session_stops DISABLE ROW LEVEL SECURITY;
