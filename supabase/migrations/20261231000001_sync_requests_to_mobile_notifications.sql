-- Migration to link the new unified Requests queue to Mobile Notifications
-- Automatically generate notifications for employees when admins interact with their expenses

-- 1. Trigger for Request Status Updates
CREATE OR REPLACE FUNCTION trigger_notify_on_request_update()
RETURNS TRIGGER AS $$
BEGIN
    -- Only notify if status changed and the request belongs to an employee
    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.created_by IS NOT NULL THEN
        
        -- Insert into mobile_notifications
        INSERT INTO mobile_notifications (
            recipient_id,
            title,
            body,
            type,
            data
        ) VALUES (
            NEW.created_by,
            'Expense Status: ' || upper(NEW.status::text),
            'Your expense claim "' || COALESCE(NEW.title, 'Request') || '" was ' || NEW.status::text,
            CASE 
                WHEN NEW.status::text = 'approved' THEN 'expense_approved'
                WHEN NEW.status::text = 'rejected' THEN 'expense_rejected'
                ELSE 'expense_submitted'
            END,
            jsonb_build_object('request_id', NEW.id, 'reference_id', NEW.reference_id, 'status', NEW.status::text)
        );
        
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_on_request_update ON requests;
CREATE TRIGGER trg_notify_on_request_update
    AFTER UPDATE OF status ON requests
    FOR EACH ROW
    EXECUTE FUNCTION trigger_notify_on_request_update();

-- 2. Trigger for Request Comments
CREATE OR REPLACE FUNCTION trigger_notify_on_request_comment()
RETURNS TRIGGER AS $$
DECLARE
    v_owner_id UUID;
    v_request_title TEXT;
    v_author_name TEXT;
BEGIN
    -- Get the request owner and title
    SELECT created_by, title INTO v_owner_id, v_request_title
    FROM requests WHERE id = NEW.request_id;
    
    -- Get the author name
    SELECT name INTO v_author_name FROM employees WHERE id = NEW.author_id;
    
    -- Only notify if the comment is from someone else to the owner
    IF v_owner_id IS NOT NULL AND NEW.author_id != v_owner_id THEN
        INSERT INTO mobile_notifications (
            recipient_id,
            title,
            body,
            type,
            data
        ) VALUES (
            v_owner_id,
            'New Admin Message',
            COALESCE(v_author_name, 'Admin') || ' replied: ' || NEW.body,
            'expense_submitted',
            jsonb_build_object('request_id', NEW.request_id)
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_notify_on_request_comment ON request_comments;
CREATE TRIGGER trg_notify_on_request_comment
    AFTER INSERT ON request_comments
    FOR EACH ROW
    EXECUTE FUNCTION trigger_notify_on_request_comment();

-- 3. Enable Stuck Alert Cron using pg_cron
-- We will replace the pure pg_cron syntax with an everyday Postgres approach if pg_cron is not enabled.
-- Supabase automatically supports pg_cron if enabled.
DO $$ 
BEGIN
    -- Schedule the stuck detection
    PERFORM cron.schedule(
        'check-stuck-employees',
        '*/5 * * * *',
        'SELECT check_stuck_employees()'
    );
EXCEPTION WHEN OTHERS THEN
    -- Ignore if pg_cron is not available or already scheduled
    NULL;
END $$;
