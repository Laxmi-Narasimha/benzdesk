// ============================================================================
// BenzDesk Type Definitions
// Industry-grade type safety for the internal accounts request platform
// ============================================================================

// ============================================================================
// Enums - Mirror database enums for type safety
// ============================================================================

/**
 * Application roles - determines user permissions
 * - requester: Can create and view own requests only
 * - accounts_admin: Can manage all requests, assign, update status
 * - director: Full access + metrics and oversight capabilities
 */
export type AppRole = 'requester' | 'accounts_admin' | 'director';

/**
 * Request lifecycle statuses
 * - open: Newly created, awaiting admin attention
 * - in_progress: Admin is actively working on it
 * - waiting_on_requester: Admin needs more info from requester
 * - closed: Request completed or resolved
 */
export type RequestStatus = 'open' | 'in_progress' | 'waiting_on_requester' | 'pending_closure' | 'closed';

/**
 * Audit event types for complete request history
 */
export type RequestEventType =
    | 'created'
    | 'comment'
    | 'status_changed'
    | 'assigned'
    | 'closed'
    | 'reopened'
    | 'attachment_added'
    | 'attachment_removed';

/**
 * Request categories for Indian manufacturing companies
 */
export type RequestCategory =
    | 'expense_reimbursement'
    | 'salary_payroll'
    | 'purchase_order'
    | 'delivery_challan'
    | 'invoice_query'
    | 'vendor_payment'
    | 'travel_allowance'
    | 'transport_expense'
    | 'gst_tax_query'
    | 'bank_account_update'
    | 'advance_request'
    | 'petty_cash'
    | 'other';

/**
 * Priority levels (1-5, where 1 is highest priority)
 */
export type Priority = 1 | 2 | 3 | 4 | 5;

// ============================================================================
// Database Models - Match Supabase table structures
// ============================================================================

/**
 * User role assignment - one per user
 */
export interface UserRole {
    user_id: string;
    role: AppRole;
    created_at: string;
    created_by: string | null;
    is_active: boolean;
}

/**
 * Core request entity - current state of a ticket
 */
export interface Request {
    id: string;
    created_at: string;
    created_by: string;
    title: string;
    description: string;
    category: RequestCategory;
    priority: Priority;
    status: RequestStatus;
    deadline: string | null;
    assigned_to: string | null;
    closed_at: string | null;
    closed_by: string | null;
    updated_at: string;
    updated_by: string | null;
    last_activity_at: string;
    last_activity_by: string | null;
    first_admin_response_at: string | null;
    first_admin_response_by: string | null;
    row_version: number;
}

/**
 * Request comment - visible conversation on a request
 */
export interface RequestComment {
    id: number;
    request_id: string;
    created_at: string;
    author_id: string;
    body: string;
    is_internal: boolean;
}

/**
 * Request event - immutable audit log entry
 */
export interface RequestEvent {
    id: number;
    request_id: string;
    created_at: string;
    actor_id: string;
    event_type: RequestEventType;
    old_data: Record<string, unknown>;
    new_data: Record<string, unknown>;
    note: string | null;
}

/**
 * Request attachment metadata
 */
export interface RequestAttachment {
    id: number;
    request_id: string;
    uploaded_at: string;
    uploaded_by: string;
    bucket: string;
    path: string;
    original_filename: string;
    mime_type: string;
    size_bytes: number;
}

// ============================================================================
// View Types - For director dashboards
// ============================================================================

/**
 * Overview of requests by status
 */
export interface RequestsOverview {
    status: RequestStatus;
    count: number;
}

/**
 * Admin backlog - open requests per admin
 */
export interface AdminBacklog {
    admin_id: string;
    admin_email: string;
    open_count: number;
    in_progress_count: number;
    waiting_count: number;
}

/**
 * SLA metrics for first response time
 */
export interface SlaFirstResponse {
    request_id: string;
    created_at: string;
    first_response_at: string | null;
    response_time_hours: number | null;
    is_breached: boolean;
}

/**
 * SLA metrics for time to close
 */
export interface SlaTimeToClose {
    request_id: string;
    created_at: string;
    closed_at: string;
    time_to_close_hours: number;
}

/**
 * Stale requests - no activity in X days
 */
export interface StaleRequest {
    id: string;
    title: string;
    status: RequestStatus;
    last_activity_at: string;
    days_since_activity: number;
    assigned_to: string | null;
}

/**
 * Admin throughput - closed requests per period
 */
export interface AdminThroughput {
    admin_id: string;
    admin_email: string;
    period_start: string;
    period_end: string;
    closed_count: number;
    avg_time_to_close_hours: number;
}

// ============================================================================
// UI Types - Application state and form handling
// ============================================================================

/**
 * Extended request with joined user data for display
 */
export interface RequestWithUsers extends Request {
    creator?: UserProfile;
    assignee?: UserProfile;
}

/**
 * User profile for display (from auth.users)
 */
export interface UserProfile {
    id: string;
    email: string;
    display_name?: string;
    avatar_url?: string;
}

/**
 * Form data for creating a new request
 */
export interface CreateRequestInput {
    title: string;
    description: string;
    category: RequestCategory;
    priority: Priority;
    deadline?: string | null;
}

/**
 * Form data for updating a request (admin only)
 */
export interface UpdateRequestInput {
    status?: RequestStatus;
    assigned_to?: string | null;
    priority?: Priority;
    row_version: number; // For optimistic concurrency
}

/**
 * Form data for adding a comment
 */
export interface CreateCommentInput {
    request_id: string;
    body: string;
    is_internal?: boolean; // Only admins can set to true
}

/**
 * Filter options for request lists
 */
export interface RequestFilters {
    status?: RequestStatus | RequestStatus[];
    category?: RequestCategory | RequestCategory[];
    priority?: Priority | Priority[];
    assigned_to?: string;
    created_by?: string;
    search?: string;
    date_from?: string;
    date_to?: string;
}

/**
 * Pagination options
 */
export interface PaginationOptions {
    page: number;
    limit: number;
}

/**
 * Paginated response wrapper
 */
export interface PaginatedResponse<T> {
    data: T[];
    total: number;
    page: number;
    limit: number;
    total_pages: number;
}

// ============================================================================
// Auth Types
// ============================================================================

/**
 * Current authenticated user with role
 */
export interface AuthUser {
    id: string;
    email: string;
    role: AppRole;
    is_active: boolean;
    requires_mfa: boolean;
    mfa_enabled: boolean;
}

/**
 * Session state
 */
export interface AuthState {
    user: AuthUser | null;
    loading: boolean;
    error: string | null;
}

// ============================================================================
// API Response Types
// ============================================================================

/**
 * Standard API response wrapper
 */
export interface ApiResponse<T = unknown> {
    success: boolean;
    data?: T;
    error?: {
        code: string;
        message: string;
        details?: unknown;
    };
}

/**
 * Turnstile verification response
 */
export interface TurnstileVerifyResponse {
    success: boolean;
    error_codes?: string[];
}

// ============================================================================
// Constants
// ============================================================================

export const REQUEST_STATUS_LABELS: Record<RequestStatus, string> = {
    open: 'Open',
    in_progress: 'In Progress',
    waiting_on_requester: 'Waiting on Requester',
    pending_closure: 'Pending Closure',
    closed: 'Closed',
};

export const REQUEST_CATEGORY_LABELS: Record<RequestCategory, string> = {
    expense_reimbursement: 'Expense Reimbursement',
    salary_payroll: 'Salary / Payroll Query',
    purchase_order: 'Purchase Order',
    delivery_challan: 'Delivery Challan',
    invoice_query: 'Invoice Query',
    vendor_payment: 'Vendor Payment',
    travel_allowance: 'Travel Allowance (TA/DA)',
    transport_expense: 'Transport Expense',
    gst_tax_query: 'GST / Tax Query',
    bank_account_update: 'Bank Account Update',
    advance_request: 'Advance Request',
    petty_cash: 'Petty Cash',
    other: 'Other',
};

export const PRIORITY_LABELS: Record<Priority, string> = {
    1: 'Critical',
    2: 'High',
    3: 'Medium',
    4: 'Low',
    5: 'Minimal',
};

export const ROLE_LABELS: Record<AppRole, string> = {
    requester: 'Requester',
    accounts_admin: 'Accounts Admin',
    director: 'Director',
};

// SLA thresholds in hours
export const SLA_THRESHOLDS = {
    first_response: {
        critical: 2,
        high: 4,
        medium: 8,
        low: 24,
        minimal: 48,
    },
    resolution: {
        critical: 24,
        high: 48,
        medium: 72,
        low: 120,
        minimal: 168, // 1 week
    },
} as const;

// ============================================================================
// Fresh Start Date - Only show requests created after this date
// ============================================================================

export const FRESH_START_DATE = '2026-01-14T00:00:00.000Z';

// ============================================================================
// User Names Mapping - Email to display name from employee directory
// ============================================================================

export const USER_NAMES: Record<string, string> = {
    'paulraj@benz-packaging.com': 'A.A. Paulraj',
    'wh.jaipur@benz-packaging.com': 'Mani Bhushan',
    'abhishek@benz-packaging.com': 'Abhishek Kori',
    'accounts.chennai@benz-packaging.com': 'Accounts Chennai',
    'accounts@benz-packaging.com': 'Accounts BENZ',
    'accounts1@benz-packaging.com': 'Accounts1',
    'ajay@benz-packaging.com': 'Ajay',
    'dispatch1@benz-packaging.com': 'Aman Roy',
    'no-reply@benz-packaging.com': 'Automated Mail',
    'sales3@benz-packaging.com': 'Babita',
    'sales4@benz-packaging.com': 'BENZ Sales',
    'deepak@benz-packaging.com': 'Deepak Bhardwaj',
    'dinesh@benz-packaging.com': 'Dinesh',
    'sales@ergopack-india.com': 'Ergopack India',
    'erp@benz-packaging.com': 'ERP Team',
    'gate@benz-packaging.com': 'Gate Entry',
    'hr@benz-packaging.com': 'HR',
    'isha@benz-packaging.com': 'Isha Mahajan',
    'chennai@benz-packaging.com': 'Jayashree N',
    'karthick@benz-packaging.com': 'Karthick Ravishankar',
    'laxmi@benz-packaging.com': 'Laxmi Narasimha',
    'lokesh@benz-packaging.com': 'Lokesh Ronchhiya',
    'hr.manager@benz-packaging.com': 'Mahesh Gupta',
    'manan@benz-packaging.com': 'Manan Chopra',
    'marketing@benz-packaging.com': 'Marketing',
    'warehouse@benz-packaging.com': 'Narender',
    'neeraj@benz-packaging.com': 'Neeraj Singh',
    'neveta@benz-packaging.com': 'Neveta',
    'supplychain@benz-packaging.com': 'Paramveer Yadav',
    'pavan.kr@benz-packaging.com': 'Pavan Kumar',
    'qa@benz-packaging.com': 'Pawan',
    'po@benz-packaging.com': 'PO',
    'ccare2@benz-packaging.com': 'Pradeep Kumar',
    'prashansa@benz-packaging.com': 'Prashansa Madan',
    'ccare6@benz-packaging.com': 'Preeti R',
    'pulak@benz-packaging.com': 'Pulak Biswas',
    'quality.chennai@benz-packaging.com': 'Quality Chennai',
    'rahul@benz-packaging.com': 'Rahul',
    'rekha@benz-packaging.com': 'Rekha C',
    'samish@benz-packaging.com': 'Samish Thakur',
    'sandeep@benz-packaging.com': 'Sandeep',
    'satender@benz-packaging.com': 'Satender Singh',
    'satheeswaran@benz-packaging.com': 'Sathees Waran',
    'saurav@benz-packaging.com': 'Saurav Kumar',
    'ccare@benz-packaging.com': 'Shikha Sharma',
    'store@benz-packaging.com': 'Store',
    'sales5@benz-packaging.com': 'Tarun Bhardwaj',
    'yamada@benz-packaging.com': 'Tomy Yamada',
    'bhandari@benz-packaging.com': 'TS Bhandari',
    'it@benz-packaging.com': 'Udit Suri',
    'bangalore@benz-packaging.com': 'Vijay Danieal',
    'warehouse.ap@benz-packaging.com': 'Warehouse AP',
    'chaitanya@benz-packaging.com': 'Chaitanya',
    'vikky@benz-packaging.com': 'Vikky',
    'hr.support@benz-packaging.com': 'HR Support',
    'rfq@benz-packaging.com': 'RFQ',
};

// Helper function to get display name from email
export function getDisplayName(email: string | null | undefined): string {
    if (!email) return 'Unknown';
    const lowerEmail = email.toLowerCase();
    if (USER_NAMES[lowerEmail]) {
        return USER_NAMES[lowerEmail];
    }
    // Fallback: format email prefix
    return email.split('@')[0]
        .replace(/[._]/g, ' ')
        .split(' ')
        .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');
}
