// ============================================================================
// Expense Claim Client Component
// Contains the actual UI logic (use client)
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
    claim_title: string;
    total_amount: number;
    status: string;
    submitted_at: string;
    employee?: {
        name: string;
        email: string;
    };
}

interface Comment {
    id: string;
    body: string;
    created_at: string;
    author_id: string;
    author?: {
        name: string;
        email: string;
    };
}

interface TimelineEvent {
    id: string;
    action: string;
    created_at: string;
}

export default function ExpenseClaimClient() {
    const params = useParams();
    const router = useRouter();
    const claimId = params.claimId as string;

    const [claim, setClaim] = useState<ExpenseClaim | null>(null);
    const [comments, setComments] = useState<Comment[]>([]);
    const [loading, setLoading] = useState(true);
    const [commentBody, setCommentBody] = useState('');
    const [isSubmitting, setIsSubmitting] = useState(false);

    useEffect(() => {
        if (claimId) {
            loadData();
        }
    }, [claimId]);

    async function loadData() {
        setLoading(true);
        const supabase = getSupabaseClient();

        // Load claim details
        const { data: claimData } = await supabase
            .from('expense_claims')
            .select(`
                *,
                employee:employees!employee_id (
                    name,
                    email
                )
            `)
            .eq('id', claimId)
            .single();

        if (claimData) {
            setClaim(claimData);
        }

        // Load comments
        const { data: commentsData } = await supabase
            .from('expense_claim_comments')
            .select('*')
            .eq('claim_id', claimId)
            .order('created_at', { ascending: true });

        setComments(commentsData || []);
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
            });

        if (!error) {
            setCommentBody('');
            loadData();
        }
        setIsSubmitting(false);
    }

    async function handleApprove() {
        const supabase = getSupabaseClient();

        const { error } = await supabase
            .from('expense_claims')
            .update({ status: 'approved' })
            .eq('id', claimId);

        if (!error) {
            loadData();
        }
    }

    async function handleReject() {
        const supabase = getSupabaseClient();

        const { error } = await supabase
            .from('expense_claims')
            .update({ status: 'rejected' })
            .eq('id', claimId);

        if (!error) {
            loadData();
        }
    }

    if (loading) {
        return <PageLoader message="Loading expense claim..." />;
    }

    if (!claim) {
        return (
            <div className="flex flex-col items-center justify-center py-16">
                <Receipt className="w-16 h-16 text-dark-500 mb-4" />
                <h2 className="text-xl font-semibold text-dark-300">Claim Not Found</h2>
                <p className="text-dark-500 mt-2">The expense claim could not be found.</p>
                <button
                    onClick={() => router.back()}
                    className="mt-4 px-4 py-2 bg-primary-600 text-white rounded-lg"
                >
                    Go Back
                </button>
            </div>
        );
    }

    return (
        <div className="space-y-6">
            {/* Header */}
            <div className="flex items-center gap-4">
                <button
                    onClick={() => router.back()}
                    className="p-2 hover:bg-dark-800 rounded-lg transition-colors"
                >
                    <ArrowLeft className="w-5 h-5 text-dark-400" />
                </button>
                <div className="flex-1">
                    <h1 className="text-2xl font-bold text-dark-100">{claim.claim_title}</h1>
                    <p className="text-dark-400 mt-1">
                        Submitted by {claim.employee?.name || 'Unknown'}
                    </p>
                </div>
                {claim.status === 'pending' && (
                    <div className="flex gap-2">
                        <button
                            onClick={handleApprove}
                            className="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg flex items-center gap-2"
                        >
                            <CheckCircle className="w-4 h-4" />
                            Approve
                        </button>
                        <button
                            onClick={handleReject}
                            className="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded-lg flex items-center gap-2"
                        >
                            <XCircle className="w-4 h-4" />
                            Reject
                        </button>
                    </div>
                )}
            </div>

            {/* Claim Details */}
            <Card className="p-6">
                <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
                    <div>
                        <p className="text-dark-500 text-sm">Amount</p>
                        <p className="text-xl font-bold text-dark-100">₹{claim.total_amount}</p>
                    </div>
                    <div>
                        <p className="text-dark-500 text-sm">Status</p>
                        <p className={`text-lg font-semibold ${claim.status === 'approved' ? 'text-green-400' :
                                claim.status === 'rejected' ? 'text-red-400' :
                                    'text-amber-400'
                            }`}>
                            {claim.status}
                        </p>
                    </div>
                    <div>
                        <p className="text-dark-500 text-sm">Submitted</p>
                        <p className="text-dark-200">{new Date(claim.submitted_at).toLocaleDateString()}</p>
                    </div>
                    <div>
                        <p className="text-dark-500 text-sm">Employee</p>
                        <p className="text-dark-200">{claim.employee?.email}</p>
                    </div>
                </div>
            </Card>

            {/* Comments Section */}
            <Card className="p-6">
                <h3 className="text-lg font-semibold text-dark-100 mb-4 flex items-center gap-2">
                    <MessageSquare className="w-5 h-5 text-primary-500" />
                    Comments
                </h3>

                <div className="space-y-4 mb-4 max-h-64 overflow-y-auto">
                    {comments.length === 0 && (
                        <p className="text-dark-500 text-center py-4">No comments yet</p>
                    )}
                    {comments.map((comment) => (
                        <div key={comment.id} className="bg-dark-900 p-3 rounded-lg">
                            <div className="flex items-center gap-2 mb-2">
                                <User className="w-4 h-4 text-dark-500" />
                                <span className="text-sm text-dark-400">{comment.author_id}</span>
                                <span className="text-xs text-dark-600">
                                    {new Date(comment.created_at).toLocaleString()}
                                </span>
                            </div>
                            <p className="text-dark-200">{comment.body}</p>
                        </div>
                    ))}
                </div>

                <div className="flex gap-2">
                    <input
                        type="text"
                        value={commentBody}
                        onChange={(e) => setCommentBody(e.target.value)}
                        placeholder="Add a comment..."
                        className="flex-1 bg-dark-900 border border-dark-700 rounded-lg px-4 py-2 text-dark-100 focus:outline-none focus:border-primary-500"
                        onKeyPress={(e) => e.key === 'Enter' && handleSendComment()}
                    />
                    <button
                        onClick={handleSendComment}
                        disabled={isSubmitting || !commentBody.trim()}
                        className="px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-lg flex items-center gap-2 disabled:opacity-50"
                    >
                        <Send className="w-4 h-4" />
                        Send
                    </button>
                </div>
            </Card>
        </div>
    );
}
