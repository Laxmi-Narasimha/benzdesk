// ============================================================================
// Request Detail Component
// Full request view with status controls for admins
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { clsx } from 'clsx';
import { formatDistanceToNow, format } from 'date-fns';
import {
    ArrowLeft,
    Clock,
    User,
    Tag,
    Paperclip,
    MessageSquare,
    Edit,
    CheckCircle,
    CheckCircle2,
    XCircle,
    AlertCircle,
} from 'lucide-react';
import {
    Card,
    CardHeader,
    Button,
    StatusBadge,
    PriorityBadge,
    Select,
    useToast,
    Spinner,
} from '@/components/ui';
import { RequestTimeline } from './RequestTimeline';
import { CommentThread } from './CommentThread';
import { AttachmentList } from './AttachmentList';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import type { Request, RequestComment, RequestEvent, RequestAttachment, RequestStatus, Priority } from '@/types';
import { REQUEST_CATEGORY_LABELS, REQUEST_STATUS_LABELS } from '@/types';
import { notifyStatusChange } from '@/lib/notificationTrigger';

// ============================================================================
// Types
// ============================================================================

interface RequestDetailProps {
    requestId: string;
}

// ============================================================================
// Status Options (for admin)
// ============================================================================

// Status options - admins can't set 'closed' directly, only 'pending_closure'
// Directors can set any status including 'closed'
const allStatusOptions = Object.entries(REQUEST_STATUS_LABELS).map(([value, label]) => ({
    value,
    label,
}));

const adminStatusOptions = allStatusOptions.filter(opt => opt.value !== 'closed');

// ============================================================================
// Component
// ============================================================================

export function RequestDetail({ requestId }: RequestDetailProps) {
    const router = useRouter();
    const { user, isAdmin, isDirector, canManageRequests } = useAuth();
    const { success, error: showError } = useToast();

    const [request, setRequest] = useState<Request | null>(null);
    const [comments, setComments] = useState<RequestComment[]>([]);
    const [events, setEvents] = useState<RequestEvent[]>([]);
    const [attachments, setAttachments] = useState<RequestAttachment[]>([]);
    const [loading, setLoading] = useState(true);
    const [updating, setUpdating] = useState(false);
    const [activeTab, setActiveTab] = useState<'comments' | 'timeline'>('comments');

    // ============================================================================
    // Fetch Data
    // ============================================================================

    useEffect(() => {
        async function fetchData() {
            if (!requestId) return;

            setLoading(true);

            try {
                const supabase = getSupabaseClient();

                // Fetch request
                const { data: requestData, error: requestError } = await supabase
                    .from('requests')
                    .select('*')
                    .eq('id', requestId)
                    .single();

                if (requestError) throw requestError;
                setRequest(requestData);

                // Fetch comments
                const { data: commentsData } = await supabase
                    .from('request_comments')
                    .select('*')
                    .eq('request_id', requestId)
                    .order('created_at', { ascending: true });

                setComments(commentsData || []);

                // Fetch events
                const { data: eventsData } = await supabase
                    .from('request_events')
                    .select('*')
                    .eq('request_id', requestId)
                    .order('created_at', { ascending: true });

                setEvents(eventsData || []);

                // Fetch attachments
                const { data: attachmentsData } = await supabase
                    .from('request_attachments')
                    .select('*')
                    .eq('request_id', requestId)
                    .order('uploaded_at', { ascending: true });

                setAttachments(attachmentsData || []);
            } catch (err: any) {
                console.error('Error fetching request:', err);
                showError('Error', 'Failed to load request details');
            } finally {
                setLoading(false);
            }
        }

        fetchData();
    }, [requestId]);

    // ============================================================================
    // Update Status (Admin only)
    // ============================================================================

    const updateStatus = async (newStatus: RequestStatus) => {
        if (!request || !canManageRequests) return;

        setUpdating(true);

        try {
            const supabase = getSupabaseClient();

            const { data, error } = await supabase
                .from('requests')
                .update({ status: newStatus })
                .eq('id', request.id)
                .select()
                .single();

            if (error) {
                throw error;
            }

            setRequest(data);
            success('Status Updated', `Request status changed to ${REQUEST_STATUS_LABELS[newStatus]}`);

            // Send push notification to requester with proper names
            if (data.created_by && user) {
                notifyStatusChange(
                    data.created_by,
                    '', // Email will be resolved by the trigger function
                    data.id,
                    data.title,
                    newStatus,
                    user.email
                );
            }

            // Refresh events
            const { data: eventsData } = await supabase
                .from('request_events')
                .select('*')
                .eq('request_id', requestId)
                .order('created_at', { ascending: true });

            setEvents(eventsData || []);
        } catch (err: any) {
            console.error('Error updating status:', err);
            showError('Error', 'Failed to update status');
        } finally {
            setUpdating(false);
        }
    };

    // ============================================================================
    // Confirm Closure (Employee only - for pending_closure status)
    // ============================================================================

    const confirmClosure = async () => {
        if (!request || !user) return;

        // Only the request creator can confirm closure
        if (request.created_by !== user.id) return;

        setUpdating(true);

        try {
            const supabase = getSupabaseClient();

            const { data, error } = await supabase
                .from('requests')
                .update({ status: 'closed' as RequestStatus })
                .eq('id', request.id)
                .select()
                .single();

            if (error) throw error;

            setRequest(data);
            success('Request Closed', 'You have confirmed the closure of this request');

            // Refresh events
            const { data: eventsData } = await supabase
                .from('request_events')
                .select('*')
                .eq('request_id', requestId)
                .order('created_at', { ascending: true });

            setEvents(eventsData || []);
        } catch (err) {
            console.error('Error confirming closure:', err);
            showError('Error', 'Failed to confirm closure');
        } finally {
            setUpdating(false);
        }
    };

    const requestReopen = async () => {
        if (!request || !user) return;

        // Only the request creator can request reopening
        if (request.created_by !== user.id) return;

        setUpdating(true);

        try {
            const supabase = getSupabaseClient();

            const { data, error } = await supabase
                .from('requests')
                .update({ status: 'open' as RequestStatus })
                .eq('id', request.id)
                .select()
                .single();

            if (error) throw error;

            setRequest(data);
            success('Request Reopened', 'You have reopened this request');

            // Refresh events
            const { data: eventsData } = await supabase
                .from('request_events')
                .select('*')
                .eq('request_id', requestId)
                .order('created_at', { ascending: true });

            setEvents(eventsData || []);
        } catch (err) {
            console.error('Error reopening request:', err);
            showError('Error', 'Failed to reopen request');
        } finally {
            setUpdating(false);
        }
    };

    // ============================================================================
    // Add Comment
    // ============================================================================

    const handleAddComment = async (body: string, isInternal: boolean) => {
        if (!request || !user) return;

        try {
            const supabase = getSupabaseClient();

            // Debug log
            console.log('Adding comment:', {
                request_id: request.id,
                author_id: user.id,
                body_length: body.length,
                is_internal: isInternal,
            });

            const { data, error } = await supabase
                .from('request_comments')
                .insert({
                    request_id: request.id,
                    author_id: user.id,
                    body,
                    is_internal: isInternal,
                })
                .select()
                .single();

            if (error) {
                console.error('Supabase error:', {
                    message: error.message,
                    details: error.details,
                    hint: error.hint,
                    code: error.code,
                });
                throw error;
            }

            setComments((prev) => [...prev, data]);
            success('Comment Added', 'Your comment has been posted');

            // Refresh events
            const { data: eventsData } = await supabase
                .from('request_events')
                .select('*')
                .eq('request_id', requestId)
                .order('created_at', { ascending: true });

            setEvents(eventsData || []);
        } catch (err: any) {
            console.error('Error adding comment:', err);
            showError('Error', err?.message || 'Failed to add comment');
            throw err;
        }
    };

    // ============================================================================
    // Loading State
    // ============================================================================

    if (loading) {
        return (
            <div className="flex items-center justify-center min-h-[400px]">
                <Spinner size="lg" />
            </div>
        );
    }

    if (!request) {
        return (
            <Card className="text-center py-12">
                <AlertCircle className="w-12 h-12 mx-auto text-red-500 mb-4" />
                <h2 className="text-lg font-semibold text-gray-900">Request Not Found</h2>
                <p className="text-gray-500 mt-2">This request may have been deleted or you don't have access.</p>
                <Button variant="secondary" onClick={() => router.back()} className="mt-4">
                    Go Back
                </Button>
            </Card>
        );
    }

    // ============================================================================
    // Render
    // ============================================================================

    return (
        <div className="space-y-6">
            {/* Back button */}
            <Button variant="ghost" size="sm" onClick={() => router.back()}>
                <ArrowLeft className="w-4 h-4 mr-2" />
                Back
            </Button>

            {/* Pending Closure Confirmation Banner (for employees only) */}
            {request.status === 'pending_closure' && request.created_by === user?.id && (
                <div className="p-4 bg-purple-50 border border-purple-200 rounded-xl flex flex-col sm:flex-row items-start sm:items-center gap-4">
                    <div className="flex-1">
                        <h3 className="font-semibold text-purple-900 flex items-center gap-2">
                            <CheckCircle2 className="w-5 h-5" />
                            Admin has requested to close this request
                        </h3>
                        <p className="text-sm text-purple-700 mt-1">
                            Please confirm if your issue has been resolved, or request to reopen if you need further assistance.
                        </p>
                    </div>
                    <div className="flex gap-2 w-full sm:w-auto">
                        <Button
                            onClick={confirmClosure}
                            isLoading={updating}
                            className="flex-1 sm:flex-initial bg-green-600 hover:bg-green-700"
                        >
                            <CheckCircle2 className="w-4 h-4 mr-1" />
                            Confirm Close
                        </Button>
                        <Button
                            variant="secondary"
                            onClick={requestReopen}
                            isLoading={updating}
                            className="flex-1 sm:flex-initial"
                        >
                            <XCircle className="w-4 h-4 mr-1" />
                            Reopen
                        </Button>
                    </div>
                </div>
            )}

            {/* Main content */}
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                {/* Left column - Request details */}
                <div className="lg:col-span-2 space-y-6">
                    <Card padding="lg">
                        <div className="flex flex-col sm:flex-row items-start justify-between gap-4 mb-4">
                            <div>
                                <h1 className="text-xl sm:text-2xl font-bold text-gray-900">{request.title}</h1>
                                <div className="flex flex-wrap items-center gap-2 sm:gap-3 mt-2">
                                    <StatusBadge status={request.status} size="md" />
                                    <PriorityBadge priority={request.priority as Priority} size="md" />
                                </div>
                            </div>

                            {/* Admin status control */}
                            {canManageRequests && (
                                <div className="flex-shrink-0 w-full sm:w-auto">
                                    <Select
                                        options={isDirector ? allStatusOptions : adminStatusOptions}
                                        value={request.status}
                                        onChange={(e) => updateStatus(e.target.value as RequestStatus)}
                                        size="sm"
                                        fullWidth={false}
                                        className="w-full sm:w-48"
                                        disabled={updating}
                                    />
                                </div>
                            )}
                        </div>

                        {/* Description */}
                        <div className="prose max-w-none">
                            <p className="text-gray-600 whitespace-pre-wrap">{request.description}</p>
                        </div>
                    </Card>

                    {/* Tabs - Comments / Timeline */}
                    <div className="flex gap-1 p-1 rounded-xl bg-gray-100 border border-gray-200">
                        <button
                            onClick={() => setActiveTab('comments')}
                            className={clsx(
                                'flex-1 flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors',
                                activeTab === 'comments'
                                    ? 'bg-white text-gray-900 shadow-sm'
                                    : 'text-gray-500 hover:text-gray-700'
                            )}
                        >
                            <MessageSquare className="w-4 h-4" />
                            Comments ({comments.filter(c => !c.is_internal || canManageRequests).length})
                        </button>
                        <button
                            onClick={() => setActiveTab('timeline')}
                            className={clsx(
                                'flex-1 flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors',
                                activeTab === 'timeline'
                                    ? 'bg-white text-gray-900 shadow-sm'
                                    : 'text-gray-500 hover:text-gray-700'
                            )}
                        >
                            <Clock className="w-4 h-4" />
                            Timeline ({events.length})
                        </button>
                    </div>

                    {/* Tab content */}
                    {activeTab === 'comments' ? (
                        <CommentThread
                            comments={comments}
                            onAddComment={handleAddComment}
                            canAddInternal={canManageRequests}
                            requestCreatorId={request.created_by}
                        />
                    ) : (
                        <RequestTimeline events={events} />
                    )}
                </div>

                {/* Right column - Metadata & Attachments */}
                <div className="space-y-6">
                    {/* Metadata */}
                    <Card>
                        <h3 className="text-sm font-semibold text-dark-300 uppercase tracking-wider mb-4">
                            Details
                        </h3>
                        <dl className="space-y-4">
                            <div className="flex items-center justify-between">
                                <dt className="text-sm text-dark-500 flex items-center gap-2">
                                    <Tag className="w-4 h-4" />
                                    Category
                                </dt>
                                <dd className="text-sm text-dark-200">
                                    {REQUEST_CATEGORY_LABELS[request.category as keyof typeof REQUEST_CATEGORY_LABELS] || request.category}
                                </dd>
                            </div>

                            {/* Deadline display */}
                            {request.deadline && (
                                <div className="flex items-center justify-between pt-3 border-t border-dark-700">
                                    <dt className="text-sm text-dark-500 flex items-center gap-2">
                                        <Clock className="w-4 h-4" />
                                        Deadline
                                    </dt>
                                    <dd className={clsx(
                                        "text-sm font-medium",
                                        new Date(request.deadline) < new Date() && request.status !== 'closed'
                                            ? "text-red-400"
                                            : "text-dark-200"
                                    )}>
                                        {format(new Date(request.deadline), 'dd MMM yyyy, HH:mm')}
                                        {new Date(request.deadline) < new Date() && request.status !== 'closed' && (
                                            <span className="ml-2 text-xs text-red-500">(Overdue)</span>
                                        )}
                                    </dd>
                                </div>
                            )}

                            <div className="pt-4 border-t border-dark-700 space-y-3">
                                <h4 className="text-xs font-medium text-dark-400 uppercase tracking-wider mb-2">Timestamps</h4>

                                {/* Created timestamp */}
                                <div>
                                    <dt className="text-xs text-dark-500">Created</dt>
                                    <dd className="text-sm text-dark-100 font-mono">
                                        {format(new Date(request.created_at), 'dd MMM yyyy, HH:mm:ss')}
                                    </dd>
                                    <dd className="text-xs text-dark-500">
                                        ({formatDistanceToNow(new Date(request.created_at), { addSuffix: true })})
                                    </dd>
                                </div>

                                {/* Last Activity timestamp */}
                                <div>
                                    <dt className="text-xs text-dark-500">Last Activity</dt>
                                    <dd className="text-sm text-dark-100 font-mono">
                                        {format(new Date(request.last_activity_at), 'dd MMM yyyy, HH:mm:ss')}
                                    </dd>
                                    <dd className="text-xs text-dark-500">
                                        ({formatDistanceToNow(new Date(request.last_activity_at), { addSuffix: true })})
                                    </dd>
                                </div>

                                {/* First Admin Response */}
                                {request.first_admin_response_at && (
                                    <div>
                                        <dt className="text-xs text-dark-500 flex items-center gap-1">
                                            <CheckCircle className="w-3 h-3 text-green-500" />
                                            First Response
                                        </dt>
                                        <dd className="text-sm text-dark-100 font-mono">
                                            {format(new Date(request.first_admin_response_at), 'dd MMM yyyy, HH:mm:ss')}
                                        </dd>
                                        <dd className="text-xs text-dark-500">
                                            ({formatDistanceToNow(new Date(request.first_admin_response_at), { addSuffix: true })})
                                        </dd>
                                    </div>
                                )}

                                {/* Closed timestamp */}
                                {request.closed_at && (
                                    <div>
                                        <dt className="text-xs text-dark-500 flex items-center gap-1">
                                            <CheckCircle className="w-3 h-3 text-blue-500" />
                                            Closed
                                        </dt>
                                        <dd className="text-sm text-dark-100 font-mono">
                                            {format(new Date(request.closed_at), 'dd MMM yyyy, HH:mm:ss')}
                                        </dd>
                                        <dd className="text-xs text-dark-500">
                                            ({formatDistanceToNow(new Date(request.closed_at), { addSuffix: true })})
                                        </dd>
                                    </div>
                                )}

                                {/* Time to close (if closed) */}
                                {request.closed_at && (
                                    <div className="pt-2 border-t border-dark-700">
                                        <dt className="text-xs text-dark-500">Resolution Time</dt>
                                        <dd className="text-sm text-green-400 font-medium">
                                            {(() => {
                                                const created = new Date(request.created_at);
                                                const closed = new Date(request.closed_at);
                                                const diffMs = closed.getTime() - created.getTime();
                                                const hours = Math.floor(diffMs / (1000 * 60 * 60));
                                                const minutes = Math.floor((diffMs % (1000 * 60 * 60)) / (1000 * 60));
                                                if (hours > 24) {
                                                    const days = Math.floor(hours / 24);
                                                    return `${days} day${days > 1 ? 's' : ''} ${hours % 24}h`;
                                                }
                                                return `${hours}h ${minutes}m`;
                                            })()}
                                        </dd>
                                    </div>
                                )}
                            </div>
                        </dl>
                    </Card>

                    {/* Attachments */}
                    <Card>
                        <h3 className="text-sm font-semibold text-dark-300 uppercase tracking-wider mb-4 flex items-center gap-2">
                            <Paperclip className="w-4 h-4" />
                            Attachments ({attachments.length})
                        </h3>
                        <AttachmentList
                            attachments={attachments}
                            requestId={request.id}
                            canUpload={request.created_by === user?.id || canManageRequests}
                            onUpload={(newAttachment) => setAttachments(prev => [...prev, newAttachment])}
                        />
                    </Card>
                </div>
            </div>
        </div>
    );
}

export default RequestDetail;
