// ============================================================================
// Sales Manager — Request Detail Page
// Manager can review, chat, adjust amount, and approve/request more info
// ============================================================================

'use client';

import React, { useState, useEffect, Suspense } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { ArrowLeft, CheckCircle2, MessageSquare, IndianRupee, Clock, AlertCircle, User } from 'lucide-react';
import {
    Card,
    CardHeader,
    Button,
    StatusBadge,
    PriorityBadge,
    Spinner,
    useToast,
} from '@/components/ui';
import { CommentThread } from '@/components/requests/CommentThread';
import { AttachmentList } from '@/components/requests/AttachmentList';
import { RequestTimeline } from '@/components/requests/RequestTimeline';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import { formatDistanceToNow, format } from 'date-fns';
import {
    notifySalesPersonOfManagerAction,
    notifyAdminsOfManagerApproval,
    notifyNewComment,
} from '@/lib/notificationTrigger';
import { REQUEST_CATEGORY_LABELS, REQUEST_STATUS_LABELS } from '@/types';
import type { Request, RequestComment, RequestEvent, RequestAttachment } from '@/types';

// ============================================================================
// Inner Component (uses useSearchParams — must be inside Suspense)
// ============================================================================

function ManagerRequestDetailInner() {
    const searchParams = useSearchParams();
    const requestId = searchParams.get('id');
    const router = useRouter();
    const { user } = useAuth();
    const { success, error: showError } = useToast();

    const [request, setRequest] = useState<Request | null>(null);
    const [comments, setComments] = useState<RequestComment[]>([]);
    const [events, setEvents] = useState<RequestEvent[]>([]);
    const [attachments, setAttachments] = useState<RequestAttachment[]>([]);
    const [loading, setLoading] = useState(true);
    const [approving, setApproving] = useState(false);
    const [activeTab, setActiveTab] = useState<'comments' | 'timeline'>('comments');

    // Editable amount field (manager can override)
    const [adjustedAmount, setAdjustedAmount] = useState<string>('');

    useEffect(() => {
        if (!requestId) return;
        async function fetchData() {
            const supabase = getSupabaseClient();
            const [reqRes, commentsRes, eventsRes, attachmentsRes] = await Promise.all([
                supabase.from('requests').select('*').eq('id', requestId).single(),
                supabase.from('request_comments').select('*').eq('request_id', requestId).order('created_at', { ascending: true }),
                supabase.from('request_events').select('*').eq('request_id', requestId).order('created_at', { ascending: true }),
                supabase.from('request_attachments').select('*').eq('request_id', requestId).order('uploaded_at', { ascending: true }),
            ]);

            if (reqRes.data) {
                setRequest(reqRes.data);
                setAdjustedAmount(reqRes.data.amount?.toString() || '');
            }
            setComments(commentsRes.data || []);
            setEvents(eventsRes.data || []);
            setAttachments(attachmentsRes.data || []);
            setLoading(false);
        }
        fetchData();
    }, [requestId]);

    const handleApprove = async () => {
        if (!request || !user) return;
        setApproving(true);
        try {
            const supabase = getSupabaseClient();
            const adj = adjustedAmount ? parseFloat(adjustedAmount) : null;

            const { data, error } = await supabase
                .from('requests')
                .update({
                    status: 'open', // Now goes to accounts admins
                    manager_approved_at: new Date().toISOString(),
                    manager_approved_by: user.id,
                    manager_adjusted_amount: adj !== null && adj !== request.amount ? adj : null,
                })
                .eq('id', request.id)
                .select()
                .single();

            if (error) throw error;
            setRequest(data);
            success('Approved', 'Request forwarded to Accounts team');

            // Notify requester + admins
            notifySalesPersonOfManagerAction(
                request.created_by, request.id, request.title, 'approved', user.email || ''
            ).catch(console.error);

            // Fetch requester email for admin notification
            const { data: requesterData } = await supabase
                .from('user_roles')
                .select('user_id')
                .eq('user_id', request.created_by)
                .single();

            const { data: authUser } = await (supabase.auth as any).admin?.getUserById(request.created_by) || {};
            notifyAdminsOfManagerApproval(
                request.id,
                request.title,
                user.email || '',
                authUser?.user?.email || request.created_by
            ).catch(console.error);

            // Refresh events
            const { data: eventsData } = await supabase
                .from('request_events')
                .select('*')
                .eq('request_id', requestId)
                .order('created_at', { ascending: true });
            setEvents(eventsData || []);
        } catch (err: any) {
            console.error('Approve error:', err);
            showError('Error', 'Failed to approve request');
        } finally {
            setApproving(false);
        }
    };

    const handleRequestMoreInfo = async () => {
        if (!request || !user) return;
        setApproving(true);
        try {
            const supabase = getSupabaseClient();
            const { data, error } = await supabase
                .from('requests')
                .update({ status: 'waiting_on_requester' })
                .eq('id', request.id)
                .select()
                .single();

            if (error) throw error;
            setRequest(data);
            success('Updated', 'Status changed to Waiting on Requester');

            notifySalesPersonOfManagerAction(
                request.created_by, request.id, request.title, 'more_info', user.email || ''
            ).catch(console.error);

            const { data: eventsData } = await supabase
                .from('request_events')
                .select('*')
                .eq('request_id', requestId)
                .order('created_at', { ascending: true });
            setEvents(eventsData || []);
        } catch (err: any) {
            console.error('More info error:', err);
            showError('Error', 'Failed to update status');
        } finally {
            setApproving(false);
        }
    };

    const handleAddComment = async (body: string, isInternal: boolean) => {
        if (!request || !user) return;
        const supabase = getSupabaseClient();
        const { data, error } = await supabase
            .from('request_comments')
            .insert({ request_id: request.id, author_id: user.id, body, is_internal: false })
            .select()
            .single();

        if (error) { showError('Error', 'Failed to post comment'); return; }
        setComments(prev => [...prev, data]);
        success('Comment Added', '');

        // Notify the sales person
        notifyNewComment(
            request.created_by, '', user.email || 'Manager',
            request.id, request.title, body, true
        ).catch(console.error);
    };

    if (loading) {
        return <div className="flex justify-center py-20"><Spinner size="lg" /></div>;
    }

    if (!request) {
        return (
            <div className="text-center py-20">
                <AlertCircle className="w-12 h-12 text-red-500 mx-auto mb-3" />
                <p className="text-dark-400">Request not found or you don&apos;t have access.</p>
            </div>
        );
    }

    const isPendingApproval = request.status === 'pending_manager_approval';
    const isAlreadyApproved = !!request.manager_approved_at;

    return (
        <div className="max-w-5xl mx-auto space-y-6">
            {/* Back */}
            <Button variant="ghost" size="sm" onClick={() => router.back()}>
                <ArrowLeft className="w-4 h-4 mr-2" />
                Back
            </Button>

            {/* Approval Panel */}
            {isPendingApproval && (
                <div className="p-5 bg-amber-500/10 border border-amber-500/30 rounded-2xl">
                    <h3 className="font-semibold text-amber-300 flex items-center gap-2 mb-4">
                        <Clock className="w-5 h-5" />
                        Pending Your Approval
                    </h3>

                    {/* Amount adjustment */}
                    <div className="mb-4">
                        <label className="block text-sm font-medium text-dark-300 mb-1.5">
                            <IndianRupee className="w-4 h-4 inline mr-1" />
                            Amount (₹)
                            <span className="text-xs text-dark-500 ml-2">You can adjust the amount before approving</span>
                        </label>
                        <div className="relative max-w-xs">
                            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-dark-400 font-semibold">₹</span>
                            <input
                                type="number"
                                min="0"
                                step="0.01"
                                value={adjustedAmount}
                                onChange={e => setAdjustedAmount(e.target.value)}
                                placeholder={request.amount?.toString() || '0.00'}
                                className="w-full pl-8 pr-4 py-2.5 bg-dark-800 border border-dark-600 rounded-lg text-dark-100 focus:outline-none focus:border-primary-500"
                            />
                        </div>
                        {request.amount && adjustedAmount && parseFloat(adjustedAmount) !== request.amount && (
                            <p className="text-xs text-amber-400 mt-1">
                                ⚠️ Original: ₹{request.amount.toLocaleString('en-IN')} → You&apos;re changing to ₹{parseFloat(adjustedAmount).toLocaleString('en-IN')}
                            </p>
                        )}
                    </div>

                    <div className="flex gap-3">
                        <Button
                            onClick={handleApprove}
                            isLoading={approving}
                            className="bg-green-600 hover:bg-green-700 text-white"
                        >
                            <CheckCircle2 className="w-4 h-4 mr-2" />
                            Approve & Forward to Accounts
                        </Button>
                        <Button
                            variant="secondary"
                            onClick={handleRequestMoreInfo}
                            isLoading={approving}
                        >
                            <MessageSquare className="w-4 h-4 mr-2" />
                            Request More Info
                        </Button>
                    </div>
                </div>
            )}

            {/* Already approved banner */}
            {isAlreadyApproved && (
                <div className="p-4 bg-green-500/10 border border-green-500/30 rounded-xl flex items-center gap-3">
                    <CheckCircle2 className="w-5 h-5 text-green-400 flex-shrink-0" />
                    <div>
                        <p className="text-sm font-medium text-green-300">Approved by you</p>
                        <p className="text-xs text-dark-500">
                            {format(new Date(request.manager_approved_at!), 'dd MMM yyyy, HH:mm')}
                            {request.manager_adjusted_amount && (
                                <span className="ml-2">· Adjusted amount: ₹{request.manager_adjusted_amount.toLocaleString('en-IN')}</span>
                            )}
                        </p>
                    </div>
                </div>
            )}

            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                {/* Left: Main content */}
                <div className="lg:col-span-2 space-y-6">
                    <Card padding="lg">
                        <h1 className="text-xl font-bold text-dark-50 mb-3">{request.title}</h1>
                        <div className="flex flex-wrap gap-2 mb-4">
                            <StatusBadge status={request.status} size="md" />
                            <PriorityBadge priority={request.priority} size="md" />
                        </div>
                        <p className="text-dark-300 whitespace-pre-wrap">{request.description}</p>
                    </Card>

                    {/* Attachments */}
                    {attachments.length > 0 && (
                        <Card padding="lg">
                            <CardHeader title="Attachments" />
                            <AttachmentList attachments={attachments} requestId={request.id} />
                        </Card>
                    )}

                    {/* Comments / Timeline tabs */}
                    <Card padding="lg">
                        <div className="flex gap-1 mb-4 bg-dark-800/50 p-1 rounded-lg">
                            <button
                                onClick={() => setActiveTab('comments')}
                                className={`flex-1 flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors ${activeTab === 'comments' ? 'bg-dark-700 text-dark-50' : 'text-dark-500 hover:text-dark-300'}`}
                            >
                                <MessageSquare className="w-4 h-4" />
                                Discussion ({comments.length})
                            </button>
                            <button
                                onClick={() => setActiveTab('timeline')}
                                className={`flex-1 flex items-center justify-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors ${activeTab === 'timeline' ? 'bg-dark-700 text-dark-50' : 'text-dark-500 hover:text-dark-300'}`}
                            >
                                <Clock className="w-4 h-4" />
                                Timeline ({events.length})
                            </button>
                        </div>
                        {activeTab === 'comments' ? (
                            <CommentThread
                                comments={comments.filter(c => !c.is_internal)}
                                onAddComment={handleAddComment}
                                canAddInternal={false}
                                requestCreatorId={request.created_by}
                            />
                        ) : (
                            <RequestTimeline events={events} />
                        )}
                    </Card>
                </div>

                {/* Right: Sidebar */}
                <div className="space-y-4">
                    <Card>
                        <h3 className="text-sm font-semibold text-dark-300 uppercase tracking-wider mb-4">Details</h3>
                        <dl className="space-y-3 text-sm">
                            <div className="flex justify-between">
                                <dt className="text-dark-500">Submitted by</dt>
                                <dd className="text-dark-200 font-medium">{request.created_by}</dd>
                            </div>
                            <div className="flex justify-between">
                                <dt className="text-dark-500">Category</dt>
                                <dd className="text-dark-200">{REQUEST_CATEGORY_LABELS[request.category as keyof typeof REQUEST_CATEGORY_LABELS]}</dd>
                            </div>
                            {request.amount && (
                                <div className="flex justify-between">
                                    <dt className="text-dark-500 flex items-center gap-1"><IndianRupee className="w-3.5 h-3.5" />Amount</dt>
                                    <dd className="text-green-400 font-semibold">₹{request.amount.toLocaleString('en-IN')}</dd>
                                </div>
                            )}
                            {request.manager_adjusted_amount && (
                                <div className="flex justify-between">
                                    <dt className="text-dark-500">Adjusted</dt>
                                    <dd className="text-amber-400 font-semibold">₹{request.manager_adjusted_amount.toLocaleString('en-IN')}</dd>
                                </div>
                            )}
                            <div className="flex justify-between">
                                <dt className="text-dark-500">Submitted</dt>
                                <dd className="text-dark-400 text-xs">{formatDistanceToNow(new Date(request.created_at), { addSuffix: true })}</dd>
                            </div>
                            {request.deadline && (
                                <div className="flex justify-between">
                                    <dt className="text-dark-500">Deadline</dt>
                                    <dd className="text-dark-200 text-xs">{format(new Date(request.deadline), 'dd MMM yyyy')}</dd>
                                </div>
                            )}
                        </dl>
                    </Card>
                </div>
            </div>
        </div>
    );
}

// ============================================================================
// Page Wrapper with Suspense
// ============================================================================

export default function ManagerRequestPage() {
    return (
        <Suspense fallback={<div className="flex justify-center py-20"><Spinner size="lg" /></div>}>
            <ManagerRequestDetailInner />
        </Suspense>
    );
}
