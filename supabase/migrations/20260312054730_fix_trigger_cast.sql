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
