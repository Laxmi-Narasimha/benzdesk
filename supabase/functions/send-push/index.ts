// ============================================================================
// Supabase Edge Function: Send Push Notification
// Uses web-push library for proper encryption and delivery
// ALSO stores notification in database for in-app display with proper names
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.3'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// User names mapping from employee directory
const USER_NAMES: Record<string, string> = {
    'paulraj@benz-packaging.com': 'A.A. Paulraj',
    'wh.jaipur@benz-packaging.com': 'Mani Bhushan',
    'abhishek@benz-packaging.com': 'Abhishek Kori',
    'accounts.chennai@benz-packaging.com': 'Accounts Chennai',
    'accounts@benz-packaging.com': 'Accounts Team',
    'accounts1@benz-packaging.com': 'Accounts1',
    'ajay@benz-packaging.com': 'Ajay',
    'dispatch1@benz-packaging.com': 'Aman Roy',
    'sales3@benz-packaging.com': 'Babita',
    'sales4@benz-packaging.com': 'BENZ Sales',
    'deepak@benz-packaging.com': 'Deepak Bhardwaj',
    'dinesh@benz-packaging.com': 'Dinesh',
    'sales@ergopack-india.com': 'Ergopack India',
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

function getDisplayName(email: string | null | undefined): string {
    if (!email) return 'Someone';
    const lowerEmail = email.toLowerCase();
    if (USER_NAMES[lowerEmail]) {
        return USER_NAMES[lowerEmail];
    }
    // Fallback: format email prefix nicely
    return email.split('@')[0]
        .replace(/[._]/g, ' ')
        .split(' ')
        .map((word: string) => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');
}

// Detect notification type from title
function detectNotificationType(title: string): string {
    const t = title.toLowerCase();
    if (t.includes('comment') || t.includes('replied') || title.includes('💬')) {
        return 'comment';
    }
    if (t.includes('upload') || t.includes('file') || t.includes('document') || title.includes('📎')) {
        return 'file_upload';
    }
    if (t.includes('status') || title.includes('🔄') || title.includes('✅') || title.includes('⚠️')) {
        return 'status_change';
    }
    return 'comment';
}

// Extract request ID from URL
function extractRequestId(url: string | undefined): string | null {
    if (!url) return null;
    const match = url.match(/[?&]id=([a-f0-9-]+)/i);
    return match ? match[1] : null;
}

serve(async (req: Request) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const requestBody = await req.json()
        const { user_id, title, body, url, tag, sender_email } = requestBody

        console.log('=== SEND-PUSH INVOKED ===')
        console.log('user_id:', user_id)
        console.log('title:', title)
        console.log('sender_email:', sender_email)

        // Environment variables
        const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
        const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY') || ''
        const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY') || ''

        if (!vapidPublicKey || !vapidPrivateKey) {
            console.error('Missing VAPID keys!')
            throw new Error('Missing VAPID keys')
        }

        // Configure web-push
        webpush.setVapidDetails(
            'mailto:support@benz-packaging.com',
            vapidPublicKey,
            vapidPrivateKey
        )

        // Initialize Supabase client with service role
        const supabase = createClient(supabaseUrl, supabaseServiceKey)

        // Get the proper display name for the sender
        const senderName = getDisplayName(sender_email);
        console.log('Sender display name:', senderName)

        // Format title and body - REPLACE "client" with actual name
        let formattedTitle = title || 'BenzDesk Notification';
        let formattedBody = body || 'You have a new update';

        // Replace any occurrence of "client" with actual sender name
        formattedTitle = formattedTitle.replace(/\bThe client\b/gi, senderName);
        formattedTitle = formattedTitle.replace(/\bclient\b/gi, senderName);
        formattedBody = formattedBody.replace(/\bThe client\b/gi, senderName);
        formattedBody = formattedBody.replace(/\bclient\b/gi, senderName);

        console.log('Formatted title:', formattedTitle)
        console.log('Formatted body:', formattedBody)

        // =========================================================
        // STEP 1: Store notification in database for in-app display
        // =========================================================
        const notificationType = detectNotificationType(formattedTitle);
        const requestId = extractRequestId(url);

        console.log('Storing in-app notification...')
        console.log('Type:', notificationType, 'Request ID:', requestId)

        try {
            const { error: insertError } = await supabase
                .from('notifications')
                .insert({
                    user_id: user_id,
                    request_id: requestId,
                    type: notificationType,
                    title: formattedTitle,
                    message: formattedBody,
                    is_read: false,
                });

            if (insertError) {
                console.error('Failed to insert notification:', insertError.message);
            } else {
                console.log('✅ In-app notification stored successfully');
            }

            // Cleanup old notifications - keep only latest 10 per user
            const { data: oldNotifications } = await supabase
                .from('notifications')
                .select('id')
                .eq('user_id', user_id)
                .order('created_at', { ascending: false })
                .range(10, 1000);

            if (oldNotifications && oldNotifications.length > 0) {
                const idsToDelete = oldNotifications.map((n: { id: string }) => n.id);
                await supabase
                    .from('notifications')
                    .delete()
                    .in('id', idsToDelete);
                console.log(`Cleaned up ${idsToDelete.length} old notifications`);
            }
        } catch (dbErr) {
            console.error('Database error for in-app notification:', dbErr);
            // Continue with push notification even if in-app fails
        }

        // =========================================================
        // STEP 2: Send push notification to all user subscriptions
        // =========================================================
        const { data: subscriptions, error: dbError } = await supabase
            .from('push_subscriptions')
            .select('*')
            .eq('user_id', user_id)

        if (dbError) {
            console.error('Error fetching subscriptions:', dbError.message)
            throw new Error(`Database error: ${dbError.message}`)
        }

        if (!subscriptions || subscriptions.length === 0) {
            console.log('No push subscriptions found for user, in-app only')
            return new Response(
                JSON.stringify({ success: true, message: 'In-app notification stored, no push subscriptions', sent: 0, inApp: true }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        console.log(`Found ${subscriptions.length} push subscription(s) for user ${user_id}`)

        // Prepare push payload
        const payload = JSON.stringify({
            title: formattedTitle,
            body: formattedBody,
            url: url || '/',
            tag: tag || 'benzdesk-notification',
            icon: '/icon-192.png',
            badge: '/icon-192.png',
            timestamp: Date.now()
        })

        // Send push to all subscriptions
        const results = await Promise.allSettled(
            subscriptions.map(async (sub: { id: string; endpoint: string; p256dh: string; auth: string }) => {
                try {
                    const pushSubscription = {
                        endpoint: sub.endpoint,
                        keys: {
                            p256dh: sub.p256dh,
                            auth: sub.auth
                        }
                    }

                    await webpush.sendNotification(pushSubscription, payload)
                    console.log(`✅ Push sent to endpoint: ${sub.endpoint.substring(0, 50)}...`)
                    return { success: true, endpoint: sub.endpoint }
                } catch (error: unknown) {
                    console.error(`❌ Failed to send to ${sub.endpoint.substring(0, 50)}:`, error)

                    // If subscription is invalid/expired, delete it
                    const err = error as { statusCode?: number };
                    if (err.statusCode === 404 || err.statusCode === 410) {
                        await supabase.from('push_subscriptions').delete().eq('id', sub.id)
                        console.log(`Deleted invalid subscription: ${sub.id}`)
                    }

                    throw error
                }
            })
        )

        const sentCount = results.filter((r: PromiseSettledResult<unknown>) => r.status === 'fulfilled').length
        const failedCount = results.filter((r: PromiseSettledResult<unknown>) => r.status === 'rejected').length

        console.log(`=== COMPLETE: Sent ${sentCount}, Failed ${failedCount} ===`)

        return new Response(
            JSON.stringify({
                success: true,
                sent: sentCount,
                failed: failedCount,
                inApp: true
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error: unknown) {
        const err = error as { message?: string };
        console.error('=== ERROR in send-push ===', error)
        return new Response(
            JSON.stringify({ success: false, error: err.message || 'Unknown error' }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
        )
    }
})
