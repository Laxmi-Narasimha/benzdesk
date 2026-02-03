-- ============================================================================
-- Migration 035: Fix Expense Comments RLS and Mobile Visibility
-- FIXES:
--   1. Comment posting fails (RLS INSERT blocked)
--   2. Expenses not visible in mobile app (missing owner SELECT policy)
-- ============================================================================

-- ============================================================================
-- STEP 1: expense_claim_comments - Allow INSERT for authenticated users
-- ============================================================================

-- Enable RLS if not already enabled
ALTER TABLE expense_claim_comments ENABLE ROW LEVEL SECURITY;

-- Drop any existing policies to avoid conflicts
DROP POLICY IF EXISTS "Users can insert comments on their claims" ON expense_claim_comments;
DROP POLICY IF EXISTS "Admins can insert comments" ON expense_claim_comments;
DROP POLICY IF EXISTS "Users can view comments on their claims" ON expense_claim_comments;
DROP POLICY IF EXISTS "Admins can view all comments" ON expense_claim_comments;

-- INSERT: Employees can comment on their own expense claims
CREATE POLICY "Users can insert comments on their claims" ON expense_claim_comments
FOR INSERT WITH CHECK (
  -- Author must be the authenticated user
  author_id = auth.uid()
  AND
  -- Claim must belong to the user OR user is admin
  EXISTS (
    SELECT 1 FROM expense_claims ec
    WHERE ec.id = expense_claim_comments.claim_id
    AND (
      ec.employee_id = auth.uid()
      OR EXISTS (
        SELECT 1 FROM employees e
        WHERE e.id = auth.uid()
        AND e.role IN ('admin', 'super_admin', 'director')
      )
    )
  )
);

-- SELECT: Users can see comments on their own claims
CREATE POLICY "Users can view comments on their claims" ON expense_claim_comments
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM expense_claims ec
    WHERE ec.id = expense_claim_comments.claim_id
    AND ec.employee_id = auth.uid()
  )
);

-- SELECT: Admins can view all comments
CREATE POLICY "Admins can view all comments" ON expense_claim_comments
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM employees e
    WHERE e.id = auth.uid()
    AND e.role IN ('admin', 'super_admin', 'director')
  )
);

-- INSERT: Admins can comment on any claim
CREATE POLICY "Admins can insert comments" ON expense_claim_comments
FOR INSERT WITH CHECK (
  author_id = auth.uid()
  AND EXISTS (
    SELECT 1 FROM employees e
    WHERE e.id = auth.uid()
    AND e.role IN ('admin', 'super_admin', 'director')
  )
);

-- ============================================================================
-- STEP 2: expense_claims - Employees can see their OWN claims (mobile app)
-- ============================================================================

DROP POLICY IF EXISTS "Employees can view own claims" ON expense_claims;

CREATE POLICY "Employees can view own claims" ON expense_claims
FOR SELECT USING (
  employee_id = auth.uid()
);

-- ============================================================================
-- STEP 3: expense_items - Employees can see items of their OWN claims
-- ============================================================================

DROP POLICY IF EXISTS "Employees can view own expense items" ON expense_items;

CREATE POLICY "Employees can view own expense items" ON expense_items
FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM expense_claims ec
    WHERE ec.id = expense_items.claim_id
    AND ec.employee_id = auth.uid()
  )
);

-- ============================================================================
-- STEP 4: Enable realtime for expense tables (for live sync)
-- ============================================================================

-- This requires supabase_realtime publication
-- Check if tables are already in the publication
DO $$
BEGIN
  -- Add expense_claims to realtime if not present
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'expense_claims'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE expense_claims;
    RAISE NOTICE 'Added expense_claims to realtime publication';
  END IF;

  -- Add expense_claim_comments to realtime if not present
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' 
    AND tablename = 'expense_claim_comments'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE expense_claim_comments;
    RAISE NOTICE 'Added expense_claim_comments to realtime publication';
  END IF;
END $$;

-- ============================================================================
-- SUCCESS
-- ============================================================================

DO $$
BEGIN
  RAISE NOTICE '✅ Migration 035 completed successfully!';
  RAISE NOTICE '   - Added INSERT policy for expense_claim_comments (employees)';
  RAISE NOTICE '   - Added INSERT policy for expense_claim_comments (admins)';
  RAISE NOTICE '   - Added SELECT policy for expense_claim_comments (owners)';
  RAISE NOTICE '   - Added SELECT policy for expense_claim_comments (admins)';
  RAISE NOTICE '   - Added SELECT policy for expense_claims (owners)';
  RAISE NOTICE '   - Added SELECT policy for expense_items (owners)';
  RAISE NOTICE '   - Enabled realtime for expense tables';
END $$;
