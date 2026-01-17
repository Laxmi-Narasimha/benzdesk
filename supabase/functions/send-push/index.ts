// ============================================================================
// Supabase Edge Function: Send Push Notification
// Uses web-push library for proper encryption and delivery
// ============================================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.3'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const { user_id, title, body, url, tag } = await req.json()

        // Environment variables
        const supabaseUrl = Deno.env.get('SUPABASE_URL') || ''
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
        const vapidPublicKey = Deno.env.get('VAPID_PUBLIC_KEY') || ''
        const vapidPrivateKey = Deno.env.get('VAPID_PRIVATE_KEY') || ''

        if (!vapidPublicKey || !vapidPrivateKey) {
            throw new Error('Missing VAPID keys')
        }

        // Configure web-push
        webpush.setVapidDetails(
            'mailto:support@benz-packaging.com',
            vapidPublicKey,
            vapidPrivateKey
        )

        // Initialize Supabase client
        const supabase = createClient(supabaseUrl, supabaseServiceKey)

        // Get subscriptions for user
        const { data: subscriptions, error: dbError } = await supabase
            .from('push_subscriptions')
            .select('*')
            .eq('user_id', user_id)

        if (dbError) {
            throw new Error(`Database error: ${dbError.message}`)
        }

        if (!subscriptions || subscriptions.length === 0) {
            return new Response(
                JSON.stringify({ success: false, message: 'No subscriptions found', sent: 0 }),
                { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        console.log(`Found ${subscriptions.length} subscriptions for user ${user_id}`)

        // Prepare payload
        const payload = JSON.stringify({
            title: title || 'BenzDesk Notification',
            body: body || 'You have a new update',
            url: url || '/',
            tag: tag || 'benzdesk-notification',
            icon: '/icon-192.png',
            badge: '/icon-192.png',
            timestamp: Date.now()
        })

        // Send notifications
        const results = await Promise.allSettled(
            subscriptions.map(async (sub) => {
                try {
                    const pushSubscription = {
                        endpoint: sub.endpoint,
                        keys: {
                            p256dh: sub.p256dh,
                            auth: sub.auth
                        }
                    }

                    await webpush.sendNotification(pushSubscription, payload)
                    return { success: true, endpoint: sub.endpoint }
                } catch (error) {
                    console.error(`Failed to send to ${sub.endpoint}:`, error)

                    // If subscription is invalid/expired, delete it
                    if (error.statusCode === 404 || error.statusCode === 410) {
                        await supabase.from('push_subscriptions').delete().eq('id', sub.id)
                        console.log(`Deleted invalid subscription: ${sub.id}`)
                    }

                    throw error
                }
            })
        )

        const sentCount = results.filter(r => r.status === 'fulfilled').length
        const failedCount = results.filter(r => r.status === 'rejected').length

        console.log(`Sent: ${sentCount}, Failed: ${failedCount}`)

        return new Response(
            JSON.stringify({
                success: true,
                sent: sentCount,
                failed: failedCount
            }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )

    } catch (error: any) {
        console.error('Error in send-push:', error)
        return new Response(
            JSON.stringify({ success: false, error: error.message }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
        )
    }
})
