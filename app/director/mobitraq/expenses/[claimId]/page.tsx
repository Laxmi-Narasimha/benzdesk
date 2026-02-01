// ============================================================================
// Expense Claim Detail & Review Page
// Admin view for detailed expense review with chat, timeline, and attachments
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { PageLoader, Card } from '@/components/ui';
import {
    Receipt,
    ArrowLeft,
    CheckCircle,
    XCircle,
    Clock,
    Send,
    Paperclip,
    User,
    Calendar,
    DollarSign,
    MessageSquare,
    History,
    FileText,
} from 'lucide-react';

interface ExpenseClaim {
    id: string;
    employee_id: string;
    claim_date: string;
    total_amount: number;
    status: string;
    notes: string;
    created_at: string;
    reviewed_at: string | null;
    employee: {
        name: string;
        email: string;
        role: string;
    };
}

interface Comment {
    id: number;
    body: string;
    is_internal: boolean;
    created_at: string;
    author: {
        name: string;
        role: string;
    };
}

interface Event {
    id: number;
    event_type: string;
    note: string | null;
    created_at: string;
    actor: {
        name: string;
    };
}

interface Attachment {
    id: number;
    original_filename: string;
    size_bytes: number;
    uploaded_at: string;
    path: string;
}

export default function ExpenseDetailPage() {
    const params = useParams();
    const router = useRouter();
    const claimId = params?.claimId as string;

    const [claim, setClaim] = useState<ExpenseClaim | null>(null);
    const [comments, setComments] = useState<Comment[]>([]);
    const [events, setEvents] = useState<Event[]>([]);
    const [attachments, setAttachments] = useState<Attachment[]>([]);
    const [loading, setLoading] = useState(true);
    const [activeTab, setActiveTab] = useState<'chat' | 'timeline' | 'attachments'>('chat');

    const [commentBody, setCommentBody] = useState('');
    const [isSubmitting, setIsSubmitting] = useState(false);
    const [rejectionReason, setRejectionReason] = useState('');
    const [showRejectModal, setShowRejectModal] = useState(false);

    useEffect(() => {
        if (claimId) {
            loadData();
        }
    }, [claimId]);

    async function loadData() {
        setLoading(true);
        const supabase = getSupabaseClient();

        // Load claim details
        const { data: claimData, error: claimError } = await supabase
            .from('expense_claims')
            .select(`
        *,
        employee:employees!employee_id (
          name,
          email,
          role
        )
      `)
            .eq('id', claimId)
            .single();

        if (!claimError && claimData) {
            setClaim(claimData);
        }

        // Load comments
        const { data: commentsData } = await supabase
            .from('expense_claim_comments')
            .select(`
        *,
        author:employees!author_id (
          name,
          role
        )
      `)
            .eq('claim_id', claimId)
            .order('created_at', { ascending: true });

        if (commentsData) setComments(commentsData);

        // Load events
        const { data: eventsData } = await supabase
            .from('expense_claim_events')
            .select(`
        *,
        actor:employees!actor_id (
          name
        )
      `)
            .eq('claim_id', claimId)
            .order('created_at', { ascending: false });

        if (eventsData) setEvents(eventsData);

        // Load attachments
        const { data: attachmentsData } = await supabase
            .from('expense_claim_attachments')
            .select('*')
            .eq('claim_id', claimId)
            .order('uploaded_at', { ascending: false });

        if (attachmentsData) setAttachments(attachmentsData);

        setLoading(false);
    }

    async function handleSendComment() {
        if (!commentBody.trim()) return;

        setIsSubmitting(true);
        const supabase = getSupabaseClient();

        const { data: { user } } = await supabase.auth.getUser();

        const { error } = await supabase
            .from('expense_claim_comments')
            .insert({
                claim_id: claimId,
                author_id: user?.id,
                body: commentBody.trim(),
                is_internal: false,
            });

        if (!error) {
            setCommentBody('');
            await loadData();
        }

        setIsSubmitting(false);
    }

    async function handleApprove() {
        const supabase = getSupabaseClient();

        const { error } = await supabase
            .from('expense_claims')
            .update({
                status: 'approved',
                reviewed_at: new Date().toISOString(),
            })
            .eq('id', claimId);

        if (!error) {
            router.push('/director/mobitraq/expenses');
        }
    }

    async function handleReject() {
        const supabase = getSupabaseClient();

        const { error } = await supabase
            .from('expense_claims')
            .update({
                status: 'rejected',
                reviewed_at: new Date().toISOString(),
                rejection_reason: rejectionReason || 'No reason provided',
            })
            .eq('id', claimId);

        if (!error) {
            setShowRejectModal(false);
            router.push('/director/mobitraq/expenses');
        }
    }

    if (loading) {
        return <PageLoader message="Loading expense claim..." />;
    }

    if (!claim) {
        return (
            <div className="p-6">
                <Card className="p-8 text-center">
                    <p className="text-dark-400">Expense claim not found</p>
                </Card>
            </div>
        );
    }

    return (
        <div className="space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-4">
                    <button
                        onClick={() => router.back()}
                        className="p-2 hover:bg-dark-900 rounded-lg transition-colors"
                    >
                        <ArrowLeft className="w-5 h-5 text-dark-400" />
                    </button>
                    <div>
                        <h1 className="text-2xl font-bold text-dark-100">Expense Claim Review</h1>
                        <p className="text-dark-400 mt-1">Claim ID: {claim.id.slice(0, 8)}</p>
                    </div>
                </div>

                {/* Action Buttons */}
                {claim.status === 'submitted' && (
                    <div className="flex items-center gap-3">
                        <button
                            onClick={() => setShowRejectModal(true)}
                            className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg font-medium transition-colors flex items-center gap-2"
                        >
                            <XCircle className="w-4 h-4" />
                            Reject
                        </button>
                        <button
                            onClick={handleApprove}
                            className="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg font-medium transition-colors flex items-center gap-2"
                        >
                            <CheckCircle className="w-4 h-4" />
                            Approve
                        </button>
                    </div>
                )}
            </div>

            {/* Claim Summary Card */}
            <Card className="p-6">
                <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                    <div>
                        <div className="flex items-center gap-2 text-dark-400 text-sm mb-2">
                            <User className="w-4 h-4" />
                            Employee
                        </div>
                        <div className="text-dark-100 font-medium">{claim.employee.name}</div>
                        <div className="text-dark-500 text-sm">{claim.employee.role}</div>
                    </div>
                    <div>
                        <div className="flex items-center gap-2 text-dark-400 text-sm mb-2">
                            <Calendar className="w-4 h-4" />
                            Claim Date
                        </div>
                        <div className="text-dark-100 font-medium">
                            {new Date(claim.claim_date).toLocaleDateString()}
                        </div>
                    </div>
                    <div>
                        <div className="flex items-center gap-2 text-dark-400 text-sm mb-2">
                            <DollarSign className="w-4 h-4" />
                            Total Amount
                        </div>
                        <div className="text-dark-100 font-bold text-lg">
                            ₹{claim.total_amount.toLocaleString('en-IN')}
                        </div>
                    </div>
                    <div>
                        <div className="flex items-center gap-2 text-dark-400 text-sm mb-2">
                            <Clock className="w-4 h-4" />
                            Status
                        </div>
                        <div className={`inline-flex px-3 py-1 rounded-full text-sm font-medium ${claim.status === 'approved' ? 'bg-green-100 text-green-700' :
                            claim.status === 'rejected' ? 'bg-red-100 text-red-700' :
                                claim.status === 'in_review' ? 'bg-yellow-100 text-yellow-700' :
                                    'bg-blue-100 text-blue-700'
                            }`}>
                            {claim.status.toUpperCase()}
                        </div>
                    </div>
                </div>
                {claim.notes && (
                    <div className="mt-4 pt-4 border-t border-dark-700">
                        <div className="text-dark-400 text-sm mb-1">Notes</div>
                        <div className="text-dark-200">{claim.notes}</div>
                    </div>
                )}
            </Card>

            {/* Tabs */}
            <div className="flex gap-2 border-b border-dark-700">
                <button
                    onClick={() => setActiveTab('chat')}
                    className={`px-4 py-2 font-medium transition-colors ${activeTab === 'chat'
                        ? 'text-primary-500 border-b-2 border-primary-500'
                        : 'text-dark-400 hover:text-dark-200'
                        }`}
                >
                    <MessageSquare className="w-4 h-4 inline mr-2" />
                    Chat
                </button>
                <button
                    onClick={() => setActiveTab('timeline')}
                    className={`px-4 py-2 font-medium transition-colors ${activeTab === 'timeline'
                        ? 'text-primary-500 border-b-2 border-primary-500'
                        : 'text-dark-400 hover:text-dark-200'
                        }`}
                >
                    <History className="w-4 h-4 inline mr-2" />
                    Timeline
                </button>
                <button
                    onClick={() => setActiveTab('attachments')}
                    className={`px-4 py-2 font-medium transition-colors ${activeTab === 'attachments'
                        ? 'text-primary-500 border-b-2 border-primary-500'
                        : 'text-dark-400 hover:text-dark-200'
                        }`}
                >
                    <Paperclip className="w-4 h-4 inline mr-2" />
                    Attachments ({attachments.length})
                </button>
            </div>

            {/* Tab Content */}
            <Card className="p-6 min-h-[400px]">
                {activeTab === 'chat' && (
                    <div className="space-y-4">
                        {/* Messages */}
                        <div className="space-y-4 max-h-[500px] overflow-y-auto">
                            {comments.map((comment) => (
                                <div key={comment.id} className="flex gap-3">
                                    <div className="w-8 h-8 rounded-full bg-primary-500 flex items-center justify-center text-white text-sm font-medium flex-shrink-0">
                                        {comment.author.name.charAt(0)}
                                    </div>
                                    <div className="flex-1">
                                        <div className="flex items-baseline gap-2">
                                            <span className="font-medium text-dark-100">{comment.author.name}</span>
                                            <span className="text-xs text-dark-500">
                                                {new Date(comment.created_at).toLocaleString()}
                                            </span>
                                        </div>
                                        <div className="mt-1 text-dark-200 bg-dark-900 rounded-lg p-3">
                                            {comment.body}
                                        </div>
                                    </div>
                                </div>
                            ))}
                            {comments.length === 0 && (
                                <div className="text-center text-dark-500 py-8">
                                    No messages yet. Start a conversation!
                                </div>
                            )}
                        </div>

                        {/* Input */}
                        <div className="flex gap-3 pt-4 border-t border-dark-700">
                            <input
                                type="text"
                                placeholder="Type a message..."
                                value={commentBody}
                                onChange={(e) => setCommentBody(e.target.value)}
                                onKeyPress={(e) => e.key === 'Enter' && handleSendComment()}
                                className="flex-1 px-4 py-2 bg-dark-900 border border-dark-700 rounded-lg text-dark-100 placeholder-dark-500 focus:outline-none focus:border-primary-500"
                                disabled={isSubmitting}
                            />
                            <button
                                onClick={handleSendComment}
                                disabled={isSubmitting || !commentBody.trim()}
                                className="px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-lg transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                            >
                                <Send className="w-4 h-4" />
                            </button>
                        </div>
                    </div>
                )}

                {activeTab === 'timeline' && (
                    <div className="space-y-4">
                        {events.map((event) => (
                            <div key={event.id} className="flex gap-4">
                                <div className="flex flex-col items-center">
                                    <div className="w-3 h-3 rounded-full bg-primary-500" />
                                    <div className="w-0.5 h-full bg-dark-700" />
                                </div>
                                <div className="flex-1 pb-4">
                                    <div className="font-medium text-dark-100">
                                        {event.event_type.replace('_', ' ').toUpperCase()}
                                    </div>
                                    <div className="text-sm text-dark-400 mt-1">
                                        By {event.actor.name} • {new Date(event.created_at).toLocaleString()}
                                    </div>
                                    {event.note && (
                                        <div className="mt-2 text-dark-300 bg-dark-900 rounded px-3 py-2">
                                            {event.note}
                                        </div>
                                    )}
                                </div>
                            </div>
                        ))}
                        {events.length === 0 && (
                            <div className="text-center text-dark-500 py-8">
                                No activity yet
                            </div>
                        )}
                    </div>
                )}

                {activeTab === 'attachments' && (
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {attachments.map((attachment) => (
                            <div key={attachment.id} className="p-4 bg-dark-900 rounded-lg flex items-center gap-3">
                                <FileText className="w-8 h-8 text-primary-500 flex-shrink-0" />
                                <div className="flex-1 min-w-0">
                                    <div className="font-medium text-dark-100 truncate">
                                        {attachment.original_filename}
                                    </div>
                                    <div className="text-sm text-dark-400">
                                        {(attachment.size_bytes / 1024).toFixed(1)} KB • {new Date(attachment.uploaded_at).toLocaleDateString()}
                                    </div>
                                </div>
                            </div>
                        ))}
                        {attachments.length === 0 && (
                            <div className="col-span-2 text-center text-dark-500 py-8">
                                No attachments
                            </div>
                        )}
                    </div>
                )}
            </Card>

            {/* Reject Modal */}
            {showRejectModal && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
                    <Card className="p-6 max-w-md w-full mx-4">
                        <h3 className="text-lg font-bold text-dark-100 mb-4">Reject Expense Claim</h3>
                        <textarea
                            placeholder="Enter rejection reason..."
                            value={rejectionReason}
                            onChange={(e) => setRejectionReason(e.target.value)}
                            className="w-full px-4 py-2 bg-dark-900 border border-dark-700 rounded-lg text-dark-100 placeholder-dark-500 focus:outline-none focus:border-primary-500 min-h-[100px]"
                        />
                        <div className="flex gap-3 mt-4">
                            <button
                                onClick={() => setShowRejectModal(false)}
                                className="flex-1 px-4 py-2 bg-dark-700 hover:bg-dark-600 text-dark-100 rounded-lg transition-colors"
                            >
                                Cancel
                            </button>
                            <button
                                onClick={handleReject}
                                className="flex-1 px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg transition-colors"
                            >
                                Reject Claim
                            </button>
                        </div>
                    </Card>
                </div>
            )}
        </div>
    );
}
