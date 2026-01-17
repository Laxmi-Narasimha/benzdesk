// ============================================================================
// Notification Trigger Helper
// Triggers push notifications via Supabase Edge Function
// ============================================================================

import { getSupabaseClient } from './supabaseClient';

interface NotificationPayload {
    user_id: string;
    title: string;
    body: string;
    url?: string;
    tag?: string;
}

/**
 * Send a push notification to a user via Supabase Edge Function
 */
export async function sendNotification(payload: NotificationPayload): Promise<boolean> {
    try {
        const supabase = getSupabaseClient();

        const { data, error } = await supabase.functions.invoke('send-push', {
            body: payload,
        });

        if (error) {
            console.error('[Notify] Error calling send-push:', error);
            return false;
        }

        console.log('[Notify] Push sent:', data);
        return data?.success || false;
    } catch (error) {
        console.error('[Notify] Failed to send notification:', error);
        return false;
    }
}

/**
 * Notify admins about a new request
 */
export async function notifyNewRequest(requestTitle: string, creatorName: string): Promise<void> {
    try {
        const supabase = getSupabaseClient();

        // Get all admin user IDs
        const { data: admins } = await supabase
            .from('user_roles')
            .select('user_id')
            .in('role', ['accounts_admin', 'director'])
            .eq('is_active', true);

        if (!admins) return;

        for (const admin of admins) {
            await sendNotification({
                user_id: admin.user_id,
                title: '📩 New Request',
                body: `${creatorName}: ${requestTitle}`,
                url: '/admin/queue',
                tag: 'new-request',
            });
        }
    } catch (error) {
        console.error('[Notify] Failed to notify admins:', error);
    }
}

/**
 * Notify requester about status change
 */
export async function notifyStatusChange(
    requesterId: string,
    requestTitle: string,
    newStatus: string,
    url: string
): Promise<void> {
    const statusMessages: Record<string, string> = {
        'in_progress': '🔄 Your request is now being processed',
        'waiting_on_requester': '⚠️ Action needed on your request',
        'pending_closure': '✅ Your request is complete - please confirm',
        'closed': '📁 Your request has been closed',
    };

    const message = statusMessages[newStatus] || `Status updated to ${newStatus}`;

    await sendNotification({
        user_id: requesterId,
        title: message,
        body: requestTitle,
        url,
        tag: `status-${newStatus}`,
    });
}

/**
 * Notify about new comment
 */
export async function notifyNewComment(
    recipientId: string,
    senderName: string,
    requestTitle: string,
    url: string
): Promise<void> {
    await sendNotification({
        user_id: recipientId,
        title: '💬 New Comment',
        body: `${senderName} commented on: ${requestTitle}`,
        url,
        tag: 'new-comment',
    });
}
