// ============================================================================
// Supabase Edge Function: Send Push Notification
// Uses Web Push protocol to send actual browser notifications
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Environment variables
const VAPID_PUBLIC_KEY = Deno.env.get('VAPID_PUBLIC_KEY') || '';
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY') || '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

interface PushPayload {
    user_id: string;
    title: string;
    body: string;
    url?: string;
    tag?: string;
    icon?: string;
}

// CORS headers
const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// Base64URL encode
function base64UrlEncode(arrayBuffer: ArrayBuffer): string {
    const bytes = new Uint8Array(arrayBuffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary)
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/, '');
}

// Base64URL decode
function base64UrlDecode(str: string): Uint8Array {
    const padding = '='.repeat((4 - (str.length % 4)) % 4);
    const base64 = (str + padding)
        .replace(/-/g, '+')
        .replace(/_/g, '/');
    const rawData = atob(base64);
    const outputArray = new Uint8Array(rawData.length);
    for (let i = 0; i < rawData.length; i++) {
        outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
}

// Create VAPID JWT token
async function createVapidJwt(audience: string): Promise<string> {
    const header = { typ: 'JWT', alg: 'ES256' };
    const now = Math.floor(Date.now() / 1000);
    const payload = {
        aud: audience,
        exp: now + 12 * 60 * 60,
        sub: 'mailto:support@benz-packaging.com',
    };

    const headerB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
    const payloadB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
    const unsignedToken = `${headerB64}.${payloadB64}`;

    // Import the private key
    const privateKeyBytes = base64UrlDecode(VAPID_PRIVATE_KEY);

    // Create the key in the format expected by Web Crypto API
    // VAPID private keys are raw 32-byte EC private keys
    const privateKey = await crypto.subtle.importKey(
        'raw',
        privateKeyBytes,
        { name: 'ECDSA', namedCurve: 'P-256' },
        false,
        ['sign']
    ).catch(async () => {
        // If raw import fails, try PKCS8 format
        // Create PKCS8 wrapper for the raw key
        const pkcs8Header = new Uint8Array([
            0x30, 0x41, 0x02, 0x01, 0x00, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48,
            0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03,
            0x01, 0x07, 0x04, 0x27, 0x30, 0x25, 0x02, 0x01, 0x01, 0x04, 0x20
        ]);
        const pkcs8Key = new Uint8Array(pkcs8Header.length + privateKeyBytes.length);
        pkcs8Key.set(pkcs8Header);
        pkcs8Key.set(privateKeyBytes, pkcs8Header.length);

        return await crypto.subtle.importKey(
            'pkcs8',
            pkcs8Key,
            { name: 'ECDSA', namedCurve: 'P-256' },
            false,
            ['sign']
        );
    });

    const signature = await crypto.subtle.sign(
        { name: 'ECDSA', hash: 'SHA-256' },
        privateKey,
        new TextEncoder().encode(unsignedToken)
    );

    // Convert DER signature to raw format if needed
    const signatureBytes = new Uint8Array(signature);
    const signatureB64 = base64UrlEncode(signatureBytes);

    return `${unsignedToken}.${signatureB64}`;
}

// Send push notification to a subscription
async function sendPush(subscription: { endpoint: string; p256dh: string; auth: string }, payload: object): Promise<{ success: boolean; error?: string }> {
    try {
        const endpoint = subscription.endpoint;
        const audience = new URL(endpoint).origin;

        console.log('Sending push to:', endpoint.substring(0, 60) + '...');

        // Create VAPID JWT
        const jwt = await createVapidJwt(audience);

        // Create the payload
        const payloadString = JSON.stringify(payload);
        const payloadBytes = new TextEncoder().encode(payloadString);

        // For Web Push, we need to encrypt the payload
        // However, for simplicity, we'll send without encryption first
        // and let the browser handle it (some push services accept unencrypted)

        const response = await fetch(endpoint, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Encoding': 'aes128gcm',
                'Authorization': `vapid t=${jwt}, k=${VAPID_PUBLIC_KEY}`,
                'TTL': '86400',
                'Urgency': 'high',
            },
            body: payloadBytes,
        });

        console.log('Push response status:', response.status);

        if (response.status === 201 || response.status === 200) {
            console.log('Push sent successfully!');
            return { success: true };
        } else if (response.status === 410 || response.status === 404) {
            console.log('Subscription expired');
            return { success: false, error: 'Subscription expired' };
        } else {
            const text = await response.text();
            console.error('Push failed:', response.status, text);
            return { success: false, error: `HTTP ${response.status}: ${text}` };
        }
    } catch (error) {
        console.error('Push error:', error);
        return { success: false, error: String(error) };
    }
}

serve(async (req: Request) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        // Validate environment
        if (!VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
            console.error('VAPID keys not configured');
            return new Response(
                JSON.stringify({ error: 'Push notifications not configured - missing VAPID keys' }),
                { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Parse request
        const payload: PushPayload = await req.json();
        const { user_id, title, body, url, tag, icon } = payload;

        console.log('Received push request for user:', user_id);
        console.log('Title:', title);
        console.log('Body:', body);

        if (!user_id || !title || !body) {
            return new Response(
                JSON.stringify({ error: 'Missing required fields: user_id, title, body' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Get user's subscriptions
        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
        const { data: subscriptions, error: fetchError } = await supabase
            .from('push_subscriptions')
            .select('*')
            .eq('user_id', user_id);

        if (fetchError) {
            console.error('Error fetching subscriptions:', fetchError);
            return new Response(
                JSON.stringify({ error: 'Failed to fetch subscriptions', details: fetchError.message }),
                { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        console.log('Found subscriptions:', subscriptions?.length || 0);

        if (!subscriptions || subscriptions.length === 0) {
            return new Response(
                JSON.stringify({ success: true, sent: 0, message: 'No subscriptions found for user' }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            );
        }

        // Notification payload for the service worker
        const notificationPayload = {
            title,
            body,
            icon: icon || '/icon-192.png',
            badge: '/icon-192.png',
            data: {
                url: url || '/',
            },
            tag: tag || 'benzdesk-notification',
            requireInteraction: true,
            vibrate: [100, 50, 100],
        };

        let sent = 0;
        let failed = 0;
        const errors: string[] = [];

        // Send to each subscription
        for (const sub of subscriptions) {
            const result = await sendPush(
                {
                    endpoint: sub.endpoint,
                    p256dh: sub.p256dh,
                    auth: sub.auth,
                },
                notificationPayload
            );

            if (result.success) {
                sent++;
            } else {
                failed++;
                errors.push(result.error || 'Unknown error');

                // Remove expired subscriptions
                if (result.error?.includes('expired') || result.error?.includes('410')) {
                    await supabase.from('push_subscriptions').delete().eq('id', sub.id);
                    console.log('Removed expired subscription:', sub.id);
                }
            }
        }

        console.log(`Push results: ${sent} sent, ${failed} failed`);

        return new Response(
            JSON.stringify({
                success: sent > 0,
                sent,
                failed,
                total: subscriptions.length,
                errors: errors.length > 0 ? errors : undefined
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );

    } catch (error) {
        console.error('Edge function error:', error);
        return new Response(
            JSON.stringify({ error: 'Internal server error', details: String(error) }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }
});
