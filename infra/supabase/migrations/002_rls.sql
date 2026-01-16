-- ============================================================================
-- BenzDesk Database Schema - Migration 002: Row Level Security
-- Implements strict database-level access control
-- ============================================================================

-- ============================================================================
-- ENABLE RLS ON ALL TABLES
-- ============================================================================

ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE request_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE request_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE request_attachments ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- USER_ROLES POLICIES
-- ============================================================================

-- Users can read their own role
CREATE POLICY "Users can read own role"
  ON user_roles
  FOR SELECT
  USING (user_id = auth.uid());

-- Directors can read all roles (for admin management)
CREATE POLICY "Directors can read all roles"
  ON user_roles
  FOR SELECT
  USING (has_role('director'));

-- Only directors can insert roles (provisioning)
CREATE POLICY "Directors can insert roles"
  ON user_roles
  FOR INSERT
  WITH CHECK (has_role('director'));

-- Only directors can update roles
CREATE POLICY "Directors can update roles"
  ON user_roles
  FOR UPDATE
  USING (has_role('director'))
  WITH CHECK (has_role('director'));

-- No one can delete roles (use is_active = false for offboarding)
-- (No DELETE policy = no deletes allowed)

-- ============================================================================
-- REQUESTS POLICIES
-- ============================================================================

-- Requesters can only see their own requests
CREATE POLICY "Requesters can read own requests"
  ON requests
  FOR SELECT
  USING (created_by = auth.uid());

-- Admins and Directors can see all requests
CREATE POLICY "Admins can read all requests"
  ON requests
  FOR SELECT
  USING (has_any_role(ARRAY['accounts_admin', 'director']::app_role[]));

-- Requesters can create requests (only for themselves)
CREATE POLICY "Requesters can create requests"
  ON requests
  FOR INSERT
  WITH CHECK (
    created_by = auth.uid()
    AND has_role('requester')
  );

-- Admins can also create requests (on behalf of walk-in requesters)
CREATE POLICY "Admins can create requests"
  ON requests
  FOR INSERT
  WITH CHECK (has_any_role(ARRAY['accounts_admin', 'director']::app_role[]));

-- Only admins can update requests (status, assignment, etc.)
CREATE POLICY "Admins can update requests"
  ON requests
  FOR UPDATE
  USING (has_any_role(ARRAY['accounts_admin', 'director']::app_role[]))
  WITH CHECK (has_any_role(ARRAY['accounts_admin', 'director']::app_role[]));

-- No one can delete requests (use status = 'closed')
-- (No DELETE policy = no deletes allowed)

-- ============================================================================
-- REQUEST_COMMENTS POLICIES
-- ============================================================================

-- Users can read non-internal comments on their own requests
CREATE POLICY "Requesters can read comments on own requests"
  ON request_comments
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM requests r 
      WHERE r.id = request_comments.request_id 
      AND r.created_by = auth.uid()
    )
    AND is_internal = false
  );

-- Admins and Directors can read all comments (including internal)
CREATE POLICY "Admins can read all comments"
  ON request_comments
  FOR SELECT
  USING (has_any_role(ARRAY['accounts_admin', 'director']::app_role[]));

-- Requesters can add non-internal comments to their own requests
CREATE POLICY "Requesters can comment on own requests"
  ON request_comments
  FOR INSERT
  WITH CHECK (
    author_id = auth.uid()
    AND is_internal = false
    AND EXISTS (
      SELECT 1 FROM requests r 
      WHERE r.id = request_comments.request_id 
      AND r.created_by = auth.uid()
    )
  );

-- Admins can add comments (including internal) to any request
CREATE POLICY "Admins can add comments"
  ON request_comments
  FOR INSERT
  WITH CHECK (
    author_id = auth.uid()
    AND has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
  );

-- No updates or deletes on comments (immutable conversation)
-- (No UPDATE/DELETE policies = no modifications allowed)

-- ============================================================================
-- REQUEST_EVENTS POLICIES (AUDIT LOG)
-- ============================================================================

-- Users can read events on requests they can access
CREATE POLICY "Users can read events on accessible requests"
  ON request_events
  FOR SELECT
  USING (can_access_request(request_id));

-- NO INSERT POLICY FOR USERS - only triggers can insert events
-- This ensures audit log integrity
-- Events are inserted via SECURITY DEFINER functions/triggers

-- Grant insert to service role only (for triggers)
-- The trigger functions will run as SECURITY DEFINER

-- No updates or deletes on events (append-only audit log)
-- (No UPDATE/DELETE policies = immutable log)

-- ============================================================================
-- REQUEST_ATTACHMENTS POLICIES
-- ============================================================================

-- Users can read attachments on requests they can access
CREATE POLICY "Users can read attachments on accessible requests"
  ON request_attachments
  FOR SELECT
  USING (can_access_request(request_id));

-- Requesters can upload attachments to their own requests
CREATE POLICY "Requesters can upload to own requests"
  ON request_attachments
  FOR INSERT
  WITH CHECK (
    uploaded_by = auth.uid()
    AND EXISTS (
      SELECT 1 FROM requests r 
      WHERE r.id = request_attachments.request_id 
      AND r.created_by = auth.uid()
    )
  );

-- Admins can upload attachments to any request
CREATE POLICY "Admins can upload attachments"
  ON request_attachments
  FOR INSERT
  WITH CHECK (
    uploaded_by = auth.uid()
    AND has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
  );

-- No updates on attachments (metadata is immutable)
-- Deletes would need to also remove from storage and log the event
-- (No UPDATE policy = no modifications)

-- ============================================================================
-- STORAGE POLICIES (Supabase Storage)
-- ============================================================================

-- Policy for reading files from benzdesk bucket
CREATE POLICY "Users can read attachments they have access to"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'benzdesk'
    AND (
      -- Check if user can access the request
      -- Path format: requests/<request_id>/<filename>
      can_access_request(
        (string_to_array(name, '/'))[2]::uuid
      )
    )
  );

-- Policy for uploading files to benzdesk bucket
CREATE POLICY "Users can upload to their own request folders"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'benzdesk'
    AND (
      -- Admins can upload anywhere
      has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
      OR
      -- Requesters can only upload to their own request folders
      EXISTS (
        SELECT 1 FROM requests r
        WHERE r.id = (string_to_array(name, '/'))[2]::uuid
        AND r.created_by = auth.uid()
      )
    )
  );

-- Policy for deleting files (optional, restricted)
CREATE POLICY "Only admins can delete attachments"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'benzdesk'
    AND has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
  );
