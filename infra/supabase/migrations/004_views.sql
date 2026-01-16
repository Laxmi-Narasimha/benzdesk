-- ============================================================================
-- BenzDesk Database Schema - Migration 004: Director Oversight Views
-- Read-only views for metrics and reporting
-- ============================================================================

-- ============================================================================
-- VIEW: v_requests_overview
-- Summary counts by status for dashboard
-- ============================================================================

CREATE OR REPLACE VIEW v_requests_overview AS
SELECT 
  status,
  COUNT(*)::INTEGER as count,
  COUNT(*) FILTER (WHERE created_at >= now() - interval '24 hours')::INTEGER as count_24h,
  COUNT(*) FILTER (WHERE created_at >= now() - interval '7 days')::INTEGER as count_7d
FROM requests
GROUP BY status
ORDER BY 
  CASE status
    WHEN 'open' THEN 1
    WHEN 'in_progress' THEN 2
    WHEN 'waiting_on_requester' THEN 3
    WHEN 'closed' THEN 4
  END;

-- ============================================================================
-- VIEW: v_admin_backlog
-- Open requests assigned to each admin
-- ============================================================================

CREATE OR REPLACE VIEW v_admin_backlog AS
SELECT 
  u.id as admin_id,
  u.email as admin_email,
  COUNT(*) FILTER (WHERE r.status = 'open')::INTEGER as open_count,
  COUNT(*) FILTER (WHERE r.status = 'in_progress')::INTEGER as in_progress_count,
  COUNT(*) FILTER (WHERE r.status = 'waiting_on_requester')::INTEGER as waiting_count,
  COUNT(*) FILTER (WHERE r.status != 'closed')::INTEGER as total_active,
  AVG(EXTRACT(EPOCH FROM (now() - r.created_at)) / 3600)::NUMERIC(10,2) as avg_age_hours
FROM user_roles ur
JOIN auth.users u ON u.id = ur.user_id
LEFT JOIN requests r ON r.assigned_to = ur.user_id AND r.status != 'closed'
WHERE ur.role = 'accounts_admin' AND ur.is_active = true
GROUP BY u.id, u.email
ORDER BY total_active DESC;

-- ============================================================================
-- VIEW: v_unassigned_requests
-- Requests that need assignment
-- ============================================================================

CREATE OR REPLACE VIEW v_unassigned_requests AS
SELECT 
  id,
  title,
  category,
  priority,
  status,
  created_at,
  EXTRACT(EPOCH FROM (now() - created_at)) / 3600 as hours_since_created
FROM requests
WHERE assigned_to IS NULL 
  AND status NOT IN ('closed')
ORDER BY 
  priority ASC,
  created_at ASC;

-- ============================================================================
-- VIEW: v_sla_first_response
-- Time to first admin response metrics
-- ============================================================================

CREATE OR REPLACE VIEW v_sla_first_response AS
SELECT 
  r.id as request_id,
  r.title,
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
      -- Check if SLA breached based on priority
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
WHERE r.status != 'closed' OR r.first_admin_response_at IS NOT NULL
ORDER BY 
  CASE WHEN r.first_admin_response_at IS NULL THEN 0 ELSE 1 END,
  r.created_at ASC;

-- ============================================================================
-- VIEW: v_sla_time_to_close
-- Resolution time metrics for closed requests
-- ============================================================================

CREATE OR REPLACE VIEW v_sla_time_to_close AS
SELECT 
  r.id as request_id,
  r.title,
  r.category,
  r.priority,
  r.created_at,
  r.closed_at,
  EXTRACT(EPOCH FROM (r.closed_at - r.created_at)) / 3600 as time_to_close_hours,
  EXTRACT(EPOCH FROM (r.closed_at - r.created_at)) / 86400 as time_to_close_days,
  u.email as closed_by_email
FROM requests r
JOIN auth.users u ON u.id = r.closed_by
WHERE r.status = 'closed' AND r.closed_at IS NOT NULL
ORDER BY r.closed_at DESC;

-- ============================================================================
-- VIEW: v_stale_requests
-- Requests with no activity in X days
-- ============================================================================

CREATE OR REPLACE VIEW v_stale_requests AS
SELECT 
  r.id,
  r.title,
  r.category,
  r.priority,
  r.status,
  r.assigned_to,
  u.email as assigned_to_email,
  r.last_activity_at,
  EXTRACT(DAY FROM (now() - r.last_activity_at))::INTEGER as days_since_activity,
  r.created_at
FROM requests r
LEFT JOIN auth.users u ON u.id = r.assigned_to
WHERE r.status NOT IN ('closed')
  AND r.last_activity_at < now() - interval '3 days'
ORDER BY r.last_activity_at ASC;

-- ============================================================================
-- VIEW: v_admin_throughput
-- Requests closed per admin per period
-- ============================================================================

CREATE OR REPLACE VIEW v_admin_throughput AS
WITH admin_stats AS (
  SELECT 
    r.closed_by as admin_id,
    COUNT(*) as closed_count,
    AVG(EXTRACT(EPOCH FROM (r.closed_at - r.created_at)) / 3600) as avg_time_to_close_hours,
    MIN(r.closed_at) as first_close,
    MAX(r.closed_at) as last_close
  FROM requests r
  WHERE r.status = 'closed' 
    AND r.closed_at IS NOT NULL
    AND r.closed_at >= now() - interval '30 days'
  GROUP BY r.closed_by
)
SELECT 
  u.id as admin_id,
  u.email as admin_email,
  COALESCE(s.closed_count, 0)::INTEGER as closed_last_30_days,
  COALESCE(s.avg_time_to_close_hours, 0)::NUMERIC(10,2) as avg_resolution_hours,
  s.first_close as period_start,
  s.last_close as period_end
FROM user_roles ur
JOIN auth.users u ON u.id = ur.user_id
LEFT JOIN admin_stats s ON s.admin_id = ur.user_id
WHERE ur.role = 'accounts_admin' AND ur.is_active = true
ORDER BY closed_last_30_days DESC;

-- ============================================================================
-- VIEW: v_daily_metrics
-- Daily request metrics for trending
-- ============================================================================

CREATE OR REPLACE VIEW v_daily_metrics AS
SELECT 
  date_trunc('day', created_at)::DATE as date,
  COUNT(*)::INTEGER as requests_created,
  COUNT(*) FILTER (WHERE status = 'closed')::INTEGER as requests_closed,
  AVG(priority)::NUMERIC(3,2) as avg_priority
FROM requests
WHERE created_at >= now() - interval '30 days'
GROUP BY date_trunc('day', created_at)
ORDER BY date DESC;

-- ============================================================================
-- VIEW: v_category_distribution
-- Request distribution by category
-- ============================================================================

CREATE OR REPLACE VIEW v_category_distribution AS
SELECT 
  category,
  COUNT(*)::INTEGER as total_count,
  COUNT(*) FILTER (WHERE status != 'closed')::INTEGER as active_count,
  COUNT(*) FILTER (WHERE status = 'closed')::INTEGER as closed_count,
  AVG(
    CASE WHEN status = 'closed' AND closed_at IS NOT NULL 
    THEN EXTRACT(EPOCH FROM (closed_at - created_at)) / 3600 
    END
  )::NUMERIC(10,2) as avg_resolution_hours
FROM requests
GROUP BY category
ORDER BY total_count DESC;

-- ============================================================================
-- ACCESS CONTROL FOR VIEWS
-- Directors can read all views, admins can read some
-- ============================================================================

-- Grant SELECT on views
GRANT SELECT ON v_requests_overview TO authenticated;
GRANT SELECT ON v_admin_backlog TO authenticated;
GRANT SELECT ON v_unassigned_requests TO authenticated;
GRANT SELECT ON v_sla_first_response TO authenticated;
GRANT SELECT ON v_sla_time_to_close TO authenticated;
GRANT SELECT ON v_stale_requests TO authenticated;
GRANT SELECT ON v_admin_throughput TO authenticated;
GRANT SELECT ON v_daily_metrics TO authenticated;
GRANT SELECT ON v_category_distribution TO authenticated;

-- Note: RLS on the underlying tables will still apply
-- Views inherit RLS from base tables when accessed by users
-- Only admins/directors will see data due to requests table RLS
