-- ============================================================================
-- Migration 033: Admin Delete Policies
-- Allows admins and directors to permanently delete comments and attachments
-- ============================================================================

-- ============================================================================
-- REQUEST_COMMENTS: Allow admins to delete any comment
-- ============================================================================

CREATE POLICY "Admins can delete comments"
  ON request_comments
  FOR DELETE
  USING (has_any_role(ARRAY['accounts_admin', 'director']::app_role[]));

-- ============================================================================
-- REQUEST_ATTACHMENTS: Allow admins and uploader to delete attachments
-- ============================================================================

CREATE POLICY "Admins can delete attachments"
  ON request_attachments
  FOR DELETE
  USING (has_any_role(ARRAY['accounts_admin', 'director']::app_role[]));

-- Requesters can also delete their own attachments
CREATE POLICY "Uploaders can delete own attachments"
  ON request_attachments
  FOR DELETE
  USING (uploaded_by = auth.uid());
