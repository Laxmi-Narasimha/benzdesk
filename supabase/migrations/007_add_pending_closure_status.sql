-- ============================================================================
-- Migration: Add pending_closure status
-- Implements two-step closure workflow
-- ============================================================================

-- Add pending_closure to the request_status enum
-- Note: In PostgreSQL, you can add enum values with ALTER TYPE
DO $$ 
BEGIN
    -- Check if the value already exists to make this idempotent
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum 
        WHERE enumlabel = 'pending_closure' 
        AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'request_status')
    ) THEN
        ALTER TYPE request_status ADD VALUE 'pending_closure' BEFORE 'closed';
    END IF;
END $$;

-- ============================================================================
-- IMPORTANT: Run this migration in Supabase SQL Editor
-- The new workflow:
-- 1. Admin sets status to 'pending_closure' instead of directly to 'closed'
-- 2. Employee sees a banner asking them to confirm or reopen
-- 3. If employee clicks "Confirm Close", status becomes 'closed'
-- 4. If employee clicks "Reopen", status becomes 'open' again
-- ============================================================================
