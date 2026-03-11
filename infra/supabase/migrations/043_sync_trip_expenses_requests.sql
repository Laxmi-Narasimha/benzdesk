-- ============================================================================
-- BenzDesk Database Schema - Migration 043: Sync Trip Expenses to Requests
-- Maps all trip_expenses 1:1 to requests so they appear natively in the
-- main Benzdesk Admin Queue with full chat and notification support.
-- ============================================================================

-- Backfill existing trip_expenses to requests
INSERT INTO requests (id, created_at, created_by, title, description, category, status, priority)
SELECT
    te.id,
    te.created_at,
    te.employee_id,
    'Trip Expense Claim' AS title,
    'Trip ID: ' || te.trip_id || chr(10) ||
    'Category: ' || te.category || chr(10) ||
    'Amount: ₹' || te.amount || chr(10) ||
    'Details: ' || COALESCE(te.description, 'N/A') AS description,
    'expense_claim' AS category,
    (CASE 
        WHEN te.status = 'pending' THEN 'open'::request_status
        WHEN te.status = 'approved' THEN 'closed'::request_status
        WHEN te.status = 'rejected' THEN 'closed'::request_status
        ELSE 'open'::request_status
    END) AS status,
    4 AS priority -- Default to Priority 4 (Low) for expenses
FROM trip_expenses te
ON CONFLICT (id) DO NOTHING;

-- Function to sync newly created trip_expenses into requests
CREATE OR REPLACE FUNCTION public.trigger_sync_trip_expense_to_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    INSERT INTO requests (
        id, created_at, created_by, title, description, category, status, priority
    ) VALUES (
        NEW.id,
        NEW.created_at,
        NEW.employee_id,
        'Trip Expense Claim',
        'Trip ID: ' || NEW.trip_id || chr(10) ||
        'Category: ' || NEW.category || chr(10) ||
        'Amount: ₹' || NEW.amount || chr(10) ||
        'Details: ' || COALESCE(NEW.description, 'N/A'),
        'expense_claim',
        'open',
        4
    ) ON CONFLICT (id) DO NOTHING;
    
    RETURN NEW;
END;
$$;

-- Attach trigger
DROP TRIGGER IF EXISTS sync_trip_expense_to_request_tg ON trip_expenses;
CREATE TRIGGER sync_trip_expense_to_request_tg
    AFTER INSERT ON trip_expenses
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_sync_trip_expense_to_request();

-- Note: We will handle status updates (Approved/Rejected) directly via the Next.js API/Frontend 
-- to ensure comments are properly appended to the requests timeline.
