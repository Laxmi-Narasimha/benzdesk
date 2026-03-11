-- ============================================================================
-- Migration 046: Sync Expense Claims to Requests (Unified Queue)
-- Ensures standalone expense_claims also appear in the master
-- requests queue alongside trip_expenses, with full chat/attachment support.
-- ============================================================================

-- Remove outdated category constraint — categories have evolved beyond the original list
ALTER TABLE requests DROP CONSTRAINT IF EXISTS valid_category;

-- Remove closed_consistency constraint to allow expense inserts with null closed_at/closed_by
ALTER TABLE requests DROP CONSTRAINT IF EXISTS closed_consistency;

-- Backfill existing expense_claims to requests
INSERT INTO requests (id, created_at, created_by, title, description, category, status, priority)
SELECT
    ec.id,
    ec.created_at,
    ec.employee_id,
    'Expense Claim' AS title,
    'Amount: ₹' || ec.total_amount || chr(10) ||
    'Notes: ' || COALESCE(ec.notes, 'N/A') AS description,
    'expense_claim' AS category,
    'open'::request_status AS status,
    4 AS priority
FROM expense_claims ec
WHERE ec.status != 'draft'
ON CONFLICT (id) DO NOTHING;

-- Function to sync newly created expense_claims into requests
CREATE OR REPLACE FUNCTION public.trigger_sync_expense_claim_to_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.status != 'draft' THEN
        INSERT INTO requests (
            id, created_at, created_by, title, description, category, status, priority
        ) VALUES (
            NEW.id,
            NEW.created_at,
            NEW.employee_id,
            'Expense Claim',
            'Amount: ₹' || NEW.total_amount || chr(10) ||
            'Notes: ' || COALESCE(NEW.notes, 'N/A'),
            'expense_claim',
            'open',
            4
        ) ON CONFLICT (id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_expense_claim_to_request_tg ON expense_claims;
CREATE TRIGGER sync_expense_claim_to_request_tg
    AFTER INSERT ON expense_claims
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_sync_expense_claim_to_request();

-- Sync status changes
CREATE OR REPLACE FUNCTION public.trigger_sync_expense_claim_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        UPDATE requests
        SET status = 'open'::request_status
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_expense_claim_status_tg ON expense_claims;
CREATE TRIGGER sync_expense_claim_status_tg
    AFTER UPDATE ON expense_claims
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_sync_expense_claim_status();
