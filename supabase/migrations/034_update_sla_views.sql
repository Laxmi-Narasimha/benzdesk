-- ============================================================================
-- Migration 034: Update SLA Views
-- 1. v_sla_time_to_close: use pending_closure event time as admin resolution time
--    (admin's work is done when they mark pending_closure, not when employee confirms)
-- 2. v_sla_first_response: add FRESH_START_DATE filter
-- 3. v_admin_backlog: include pending_closure in active counts
-- ============================================================================

-- ============================================================================
-- UPDATE: v_sla_time_to_close
-- Admin resolution time = when admin set status to pending_closure/closed
-- NOT the final closed_at (which depends on employee confirming)
-- ============================================================================

DROP VIEW IF EXISTS v_sla_time_to_close;

CREATE OR REPLACE VIEW v_sla_time_to_close AS
WITH admin_resolution AS (
  -- Find when admin first moved the request to pending_closure or closed
  SELECT DISTINCT ON (request_id)
    request_id,
    actor_id as resolved_by,
    created_at as admin_resolved_at
  FROM request_events
  WHERE event_type IN ('status_changed', 'closed')
    AND (new_data->>'status' = 'pending_closure' OR new_data->>'status' = 'closed')
  ORDER BY request_id, created_at ASC
)
SELECT
  r.id as request_id,
  r.title,
  r.category,
  r.priority,
  r.status,
  r.created_at,
  ar.admin_resolved_at,
  r.closed_at,
  -- Admin resolution time: from creation to when admin said "done"
  CASE
    WHEN ar.admin_resolved_at IS NOT NULL THEN
      EXTRACT(EPOCH FROM (ar.admin_resolved_at - r.created_at)) / 3600
    ELSE NULL
  END::NUMERIC(10,2) as admin_resolution_hours,
  -- Full time to close (for reference only)
  CASE
    WHEN r.closed_at IS NOT NULL THEN
      EXTRACT(EPOCH FROM (r.closed_at - r.created_at)) / 3600
    ELSE NULL
  END::NUMERIC(10,2) as full_close_hours,
  u.email as resolved_by_email
FROM requests r
LEFT JOIN admin_resolution ar ON ar.request_id = r.id
LEFT JOIN auth.users u ON u.id = ar.resolved_by
WHERE (r.status IN ('pending_closure', 'closed') OR ar.admin_resolved_at IS NOT NULL)
  AND r.created_at >= '2026-01-14T00:00:00.000Z'
ORDER BY ar.admin_resolved_at DESC NULLS LAST;

-- ============================================================================
-- UPDATE: v_sla_first_response
-- Add fresh start date filter + correct field naming
-- ============================================================================

DROP VIEW IF EXISTS v_sla_first_response;

CREATE OR REPLACE VIEW v_sla_first_response AS
SELECT
  r.id as request_id,
  r.title,
  r.status,
  r.priority,
  r.created_at,
  r.first_admin_response_at,
  CASE
    WHEN r.first_admin_response_at IS NOT NULL THEN
      EXTRACT(EPOCH FROM (r.first_admin_response_at - r.created_at)) / 3600
    ELSE
      EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600
  END::NUMERIC(10,2) as response_time_hours,
  CASE
    WHEN r.first_admin_response_at IS NULL THEN
      CASE r.priority
        WHEN 1 THEN EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600 > 2
        WHEN 2 THEN EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600 > 4
        WHEN 3 THEN EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600 > 8
        WHEN 4 THEN EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600 > 24
        ELSE EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600 > 48
      END
    ELSE
      CASE r.priority
        WHEN 1 THEN EXTRACT(EPOCH FROM (r.first_admin_response_at - r.created_at)) / 3600 > 2
        WHEN 2 THEN EXTRACT(EPOCH FROM (r.first_admin_response_at - r.created_at)) / 3600 > 4
        WHEN 3 THEN EXTRACT(EPOCH FROM (r.first_admin_response_at - r.created_at)) / 3600 > 8
        WHEN 4 THEN EXTRACT(EPOCH FROM (r.first_admin_response_at - r.created_at)) / 3600 > 24
        ELSE EXTRACT(EPOCH FROM (r.first_admin_response_at - r.created_at)) / 3600 > 48
      END
  END as is_breached,
  u.email as first_responder_email
FROM requests r
LEFT JOIN auth.users u ON u.id = r.first_admin_response_by
WHERE r.created_at >= '2026-01-14T00:00:00.000Z'
  AND r.status != 'closed'
ORDER BY
  CASE WHEN r.first_admin_response_at IS NULL THEN 0 ELSE 1 END,
  r.created_at ASC;

-- ============================================================================
-- UPDATE: v_admin_backlog
-- Include pending_closure in active counts (admin hasn't been released yet)
-- ============================================================================

DROP VIEW IF EXISTS v_admin_backlog;

CREATE OR REPLACE VIEW v_admin_backlog AS
SELECT
  u.id as admin_id,
  u.email as admin_email,
  COUNT(*) FILTER (WHERE r.status = 'open')::INTEGER as open_count,
  COUNT(*) FILTER (WHERE r.status = 'in_progress')::INTEGER as in_progress_count,
  COUNT(*) FILTER (WHERE r.status = 'waiting_on_requester')::INTEGER as waiting_count,
  COUNT(*) FILTER (WHERE r.status = 'pending_closure')::INTEGER as pending_closure_count,
  COUNT(*) FILTER (WHERE r.status NOT IN ('closed'))::INTEGER as total_active,
  AVG(EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600)::NUMERIC(10,2) as avg_age_hours
FROM user_roles ur
JOIN auth.users u ON u.id = ur.user_id
LEFT JOIN requests r ON r.assigned_to = ur.user_id AND r.status NOT IN ('closed')
  AND r.created_at >= '2026-01-14T00:00:00.000Z'
WHERE ur.role = 'accounts_admin' AND ur.is_active = true
GROUP BY u.id, u.email
ORDER BY total_active DESC;

-- Grant access
GRANT SELECT ON v_sla_time_to_close TO authenticated;
GRANT SELECT ON v_sla_first_response TO authenticated;
GRANT SELECT ON v_admin_backlog TO authenticated;
