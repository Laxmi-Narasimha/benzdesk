// ============================================================================
// Notification Trigger Helper
// Comprehensive notification system for all BenzDesk events
// ============================================================================

import { getSupabaseClient } from './supabaseClient';
import { getDisplayName } from '@/types';

interface NotificationPayload {
    user_id: string;
    title: string;
    body: string;
    url?: string;
    tag?: string;
    icon?: string;
}

// ============================================================================
// Core Send Function
// ============================================================================

/**
 * Send a push notification to a user via Supabase Edge Function
 */
export async function sendNotification(payload: NotificationPayload): Promise<boolean> {
    try {
        const supabase = getSupabaseClient();

        console.log('[Notify] Sending notification:', payload);

        const { data, error } = await supabase.functions.invoke('send-push', {
            body: payload,
        });

        if (error) {
            console.error('[Notify] Error calling send-push:', error);
            return false;
        }

        console.log('[Notify] Push result:', data);
        return data?.success || false;
    } catch (error) {
        console.error('[Notify] Failed to send notification:', error);
        return false;
    }
}

// ============================================================================
// Status Change Notifications
// ============================================================================

const STATUS_NOTIFICATIONS: Record<string, { emoji: string; title: string; description: string }> = {
    'open': {
        emoji: '📬',
        title: 'Request Opened',
        description: 'Your request has been received',
    },
    'in_progress': {
        emoji: '🔄',
        title: 'Work Started',
        description: 'An admin is now working on your request',
    },
    'waiting_on_requester': {
        emoji: '⚠️',
        title: 'Action Required',
        description: 'The admin needs more information from you',
    },
    'pending_closure': {
        emoji: '✅',
        title: 'Ready for Confirmation',
        description: 'Your request is complete. Please confirm to close it.',
    },
    'closed': {
        emoji: '📁',
        title: 'Request Closed',
        description: 'Your request has been successfully closed',
    },
};

/**
 * Notify requester about status change
 */
export async function notifyStatusChange(
    requesterId: string,
    requesterEmail: string,
    requestId: string,
    requestTitle: string,
    newStatus: string,
    changedByEmail: string
): Promise<void> {
    const statusInfo = STATUS_NOTIFICATIONS[newStatus];
    if (!statusInfo) return;

    const changedByName = getDisplayName(changedByEmail);
    const requesterName = getDisplayName(requesterEmail);

    await sendNotification({
        user_id: requesterId,
        title: `${statusInfo.emoji} ${statusInfo.title}`,
        body: `${requestTitle}\n${statusInfo.description}\nUpdated by: ${changedByName}`,
        url: `/app/request?id=${requestId}`,
        tag: `status-${requestId}`,
    });
}

/**
 * Notify admins about new request
 */
export async function notifyNewRequest(
    requestId: string,
    requestTitle: string,
    requestCategory: string,
    creatorEmail: string
): Promise<void> {
    try {
        const supabase = getSupabaseClient();
        const creatorName = getDisplayName(creatorEmail);

        // Get all admin user IDs
        const { data: admins, error } = await supabase
            .from('user_roles')
            .select('user_id')
            .in('role', ['accounts_admin', 'director'])
            .eq('is_active', true);

        if (error || !admins) {
            console.error('[Notify] Failed to fetch admins:', error);
            return;
        }

        console.log(`[Notify] Notifying ${admins.length} admins about new request`);

        for (const admin of admins) {
            await sendNotification({
                user_id: admin.user_id,
                title: `📩 New Request from ${creatorName}`,
                body: `${requestTitle}\nCategory: ${requestCategory}`,
                url: `/admin/request?id=${requestId}`,
                tag: `new-request-${requestId}`,
            });
        }
    } catch (error) {
        console.error('[Notify] Failed to notify admins:', error);
    }
}

// ============================================================================
// Comment Notifications
// ============================================================================

/**
 * Notify about new comment on a request
 */
export async function notifyNewComment(
    recipientId: string,
    recipientEmail: string,
    senderEmail: string,
    requestId: string,
    requestTitle: string,
    commentPreview: string,
    isAdmin: boolean
): Promise<void> {
    const senderName = getDisplayName(senderEmail);
    const preview = commentPreview.length > 50
        ? commentPreview.substring(0, 50) + '...'
        : commentPreview;

    const url = isAdmin
        ? `/admin/request?id=${requestId}`
        : `/app/request?id=${requestId}`;

    await sendNotification({
        user_id: recipientId,
        title: `💬 ${senderName} commented`,
        body: `On: ${requestTitle}\n"${preview}"`,
        url,
        tag: `comment-${requestId}`,
    });
}

/**
 * Notify about reply to a comment
 */
export async function notifyCommentReply(
    originalCommenterId: string,
    replierEmail: string,
    requestId: string,
    requestTitle: string,
    replyPreview: string,
    isAdmin: boolean
): Promise<void> {
    const replierName = getDisplayName(replierEmail);
    const preview = replyPreview.length > 50
        ? replyPreview.substring(0, 50) + '...'
        : replyPreview;

    const url = isAdmin
        ? `/admin/request?id=${requestId}`
        : `/app/request?id=${requestId}`;

    await sendNotification({
        user_id: originalCommenterId,
        title: `↩️ ${replierName} replied`,
        body: `On: ${requestTitle}\n"${preview}"`,
        url,
        tag: `reply-${requestId}`,
    });
}

// ============================================================================
// Document/Attachment Notifications
// ============================================================================

/**
 * Notify about new document/attachment uploaded
 */
export async function notifyNewAttachment(
    recipientId: string,
    uploaderEmail: string,
    requestId: string,
    requestTitle: string,
    fileName: string,
    isAdmin: boolean
): Promise<void> {
    const uploaderName = getDisplayName(uploaderEmail);

    const url = isAdmin
        ? `/admin/request?id=${requestId}`
        : `/app/request?id=${requestId}`;

    await sendNotification({
        user_id: recipientId,
        title: `📎 ${uploaderName} uploaded a file`,
        body: `${fileName}\nOn: ${requestTitle}`,
        url,
        tag: `attachment-${requestId}`,
    });
}

// ============================================================================
// Assignment Notifications
// ============================================================================

/**
 * Notify admin when assigned to a request
 */
export async function notifyAssignment(
    assignedAdminId: string,
    assignerEmail: string,
    requestId: string,
    requestTitle: string,
    requesterEmail: string
): Promise<void> {
    const assignerName = getDisplayName(assignerEmail);
    const requesterName = getDisplayName(requesterEmail);

    await sendNotification({
        user_id: assignedAdminId,
        title: `👤 Request Assigned to You`,
        body: `${requestTitle}\nFrom: ${requesterName}\nAssigned by: ${assignerName}`,
        url: `/admin/request?id=${requestId}`,
        tag: `assigned-${requestId}`,
    });
}

// ============================================================================
// Reminder Notifications
// ============================================================================

/**
 * Notify admin about stale request
 */
export async function notifyStaleRequest(
    adminId: string,
    requestId: string,
    requestTitle: string,
    requesterEmail: string,
    daysSinceUpdate: number
): Promise<void> {
    const requesterName = getDisplayName(requesterEmail);

    await sendNotification({
        user_id: adminId,
        title: `⏰ Request needs attention`,
        body: `${requestTitle}\nFrom: ${requesterName}\nNo updates for ${daysSinceUpdate} days`,
        url: `/admin/request?id=${requestId}`,
        tag: `stale-${requestId}`,
    });
}

/**
 * Notify requester to confirm closure
 */
export async function notifyPendingClosureReminder(
    requesterId: string,
    requestId: string,
    requestTitle: string
): Promise<void> {
    await sendNotification({
        user_id: requesterId,
        title: `🔔 Please confirm your request`,
        body: `${requestTitle}\nThis request is waiting for your confirmation to close.`,
        url: `/app/request?id=${requestId}`,
        tag: `pending-${requestId}`,
    });
}
