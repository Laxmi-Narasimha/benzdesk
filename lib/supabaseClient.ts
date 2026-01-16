// ============================================================================
// Supabase Client Configuration
// Industry-grade setup with proper error handling and type safety
// ============================================================================

import { createClient, SupabaseClient, Session, User } from '@supabase/supabase-js';

// Environment validation
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl) {
    console.error('Missing NEXT_PUBLIC_SUPABASE_URL environment variable');
}

if (!supabaseAnonKey) {
    console.error('Missing NEXT_PUBLIC_SUPABASE_ANON_KEY environment variable');
}

// ============================================================================
// Database Types (generated from schema)
// ============================================================================

export type Database = {
    public: {
        Tables: {
            user_roles: {
                Row: {
                    user_id: string;
                    role: 'requester' | 'accounts_admin' | 'director';
                    created_at: string;
                    created_by: string | null;
                    is_active: boolean;
                };
                Insert: {
                    user_id: string;
                    role?: 'requester' | 'accounts_admin' | 'director';
                    created_at?: string;
                    created_by?: string | null;
                    is_active?: boolean;
                };
                Update: {
                    user_id?: string;
                    role?: 'requester' | 'accounts_admin' | 'director';
                    created_at?: string;
                    created_by?: string | null;
                    is_active?: boolean;
                };
            };
            requests: {
                Row: {
                    id: string;
                    created_at: string;
                    created_by: string;
                    title: string;
                    description: string;
                    category: string;
                    priority: number;
                    status: 'open' | 'in_progress' | 'waiting_on_requester' | 'closed';
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
                };
                Insert: {
                    id?: string;
                    created_at?: string;
                    created_by: string;
                    title: string;
                    description: string;
                    category: string;
                    priority?: number;
                    status?: 'open' | 'in_progress' | 'waiting_on_requester' | 'closed';
                    assigned_to?: string | null;
                    closed_at?: string | null;
                    closed_by?: string | null;
                    updated_at?: string;
                    updated_by?: string | null;
                    last_activity_at?: string;
                    last_activity_by?: string | null;
                    first_admin_response_at?: string | null;
                    first_admin_response_by?: string | null;
                    row_version?: number;
                };
                Update: {
                    id?: string;
                    created_at?: string;
                    created_by?: string;
                    title?: string;
                    description?: string;
                    category?: string;
                    priority?: number;
                    status?: 'open' | 'in_progress' | 'waiting_on_requester' | 'closed';
                    assigned_to?: string | null;
                    closed_at?: string | null;
                    closed_by?: string | null;
                    updated_at?: string;
                    updated_by?: string | null;
                    last_activity_at?: string;
                    last_activity_by?: string | null;
                    first_admin_response_at?: string | null;
                    first_admin_response_by?: string | null;
                    row_version?: number;
                };
            };
            request_comments: {
                Row: {
                    id: number;
                    request_id: string;
                    created_at: string;
                    author_id: string;
                    body: string;
                    is_internal: boolean;
                };
                Insert: {
                    id?: number;
                    request_id: string;
                    created_at?: string;
                    author_id: string;
                    body: string;
                    is_internal?: boolean;
                };
                Update: {
                    id?: number;
                    request_id?: string;
                    created_at?: string;
                    author_id?: string;
                    body?: string;
                    is_internal?: boolean;
                };
            };
            request_events: {
                Row: {
                    id: number;
                    request_id: string;
                    created_at: string;
                    actor_id: string;
                    event_type: string;
                    old_data: Record<string, unknown>;
                    new_data: Record<string, unknown>;
                    note: string | null;
                };
                Insert: {
                    id?: number;
                    request_id: string;
                    created_at?: string;
                    actor_id: string;
                    event_type: string;
                    old_data?: Record<string, unknown>;
                    new_data?: Record<string, unknown>;
                    note?: string | null;
                };
                Update: {
                    id?: number;
                    request_id?: string;
                    created_at?: string;
                    actor_id?: string;
                    event_type?: string;
                    old_data?: Record<string, unknown>;
                    new_data?: Record<string, unknown>;
                    note?: string | null;
                };
            };
            request_attachments: {
                Row: {
                    id: number;
                    request_id: string;
                    uploaded_at: string;
                    uploaded_by: string;
                    bucket: string;
                    path: string;
                    original_filename: string;
                    mime_type: string;
                    size_bytes: number;
                };
                Insert: {
                    id?: number;
                    request_id: string;
                    uploaded_at?: string;
                    uploaded_by: string;
                    bucket: string;
                    path: string;
                    original_filename: string;
                    mime_type: string;
                    size_bytes: number;
                };
                Update: {
                    id?: number;
                    request_id?: string;
                    uploaded_at?: string;
                    uploaded_by?: string;
                    bucket?: string;
                    path?: string;
                    original_filename?: string;
                    mime_type?: string;
                    size_bytes?: number;
                };
            };
        };
        Views: {
            v_requests_overview: {
                Row: {
                    status: string;
                    count: number;
                };
            };
            v_admin_backlog: {
                Row: {
                    admin_id: string;
                    admin_email: string;
                    open_count: number;
                    in_progress_count: number;
                    waiting_count: number;
                };
            };
            v_stale_requests: {
                Row: {
                    id: string;
                    title: string;
                    status: string;
                    last_activity_at: string;
                    days_since_activity: number;
                    assigned_to: string | null;
                };
            };
        };
        Functions: {
            has_role: {
                Args: { required_role: string };
                Returns: boolean;
            };
        };
    };
};

// ============================================================================
// Supabase Client Singleton
// ============================================================================

let supabaseInstance: SupabaseClient | null = null;

/**
 * Get the Supabase client instance (singleton pattern)
 * Uses only the anon key - service role key is NEVER used in browser
 */
export function getSupabaseClient(): SupabaseClient {
    if (supabaseInstance) {
        return supabaseInstance;
    }

    if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error(
            'Supabase configuration missing. Please set NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY environment variables.'
        );
    }

    supabaseInstance = createClient(supabaseUrl, supabaseAnonKey, {
        auth: {
            autoRefreshToken: true,
            persistSession: true,
            detectSessionInUrl: true,
            storage: typeof window !== 'undefined' ? window.localStorage : undefined,
        },
        global: {
            headers: {
                'X-Client-Info': 'benzdesk-web/1.0.0',
            },
        },
    });

    return supabaseInstance;
}

// Export singleton for direct imports
export const supabase = typeof window !== 'undefined' ? getSupabaseClient() : null;

// ============================================================================
// Auth Helper Functions
// ============================================================================

/**
 * Get current session
 */
export async function getSession(): Promise<Session | null> {
    const client = getSupabaseClient();
    const { data: { session }, error } = await client.auth.getSession();

    if (error) {
        console.error('Error getting session:', error.message);
        return null;
    }

    return session;
}

/**
 * Get current user
 */
export async function getCurrentUser(): Promise<User | null> {
    const session = await getSession();
    return session?.user ?? null;
}

/**
 * Sign in with OTP (passwordless)
 * IMPORTANT: shouldCreateUser: false prevents signup-by-OTP
 */
export async function signInWithOtp(email: string): Promise<{ error: Error | null }> {
    const client = getSupabaseClient();

    const { error } = await client.auth.signInWithOtp({
        email,
        options: {
            shouldCreateUser: false, // SECURITY: Prevents signup-by-OTP
        },
    });

    return { error };
}

/**
 * Verify OTP token
 */
export async function verifyOtp(
    email: string,
    token: string
): Promise<{ session: Session | null; error: Error | null }> {
    const client = getSupabaseClient();

    const { data, error } = await client.auth.verifyOtp({
        email,
        token,
        type: 'email',
    });

    return {
        session: data?.session ?? null,
        error,
    };
}

/**
 * Sign in with email and password
 */
export async function signInWithPassword(
    email: string,
    password: string
): Promise<{ session: Session | null; error: Error | null }> {
    const client = getSupabaseClient();

    const { data, error } = await client.auth.signInWithPassword({
        email,
        password,
    });

    return {
        session: data?.session ?? null,
        error,
    };
}

/**
 * Update user password (after first OTP login)
 */
export async function updatePassword(
    newPassword: string
): Promise<{ error: Error | null }> {
    const client = getSupabaseClient();

    const { error } = await client.auth.updateUser({
        password: newPassword,
    });

    return { error };
}

/**
 * Sign out
 */
export async function signOut(): Promise<{ error: Error | null }> {
    const client = getSupabaseClient();
    const { error } = await client.auth.signOut();
    return { error };
}

/**
 * Get user role from user_roles table
 */
export async function getUserRole(userId: string): Promise<{
    role: 'requester' | 'accounts_admin' | 'director' | null;
    is_active: boolean;
    error: Error | null;
}> {
    const client = getSupabaseClient();

    const { data, error } = await client
        .from('user_roles')
        .select('role, is_active')
        .eq('user_id', userId)
        .single();

    if (error) {
        return { role: null, is_active: false, error };
    }

    return {
        role: data?.role ?? null,
        is_active: data?.is_active ?? false,
        error: null,
    };
}

// ============================================================================
// Subscription Helpers
// ============================================================================

/**
 * Subscribe to auth state changes
 */
export function onAuthStateChange(
    callback: (event: string, session: Session | null) => void
) {
    const client = getSupabaseClient();

    const { data: { subscription } } = client.auth.onAuthStateChange(
        (event, session) => {
            callback(event, session);
        }
    );

    return subscription;
}
