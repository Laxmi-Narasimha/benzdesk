-- ============================================================================
-- Migration 019: Fix Expense Categories & Status Column
-- Fixes:
-- 1. Updates expense_items CHECK constraint to include all BenzDesk categories
-- 2. Fixes status column for migration 018 enum conversion
-- ============================================================================

-- ============================================================================
-- STEP 1: Fix expense_items category constraint  
-- Add all 11 BenzDesk categories
-- ============================================================================

-- Drop the existing constraint
ALTER TABLE expense_items DROP CONSTRAINT IF EXISTS expense_items_category_check;

-- Add the new constraint with all BenzDesk categories
-- Categories aligned with BenzDesk request types + daily expense tracking
ALTER TABLE expense_items ADD CONSTRAINT expense_items_category_check
CHECK (category IN (
  -- Travel & Transport
  'travel_allowance',     -- TA/DA as per BenzDesk
  'transport_expense',    -- Transport/conveyance
  'local_conveyance',     -- Local travel
  'fuel',                 -- Fuel for company vehicle
  'toll',                 -- Toll charges
  
  -- Daily Expenses
  'food',                 -- Food & meals (daily allowance)
  'accommodation',        -- Hotel stay
  
  -- Business Expenses
  'petty_cash',           -- Petty cash expenses
  'advance_request',      -- Advance expenses
  'mobile_internet',      -- Phone/internet recharge
  'stationary',           -- Office supplies
  'medical',              -- Medical expenses
  
  -- Other
  'other'                 -- Miscellaneous
));

-- ============================================================================
-- STEP 2: Fix status column for enum conversion
-- Drop the default before converting, then re-add it
-- ============================================================================

-- Drop the default constraint on status column
ALTER TABLE expense_claims ALTER COLUMN status DROP DEFAULT;

-- Now the enum conversion from migration 018 will work
-- If status enum doesn't exist yet, create it
DO $$
BEGIN
  CREATE TYPE expense_claim_status AS ENUM (
    'draft',
    'submitted',
    'in_review',
    'approved',
    'rejected'
  );
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- Convert any invalid status values
UPDATE expense_claims SET status = 'submitted' WHERE status = 'pending';

-- Now convert the column type
DO $$
BEGIN
  ALTER TABLE expense_claims ALTER COLUMN status TYPE expense_claim_status 
    USING status::expense_claim_status;
EXCEPTION
  WHEN others THEN
    -- If it's already the correct type, ignore the error
    null;
END $$;

-- Re-add the default
ALTER TABLE expense_claims ALTER COLUMN status SET DEFAULT 'draft';

-- ============================================================================
-- STEP 3: Add missing columns to expense_claims if not exists
-- (from migration 018 that may have failed)
-- ============================================================================

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

-- ============================================================================
-- STEP 4: Create event type enum if not exists
-- ============================================================================

DO $$
BEGIN
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
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- STEP 5: Create tables from migration 018 if they don't exist
-- ============================================================================

-- Comments table
CREATE TABLE IF NOT EXISTS expense_claim_comments (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  claim_id UUID NOT NULL REFERENCES expense_claims(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES employees(id) ON DELETE RESTRICT,
  body TEXT NOT NULL,
  is_internal BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT non_empty_comment_body CHECK (length(trim(body)) > 0)
);

-- Events table
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

-- Attachments table
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
  CONSTRAINT valid_attachment_size CHECK (size_bytes > 0 AND size_bytes <= 10485760)
);

-- Create indexes if not exist
CREATE INDEX IF NOT EXISTS idx_expense_comments_claim ON expense_claim_comments(claim_id, created_at);
CREATE INDEX IF NOT EXISTS idx_expense_events_claim ON expense_claim_events(claim_id, created_at);
CREATE INDEX IF NOT EXISTS idx_expense_attachments_claim ON expense_claim_attachments(claim_id, uploaded_at);

-- ============================================================================
-- STEP 6: Enable RLS on new tables
-- ============================================================================

ALTER TABLE expense_claim_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_claim_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_claim_attachments ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 7: Create RLS policies for new tables
-- ============================================================================

-- Comments policies
DROP POLICY IF EXISTS "Employees view own claim comments" ON expense_claim_comments;
CREATE POLICY "Employees view own claim comments" ON expense_claim_comments
FOR SELECT USING (
  claim_id IN (SELECT id FROM expense_claims WHERE employee_id = auth.uid())
  AND is_internal = false
);

DROP POLICY IF EXISTS "Employees add comments to own claims" ON expense_claim_comments;
CREATE POLICY "Employees add comments to own claims" ON expense_claim_comments
FOR INSERT WITH CHECK (
  claim_id IN (SELECT id FROM expense_claims WHERE employee_id = auth.uid())
  AND author_id = auth.uid()
  AND is_internal = false
);

DROP POLICY IF EXISTS "Admins view all comments" ON expense_claim_comments;
CREATE POLICY "Admins view all comments" ON expense_claim_comments
FOR SELECT USING (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

DROP POLICY IF EXISTS "Admins add comments" ON expense_claim_comments;
CREATE POLICY "Admins add comments" ON expense_claim_comments
FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
  AND author_id = auth.uid()
);

-- Events policies  
DROP POLICY IF EXISTS "Employees view own claim events" ON expense_claim_events;
CREATE POLICY "Employees view own claim events" ON expense_claim_events
FOR SELECT USING (
  claim_id IN (SELECT id FROM expense_claims WHERE employee_id = auth.uid())
);

DROP POLICY IF EXISTS "Admins view all events" ON expense_claim_events;
CREATE POLICY "Admins view all events" ON expense_claim_events
FOR SELECT USING (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

-- Attachments policies
DROP POLICY IF EXISTS "Employees view own claim attachments" ON expense_claim_attachments;
CREATE POLICY "Employees view own claim attachments" ON expense_claim_attachments
FOR SELECT USING (
  claim_id IN (SELECT id FROM expense_claims WHERE employee_id = auth.uid())
);

DROP POLICY IF EXISTS "Employees upload to own claims" ON expense_claim_attachments;
CREATE POLICY "Employees upload to own claims" ON expense_claim_attachments
FOR INSERT WITH CHECK (
  claim_id IN (SELECT id FROM expense_claims WHERE employee_id = auth.uid())
  AND uploaded_by = auth.uid()
);

DROP POLICY IF EXISTS "Employees delete own attachments" ON expense_claim_attachments;
CREATE POLICY "Employees delete own attachments" ON expense_claim_attachments
FOR DELETE USING (uploaded_by = auth.uid());

DROP POLICY IF EXISTS "Admins view all attachments" ON expense_claim_attachments;
CREATE POLICY "Admins view all attachments" ON expense_claim_attachments
FOR SELECT USING (
  EXISTS (SELECT 1 FROM employees WHERE id = auth.uid() AND role IN ('admin', 'super_admin'))
);

-- ============================================================================
-- STEP 8: Create storage bucket for receipts
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'benzmobitraq-receipts',
  'benzmobitraq-receipts',
  false,
  10485760,
  ARRAY['application/pdf', 'image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp']
) ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- STEP 9: Grant permissions
-- ============================================================================

DO $$
BEGIN
  GRANT USAGE ON TYPE expense_claim_status TO authenticated;
  GRANT USAGE ON TYPE expense_event_type TO authenticated;
EXCEPTION
  WHEN others THEN null;
END $$;

-- ============================================================================
-- SUCCESS
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Migration 019 completed successfully!';
  RAISE NOTICE '   - Fixed expense_items category constraint (11 categories)';
  RAISE NOTICE '   - Fixed status column for enum conversion';
  RAISE NOTICE '   - Created comments, events, attachments tables';
  RAISE NOTICE '   - Applied RLS policies';
  RAISE NOTICE '   - Created storage bucket';
END $$;
