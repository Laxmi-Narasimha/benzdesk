-- ============================================================================
-- BenzDesk Database Schema - Migration 001: Initial Setup
-- Creates enums, tables, and indexes for the internal accounts request platform
-- ============================================================================

-- ============================================================================
-- ENUMS
-- ============================================================================

-- Application roles for authorization
CREATE TYPE app_role AS ENUM ('requester', 'accounts_admin', 'director');

-- Request lifecycle statuses
CREATE TYPE request_status AS ENUM (
  'open',
  'in_progress', 
  'waiting_on_requester',
  'closed'
);

-- Audit event types for complete history tracking
CREATE TYPE request_event_type AS ENUM (
  'created',
  'comment',
  'status_changed',
  'assigned',
  'closed',
  'reopened',
  'attachment_added',
  'attachment_removed'
);

-- ============================================================================
-- TABLES
-- ============================================================================

-- -----------------------------------------------------------------------------
-- user_roles: Application role assignments
-- Separates app roles from Supabase auth for flexibility
-- -----------------------------------------------------------------------------
CREATE TABLE user_roles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role app_role NOT NULL DEFAULT 'requester',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  
  -- Constraints
  CONSTRAINT valid_role CHECK (role IN ('requester', 'accounts_admin', 'director'))
);

-- Index for active role lookups
CREATE INDEX idx_user_roles_active ON user_roles(user_id) WHERE is_active = true;

-- -----------------------------------------------------------------------------
-- requests: Core ticket entity - current state of each request
-- -----------------------------------------------------------------------------
CREATE TABLE requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Creation metadata (immutable after insert)
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  
  -- Content
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 3 
    CHECK (priority >= 1 AND priority <= 5),
  
  -- Status
  status request_status NOT NULL DEFAULT 'open',
  assigned_to UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  
  -- Closure tracking
  closed_at TIMESTAMPTZ,
  closed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  
  -- Last modification tracking
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  
  -- Activity tracking for dashboard queries
  last_activity_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_activity_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  
  -- SLA tracking - first admin response
  first_admin_response_at TIMESTAMPTZ,
  first_admin_response_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  
  -- Optimistic concurrency control
  row_version INTEGER NOT NULL DEFAULT 1,
  
  -- Constraints
  CONSTRAINT valid_category CHECK (
    category IN (
      'invoice', 'reimbursement', 'vendor_payment', 'salary_query',
      'tax_document', 'expense_claim', 'budget_approval', 'other'
    )
  ),
  CONSTRAINT closed_consistency CHECK (
    (status = 'closed' AND closed_at IS NOT NULL AND closed_by IS NOT NULL) OR
    (status != 'closed' AND closed_at IS NULL AND closed_by IS NULL)
  )
);

-- Indexes for common query patterns
CREATE INDEX idx_requests_created_by ON requests(created_by, created_at DESC);
CREATE INDEX idx_requests_status ON requests(status, created_at DESC);
CREATE INDEX idx_requests_assigned ON requests(assigned_to, status) WHERE assigned_to IS NOT NULL;
CREATE INDEX idx_requests_activity ON requests(last_activity_at DESC);
CREATE INDEX idx_requests_open ON requests(created_at DESC) WHERE status != 'closed';

-- -----------------------------------------------------------------------------
-- request_comments: User-visible conversation on requests
-- -----------------------------------------------------------------------------
CREATE TABLE request_comments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id UUID NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  body TEXT NOT NULL,
  
  -- Internal comments visible only to admins/director
  is_internal BOOLEAN NOT NULL DEFAULT false,
  
  -- Constraints
  CONSTRAINT non_empty_body CHECK (length(trim(body)) > 0)
);

-- Index for fetching comments by request
CREATE INDEX idx_request_comments_thread ON request_comments(request_id, created_at);
CREATE INDEX idx_request_comments_author ON request_comments(author_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- request_events: Append-only audit log for complete history
-- NO UPDATE OR DELETE ALLOWED - enforced by RLS and triggers
-- -----------------------------------------------------------------------------
CREATE TABLE request_events (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id UUID NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  actor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  event_type request_event_type NOT NULL,
  
  -- State change data
  old_data JSONB NOT NULL DEFAULT '{}',
  new_data JSONB NOT NULL DEFAULT '{}',
  
  -- Optional note for context
  note TEXT
);

-- Index for fetching events by request
CREATE INDEX idx_request_events_timeline ON request_events(request_id, created_at);
CREATE INDEX idx_request_events_actor ON request_events(actor_id, created_at DESC);
CREATE INDEX idx_request_events_type ON request_events(event_type, created_at DESC);

-- -----------------------------------------------------------------------------
-- request_attachments: File metadata (files stored in Supabase Storage)
-- -----------------------------------------------------------------------------
CREATE TABLE request_attachments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id UUID NOT NULL REFERENCES requests(id) ON DELETE CASCADE,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  uploaded_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  
  -- Storage location
  bucket TEXT NOT NULL,
  path TEXT NOT NULL,
  
  -- File metadata
  original_filename TEXT NOT NULL,
  mime_type TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  
  -- Constraints
  CONSTRAINT valid_mime_type CHECK (
    mime_type IN (
      'application/pdf',
      'image/jpeg',
      'image/png',
      'image/gif',
      'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    )
  ),
  CONSTRAINT valid_size CHECK (size_bytes > 0 AND size_bytes <= 10485760), -- 10MB max
  CONSTRAINT unique_path UNIQUE (bucket, path)
);

-- Index for fetching attachments by request
CREATE INDEX idx_request_attachments_request ON request_attachments(request_id, uploaded_at);
CREATE INDEX idx_request_attachments_uploader ON request_attachments(uploaded_by, uploaded_at DESC);

-- ============================================================================
-- STORAGE BUCKET
-- ============================================================================

-- Create storage bucket for attachments
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'benzdesk',
  'benzdesk',
  false,  -- Private bucket
  10485760,  -- 10MB limit
  ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/gif',
        'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
) ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function to check if current user has a specific role
CREATE OR REPLACE FUNCTION public.has_role(required_role app_role)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM user_roles 
    WHERE user_id = auth.uid() 
      AND role = required_role 
      AND is_active = true
  );
$$;

-- Function to check if current user has any of the specified roles
CREATE OR REPLACE FUNCTION public.has_any_role(required_roles app_role[])
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM user_roles 
    WHERE user_id = auth.uid() 
      AND role = ANY(required_roles) 
      AND is_active = true
  );
$$;

-- Function to get current user's role
CREATE OR REPLACE FUNCTION public.get_user_role()
RETURNS app_role
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT role 
  FROM user_roles 
  WHERE user_id = auth.uid() 
    AND is_active = true
  LIMIT 1;
$$;

-- Function to check if user can access a specific request
CREATE OR REPLACE FUNCTION public.can_access_request(request_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM requests r
    WHERE r.id = request_id
    AND (
      -- Requester can access own requests
      r.created_by = auth.uid()
      -- Admins and directors can access all
      OR has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
    )
  );
$$;

-- ============================================================================
-- GRANTS
-- ============================================================================

-- Grant usage on types
GRANT USAGE ON TYPE app_role TO authenticated;
GRANT USAGE ON TYPE request_status TO authenticated;
GRANT USAGE ON TYPE request_event_type TO authenticated;

-- Grant execute on helper functions
GRANT EXECUTE ON FUNCTION public.has_role TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_any_role TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_role TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_request TO authenticated;
