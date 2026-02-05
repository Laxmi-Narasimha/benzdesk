-- ============================================================================
-- Migration 039: Robust Session Closure
-- Adds a server-side function to force-close stuck sessions.
-- This allows Admins to recover from "zombie" sessions caused by network failures.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.force_end_session(target_session_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_session_record RECORD;
  v_employee_id UUID;
BEGIN
  -- 1. Check if session exists
  SELECT * INTO v_session_record
  FROM shift_sessions
  WHERE id = target_session_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'Session not found');
  END IF;

  -- 2. If already completed, just ensure state is cleared and return success
  IF v_session_record.status = 'completed' THEN
    -- Ensure employee_states is clear
    UPDATE employee_states
    SET current_session_id = NULL, is_stuck = false, updated_at = NOW()
    WHERE current_session_id = target_session_id;
    
    RETURN jsonb_build_object('success', true, 'message', 'Session was already completed');
  END IF;

  v_employee_id := v_session_record.employee_id;

  -- 3. Force update session to completed
  -- We use COALESCE to keep existing data where possible, but ensure valid end state
  UPDATE shift_sessions
  SET 
    end_time = COALESCE(end_time, NOW()), -- Use existing end_time if set (e.g. partial upload), else NOW
    status = 'completed',
    updated_at = NOW(),
    -- Ensure total_km is not null (DB constraint might allow null, but logic prefers 0)
    total_km = COALESCE(total_km, 0)
  WHERE id = target_session_id;

  -- 4. Clear employee state
  -- This is critical so the Mobile App stops "Resuming" the session
  UPDATE employee_states
  SET 
    current_session_id = NULL,
    is_stuck = false,
    updated_at = NOW()
  WHERE current_session_id = target_session_id;

  -- 5. Log activity (Optional, but good for audit)
  -- We could insert into an audit log if it existed.
  
  RETURN jsonb_build_object('success', true, 'session_id', target_session_id);
END;
$$;

-- Grant execution permission to authenticated users (so Admin UI can call it)
GRANT EXECUTE ON FUNCTION public.force_end_session(UUID) TO authenticated;

-- Log migration
DO $$
BEGIN
  RAISE NOTICE 'Migration 039 complete: force_end_session function created.';
END $$;
