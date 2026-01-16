// ============================================================================
// Admin Invite User Function
// Cloudflare Pages Function to invite new users (Director only)
// ============================================================================

import { createClient } from '@supabase/supabase-js';

interface Env {
    SUPABASE_URL: string;
    SUPABASE_SERVICE_ROLE_KEY: string;
}

interface InviteRequest {
    email: string;
    role: 'requester' | 'accounts_admin';
    invitedBy: string; // Director's user ID
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
        // Create Supabase admin client
        const supabase = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
            auth: {
                autoRefreshToken: false,
                persistSession: false,
            },
        });

        // Verify the requester is a director
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

        // Parse request body
        const body: InviteRequest = await request.json();
        const { email, role } = body;

        // Validate input
        if (!email || !role) {
            return Response.json(
                { success: false, error: 'Missing email or role' },
                { status: 400, headers: corsHeaders }
            );
        }

        if (!['requester', 'accounts_admin'].includes(role)) {
            return Response.json(
                { success: false, error: 'Invalid role' },
                { status: 400, headers: corsHeaders }
            );
        }

        // Check if user already exists
        const { data: existingUsers } = await supabase.auth.admin.listUsers();
        const existingUser = existingUsers?.users?.find(u => u.email === email);

        if (existingUser) {
            // User exists, just update/add role
            const { error: upsertError } = await supabase
                .from('user_roles')
                .upsert({
                    user_id: existingUser.id,
                    role: role,
                }, {
                    onConflict: 'user_id',
                });

            if (upsertError) {
                console.error('Role upsert error:', upsertError);
                return Response.json(
                    { success: false, error: 'Failed to update role' },
                    { status: 500, headers: corsHeaders }
                );
            }

            return Response.json(
                { success: true, message: 'Role updated for existing user', userId: existingUser.id },
                { status: 200, headers: corsHeaders }
            );
        }

        // Create new user with invite
        const { data: newUser, error: createError } = await supabase.auth.admin.createUser({
            email: email,
            email_confirm: false, // They'll need to verify via OTP
            user_metadata: {
                invited_by: user.id,
                invited_at: new Date().toISOString(),
            },
        });

        if (createError) {
            console.error('User creation error:', createError);
            return Response.json(
                { success: false, error: createError.message },
                { status: 500, headers: corsHeaders }
            );
        }

        if (!newUser.user) {
            return Response.json(
                { success: false, error: 'User creation failed' },
                { status: 500, headers: corsHeaders }
            );
        }

        // Create role entry
        const { error: roleInsertError } = await supabase
            .from('user_roles')
            .insert({
                user_id: newUser.user.id,
                role: role,
            });

        if (roleInsertError) {
            console.error('Role insert error:', roleInsertError);
            // Try to clean up the created user
            await supabase.auth.admin.deleteUser(newUser.user.id);
            return Response.json(
                { success: false, error: 'Failed to assign role' },
                { status: 500, headers: corsHeaders }
            );
        }

        return Response.json(
            {
                success: true,
                message: 'User invited successfully',
                userId: newUser.user.id,
                email: email,
                role: role,
            },
            { status: 201, headers: corsHeaders }
        );
    } catch (error) {
        console.error('Invite user error:', error);
        return Response.json(
            { success: false, error: 'Internal error' },
            { status: 500, headers: corsHeaders }
        );
    }
};
