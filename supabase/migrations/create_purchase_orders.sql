-- ============================================================================
-- Purchase Orders Table for PO Extractor Feature
-- Run this in Supabase SQL Editor
-- ============================================================================

CREATE TABLE IF NOT EXISTS purchase_orders (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  po_number TEXT NOT NULL,
  po_date DATE,
  vendor_name TEXT,
  vendor_address TEXT,
  vendor_gstin TEXT,
  vendor_pan TEXT,
  freight_charges TEXT DEFAULT 'Extras as actual',
  payment_terms TEXT DEFAULT 'Immediate Basis',
  currency TEXT DEFAULT 'INR',
  items JSONB DEFAULT '[]'::jsonb,
  subtotal NUMERIC(12,2) DEFAULT 0,
  igst NUMERIC(12,2) DEFAULT 0,
  round_off NUMERIC(12,2) DEFAULT 0,
  total NUMERIC(12,2) DEFAULT 0,
  raw_extracted_text TEXT,
  source_filename TEXT,
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE purchase_orders ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view their own POs"
  ON purchase_orders FOR SELECT
  USING (auth.uid() = created_by);

CREATE POLICY "Users can insert POs"
  ON purchase_orders FOR INSERT
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Users can update their own POs"
  ON purchase_orders FOR UPDATE
  USING (auth.uid() = created_by);
