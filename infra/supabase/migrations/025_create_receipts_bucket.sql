-- Migration: Create benzmobitraq-receipts storage bucket
-- This bucket stores expense receipts (images, PDFs, Excel files)

-- Create the storage bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'benzmobitraq-receipts',
  'benzmobitraq-receipts',
  false,
  10485760, -- 10MB max file size
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
    'application/pdf',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- RLS Policies for the bucket

-- Allow authenticated users to upload their own receipts
CREATE POLICY "Users can upload own receipts"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'benzmobitraq-receipts' AND
  (storage.foldername(name))[1] = 'receipts'
);

-- Allow users to view their own receipts
CREATE POLICY "Users can view own receipts"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'benzmobitraq-receipts'
);

-- Allow users to delete their own receipts
CREATE POLICY "Users can delete own receipts"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'benzmobitraq-receipts'
);

-- Allow updates (e.g., for replacing files)
CREATE POLICY "Users can update own receipts"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'benzmobitraq-receipts')
WITH CHECK (bucket_id = 'benzmobitraq-receipts');
