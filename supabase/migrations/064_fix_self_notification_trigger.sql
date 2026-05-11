-- ============================================================================
-- Migration 064: Fix self-notification bug in request comment trigger
-- The trigger was storing notifications with user_id = comment author,
-- causing admins to see their own messages in their notification bell.
-- Now stores with user_id = request creator (the actual recipient).
-- ============================================================================

-- Step 1: Drop the existing trigger so we can recreate the function cleanly
DROP TRIGGER IF EXISTS trg_notify_request_comment ON public.request_comments;

-- Step 2: Recreate the function with the corrected user_id assignment
CREATE OR REPLACE FUNCTION public.notify_request_comment()
RETURNS TRIGGER AS $$
DECLARE
    v_req RECORD;
    v_author_name TEXT;
    v_notification_type TEXT := 'chat_message';
BEGIN
    BEGIN
        SELECT id, created_by, title INTO v_req
        FROM public.requests WHERE id = NEW.request_id;

        IF v_req.id IS NULL THEN
            RETURN NEW;
        END IF;

        -- Skip if comment author is the request creator (don't self-notify)
        IF NEW.author_id = v_req.created_by THEN
            RETURN NEW;
        END IF;

        SELECT name INTO v_author_name FROM public.employees WHERE id = NEW.author_id;

        -- Insert into notifications (in-app bell)
        -- FIXED: user_id is now the request creator (recipient), not the comment author
        INSERT INTO public.notifications (
            type, title, body, message, user_id, recipient_id, data, related_employee_id, created_at
        ) VALUES (
            v_notification_type,
            'New message from ' || COALESCE(v_author_name, 'Admin'),
            COALESCE(NEW.body, 'You have a new follow-up message'),
            COALESCE(NEW.body, 'You have a new follow-up message'),
            v_req.created_by,
            v_req.created_by,
            jsonb_build_object(
                'request_id', NEW.request_id,
                'comment_id', NEW.id,
                'claim_id', NEW.request_id
            ),
            v_req.created_by,
            NOW()
        );

        -- Also insert into mobile_notifications (push notifications)
        BEGIN
            INSERT INTO public.mobile_notifications (
                recipient_id, title, body, type, data
            ) VALUES (
                v_req.created_by,
                'New message from ' || COALESCE(v_author_name, 'Admin'),
                COALESCE(NEW.body, 'You have a new follow-up message'),
                'chat_message',
                jsonb_build_object('request_id', NEW.request_id, 'comment_id', NEW.id)
            );
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Failed to insert mobile_notification: %', SQLERRM;
        END;

        RETURN NEW;
    EXCEPTION WHEN OTHERS THEN
        -- Never let notification errors block comment insertion
        RAISE WARNING 'notify_request_comment error: %', SQLERRM;
        RETURN NEW;
    END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Step 3: Re-attach the trigger
CREATE TRIGGER trg_notify_request_comment
    AFTER INSERT ON public.request_comments
    FOR EACH ROW EXECUTE FUNCTION public.notify_request_comment();

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
    RAISE NOTICE '✅ Migration 064: Fixed self-notification bug. user_id now points to recipient.';
END $$;
