-- ============================================================================
-- Migration 026: Expense Policy Update (BENZ Travel Policy Feb 2026)
-- Updates expense categories to align with BENZ Travel Policy
-- ============================================================================

-- ============================================================================
-- STEP 1: Update expense_items category constraint with new categories
-- ============================================================================

-- Drop the existing constraint
ALTER TABLE expense_items DROP CONSTRAINT IF EXISTS expense_items_category_check;

-- Add the new constraint with all BENZ Travel Policy categories
ALTER TABLE expense_items ADD CONSTRAINT expense_items_category_check
CHECK (category IN (
  -- Travel & Transport
  'local_conveyance',     -- Local travel (Auto, Bus, Cab)
  'fuel',                 -- Car @₹7.5/km, Bike @₹5/km
  'toll',                 -- Toll / Parking (Actuals)
  'outstation_travel',    -- Flight / Train / Bus tickets
  
  -- Daily Allowances (Outstation)
  'food_da',              -- Food & Daily Allowance
  'food',                 -- Legacy: Food & meals
  'accommodation',        -- Hotel stay (via Corporate MMT)
  'laundry',              -- Laundry (Max ₹300/day if >3 nights)
  
  -- Miscellaneous (Actuals)
  'internet',             -- Internet / Connectivity
  'mobile',               -- Mobile Recharge
  
  -- Business Expenses
  'petty_cash',           -- Small office expenses
  'advance_request',      -- Pre-approved advances
  'stationary',           -- Office supplies
  'medical',              -- Emergency medical
  
  -- Legacy categories (for backward compatibility)
  'travel_allowance',     -- TA/DA (maps to local_conveyance)
  'transport_expense',    -- Transport (maps to local_conveyance)
  'mobile_internet',      -- Legacy combined category
  
  -- Other
  'other'                 -- Miscellaneous
));

-- ============================================================================
-- STEP 2: Update attachment mime types to include Excel
-- ============================================================================

ALTER TABLE expense_claim_attachments 
  DROP CONSTRAINT IF EXISTS valid_attachment_mime_type;

ALTER TABLE expense_claim_attachments 
  ADD CONSTRAINT valid_attachment_mime_type CHECK (
    mime_type IN (
      'application/pdf',
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/gif',
      'image/webp',
      'application/vnd.ms-excel',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    )
  );

-- ============================================================================
-- STEP 3: Add employee band/grade column if not exists
-- Needed for policy-based limit enforcement
-- ============================================================================

ALTER TABLE employees
  ADD COLUMN IF NOT EXISTS band TEXT DEFAULT 'executive'
    CHECK (band IN (
      'executive',
      'senior_executive', 
      'assistant',
      'assistant_manager',
      'manager',
      'senior_manager',
      'agm',
      'gm',
      'plant_head',
      'vp',
      'director'
    ));

-- ============================================================================
-- STEP 4: Add limit_exceeded flag to expense_items
-- For flagging expenses that exceed policy limits
-- ============================================================================

ALTER TABLE expense_items
  ADD COLUMN IF NOT EXISTS exceeds_limit BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS limit_amount NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS requires_skip_approval BOOLEAN DEFAULT false;

-- ============================================================================
-- STEP 5: Add approved_by column to track approver
-- ============================================================================

ALTER TABLE expense_claims
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS rejected_by UUID REFERENCES employees(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS approval_level TEXT DEFAULT 'pending'
    CHECK (approval_level IN ('pending', 'manager', 'head', 'hr', 'finance', 'complete'));

-- ============================================================================
-- STEP 6: Create index for faster expense queries
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_expense_claims_status ON expense_claims(status);
CREATE INDEX IF NOT EXISTS idx_expense_claims_employee ON expense_claims(employee_id);
CREATE INDEX IF NOT EXISTS idx_expense_items_claim ON expense_items(claim_id);
CREATE INDEX IF NOT EXISTS idx_expense_items_category ON expense_items(category);

-- ============================================================================
-- STEP 7: Update storage bucket with Excel MIME types
-- ============================================================================

UPDATE storage.buckets 
SET allowed_mime_types = ARRAY[
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'application/pdf',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
]
WHERE id = 'benzmobitraq-receipts';

-- ============================================================================
-- SUCCESS
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Migration 026 completed successfully!';
  RAISE NOTICE '   - Updated expense categories (14 categories)';
  RAISE NOTICE '   - Added Excel MIME types to attachments';
  RAISE NOTICE '   - Added employee band column';
  RAISE NOTICE '   - Added limit tracking columns';
  RAISE NOTICE '   - Added approval tracking columns';
END $$;
