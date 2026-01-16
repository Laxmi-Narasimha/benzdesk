// ============================================================================
// Authentication Context
// Provides auth state and user role throughout the application
// ============================================================================

'use client';

import React, {
    createContext,
    useContext,
    useEffect,
    useState,
    useCallback,
    useMemo,
} from 'react';
import { Session, User, AuthChangeEvent } from '@supabase/supabase-js';
import {
    getSupabaseClient,
    getSession,
    getUserRole,
    signInWithOtp,
    verifyOtp,
    signInWithPassword,
    signOut,
    onAuthStateChange,
} from './supabaseClient';
import type { AppRole, AuthUser, AuthState } from '@/types';

// ============================================================================
// Context Types
// ============================================================================

interface AuthContextValue extends AuthState {
    // Auth methods
    sendOtp: (email: string) => Promise<{ success: boolean; error?: string }>;
    verifyOtpCode: (email: string, token: string) => Promise<{ success: boolean; error?: string }>;
    loginWithPassword: (email: string, password: string) => Promise<{ success: boolean; error?: string }>;
    logout: () => Promise<void>;

    // Role checks
    isRequester: boolean;
    isAdmin: boolean;
    isDirector: boolean;
    canManageRequests: boolean;
    canViewMetrics: boolean;

    // Refresh
    refreshUser: () => Promise<void>;
}

// ============================================================================
// Context Creation
// ============================================================================

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

// ============================================================================
// Auth Provider Component
// ============================================================================

interface AuthProviderProps {
    children: React.ReactNode;
}

export function AuthProvider({ children }: AuthProviderProps) {
    const [state, setState] = useState<AuthState>({
        user: null,
        loading: true,
        error: null,
    });

    // ============================================================================
    // Load user and role
    // ============================================================================

    const loadUser = useCallback(async (session: Session | null) => {
        if (!session?.user) {
            setState({ user: null, loading: false, error: null });
            return;
        }

        try {
            const supabaseUser = session.user;
            const { role, is_active, error } = await getUserRole(supabaseUser.id);

            if (error) {
                console.error('Error fetching user role:', error);
                setState({
                    user: null,
                    loading: false,
                    error: 'Failed to load user permissions',
                });
                return;
            }

            if (!role || !is_active) {
                setState({
                    user: null,
                    loading: false,
                    error: 'Your account is not active or has no role assigned',
                });
                return;
            }

            const authUser: AuthUser = {
                id: supabaseUser.id,
                email: supabaseUser.email || '',
                role,
                is_active,
                requires_mfa: role === 'accounts_admin' || role === 'director',
                mfa_enabled: Boolean(supabaseUser.factors?.find(f => f.status === 'verified')),
            };

            setState({
                user: authUser,
                loading: false,
                error: null,
            });
        } catch (err) {
            console.error('Error in loadUser:', err);
            setState({
                user: null,
                loading: false,
                error: 'An unexpected error occurred',
            });
        }
    }, []);

    // ============================================================================
    // Initialize auth and listen for changes
    // ============================================================================

    useEffect(() => {
        let mounted = true;

        async function initializeAuth() {
            try {
                const session = await getSession();
                if (mounted) {
                    await loadUser(session);
                }
            } catch (err) {
                console.error('Error initializing auth:', err);
                if (mounted) {
                    setState({ user: null, loading: false, error: 'Failed to initialize auth' });
                }
            }
        }

        initializeAuth();

        // Subscribe to auth changes
        const subscription = onAuthStateChange(
            async (event: string, session: Session | null) => {
                if (!mounted) return;

                if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED') {
                    await loadUser(session);
                } else if (event === 'SIGNED_OUT') {
                    setState({ user: null, loading: false, error: null });
                }
            }
        );

        return () => {
            mounted = false;
            subscription?.unsubscribe();
        };
    }, [loadUser]);

    // ============================================================================
    // Auth Methods
    // ============================================================================

    const sendOtp = useCallback(async (email: string) => {
        setState(prev => ({ ...prev, loading: true, error: null }));

        const { error } = await signInWithOtp(email);

        if (error) {
            setState(prev => ({ ...prev, loading: false }));
            // Don't expose whether account exists (security)
            return {
                success: true, // Always return success to prevent email enumeration
                error: undefined,
            };
        }

        setState(prev => ({ ...prev, loading: false }));
        return { success: true };
    }, []);

    const verifyOtpCode = useCallback(async (email: string, token: string) => {
        setState(prev => ({ ...prev, loading: true, error: null }));

        const { session, error } = await verifyOtp(email, token);

        if (error || !session) {
            setState(prev => ({
                ...prev,
                loading: false,
                error: 'Invalid or expired code',
            }));
            return { success: false, error: 'Invalid or expired code' };
        }

        await loadUser(session);
        return { success: true };
    }, [loadUser]);

    const loginWithPassword = useCallback(async (email: string, password: string) => {
        setState(prev => ({ ...prev, loading: true, error: null }));

        const { session, error } = await signInWithPassword(email, password);

        if (error || !session) {
            // Show detailed error message for debugging
            const errorMessage = error?.message || 'Authentication failed - no session returned';
            console.error('Login error:', error);
            setState(prev => ({
                ...prev,
                loading: false,
                error: errorMessage,
            }));
            return { success: false, error: errorMessage };
        }

        await loadUser(session);
        return { success: true };
    }, [loadUser]);

    const logout = useCallback(async () => {
        setState(prev => ({ ...prev, loading: true }));
        await signOut();
        setState({ user: null, loading: false, error: null });
    }, []);

    const refreshUser = useCallback(async () => {
        const session = await getSession();
        await loadUser(session);
    }, [loadUser]);

    // ============================================================================
    // Role Checks (memoized)
    // ============================================================================

    const roleChecks = useMemo(() => {
        const role = state.user?.role;
        return {
            isRequester: role === 'requester',
            isAdmin: role === 'accounts_admin',
            isDirector: role === 'director',
            canManageRequests: role === 'accounts_admin' || role === 'director',
            canViewMetrics: role === 'director',
        };
    }, [state.user?.role]);

    // ============================================================================
    // Context Value
    // ============================================================================

    const contextValue = useMemo<AuthContextValue>(
        () => ({
            ...state,
            ...roleChecks,
            sendOtp,
            verifyOtpCode,
            loginWithPassword,
            logout,
            refreshUser,
        }),
        [state, roleChecks, sendOtp, verifyOtpCode, loginWithPassword, logout, refreshUser]
    );

    return (
        <AuthContext.Provider value={contextValue}>
            {children}
        </AuthContext.Provider>
    );
}

// ============================================================================
// Hook for consuming auth context
// ============================================================================

export function useAuth(): AuthContextValue {
    const context = useContext(AuthContext);

    if (context === undefined) {
        throw new Error('useAuth must be used within an AuthProvider');
    }

    return context;
}

// ============================================================================
// Higher-order component for protected routes
// ============================================================================

interface ProtectedRouteProps {
    children: React.ReactNode;
    requiredRoles?: AppRole[];
    fallback?: React.ReactNode;
}

export function ProtectedRoute({
    children,
    requiredRoles,
    fallback,
}: ProtectedRouteProps) {
    const { user, loading, error } = useAuth();

    if (loading) {
        return (
            <div className="flex items-center justify-center min-h-screen">
                <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-500" />
            </div>
        );
    }

    if (!user) {
        // Redirect to login
        if (typeof window !== 'undefined') {
            window.location.href = '/login';
        }
        return fallback || null;
    }

    if (requiredRoles && !requiredRoles.includes(user.role)) {
        return (
            <div className="flex items-center justify-center min-h-screen">
                <div className="text-center">
                    <h1 className="text-2xl font-bold text-red-500">Access Denied</h1>
                    <p className="text-gray-400 mt-2">
                        You do not have permission to access this page.
                    </p>
                </div>
            </div>
        );
    }

    return <>{children}</>;
}
