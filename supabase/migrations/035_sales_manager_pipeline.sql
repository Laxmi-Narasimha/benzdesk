-- ============================================================================
-- Migration 035: Sales Manager Pipeline
-- Adds sales_manager role, amount field, manager approval flow, and team mapping
-- ============================================================================

-- ============================================================================
-- 1. ADD NEW ENUM VALUES
-- NOTE: PostgreSQL enums are non-transactional; run each ALTER separately
-- ============================================================================

-- Add 'sales_manager' role
DO $$ BEGIN
    ALTER TYPE app_role ADD VALUE 'sales_manager';
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- Add 'pending_manager_approval' status
DO $$ BEGIN
    ALTER TYPE request_status ADD VALUE 'pending_manager_approval';
EXCEPTION WHEN duplicate_object THEN null;
END $$;

-- ============================================================================
-- 2. ADD COLUMNS TO REQUESTS TABLE
-- ============================================================================

-- Claimed amount entered by the requester
ALTER TABLE requests ADD COLUMN IF NOT EXISTS amount NUMERIC(12,2) DEFAULT NULL;

-- Manager approval tracking
ALTER TABLE requests ADD COLUMN IF NOT EXISTS manager_approved_at TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS manager_approved_by UUID REFERENCES auth.users(id) DEFAULT NULL;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS manager_adjusted_amount NUMERIC(12,2) DEFAULT NULL;

-- ============================================================================
-- 3. MANAGER TEAM TABLE
-- Maps each sales_manager to their team members
-- ============================================================================

CREATE TABLE IF NOT EXISTS manager_team (
    id SERIAL PRIMARY KEY,
    manager_user_id UUID NOT NULL REFERENCES auth.users(id),
    member_user_id  UUID NOT NULL REFERENCES auth.users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (manager_user_id, member_user_id)
);

ALTER TABLE manager_team ENABLE ROW LEVEL SECURITY;

-- Sales managers can see their own team
CREATE POLICY "Managers can read own team"
    ON manager_team FOR SELECT
    USING (manager_user_id = auth.uid());

-- Directors can see all teams
CREATE POLICY "Directors can read all teams"
    ON manager_team FOR SELECT
    USING (has_role('director'));

-- Only directors can manage team memberships
CREATE POLICY "Directors can insert team"
    ON manager_team FOR INSERT
    WITH CHECK (has_role('director'));

CREATE POLICY "Directors can delete team"
    ON manager_team FOR DELETE
    USING (has_role('director'));

-- ============================================================================
-- 4. HELPER FUNCTION: get_user_manager
-- Returns the manager_user_id for a given team member, or NULL
-- ============================================================================

CREATE OR REPLACE FUNCTION get_user_manager(p_user_id UUID)
RETURNS UUID
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
    SELECT manager_user_id FROM manager_team WHERE member_user_id = p_user_id LIMIT 1;
$$;

-- ============================================================================
-- 5. RLS POLICIES FOR REQUESTS — SALES MANAGER ACCESS
-- ============================================================================

-- Sales managers can read requests from their team members
CREATE POLICY "Sales managers can read team requests"
    ON requests FOR SELECT
    USING (
        has_role('sales_manager')
        AND created_by IN (
            SELECT member_user_id FROM manager_team WHERE manager_user_id = auth.uid()
        )
    );

-- Sales managers can update approval fields on team requests
CREATE POLICY "Sales managers can approve team requests"
    ON requests FOR UPDATE
    USING (
        has_role('sales_manager')
        AND created_by IN (
            SELECT member_user_id FROM manager_team WHERE manager_user_id = auth.uid()
        )
    )
    WITH CHECK (
        has_role('sales_manager')
        AND created_by IN (
            SELECT member_user_id FROM manager_team WHERE manager_user_id = auth.uid()
        )
    );

-- ============================================================================
-- 6. RLS POLICIES FOR REQUEST_COMMENTS — SALES MANAGER ACCESS
-- ============================================================================

-- Sales managers can read comments on their team's requests
CREATE POLICY "Sales managers can read team comments"
    ON request_comments FOR SELECT
    USING (
        has_role('sales_manager')
        AND EXISTS (
            SELECT 1 FROM requests r
            WHERE r.id = request_comments.request_id
            AND r.created_by IN (
                SELECT member_user_id FROM manager_team WHERE manager_user_id = auth.uid()
            )
        )
    );

-- Sales managers can add comments to team requests
CREATE POLICY "Sales managers can comment on team requests"
    ON request_comments FOR INSERT
    WITH CHECK (
        author_id = auth.uid()
        AND has_role('sales_manager')
        AND EXISTS (
            SELECT 1 FROM requests r
            WHERE r.id = request_comments.request_id
            AND r.created_by IN (
                SELECT member_user_id FROM manager_team WHERE manager_user_id = auth.uid()
            )
        )
    );

-- ============================================================================
-- 7. RLS POLICIES FOR REQUEST_EVENTS — SALES MANAGER ACCESS
-- ============================================================================

CREATE POLICY "Sales managers can read team events"
    ON request_events FOR SELECT
    USING (
        has_role('sales_manager')
        AND EXISTS (
            SELECT 1 FROM requests r
            WHERE r.id = request_events.request_id
            AND r.created_by IN (
                SELECT member_user_id FROM manager_team WHERE manager_user_id = auth.uid()
            )
        )
    );

-- ============================================================================
-- 8. RLS POLICIES FOR REQUEST_ATTACHMENTS — SALES MANAGER ACCESS
-- ============================================================================

CREATE POLICY "Sales managers can read team attachments"
    ON request_attachments FOR SELECT
    USING (
        has_role('sales_manager')
        AND EXISTS (
            SELECT 1 FROM requests r
            WHERE r.id = request_attachments.request_id
            AND r.created_by IN (
                SELECT member_user_id FROM manager_team WHERE manager_user_id = auth.uid()
            )
        )
    );

-- ============================================================================
-- 9. ACCOUNTS ADMINS MUST NOT SEE pending_manager_approval REQUESTS
-- Update the existing "Admins can read all requests" policy to exclude them
-- ============================================================================

DROP POLICY IF EXISTS "Admins can read all requests" ON requests;
CREATE POLICY "Admins can read all requests"
    ON requests FOR SELECT
    USING (
        has_any_role(ARRAY['accounts_admin', 'director']::app_role[])
        AND status != 'pending_manager_approval'
    );

-- Directors should see ALL requests including pending_manager_approval
CREATE POLICY "Directors can read all requests including pending"
    ON requests FOR SELECT
    USING (has_role('director'));

-- ============================================================================
-- 10. VIEW: v_manager_queue — requests awaiting manager approval
-- ============================================================================

CREATE OR REPLACE VIEW v_manager_queue AS
SELECT
    r.id,
    r.title,
    r.category,
    r.priority,
    r.status,
    r.amount,
    r.created_at,
    r.created_by,
    u.email as requester_email,
    mt.manager_user_id
FROM requests r
JOIN auth.users u ON u.id = r.created_by
JOIN manager_team mt ON mt.member_user_id = r.created_by
WHERE r.status = 'pending_manager_approval'
ORDER BY r.priority ASC, r.created_at ASC;

GRANT SELECT ON v_manager_queue TO authenticated;

-- ============================================================================
-- 11. PROVISION USERS + TEAM MAPPINGS
-- Run after users are created in Supabase Auth
-- Replace UUIDs with actual user IDs from auth.users
-- ============================================================================

-- Update roles for existing users + insert new ones
-- (Run AFTER creating accounts via invite-user API or Supabase Dashboard)
--
-- Example (replace UUIDs with real ones):
-- INSERT INTO user_roles (user_id, role) VALUES
--   ('<pulak-uuid>', 'sales_manager'),
--   ('<saksham-uuid>', 'sales_manager'),
--   ('<anand-uuid>', 'requester'),
--   ('<rahul-uuid>', 'requester'),
--   ('<ajay-uuid>', 'requester'),
--   ('<manibhushan-uuid>', 'requester')
-- ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role;
--
-- INSERT INTO manager_team (manager_user_id, member_user_id) VALUES
--   ('<pulak-uuid>', '<abhishek-uuid>'),
--   ('<pulak-uuid>', '<anand-uuid>'),
--   ('<pulak-uuid>', '<rahul-uuid>'),
--   ('<saksham-uuid>', '<ajay-uuid>'),
--   ('<saksham-uuid>', '<manibhushan-uuid>');
