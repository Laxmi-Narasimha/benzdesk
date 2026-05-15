-- ============================================================================
-- Migration 050: Add reference_id to requests and enhance titles
-- Adds the missing reference_id column to the requests table so the DB 
-- triggers can sync expense claims without crashing. Also prepends the 
-- employee's name to the request title for better visibility in the admin UI.
-- ============================================================================

-- 1. Add the missing reference_id column to requests
ALTER TABLE IF EXISTS public.requests 
    ADD COLUMN IF NOT EXISTS reference_id UUID;

-- 2. Update Expense Claims Triggers to include Employee Name in Title
CREATE OR REPLACE FUNCTION public.trigger_sync_expense_claim_to_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    final_title TEXT;
    emp_name TEXT;
BEGIN
    SELECT name INTO emp_name FROM public.employees WHERE id = NEW.employee_id;
    IF emp_name IS NULL THEN
        emp_name := 'Employee';
    END IF;

    IF NEW.status != 'draft' THEN
        final_title := split_part(split_part(NEW.notes, ']', 1), '[', 2);
        IF final_title = '' OR final_title IS NULL THEN
            final_title := 'Expense Claim';
        END IF;

        final_title := emp_name || ' - ' || final_title;

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

CREATE OR REPLACE FUNCTION public.trigger_sync_expense_claim_status_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    final_title TEXT;
    emp_name TEXT;
BEGIN
    SELECT name INTO emp_name FROM public.employees WHERE id = NEW.employee_id;
    IF emp_name IS NULL THEN
        emp_name := 'Employee';
    END IF;

    IF OLD.status = 'draft' AND NEW.status != 'draft' THEN
        final_title := split_part(split_part(NEW.notes, ']', 1), '[', 2);
        IF final_title = '' OR final_title IS NULL THEN
            final_title := 'Expense Claim';
        END IF;

        final_title := emp_name || ' - ' || final_title;

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

-- 3. Update Trip Expenses Trigger to include Employee Name in Title
CREATE OR REPLACE FUNCTION public.trigger_sync_trip_expense_to_request()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    emp_name TEXT;
BEGIN
    SELECT name INTO emp_name FROM public.employees WHERE id = NEW.employee_id;
    IF emp_name IS NULL THEN
        emp_name := 'Employee';
    END IF;

    INSERT INTO requests (
        id, created_at, created_by, title, description, category, status, priority, reference_id
    ) VALUES (
        NEW.id,
        NEW.created_at,
        NEW.employee_id,
        emp_name || ' - Trip Expense Claim',
        'Trip ID: ' || NEW.trip_id || chr(10) ||
        'Category: ' || NEW.category || chr(10) ||
        'Amount: ₹' || NEW.amount || chr(10) ||
        'Details: ' || COALESCE(NEW.description, 'N/A'),
        'expense_claim',
        'open',
        4,
        NEW.id
    ) ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
