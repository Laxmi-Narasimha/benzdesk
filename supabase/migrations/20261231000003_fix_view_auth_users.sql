-- ============================================================================
-- BenzDesk Database Schema - Migration: Fix requests_with_creator View
-- The previous migration added security_invoker = on to enforce RLS, but
-- the view still joined auth.users which regular users cannot SELECT from.
-- Fix: Use employees table for both email and name (no auth.users needed).
-- ============================================================================

-- Force PostgREST schema reload
NOTIFY pgrst, 'reload schema';

-------------------------------------------------------------------------------
-- 1. RECREATE VIEW WITHOUT auth.users JOIN
-------------------------------------------------------------------------------
-- The employees table already has both email and name columns.
-- Authenticated users CAN read from employees, unlike auth.users.
-- We keep security_invoker = on so RLS on requests is still enforced.

DROP VIEW IF EXISTS requests_with_creator;

CREATE VIEW requests_with_creator WITH (security_invoker = on) AS
  SELECT r.*,
         e.email AS creator_email,
         e.name  AS creator_name
  FROM requests r
  LEFT JOIN employees e ON r.created_by = e.id;

-- Force postgrest reload
NOTIFY pgrst, 'reload schema';
