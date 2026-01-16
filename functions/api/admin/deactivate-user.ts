// ============================================================================
// Admin Deactivate User Function
// Cloudflare Pages Function to deactivate users (Director only)
// ============================================================================

import { createClient } from '@supabase/supabase-js';

interface Env {
    SUPABASE_URL: string;
    SUPABASE_SERVICE_ROLE_KEY: string;
}

interface DeactivateRequest {
    userId: string;
}

export const onRequestPost: PagesFunction<Env> = async (context) => {
    const { request, env } = context;

    const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') {
        return new Response(null, { headers: corsHeaders });
    }

    try {
        const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
            auth: {
                autoRefreshToken: false,
                persistSession: false,
            },
        });

        // Verify requester is director
        const authHeader = request.headers.get('Authorization');
        if (!authHeader?.startsWith('Bearer ')) {
            return Response.json(
                { success: false, error: 'Unauthorized' },
                { status: 401, headers: corsHeaders }
            );
        }

        const token = authHeader.split(' ')[1];
        const { data: { user }, error: authError } = await supabase.auth.getUser(token);

        if (authError || !user) {
            return Response.json(
                { success: false, error: 'Invalid token' },
                { status: 401, headers: corsHeaders }
            );
        }

        // Check if requester is director
        const { data: roleData, error: roleError } = await supabase
            .from('user_roles')
            .select('role')
            .eq('user_id', user.id)
            .single();

        if (roleError || roleData?.role !== 'director') {
            return Response.json(
                { success: false, error: 'Director access required' },
                { status: 403, headers: corsHeaders }
            );
        }

        // Parse request
        const body: DeactivateRequest = await request.json();
        const { userId } = body;

        if (!userId) {
            return Response.json(
                { success: false, error: 'Missing userId' },
                { status: 400, headers: corsHeaders }
            );
        }

        // Prevent self-deactivation
        if (userId === user.id) {
            return Response.json(
                { success: false, error: 'Cannot deactivate yourself' },
                { status: 400, headers: corsHeaders }
            );
        }

        // Check target user exists
        const { data: targetUser, error: getUserError } = await supabase.auth.admin.getUserById(userId);

        if (getUserError || !targetUser.user) {
            return Response.json(
                { success: false, error: 'User not found' },
                { status: 404, headers: corsHeaders }
            );
        }

        // Ban the user (soft delete - preserves audit trail)
        const { error: banError } = await supabase.auth.admin.updateUserById(userId, {
            ban_duration: '87600h', // 10 years effectively
            user_metadata: {
                ...targetUser.user.user_metadata,
                deactivated_at: new Date().toISOString(),
                deactivated_by: user.id,
            },
        });

        if (banError) {
            console.error('User ban error:', banError);
            return Response.json(
                { success: false, error: 'Failed to deactivate user' },
                { status: 500, headers: corsHeaders }
            );
        }

        // Remove from user_roles (or mark inactive)
        const { error: roleDeleteError } = await supabase
            .from('user_roles')
            .delete()
            .eq('user_id', userId);

        if (roleDeleteError) {
            console.error('Role delete warning:', roleDeleteError);
            // Non-fatal - user is already banned
        }

        return Response.json(
            { success: true, message: 'User deactivated successfully', userId },
            { status: 200, headers: corsHeaders }
        );
    } catch (error) {
        console.error('Deactivate user error:', error);
        return Response.json(
            { success: false, error: 'Internal error' },
            { status: 500, headers: corsHeaders }
        );
    }
};
