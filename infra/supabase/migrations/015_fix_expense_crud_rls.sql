-- Fix expense_claims UPDATE and DELETE RLS policies
-- Users need to be able to UPDATE (submit, update total) and DELETE (remove drafts) their own claims

-- 1. UPDATE Policy for expense_claims
DROP POLICY IF EXISTS "Users can update own expenses" ON expense_claims;
CREATE POLICY "Users can update own expenses" ON expense_claims 
FOR UPDATE
USING (employee_id = auth.uid())
WITH CHECK (employee_id = auth.uid());

-- 2. DELETE Policy for expense_claims
DROP POLICY IF EXISTS "Users can delete own expenses" ON expense_claims;
CREATE POLICY "Users can delete own expenses" ON expense_claims 
FOR DELETE
USING (employee_id = auth.uid());

-- 3. UPDATE Policy for expense_items
DROP POLICY IF EXISTS "Users can update own expense items" ON expense_items;
CREATE POLICY "Users can update own expense items" ON expense_items
FOR UPDATE
USING (EXISTS (
  SELECT 1 FROM expense_claims 
  WHERE expense_claims.id = expense_items.claim_id 
  AND expense_claims.employee_id = auth.uid()
))
WITH CHECK (EXISTS (
  SELECT 1 FROM expense_claims 
  WHERE expense_claims.id = expense_items.claim_id 
  AND expense_claims.employee_id = auth.uid()
));

-- 4. DELETE Policy for expense_items
DROP POLICY IF EXISTS "Users can delete own expense items" ON expense_items;
CREATE POLICY "Users can delete own expense items" ON expense_items
FOR DELETE
USING (EXISTS (
  SELECT 1 FROM expense_claims 
  WHERE expense_claims.id = expense_items.claim_id 
  AND expense_claims.employee_id = auth.uid()
));
