-- Migration: re-relax notifications_type_check (defensive)
--
-- User hit this in production while submitting a new request:
--   new row for relation "notifications" violates check constraint
--   "notifications_type_check"
--
-- Cause: migration 059_fix_all_issues.sql had set the constraint to a
-- strict allow-list of 9 hardcoded type strings. Subsequent migrations
-- 062 and 20260515000003 relaxed it to `length(type) <= 100`. But
-- newer trigger functions (063_fix_status_update_trigger.sql) write
-- types like 'expense_status_change' that aren't in the 059 allow-list.
-- If 062/20260515 didn't run cleanly in prod, the INSERT fails.
--
-- This migration is intentionally narrow and idempotent: it drops
-- whatever notifications_type_check currently exists and re-adds the
-- permissive form. Safe to run repeatedly.

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (
    type IS NULL OR length(type) <= 100
  );

DO $$
BEGIN
    RAISE NOTICE 'notifications_type_check: now permissive (length <= 100)';
END $$;
