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
    sender_email?: string;
}

// ============================================================================
// Core Send Function
// ============================================================================

/**
 * Send a push notification to a user via Supabase Edge Function
 */
export async function sendNotification(payload: NotificationPayload): Promise<boolean> {
    const debugId = `SEND-${Date.now()}`;
    console.log(`[${debugId}] ===== SENDING NOTIFICATION ====`);
    console.log(`[${debugId}] Target user_id: ${payload.user_id}`);
    console.log(`[${debugId}] Title: ${payload.title}`);
    console.log(`[${debugId}] Body: ${payload.body?.substring(0, 50)}...`);

    try {
        const supabase = getSupabaseClient();
        console.log(`[${debugId}] Step 1: Got Supabase client`);

        console.log(`[${debugId}] Step 2: Calling send-push Edge Function...`);
        const { data, error } = await supabase.functions.invoke('send-push', {
            body: payload,
        });

        if (error) {
            console.error(`[${debugId}] ❌ FAILED: Edge function error:`, error);
            console.error(`[${debugId}] Error message: ${error.message}`);
            console.error(`[${debugId}] Error context: ${JSON.stringify(error.context || {})}`);
            return false;
        }

        console.log(`[${debugId}] ✅ SUCCESS: Edge function response:`, data);
        console.log(`[${debugId}] Sent: ${data?.sent || 0}, Failed: ${data?.failed || 0}`);
        return data?.success || false;
    } catch (error: any) {
        console.error(`[${debugId}] ❌ EXCEPTION in sendNotification:`, error);
        console.error(`[${debugId}] Exception message: ${error?.message || 'Unknown'}`);
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
        sender_email: changedByEmail,
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
    const debugId = `NEW-REQ-${Date.now()}`;
    console.log(`[${debugId}] ===== NOTIFY NEW REQUEST =====`);
    console.log(`[${debugId}] Request ID: ${requestId}`);
    console.log(`[${debugId}] Title: ${requestTitle}`);
    console.log(`[${debugId}] Category: ${requestCategory}`);
    console.log(`[${debugId}] Creator: ${creatorEmail}`);

    try {
        const supabase = getSupabaseClient();
        const creatorName = getDisplayName(creatorEmail);
        console.log(`[${debugId}] Step 1: Creator display name: ${creatorName}`);

        // Get all admin user IDs
        console.log(`[${debugId}] Step 2: Fetching admin user IDs from user_roles...`);
        const { data: admins, error } = await supabase
            .from('user_roles')
            .select('user_id')
            .in('role', ['accounts_admin', 'director'])
            .eq('is_active', true);

        if (error) {
            console.error(`[${debugId}] ❌ FAILED: Database error fetching admins:`, error);
            return;
        }

        if (!admins || admins.length === 0) {
            console.warn(`[${debugId}] ⚠️ WARNING: No admins found in user_roles table!`);
            console.warn(`[${debugId}] Query: user_roles WHERE role IN ('accounts_admin', 'director') AND is_active = true`);
            return;
        }

        console.log(`[${debugId}] Step 3: Found ${admins.length} admin(s) to notify:`);
        admins.forEach((a, i) => console.log(`[${debugId}]   Admin ${i + 1}: ${a.user_id}`));

        for (let i = 0; i < admins.length; i++) {
            const admin = admins[i];
            console.log(`[${debugId}] Step 4.${i + 1}: Sending to admin ${admin.user_id}...`);
            await sendNotification({
                user_id: admin.user_id,
                title: `📩 New Request from ${creatorName}`,
                body: `${requestTitle}\nCategory: ${requestCategory}`,
                url: `/admin/request?id=${requestId}`,
                tag: `new-request-${requestId}`,
                sender_email: creatorEmail,
            });
        }

        console.log(`[${debugId}] ✅ COMPLETE: Sent notifications to ${admins.length} admin(s)`);
    } catch (error: any) {
        console.error(`[${debugId}] ❌ EXCEPTION in notifyNewRequest:`, error);
        console.error(`[${debugId}] Exception message: ${error?.message || 'Unknown'}`);
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
    const debugId = `COMMENT-${Date.now()}`;
    console.log(`[${debugId}] ===== NOTIFY NEW COMMENT =====`);
    console.log(`[${debugId}] Recipient ID: ${recipientId}`);
    console.log(`[${debugId}] Sender: ${senderEmail}`);
    console.log(`[${debugId}] Request: ${requestId} - ${requestTitle}`);
    console.log(`[${debugId}] isAdmin sender: ${isAdmin}`);

    const senderName = getDisplayName(senderEmail);
    const preview = commentPreview.length > 50
        ? commentPreview.substring(0, 50) + '...'
        : commentPreview;

    const url = isAdmin
        ? `/admin/request?id=${requestId}`
        : `/app/request?id=${requestId}`;

    console.log(`[${debugId}] Sending to user ${recipientId}...`);
    await sendNotification({
        user_id: recipientId,
        title: `💬 ${senderName} commented`,
        body: `On: ${requestTitle}\n"${preview}"`,
        url,
        tag: `comment-${requestId}`,
        sender_email: senderEmail,
    });
    console.log(`[${debugId}] ✅ DONE`);
}

/**
 * Notify ALL admins about a new comment from an employee
 */
export async function notifyAdminsOfNewComment(
    senderEmail: string,
    requestId: string,
    requestTitle: string,
    commentPreview: string
): Promise<void> {
    const debugId = `ADMIN-COMMENT-${Date.now()}`;
    console.log(`[${debugId}] ===== NOTIFY ADMINS OF COMMENT =====`);
    console.log(`[${debugId}] Sender: ${senderEmail}`);
    console.log(`[${debugId}] Request: ${requestId} - ${requestTitle}`);

    try {
        const supabase = getSupabaseClient();
        const senderName = getDisplayName(senderEmail);
        const preview = commentPreview.length > 50
            ? commentPreview.substring(0, 50) + '...'
            : commentPreview;

        console.log(`[${debugId}] Step 1: Fetching admins from user_roles...`);
        const { data: admins, error } = await supabase
            .from('user_roles')
            .select('user_id')
            .in('role', ['accounts_admin', 'director'])
            .eq('is_active', true);

        if (error) {
            console.error(`[${debugId}] ❌ FAILED: Database error:`, error);
            return;
        }

        if (!admins || admins.length === 0) {
            console.warn(`[${debugId}] ⚠️ WARNING: No admins found!`);
            return;
        }

        console.log(`[${debugId}] Step 2: Found ${admins.length} admin(s)`);

        for (let i = 0; i < admins.length; i++) {
            const admin = admins[i];
            console.log(`[${debugId}] Step 3.${i + 1}: Sending to ${admin.user_id}...`);
            await sendNotification({
                user_id: admin.user_id,
                title: `💬 ${senderName} replied`,
                body: `On: ${requestTitle}\n"${preview}"`,
                url: `/admin/request?id=${requestId}`,
                tag: `comment-${requestId}`,
                sender_email: senderEmail,
            });
        }
        console.log(`[${debugId}] ✅ COMPLETE: Notified ${admins.length} admin(s)`);
    } catch (error: any) {
        console.error(`[${debugId}] ❌ EXCEPTION:`, error?.message || error);
    }
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

// ============================================================================
// Sales Manager Notifications
// ============================================================================

/**
 * Notify a sales manager when a team member submits a new request
 */
export async function notifyManagerOfNewRequest(
    managerId: string,
    requestId: string,
    requestTitle: string,
    submitterEmail: string
): Promise<void> {
    const submitterName = getDisplayName(submitterEmail);
    await sendNotification({
        user_id: managerId,
        title: `📋 New request needs your approval`,
        body: `${requestTitle}\nSubmitted by: ${submitterName}`,
        url: `/sales-manager/request?id=${requestId}`,
        tag: `manager-approval-${requestId}`,
        sender_email: submitterEmail,
    });
}

/**
 * Notify a sales person when their manager approves/requests more info
 */
export async function notifySalesPersonOfManagerAction(
    requesterId: string,
    requestId: string,
    requestTitle: string,
    action: 'approved' | 'more_info',
    managerEmail: string
): Promise<void> {
    const managerName = getDisplayName(managerEmail);
    const isApproved = action === 'approved';

    await sendNotification({
        user_id: requesterId,
        title: isApproved
            ? `✅ Manager approved your request`
            : `💬 Manager needs more information`,
        body: `${requestTitle}\n${isApproved
            ? `${managerName} has approved and forwarded it to Accounts.`
            : `${managerName} has requested more details from you.`}`,
        url: `/app/request?id=${requestId}`,
        tag: `manager-action-${requestId}`,
        sender_email: managerEmail,
    });
}

/**
 * Notify admins when a manager approves a request (now visible to accounts)
 */
export async function notifyAdminsOfManagerApproval(
    requestId: string,
    requestTitle: string,
    managerEmail: string,
    submitterEmail: string
): Promise<void> {
    const managerName = getDisplayName(managerEmail);
    const submitterName = getDisplayName(submitterEmail);

    const supabase = getSupabaseClient();
    const { data: admins } = await supabase
        .from('user_roles')
        .select('user_id')
        .in('role', ['accounts_admin', 'director'])
        .eq('is_active', true);

    for (const admin of admins || []) {
        await sendNotification({
            user_id: admin.user_id,
            title: `📩 New request approved by ${managerName}`,
            body: `${requestTitle}\nFrom: ${submitterName}`,
            url: `/admin/request?id=${requestId}`,
            tag: `new-request-${requestId}`,
            sender_email: managerEmail,
        });
    }
}
