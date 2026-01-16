// ============================================================================
// Turnstile Verification Function
// Cloudflare Pages Function to verify Turnstile tokens server-side
// ============================================================================

interface Env {
    TURNSTILE_SECRET_KEY: string;
}

interface TurnstileResponse {
    success: boolean;
    error_codes?: string[];
    challenge_ts?: string;
    hostname?: string;
    action?: string;
    cdata?: string;
}

export const onRequestPost: PagesFunction<Env> = async (context) => {
    const { request, env } = context;

    // CORS headers
    const corsHeaders = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
    };

    // Handle OPTIONS for CORS
    if (request.method === 'OPTIONS') {
        return new Response(null, { headers: corsHeaders });
    }

    try {
        const body = await request.json() as { token: string; ip?: string };
        const { token } = body;

        if (!token) {
            return Response.json(
                { success: false, error: 'Missing token' },
                { status: 400, headers: corsHeaders }
            );
        }

        // Get client IP from Cloudflare headers
        const ip = request.headers.get('CF-Connecting-IP') || body.ip;

        // Verify with Turnstile API
        const formData = new FormData();
        formData.append('secret', env.TURNSTILE_SECRET_KEY);
        formData.append('response', token);
        if (ip) formData.append('remoteip', ip);

        const turnstileResponse = await fetch(
            'https://challenges.cloudflare.com/turnstile/v0/siteverify',
            {
                method: 'POST',
                body: formData,
            }
        );

        const result: TurnstileResponse = await turnstileResponse.json();

        if (result.success) {
            return Response.json(
                { success: true },
                { status: 200, headers: corsHeaders }
            );
        } else {
            console.log('Turnstile verification failed:', result.error_codes);
            return Response.json(
                { success: false, error: 'Verification failed', codes: result.error_codes },
                { status: 400, headers: corsHeaders }
            );
        }
    } catch (error) {
        console.error('Turnstile verification error:', error);
        return Response.json(
            { success: false, error: 'Internal error' },
            { status: 500, headers: corsHeaders }
        );
    }
};
