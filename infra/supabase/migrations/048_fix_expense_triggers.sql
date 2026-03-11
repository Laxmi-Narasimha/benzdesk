-- ============================================================================
-- Migration 048: Fix Expense Triggers and Naming
-- Solves missing regular expenses by capturing draft -> submitted transition.
-- ============================================================================

-- Drop the old triggers and functions
DROP TRIGGER IF EXISTS sync_expense_claim_to_request_tg ON expense_claims;
DROP TRIGGER IF EXISTS sync_expense_claim_status_tg ON expense_claims;

-- Function to handle inserts (for claims immediately created as submitted)
CREATE OR REPLACE FUNCTION public.trigger_sync_expense_claim_to_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    final_title TEXT;
BEGIN
    IF NEW.status != 'draft' THEN
        -- Safely extract title if available inside []
        final_title := split_part(split_part(NEW.notes, ']', 1), '[', 2);
        IF final_title = '' OR final_title IS NULL THEN
            final_title := 'Expense Claim';
        END IF;

        INSERT INTO requests (
            id, created_at, created_by, title, description, category, status, priority, reference_id
        ) VALUES (
            NEW.id,
            NEW.created_at,
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

-- Function to handle updates (draft -> submitted transition)
CREATE OR REPLACE FUNCTION public.trigger_sync_expense_claim_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    final_title TEXT;
BEGIN
    -- Handle transition from draft to submitted
    IF OLD.status = 'draft' AND NEW.status != 'draft' THEN
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
    
    -- Handle other status transitions for existing requests
    ELSIF OLD.status IS DISTINCT FROM NEW.status AND OLD.status != 'draft' THEN
        -- If syncing to request status, keep it simple
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
