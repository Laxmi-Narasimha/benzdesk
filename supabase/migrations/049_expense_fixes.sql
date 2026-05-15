-- ============================================================================
-- BenzDesk Database Schema - Migration 049: Unified Expense System Fixes
-- Fixes trigger conditions for regular expenses, missing category constraints,
-- missing session_id columns on trip_expenses, and view profiles mapping.
-- ============================================================================

-- Force PostgREST schema reload so new columns are immediately queryable 
NOTIFY pgrst, 'reload schema';

-------------------------------------------------------------------------------
-- 1. Patch trip_expenses schema mapping
-------------------------------------------------------------------------------
-- Safely add session_id if migration 045 failed
ALTER TABLE IF EXISTS public.trip_expenses 
    ADD COLUMN IF NOT EXISTS session_id UUID;

-- Optional constraint (won't throw if shift_sessions missing)
DO $$
BEGIN
    IF EXISTS (
        SELECT FROM pg_catalog.pg_class c
        JOIN   pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE  n.nspname = 'public'
        AND    c.relname = 'shift_sessions'
    ) THEN
        ALTER TABLE public.trip_expenses
            DROP CONSTRAINT IF EXISTS fk_trip_expenses_session;
        ALTER TABLE public.trip_expenses
            ADD CONSTRAINT fk_trip_expenses_session FOREIGN KEY (session_id) REFERENCES shift_sessions(id) ON DELETE SET NULL;
    END IF;
END $$;

-------------------------------------------------------------------------------
-- 2. Patch categories constraint on expense_items
-------------------------------------------------------------------------------
-- Required for post-session fuel expenses
ALTER TABLE IF EXISTS public.expense_items 
    DROP CONSTRAINT IF EXISTS expense_items_category_check;

ALTER TABLE IF EXISTS public.expense_items
    ADD CONSTRAINT expense_items_category_check CHECK (
        category IN (
            'local_conveyance', 'fuel', 'toll', 'outstation_travel',
            'food_da', 'food', 'accommodation', 'laundry',
            'internet', 'mobile',
            'petty_cash', 'advance_request', 'stationary', 'medical',
            'travel_allowance', 'transport_expense', 'mobile_internet',
            'other', 'fuel_bike', 'fuel_car'
        )
    );

-------------------------------------------------------------------------------
-- 3. Patch Regular Expense Trippers (expense_claims -> requests)
-------------------------------------------------------------------------------
DROP TRIGGER IF EXISTS sync_expense_claim_to_request_tg ON expense_claims;
DROP TRIGGER IF EXISTS sync_expense_claim_status_tg ON expense_claims;

-- Function 1: Trigger on INSERT ONLY if non-draft (rare, since usually insert is draft)
CREATE OR REPLACE FUNCTION public.trigger_sync_expense_claim_to_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    final_title TEXT;
BEGIN
    IF NEW.status != 'draft' THEN
        final_title := split_part(split_part(NEW.notes, ']', 1), '[', 2);
        IF final_title = '' OR final_title IS NULL THEN
            final_title := 'Expense Claim';
        END IF;

        INSERT INTO requests (
            id, created_at, created_by, title, description, category, status, priority, reference_id
        ) VALUES (
            NEW.id,
            COALESCE(NEW.submitted_at, NOW()),
            NEW.employee_id,
            final_title,
            'Amount: ₹' || NEW.total_amount || chr(10) ||
            'Notes: ' || COALESCE(NEW.notes, 'N/A'),
            'expense_claim',
            'open',
            4,
            NEW.id
        ) ON CONFLICT (id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER sync_expense_claim_to_request_tg
    AFTER INSERT ON expense_claims
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_sync_expense_claim_to_request();

-- Function 2: Trigger on UPDATE when transitioned OUT of draft OR status change
CREATE OR REPLACE FUNCTION public.trigger_sync_expense_claim_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    final_title TEXT;
BEGIN
    IF OLD.status = 'draft' AND NEW.status != 'draft' THEN
        -- Safely extract title, fallback to "Expense Claim"
        final_title := split_part(split_part(NEW.notes, ']', 1), '[', 2);
        IF final_title = '' OR final_title IS NULL THEN
            final_title := 'Expense Claim';
        END IF;

        INSERT INTO requests (
            id, created_at, created_by, title, description, category, status, priority, reference_id
        ) VALUES (
            NEW.id,
            COALESCE(NEW.submitted_at, NOW()),
            NEW.employee_id,
            final_title,
            'Amount: ₹' || NEW.total_amount || chr(10) ||
            'Notes: ' || COALESCE(NEW.notes, 'N/A'),
            'expense_claim',
            'open',
            4,
            NEW.id
        ) ON CONFLICT (id) DO NOTHING;
        
    ELSIF OLD.status IS DISTINCT FROM NEW.status AND OLD.status != 'draft' THEN
        IF NEW.status = 'submitted' THEN
             UPDATE requests SET status = 'open'::request_status WHERE id = NEW.id;
        ELSIF NEW.status = 'approved' OR NEW.status = 'rejected' THEN
             UPDATE requests SET status = 'closed'::request_status WHERE id = NEW.id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER sync_expense_claim_status_tg
    AFTER UPDATE ON expense_claims
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_sync_expense_claim_status_update();

-------------------------------------------------------------------------------
-- 4. View Mapping for requests_with_creator (Fixing profile names)
-------------------------------------------------------------------------------
CREATE OR REPLACE VIEW requests_with_creator AS
  SELECT r.*,
         u.email AS creator_email,
         e.name AS creator_name
  FROM requests r
  LEFT JOIN auth.users u ON r.created_by = u.id
  LEFT JOIN employees e ON r.created_by = e.id;

-- Force postgrest reload again
NOTIFY pgrst, 'reload schema';
