// ============================================================================
// Admin Set Role Function
// Cloudflare Pages Function to update user roles (Director only)
// ============================================================================

import { createClient } from '@supabase/supabase-js';

interface Env {
    SUPABASE_URL: string;
    SUPABASE_SERVICE_ROLE_KEY: string;
}

interface SetRoleRequest {
    userId: string;
    role: 'requester' | 'accounts_admin' | 'director';
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
        const body: SetRoleRequest = await request.json();
        const { userId, role } = body;

        if (!userId || !role) {
            return Response.json(
                { success: false, error: 'Missing userId or role' },
                { status: 400, headers: corsHeaders }
            );
        }

        if (!['requester', 'accounts_admin', 'director'].includes(role)) {
            return Response.json(
                { success: false, error: 'Invalid role' },
                { status: 400, headers: corsHeaders }
            );
        }

        // Prevent self-role change
        if (userId === user.id) {
            return Response.json(
                { success: false, error: 'Cannot modify your own role' },
                { status: 400, headers: corsHeaders }
            );
        }

        // Update role
        const { error: updateError } = await supabase
            .from('user_roles')
            .upsert({
                user_id: userId,
                role: role,
            }, {
                onConflict: 'user_id',
            });

        if (updateError) {
            console.error('Role update error:', updateError);
            return Response.json(
                { success: false, error: 'Failed to update role' },
                { status: 500, headers: corsHeaders }
            );
        }

        return Response.json(
            { success: true, message: 'Role updated successfully', userId, role },
            { status: 200, headers: corsHeaders }
        );
    } catch (error) {
        console.error('Set role error:', error);
        return Response.json(
            { success: false, error: 'Internal error' },
            { status: 500, headers: corsHeaders }
        );
    }
};
