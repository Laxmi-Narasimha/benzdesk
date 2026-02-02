-- ============================================================================
-- BenzMobiTraq Expense Management System - Migration 018
-- Complete expense claim system with chat, audit log, and attachments
-- ============================================================================

-- ============================================================================
-- ENUMS
-- ============================================================================

-- Expense claim status workflow
CREATE TYPE expense_claim_status AS ENUM (
  'draft',
  'submitted',
  'in_review',
  'approved',
  'rejected'
);

-- Event types for audit trail
CREATE TYPE expense_event_type AS ENUM (
  'created',
  'submitted',
  'comment_added',
  'status_changed',
  'assigned',
  'approved',
  'rejected',
  'attachment_added',
  'attachment_removed'
);

-- ============================================================================
-- MODIFY EXISTING TABLES
-- ============================================================================

-- Add new columns to expense_claims for enhanced workflow
ALTER TABLE expense_claims
  ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 3 CHECK (priority >= 1 AND priority <= 5),
  ADD COLUMN IF NOT EXISTS assigned_to UUID REFERENCES employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS closed_by UUID REFERENCES employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS first_admin_response_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS first_admin_response_by UUID REFERENCES employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS last_activity_by UUID REFERENCES employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

-- Update existing status column to use new enum (if needed)
-- Note: This assumes your current status is a text column
DO $$
BEGIN
  -- Try to alter the column type
  BEGIN
    ALTER TABLE expense_claims ALTER COLUMN status TYPE expense_claim_status USING status::expense_claim_status;
  EXCEPTION
    WHEN invalid_text_representation THEN
      -- If conversion fails, update values first
      UPDATE expense_claims SET status = 'submitted' WHERE status = 'pending';
      UPDATE expense_claims SET status = 'draft' WHERE status NOT IN ('submitted', 'approved', 'rejected');
      ALTER TABLE expense_claims ALTER COLUMN status TYPE expense_claim_status USING status::expense_claim_status;
  END;
END $$;

-- ============================================================================
-- NEW TABLES
-- ============================================================================

-- -----------------------------------------------------------------------------
-- expense_claim_comments: Chat/conversation on expense claims
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS expense_claim_comments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  claim_id UUID NOT NULL REFERENCES expense_claims(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  body TEXT NOT NULL,
  is_internal BOOLEAN NOT NULL DEFAULT false, -- Admin-only notes
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT non_empty_comment_body CHECK (length(trim(body)) > 0)
);

CREATE INDEX idx_expense_comments_claim ON expense_claim_comments(claim_id, created_at);
CREATE INDEX idx_expense_comments_author ON expense_claim_comments(author_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- expense_claim_events: Append-only audit log
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS expense_claim_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  claim_id UUID NOT NULL REFERENCES expense_claims(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  event_type expense_event_type NOT NULL,
  old_data JSONB NOT NULL DEFAULT '{}',
  new_data JSONB NOT NULL DEFAULT '{}',
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_expense_events_claim ON expense_claim_events(claim_id, created_at);
CREATE INDEX idx_expense_events_actor ON expense_claim_events(actor_id, created_at DESC);
CREATE INDEX idx_expense_events_type ON expense_claim_events(event_type, created_at DESC);

-- -----------------------------------------------------------------------------
-- expense_claim_attachments: File metadata (files in Supabase Storage)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS expense_claim_attachments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  claim_id UUID NOT NULL REFERENCES expense_claims(id) ON DELETE CASCADE,
  uploaded_by UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  bucket TEXT NOT NULL DEFAULT 'benzmobitraq-receipts',
  path TEXT NOT NULL,
  original_filename TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  CONSTRAINT valid_attachment_mime_type CHECK (
    mime_type IN (
      'application/pdf',
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/gif',
      'image/webp'
    )
  ),
  CONSTRAINT valid_attachment_size CHECK (size_bytes > 0 AND size_bytes <= 10485760), -- 10MB max
  CONSTRAINT unique_attachment_path UNIQUE (bucket, path)
);

CREATE INDEX idx_expense_attachments_claim ON expense_claim_attachments(claim_id, uploaded_at);
CREATE INDEX idx_expense_attachments_uploader ON expense_claim_attachments(uploaded_by, uploaded_at DESC);

-- ============================================================================
-- STORAGE BUCKET
-- ============================================================================

-- Create storage bucket for expense receipts
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'benzmobitraq-receipts',
  'benzmobitraq-receipts',
  false,  -- Private bucket
  10485760,  -- 10MB limit
  ARRAY['application/pdf', 'image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp']
) ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

-- Enable RLS
ALTER TABLE expense_claim_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_claim_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_claim_attachments ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- expense_claim_comments POLICIES
-- -----------------------------------------------------------------------------

-- Employees can view comments on their own claims (excluding internal admin notes)
CREATE POLICY "Employees view own claim comments" ON expense_claim_comments
FOR SELECT
USING (
  claim_id IN (
    SELECT id FROM expense_claims WHERE employee_id = auth.uid()
  )
  AND is_internal = false
);

-- Employees can add comments to their own claims
CREATE POLICY "Employees add comments to own claims" ON expense_claim_comments
FOR INSERT
WITH CHECK (
  claim_id IN (
    SELECT id FROM expense_claims WHERE employee_id = auth.uid()
  )
  AND author_id = auth.uid()
  AND is_internal = false
);

-- Admins can view all comments (including internal notes)
CREATE POLICY "Admins view all comments" ON expense_claim_comments
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
  )
);

-- Admins can add comments (including internal notes)
CREATE POLICY "Admins add comments" ON expense_claim_comments
FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
  )
  AND author_id = auth.uid()
);

-- -----------------------------------------------------------------------------
-- expense_claim_events POLICIES (Read-only for all)
-- -----------------------------------------------------------------------------

-- Employees can view events on their own claims
CREATE POLICY "Employees view own claim events" ON expense_claim_events
FOR SELECT
USING (
  claim_id IN (
    SELECT id FROM expense_claims WHERE employee_id = auth.uid()
  )
);

-- Admins can view all events
CREATE POLICY "Admins view all events" ON expense_claim_events
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
  )
);

-- -----------------------------------------------------------------------------
-- expense_claim_attachments POLICIES
-- -----------------------------------------------------------------------------

-- Employees can view attachments on their own claims
CREATE POLICY "Employees view own claim attachments" ON expense_claim_attachments
FOR SELECT
USING (
  claim_id IN (
    SELECT id FROM expense_claims WHERE employee_id = auth.uid()
  )
);

-- Employees can upload attachments to their own claims
CREATE POLICY "Employees upload to own claims" ON expense_claim_attachments
FOR INSERT
WITH CHECK (
  claim_id IN (
    SELECT id FROM expense_claims WHERE employee_id = auth.uid()
  )
  AND uploaded_by = auth.uid()
);

-- Employees can delete their own attachments
CREATE POLICY "Employees delete own attachments" ON expense_claim_attachments
FOR DELETE
USING (uploaded_by = auth.uid());

-- Admins can view all attachments
CREATE POLICY "Admins view all attachments" ON expense_claim_attachments
FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM employees WHERE id = auth.uid() AND role = 'admin'
  )
);

-- ============================================================================
-- TRIGGERS FOR AUTO-POPULATING EVENTS
-- ============================================================================

-- Function to log expense claim events
CREATE OR REPLACE FUNCTION log_expense_claim_event()
RETURNS TRIGGER AS $$
DECLARE
  event_typ expense_event_type;
  old_dat jsonb := '{}';
  new_dat jsonb := '{}';
  note_text text := NULL;
BEGIN
  -- Determine event type
  IF (TG_OP = 'INSERT') THEN
    event_typ := 'created';
    new_dat := jsonb_build_object('status', NEW.status::text);
  ELSIF (TG_OP = 'UPDATE') THEN
    IF (OLD.status != NEW.status) THEN
      event_typ := 'status_changed';
      old_dat := jsonb_build_object('status', OLD.status::text);
      new_dat := jsonb_build_object('status', NEW.status::text);
      
      IF (NEW.status = 'approved') THEN
        event_typ := 'approved';
      ELSIF (NEW.status = 'rejected') THEN
        event_typ := 'rejected';
        note_text := NEW.rejection_reason;
      ELSIF (NEW.status = 'submitted') THEN
        event_typ := 'submitted';
      END IF;
    ELSIF (OLD.assigned_to IS DISTINCT FROM NEW.assigned_to) THEN
      event_typ := 'assigned';
      old_dat := jsonb_build_object('assigned_to', OLD.assigned_to);
      new_dat := jsonb_build_object('assigned_to', NEW.assigned_to);
    ELSE
      -- No significant change, skip event
      RETURN NEW;
    END IF;
  ELSE
    RETURN NEW;
  END IF;

  -- Insert event
  INSERT INTO expense_claim_events (claim_id, actor_id, event_type, old_data, new_data, note)
  VALUES (
    COALESCE(NEW.id, OLD.id),
    auth.uid(),
    event_typ,
    old_dat,
    new_dat,
    note_text
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger
DROP TRIGGER IF EXISTS expense_claim_event_trigger ON expense_claims;
CREATE TRIGGER expense_claim_event_trigger
  AFTER INSERT OR UPDATE ON expense_claims
  FOR EACH ROW
  EXECUTE FUNCTION log_expense_claim_event();

-- Function to log comment events
CREATE OR REPLACE FUNCTION log_comment_event()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO expense_claim_events (claim_id, actor_id, event_type, new_data)
  VALUES (
    NEW.claim_id,
    NEW.author_id,
    'comment_added',
    jsonb_build_object('comment_id', NEW.id, 'is_internal', NEW.is_internal)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Attach trigger
DROP TRIGGER IF EXISTS comment_event_trigger ON expense_claim_comments;
CREATE TRIGGER comment_event_trigger
  AFTER INSERT ON expense_claim_comments
  FOR EACH ROW
  EXECUTE FUNCTION log_comment_event();

-- ============================================================================
-- GRANTS
-- ============================================================================

GRANT USAGE ON TYPE expense_claim_status TO authenticated;
GRANT USAGE ON TYPE expense_event_type TO authenticated;

-- ============================================================================
-- COMPLETE
-- ============================================================================

-- Success message
DO $$
BEGIN
  RAISE NOTICE '✅ Expense management system migration completed successfully';
  RAISE NOTICE '   - Added status workflow (draft → submitted → in_review → approved/rejected)';
  RAISE NOTICE '   - Created comments table for chat functionality';
  RAISE NOTICE '   - Created events table for audit logging';
  RAISE NOTICE '   - Created attachments table for receipts';
  RAISE NOTICE '   - Configured RLS policies for security';
  RAISE NOTICE '   - Set up automatic event logging triggers';
END $$;
