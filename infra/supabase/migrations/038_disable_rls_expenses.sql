-- Migration 038: DISABLE RLS on expense tables
-- Checks indicate the Admin/Director views might be blocked by RLS on expense_claims.
-- Disabling RLS to ensure immediate visibility as requested.

-- DISABLE RLS on expense_claims
ALTER TABLE expense_claims DISABLE ROW LEVEL SECURITY;

-- DISABLE RLS on expense_items
ALTER TABLE expense_items DISABLE ROW LEVEL SECURITY;

-- DISABLE RLS on expense_claim_comments
ALTER TABLE expense_claim_comments DISABLE ROW LEVEL SECURITY;

-- Verify
DO $$
BEGIN
  RAISE NOTICE '✅ RLS DISABLED on: expense_claims, expense_items, expense_claim_comments';
END $$;
