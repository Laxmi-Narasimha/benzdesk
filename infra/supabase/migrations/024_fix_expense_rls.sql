-- Fix expense_claims RLS policy for mobile app
-- The INSERT policy needs to allow users to insert with any employee_id that matches auth.uid()

-- First, drop the existing INSERT policy
DROP POLICY IF EXISTS "Users can create own expenses" ON expense_claims;

-- Create a new INSERT policy that properly allows authenticated users to insert their own claims
CREATE POLICY "Users can create own expenses" ON expense_claims 
FOR INSERT 
WITH CHECK (employee_id = auth.uid());

-- Also add a more permissive SELECT policy for authenticated users to see their own claims
DROP POLICY IF EXISTS "Users can view own expenses" ON expense_claims;
CREATE POLICY "Users can view own expenses" ON expense_claims 
FOR SELECT 
USING (employee_id = auth.uid());

-- Fix expense_items RLS to allow insert if user owns the claim
DROP POLICY IF EXISTS "Users can add items to own claims" ON expense_items;
CREATE POLICY "Users can add items to own claims" ON expense_items
FOR INSERT 
WITH CHECK (EXISTS (
  SELECT 1 FROM expense_claims 
  WHERE expense_claims.id = claim_id 
  AND expense_claims.employee_id = auth.uid()
));

-- Note: If employee_id in the mobile app doesn't match auth.uid(), 
-- the PreferencesLocal.userId needs to be set to the Supabase auth.uid() value
-- This migration assumes they should be the same
