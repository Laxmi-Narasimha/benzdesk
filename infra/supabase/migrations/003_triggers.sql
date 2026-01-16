-- ============================================================================
-- BenzDesk Database Schema - Migration 003: Triggers
-- Implements automatic audit logging and timestamp management
-- ============================================================================

-- ============================================================================
-- AUDIT LOG TRIGGER FUNCTION
-- Inserts events into request_events with SECURITY DEFINER to bypass RLS
-- ============================================================================

CREATE OR REPLACE FUNCTION log_request_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor_id UUID;
  v_event_type request_event_type;
  v_old_data JSONB := '{}';
  v_new_data JSONB := '{}';
BEGIN
  -- Get current user ID
  v_actor_id := auth.uid();
  
  -- Determine event type based on operation
  IF TG_OP = 'INSERT' THEN
    v_event_type := 'created';
    v_new_data := jsonb_build_object(
      'title', NEW.title,
      'description', NEW.description,
      'category', NEW.category,
      'priority', NEW.priority,
      'status', NEW.status
    );
    
    -- Insert the event
    INSERT INTO request_events (request_id, actor_id, event_type, old_data, new_data)
    VALUES (NEW.id, COALESCE(v_actor_id, NEW.created_by), v_event_type, v_old_data, v_new_data);
    
  ELSIF TG_OP = 'UPDATE' THEN
    -- Check what changed and log appropriately
    
    -- Status changed
    IF OLD.status IS DISTINCT FROM NEW.status THEN
      IF NEW.status = 'closed' AND OLD.status != 'closed' THEN
        v_event_type := 'closed';
      ELSIF OLD.status = 'closed' AND NEW.status != 'closed' THEN
        v_event_type := 'reopened';
      ELSE
        v_event_type := 'status_changed';
      END IF;
      
      v_old_data := jsonb_build_object('status', OLD.status);
      v_new_data := jsonb_build_object('status', NEW.status);
      
      INSERT INTO request_events (request_id, actor_id, event_type, old_data, new_data)
      VALUES (NEW.id, v_actor_id, v_event_type, v_old_data, v_new_data);
    END IF;
    
    -- Assignment changed
    IF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to THEN
      v_event_type := 'assigned';
      v_old_data := jsonb_build_object('assigned_to', OLD.assigned_to);
      v_new_data := jsonb_build_object('assigned_to', NEW.assigned_to);
      
      INSERT INTO request_events (request_id, actor_id, event_type, old_data, new_data)
      VALUES (NEW.id, v_actor_id, v_event_type, v_old_data, v_new_data);
    END IF;
    
    -- Priority changed
    IF OLD.priority IS DISTINCT FROM NEW.priority THEN
      v_old_data := jsonb_build_object('priority', OLD.priority);
      v_new_data := jsonb_build_object('priority', NEW.priority);
      
      INSERT INTO request_events (request_id, actor_id, event_type, old_data, new_data, note)
      VALUES (NEW.id, v_actor_id, 'status_changed', v_old_data, v_new_data, 'Priority changed');
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Apply trigger to requests table
CREATE TRIGGER trg_request_audit
  AFTER INSERT OR UPDATE ON requests
  FOR EACH ROW
  EXECUTE FUNCTION log_request_event();

-- ============================================================================
-- COMMENT AUDIT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION log_comment_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_role app_role;
  v_request RECORD;
BEGIN
  -- Get user's role
  SELECT role INTO v_user_role 
  FROM user_roles 
  WHERE user_id = NEW.author_id AND is_active = true;
  
  -- Get request data
  SELECT * INTO v_request FROM requests WHERE id = NEW.request_id;
  
  -- Log the comment event
  INSERT INTO request_events (request_id, actor_id, event_type, new_data)
  VALUES (
    NEW.request_id, 
    NEW.author_id, 
    'comment',
    jsonb_build_object(
      'comment_id', NEW.id,
      'is_internal', NEW.is_internal,
      'body_preview', left(NEW.body, 100)
    )
  );
  
  -- Update last_activity on the request
  UPDATE requests
  SET 
    last_activity_at = now(),
    last_activity_by = NEW.author_id
  WHERE id = NEW.request_id;
  
  -- Track first admin response
  IF v_user_role IN ('accounts_admin', 'director') 
     AND v_request.first_admin_response_at IS NULL THEN
    UPDATE requests
    SET 
      first_admin_response_at = now(),
      first_admin_response_by = NEW.author_id
    WHERE id = NEW.request_id
    AND first_admin_response_at IS NULL;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Apply trigger to comments table
CREATE TRIGGER trg_comment_audit
  AFTER INSERT ON request_comments
  FOR EACH ROW
  EXECUTE FUNCTION log_comment_event();

-- ============================================================================
-- ATTACHMENT AUDIT TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION log_attachment_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Log attachment added
    INSERT INTO request_events (request_id, actor_id, event_type, new_data)
    VALUES (
      NEW.request_id,
      NEW.uploaded_by,
      'attachment_added',
      jsonb_build_object(
        'attachment_id', NEW.id,
        'filename', NEW.original_filename,
        'mime_type', NEW.mime_type,
        'size_bytes', NEW.size_bytes
      )
    );
    
    -- Update last_activity
    UPDATE requests
    SET 
      last_activity_at = now(),
      last_activity_by = NEW.uploaded_by
    WHERE id = NEW.request_id;
    
  ELSIF TG_OP = 'DELETE' THEN
    -- Log attachment removed (get actor from session)
    INSERT INTO request_events (request_id, actor_id, event_type, old_data)
    VALUES (
      OLD.request_id,
      COALESCE(auth.uid(), OLD.uploaded_by),
      'attachment_removed',
      jsonb_build_object(
        'attachment_id', OLD.id,
        'filename', OLD.original_filename
      )
    );
  END IF;
  
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- Apply trigger to attachments table
CREATE TRIGGER trg_attachment_audit
  AFTER INSERT OR DELETE ON request_attachments
  FOR EACH ROW
  EXECUTE FUNCTION log_attachment_event();

-- ============================================================================
-- REQUEST UPDATE TIMESTAMPS TRIGGER
-- ============================================================================

CREATE OR REPLACE FUNCTION update_request_timestamps()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Set updated timestamp
  NEW.updated_at := now();
  NEW.updated_by := auth.uid();
  
  -- Set last activity
  NEW.last_activity_at := now();
  NEW.last_activity_by := auth.uid();
  
  -- Increment row version for optimistic concurrency
  NEW.row_version := OLD.row_version + 1;
  
  -- Handle closure
  IF NEW.status = 'closed' AND OLD.status != 'closed' THEN
    NEW.closed_at := now();
    NEW.closed_by := auth.uid();
  ELSIF NEW.status != 'closed' AND OLD.status = 'closed' THEN
    NEW.closed_at := NULL;
    NEW.closed_by := NULL;
  END IF;
  
  -- Track first admin response on update
  IF NEW.first_admin_response_at IS NULL THEN
    DECLARE
      v_user_role app_role;
    BEGIN
      SELECT role INTO v_user_role 
      FROM user_roles 
      WHERE user_id = auth.uid() AND is_active = true;
      
      IF v_user_role IN ('accounts_admin', 'director') THEN
        NEW.first_admin_response_at := now();
        NEW.first_admin_response_by := auth.uid();
      END IF;
    END;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Apply BEFORE trigger for timestamp updates
CREATE TRIGGER trg_request_timestamps
  BEFORE UPDATE ON requests
  FOR EACH ROW
  EXECUTE FUNCTION update_request_timestamps();

-- ============================================================================
-- PREVENT AUDIT LOG MODIFICATIONS
-- ============================================================================

CREATE OR REPLACE FUNCTION prevent_audit_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'Modifications to the audit log are not allowed';
END;
$$;

-- Prevent updates on request_events
CREATE TRIGGER trg_prevent_event_update
  BEFORE UPDATE ON request_events
  FOR EACH ROW
  EXECUTE FUNCTION prevent_audit_modification();

-- Prevent deletes on request_events
CREATE TRIGGER trg_prevent_event_delete
  BEFORE DELETE ON request_events
  FOR EACH ROW
  EXECUTE FUNCTION prevent_audit_modification();
