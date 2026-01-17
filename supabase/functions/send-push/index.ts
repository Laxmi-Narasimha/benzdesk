// ============================================================================
// Supabase Edge Function: Send Push Notification
// Sends Web Push notifications to users
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// VAPID keys from environment
const VAPID_PUBLIC_KEY = Deno.env.get('VAPID_PUBLIC_KEY') || '';
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY') || '';
const VAPID_SUBJECT = 'mailto:support@benz-packaging.com';

// Supabase client
const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

interface PushPayload {
    user_id: string;
    title: string;
    body: string;
    url?: string;
    tag?: string;
}

// Base64URL encode
function base64UrlEncode(data: Uint8Array): string {
    return btoa(String.fromCharCode(...data))
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=+$/, '');
}

// Import crypto key from raw bytes
async function importVapidKey(rawKey: string): Promise<CryptoKey> {
    const keyData = Uint8Array.from(atob(rawKey.replace(/-/g, '+').replace(/_/g, '/')), c => c.charCodeAt(0));
    return await crypto.subtle.importKey(
        'pkcs8',
        keyData,
        { name: 'ECDSA', namedCurve: 'P-256' },
        false,
        ['sign']
    );
}

// Create JWT for VAPID
async function createVapidJwt(audience: string): Promise<string> {
    const header = { typ: 'JWT', alg: 'ES256' };
    const payload = {
        aud: audience,
        exp: Math.floor(Date.now() / 1000) + 12 * 60 * 60, // 12 hours
        sub: VAPID_SUBJECT,
    };

    const headerB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(header)));
    const payloadB64 = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
    const unsignedToken = `${headerB64}.${payloadB64}`;

    const key = await importVapidKey(VAPID_PRIVATE_KEY);
    const signature = await crypto.subtle.sign(
        { name: 'ECDSA', hash: 'SHA-256' },
        key,
        new TextEncoder().encode(unsignedToken)
    );

    const signatureB64 = base64UrlEncode(new Uint8Array(signature));
    return `${unsignedToken}.${signatureB64}`;
}

// Send push notification
async function sendPushNotification(subscription: any, payload: any): Promise<boolean> {
    try {
        const endpoint = subscription.endpoint;
        const audience = new URL(endpoint).origin;
        const jwt = await createVapidJwt(audience);

        const body = JSON.stringify(payload);

        const response = await fetch(endpoint, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': body.length.toString(),
                'Authorization': `vapid t=${jwt}, k=${VAPID_PUBLIC_KEY}`,
                'TTL': '86400',
            },
            body,
        });

        if (response.status === 201 || response.status === 200) {
            console.log('Push sent successfully');
            return true;
        } else if (response.status === 410 || response.status === 404) {
            // Subscription expired, delete it
            console.log('Subscription expired, removing...');
            const supabase = createClient(supabaseUrl, supabaseServiceKey);
            await supabase.from('push_subscriptions').delete().eq('endpoint', endpoint);
            return false;
        } else {
            console.error('Push failed:', response.status, await response.text());
            return false;
        }
    } catch (error) {
        console.error('Error sending push:', error);
        return false;
    }
}

serve(async (req) => {
    // CORS
    if (req.method === 'OPTIONS') {
        return new Response('ok', {
            headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'POST',
                'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
            },
        });
    }

    try {
        const { user_id, title, body, url, tag }: PushPayload = await req.json();

        if (!user_id || !title || !body) {
            return new Response(JSON.stringify({ error: 'Missing required fields' }), {
                status: 400,
                headers: { 'Content-Type': 'application/json' },
            });
        }

        // Get user's push subscriptions
        const supabase = createClient(supabaseUrl, supabaseServiceKey);
        const { data: subscriptions, error } = await supabase
            .from('push_subscriptions')
            .select('*')
            .eq('user_id', user_id);

        if (error) {
            console.error('Error fetching subscriptions:', error);
            return new Response(JSON.stringify({ error: 'Failed to fetch subscriptions' }), {
                status: 500,
                headers: { 'Content-Type': 'application/json' },
            });
        }

        if (!subscriptions || subscriptions.length === 0) {
            return new Response(JSON.stringify({ success: true, sent: 0, message: 'No subscriptions found' }), {
                headers: { 'Content-Type': 'application/json' },
            });
        }

        // Send to all subscriptions
        const payload = { title, body, url: url || '/', tag: tag || 'benzdesk' };
        let sent = 0;

        for (const sub of subscriptions) {
            const subscription = {
                endpoint: sub.endpoint,
                keys: {
                    p256dh: sub.p256dh,
                    auth: sub.auth,
                },
            };
            const success = await sendPushNotification(subscription, payload);
            if (success) sent++;
        }

        return new Response(JSON.stringify({ success: true, sent }), {
            headers: { 'Content-Type': 'application/json' },
        });
    } catch (error) {
        console.error('Error:', error);
        return new Response(JSON.stringify({ error: 'Internal server error' }), {
            status: 500,
            headers: { 'Content-Type': 'application/json' },
        });
    }
});
