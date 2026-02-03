'use client';

import React, { useEffect, useState } from 'react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import {
    Receipt,
    Calendar,
    ChevronLeft,
    ChevronRight,
    Search,
    Filter,
    Check,
    X,
    Clock,
    FileText,
    ChevronDown,
    ChevronUp,
    AlertTriangle,
    MessageCircle,
    Send
} from 'lucide-react';
import {
    Card,
    Button,
    Input,
    Select,
    Badge
} from '@/components/ui';

interface ExpenseClaimComment {
    id: number;
    claim_id: string;
    author_id: string;
    body: string;
    is_internal: boolean;
    created_at: string;
    author: {
        name: string;
        role: string;
    } | null;
}

interface ExpenseItem {
    id: string;
    category: string;
    amount: number;
    description: string | null;
    receipt_url: string | null;
    exceeds_limit: boolean;
}

interface ExpenseClaim {
    id: string;
    employee_id: string;
    total_amount: number;
    status: 'draft' | 'submitted' | 'in_review' | 'approved' | 'rejected';
    notes: string | null;
    claim_date: string;
    reviewed_at: string | null;
    created_at: string;
    rejection_reason: string | null;
    employees: {
        name: string;
        phone: string;
        band: string | null;
    } | null;
    expense_items?: ExpenseItem[];
}

// Category display mapping
const CATEGORY_INFO: Record<string, { icon: string; label: string }> = {
    local_conveyance: { icon: '🚗', label: 'Local Conveyance' },
    fuel: { icon: '⛽', label: 'Fuel' },
    toll: { icon: '🛣️', label: 'Toll / Parking' },
    outstation_travel: { icon: '✈️', label: 'Outstation Travel' },
    food_da: { icon: '🍽️', label: 'Food & DA' },
    food: { icon: '🍽️', label: 'Food & Meals' },
    accommodation: { icon: '🏨', label: 'Accommodation' },
    laundry: { icon: '👔', label: 'Laundry' },
    internet: { icon: '📶', label: 'Internet' },
    mobile: { icon: '📱', label: 'Mobile' },
    petty_cash: { icon: '💵', label: 'Petty Cash' },
    advance_request: { icon: '💳', label: 'Advance Request' },
    stationary: { icon: '✏️', label: 'Stationary' },
    medical: { icon: '🏥', label: 'Medical' },
    other: { icon: '📋', label: 'Other' },
};

// Band display names
const BAND_NAMES: Record<string, string> = {
    executive: 'Executive',
    senior_executive: 'Sr. Executive',
    assistant: 'Assistant',
    assistant_manager: 'Asst. Manager',
    manager: 'Manager',
    senior_manager: 'Sr. Manager',
    agm: 'AGM',
    gm: 'GM',
    plant_head: 'Plant Head',
    vp: 'VP',
    director: 'Director',
};

export default function ExpensesPage() {
    const [expenses, setExpenses] = useState<ExpenseClaim[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [statusFilter, setStatusFilter] = useState<'all' | 'submitted' | 'in_review' | 'approved' | 'rejected'>('all');
    const [currentPage, setCurrentPage] = useState(1);
    const [processingId, setProcessingId] = useState<string | null>(null);
    const [expandedId, setExpandedId] = useState<string | null>(null);
    const [rejectionReason, setRejectionReason] = useState('');
    const [showRejectModal, setShowRejectModal] = useState<string | null>(null);
    const [comments, setComments] = useState<Record<string, ExpenseClaimComment[]>>({});
    const [newComment, setNewComment] = useState('');
    const [currentUserId, setCurrentUserId] = useState<string | null>(null);
    const pageSize = 15;

    useEffect(() => {
        const getCurrentUser = async () => {
            const supabase = getSupabaseClient();
            const { data: { user } } = await supabase.auth.getUser();
            setCurrentUserId(user?.id || null);
        };
        getCurrentUser();
    }, []);

    useEffect(() => {
        if (expandedId) {
            fetchComments(expandedId);
        }
    }, [expandedId]);

    const fetchComments = async (claimId: string) => {
        try {
            const supabase = getSupabaseClient();
            const { data, error } = await supabase
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

            if (error) throw error;

            // Map the author array/object correctly
            const transformedComments = (data || []).map((c: any) => ({
                ...c,
                author: Array.isArray(c.author) ? c.author[0] : c.author
            }));

            setComments(prev => ({ ...prev, [claimId]: transformedComments }));
        } catch (error) {
            console.error('Error fetching comments:', error);
        }
    };

    const handlePostComment = async (claimId: string) => {
        if (!newComment.trim() || !currentUserId) return;

        try {
            const supabase = getSupabaseClient();
            const { error } = await supabase
                .from('expense_claim_comments')
                .insert({
                    claim_id: claimId,
                    author_id: currentUserId,
                    body: newComment.trim(),
                    is_internal: false
                });

            if (error) throw error;

            setNewComment('');
            fetchComments(claimId); // Refresh comments
        } catch (error) {
            console.error('Error posting comment:', error);
            alert('Failed to post comment');
        }
    };

    useEffect(() => {
        fetchExpenses();

        // Subscribe to real-time updates for live sync
        const supabase = getSupabaseClient();
        const channel = supabase
            .channel('expense_claims_changes')
            .on(
                'postgres_changes',
                {
                    event: '*', // Listen to all events (INSERT, UPDATE, DELETE)
                    schema: 'public',
                    table: 'expense_claims',
                },
                (payload) => {
                    console.log('Real-time expense update:', payload);
                    // Refresh the list when any change occurs
                    fetchExpenses();
                }
            )
            .on(
                'postgres_changes',
                {
                    event: 'INSERT',
                    schema: 'public',
                    table: 'expense_claim_comments',
                },
                (payload) => {
                    console.log('New comment received:', payload);
                    // If expanded expense matches, refresh comments
                    if (expandedId && payload.new && (payload.new as any).claim_id === expandedId) {
                        fetchComments(expandedId);
                    }
                }
            )
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [statusFilter, expandedId]);

    const fetchExpenses = async () => {
        setIsLoading(true);
        try {
            const supabase = getSupabaseClient();
            let query = supabase
                .from('expense_claims')
                .select(`
                    id,
                    employee_id,
                    total_amount,
                    status,
                    notes,
                    claim_date,
                    reviewed_at,
                    created_at,
                    rejection_reason,
                    employees!employee_id (
                        name,
                        phone,
                        band
                    ),
                    expense_items (
                        id,
                        category,
                        amount,
                        description,
                        exceeds_limit
                    )
                `)
                .neq('status', 'draft')
                .order('created_at', { ascending: false });

            if (statusFilter !== 'all') {
                query = query.eq('status', statusFilter);
            }

            const { data, error } = await query;

            if (error) throw error;

            // Transform data
            const transformedExpenses: ExpenseClaim[] = (data || []).map((e: any) => ({
                ...e,
                employees: Array.isArray(e.employees) ? e.employees[0] : e.employees,
                expense_items: e.expense_items || []
            }));

            setExpenses(transformedExpenses);
        } catch (error) {
            console.error('Error fetching expenses:', error);
        } finally {
            setIsLoading(false);
        }
    };

    const handleApprove = async (id: string, e?: React.MouseEvent) => {
        e?.stopPropagation();
        setProcessingId(id);
        try {
            const supabase = getSupabaseClient();
            const { error } = await supabase
                .from('expense_claims')
                .update({
                    status: 'approved',
                    reviewed_at: new Date().toISOString()
                })
                .eq('id', id);

            if (error) throw error;

            setExpenses(prev => prev.map(exp =>
                exp.id === id ? { ...exp, status: 'approved' as const, reviewed_at: new Date().toISOString() } : exp
            ));
        } catch (error) {
            console.error('Error approving expense:', error);
        } finally {
            setProcessingId(null);
        }
    };

    const handleReject = async (id: string) => {
        if (!rejectionReason.trim()) {
            alert('Please provide a rejection reason');
            return;
        }

        setProcessingId(id);
        try {
            const supabase = getSupabaseClient();
            const { error } = await supabase
                .from('expense_claims')
                .update({
                    status: 'rejected',
                    reviewed_at: new Date().toISOString(),
                    rejection_reason: rejectionReason
                })
                .eq('id', id);

            if (error) throw error;

            setExpenses(prev => prev.map(exp =>
                exp.id === id ? {
                    ...exp,
                    status: 'rejected' as const,
                    reviewed_at: new Date().toISOString(),
                    rejection_reason: rejectionReason
                } : exp
            ));
            setShowRejectModal(null);
            setRejectionReason('');
        } catch (error) {
            console.error('Error rejecting expense:', error);
        } finally {
            setProcessingId(null);
        }
    };

    const openRejectModal = (id: string, e?: React.MouseEvent) => {
        e?.stopPropagation();
        setShowRejectModal(id);
    };

    const formatDate = (dateStr: string) => {
        return new Date(dateStr).toLocaleDateString('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric',
        });
    };

    const formatCurrency = (amount: number) => {
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            maximumFractionDigits: 0,
        }).format(amount);
    };

    const getCategoryInfo = (category: string) => {
        return CATEGORY_INFO[category] || { icon: '📋', label: category };
    };

    const getBandName = (band: string | null | undefined) => {
        if (!band) return 'Executive';
        return BAND_NAMES[band] || band;
    };

    const getStatusBadge = (status: string) => {
        switch (status) {
            case 'submitted':
                return <Badge color="yellow" dot>Pending Review</Badge>;
            case 'in_review':
                return <Badge color="blue" dot>In Review</Badge>;
            case 'approved':
                return <Badge color="green" dot>Approved</Badge>;
            case 'rejected':
                return <Badge color="red" dot>Rejected</Badge>;
            default:
                return <Badge color="gray">{status}</Badge>;
        }
    };

    // Filter by search term
    const filteredExpenses = expenses.filter(expense => {
        if (!searchTerm) return true;
        const empName = expense.employees?.name?.toLowerCase() || '';
        const empPhone = expense.employees?.phone?.toLowerCase() || '';
        const notes = expense.notes?.toLowerCase() || '';
        return empName.includes(searchTerm.toLowerCase()) ||
            empPhone.includes(searchTerm.toLowerCase()) ||
            notes.includes(searchTerm.toLowerCase());
    });

    // Calculate stats
    const stats = {
        pending: expenses.filter(e => e.status === 'submitted' || e.status === 'in_review').length,
        pendingAmount: expenses.filter(e => e.status === 'submitted' || e.status === 'in_review').reduce((sum, e) => sum + e.total_amount, 0),
        approved: expenses.filter(e => e.status === 'approved').length,
        approvedAmount: expenses.filter(e => e.status === 'approved').reduce((sum, e) => sum + e.total_amount, 0),
        rejected: expenses.filter(e => e.status === 'rejected').length,
        exceedsLimit: expenses.filter(e => e.expense_items?.some(i => i.exceeds_limit)).length,
    };

    // Pagination
    const totalPages = Math.ceil(filteredExpenses.length / pageSize);
    const paginatedExpenses = filteredExpenses.slice(
        (currentPage - 1) * pageSize,
        currentPage * pageSize
    );

    if (isLoading) {
        return (
            <div className="flex items-center justify-center min-h-[400px]">
                <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-500"></div>
            </div>
        );
    }

    return (
        <div className="space-y-6">
            {/* Header */}
            <div>
                <h1 className="text-2xl font-bold text-dark-50">Field Expense Approval</h1>
                <p className="text-dark-400">Review and approve expense claims from field employees</p>
            </div>

            {/* Stats Cards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <Card className="border-l-4 border-yellow-500" padding="sm">
                    <div className="flex items-center gap-3">
                        <Clock className="w-8 h-8 text-yellow-500" />
                        <div>
                            <p className="text-sm text-dark-400">Pending Review</p>
                            <p className="text-xl font-bold text-dark-50">{stats.pending}</p>
                            <p className="text-xs text-yellow-500">{formatCurrency(stats.pendingAmount)}</p>
                        </div>
                    </div>
                </Card>
                <Card className="border-l-4 border-green-500" padding="sm">
                    <div className="flex items-center gap-3">
                        <Check className="w-8 h-8 text-green-500" />
                        <div>
                            <p className="text-sm text-dark-400">Approved</p>
                            <p className="text-xl font-bold text-dark-50">{stats.approved}</p>
                            <p className="text-xs text-green-500">{formatCurrency(stats.approvedAmount)}</p>
                        </div>
                    </div>
                </Card>
                <Card className="border-l-4 border-red-500" padding="sm">
                    <div className="flex items-center gap-3">
                        <X className="w-8 h-8 text-red-500" />
                        <div>
                            <p className="text-sm text-dark-400">Rejected</p>
                            <p className="text-xl font-bold text-dark-50">{stats.rejected}</p>
                        </div>
                    </div>
                </Card>
                {stats.exceedsLimit > 0 && (
                    <Card className="border-l-4 border-orange-500" padding="sm">
                        <div className="flex items-center gap-3">
                            <AlertTriangle className="w-8 h-8 text-orange-500" />
                            <div>
                                <p className="text-sm text-dark-400">Exceeds Limit</p>
                                <p className="text-xl font-bold text-dark-50">{stats.exceedsLimit}</p>
                                <p className="text-xs text-orange-500">Needs skip-level approval</p>
                            </div>
                        </div>
                    </Card>
                )}
            </div>

            {/* Filters */}
            <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
                <div className="w-full sm:w-72">
                    <Input
                        placeholder="Search by employee name..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        leftIcon={<Search className="w-4 h-4" />}
                    />
                </div>

                <div className="flex items-center gap-2">
                    <Filter className="w-4 h-4 text-dark-400" />
                    <Select
                        value={statusFilter}
                        onChange={(e) => setStatusFilter(e.target.value as typeof statusFilter)}
                        options={[
                            { value: 'all', label: 'All Status' },
                            { value: 'submitted', label: 'Pending Review' },
                            { value: 'in_review', label: 'In Review' },
                            { value: 'approved', label: 'Approved' },
                            { value: 'rejected', label: 'Rejected' },
                        ]}
                    />
                </div>
            </div>

            {/* Expense Claims List */}
            <div className="space-y-4">
                {paginatedExpenses.length === 0 ? (
                    <Card className="p-8 text-center text-dark-400">
                        <Receipt className="w-12 h-12 mx-auto text-dark-600 mb-3" />
                        <p>No expense claims found</p>
                    </Card>
                ) : (
                    paginatedExpenses.map((expense) => {
                        const isExpanded = expandedId === expense.id;
                        const hasExceedsLimit = expense.expense_items?.some(i => i.exceeds_limit);

                        return (
                            <Card
                                key={expense.id}
                                hover
                                onClick={() => setExpandedId(isExpanded ? null : expense.id)}
                                className={`transition-all ${hasExceedsLimit ? 'border-orange-500/50 bg-orange-500/10' : ''}`}
                            >
                                {/* Main Row */}
                                <div className="flex items-center gap-4">
                                    {/* Employee Info */}
                                    <div className="flex items-center gap-3 flex-1">
                                        <div className="w-10 h-10 rounded-full bg-primary-500/10 flex items-center justify-center">
                                            <span className="text-primary-400 font-semibold">
                                                {expense.employees?.name?.charAt(0).toUpperCase() || '?'}
                                            </span>
                                        </div>
                                        <div>
                                            <div className="font-medium text-dark-50 flex items-center gap-2">
                                                {expense.employees?.name || 'Unknown'}
                                                <Badge variant="outline" size="sm">
                                                    {getBandName(expense.employees?.band)}
                                                </Badge>
                                            </div>
                                            <div className="text-xs text-dark-400 flex items-center gap-2">
                                                <Calendar className="w-3 h-3" />
                                                {formatDate(expense.claim_date)}
                                            </div>
                                        </div>
                                    </div>

                                    {/* Amount */}
                                    <div className="text-right">
                                        <div className="font-bold text-lg text-dark-50">
                                            {formatCurrency(expense.total_amount)}
                                        </div>
                                        <div className="text-xs text-dark-400">
                                            {expense.expense_items?.length || 0} items
                                        </div>
                                    </div>

                                    {/* Status Badge */}
                                    <div>
                                        {getStatusBadge(expense.status)}
                                    </div>

                                    {/* Exceeds Limit Warning */}
                                    {hasExceedsLimit && (
                                        <Badge variant="subtle" color="orange" className="gap-1">
                                            <AlertTriangle className="w-3 h-3" />
                                            Over Limit
                                        </Badge>
                                    )}

                                    {/* Actions */}
                                    {(expense.status === 'submitted' || expense.status === 'in_review') && (
                                        <div className="flex items-center gap-2">
                                            <Button
                                                size="sm"
                                                variant="outline"
                                                className="text-green-500 hover:text-green-400 border-green-500/30 hover:bg-green-500/10"
                                                onClick={(e) => handleApprove(expense.id, e)}
                                                disabled={processingId === expense.id}
                                                title="Approve"
                                            >
                                                <Check className="w-4 h-4" />
                                            </Button>
                                            <Button
                                                size="sm"
                                                variant="outline"
                                                className="text-red-500 hover:text-red-400 border-red-500/30 hover:bg-red-500/10"
                                                onClick={(e) => openRejectModal(expense.id, e)}
                                                disabled={processingId === expense.id}
                                                title="Reject"
                                            >
                                                <X className="w-4 h-4" />
                                            </Button>
                                        </div>
                                    )}

                                    {/* Expand Button */}
                                    <div className="p-2 text-dark-400">
                                        {isExpanded ? <ChevronUp className="w-5 h-5" /> : <ChevronDown className="w-5 h-5" />}
                                    </div>
                                </div>

                                {/* Expanded Details */}
                                {isExpanded && (
                                    <div className="mt-4 pt-4 border-t border-dark-700/50" onClick={e => e.stopPropagation()}>
                                        {/* Notes */}
                                        {expense.notes && (
                                            <div className="mb-4 p-3 bg-dark-900/50 rounded-lg border border-dark-700/50">
                                                <div className="text-xs text-dark-400 mb-1">Notes</div>
                                                <div className="text-sm text-dark-200">{expense.notes}</div>
                                            </div>
                                        )}

                                        {/* Rejection Reason */}
                                        {expense.rejection_reason && (
                                            <div className="mb-4 p-3 bg-red-500/10 rounded-lg border border-red-500/30">
                                                <div className="text-xs text-red-400 mb-1">Rejection Reason</div>
                                                <div className="text-sm text-red-300">{expense.rejection_reason}</div>
                                            </div>
                                        )}

                                        {/* Expense Items */}
                                        <div className="text-xs text-dark-400 uppercase font-medium mb-2">Expense Items</div>
                                        <div className="space-y-2">
                                            {expense.expense_items?.map((item) => {
                                                const catInfo = getCategoryInfo(item.category);
                                                return (
                                                    <div
                                                        key={item.id}
                                                        className={`flex items-center gap-4 p-3 bg-dark-900/50 rounded-lg border ${item.exceeds_limit ? 'border-orange-500/50' : 'border-dark-700/50'
                                                            }`}
                                                    >
                                                        <span className="text-xl">{catInfo.icon}</span>
                                                        <div className="flex-1">
                                                            <div className="font-medium text-dark-200 flex items-center gap-2">
                                                                {catInfo.label}
                                                                {item.exceeds_limit && (
                                                                    <Badge variant="subtle" color="orange" size="sm">Exceeds Limit</Badge>
                                                                )}
                                                            </div>
                                                            {item.description && (
                                                                <div className="text-xs text-dark-400">{item.description}</div>
                                                            )}
                                                        </div>
                                                        <div className="font-semibold text-dark-200">
                                                            {formatCurrency(item.amount)}
                                                        </div>
                                                        {item.receipt_url && (
                                                            <a
                                                                href={item.receipt_url}
                                                                target="_blank"
                                                                rel="noopener noreferrer"
                                                                className="p-2 text-primary-400 hover:bg-primary-500/10 rounded-lg transition-colors"
                                                            >
                                                                <FileText className="w-4 h-4" />
                                                            </a>
                                                        )}
                                                    </div>
                                                );
                                            })}
                                        </div>

                                        {/* Discussion / Chat Section */}
                                        <div className="mt-6 border-t border-dark-700/50 pt-4">
                                            <h4 className="text-sm font-semibold text-dark-200 mb-4 flex items-center gap-2">
                                                <MessageCircle className="w-4 h-4" />
                                                Discussion
                                            </h4>

                                            <div className="space-y-4 mb-4">
                                                {(comments[expense.id] || []).length === 0 ? (
                                                    <p className="text-xs text-dark-500 italic">No comments yet.</p>
                                                ) : (
                                                    (comments[expense.id] || []).map((comment) => (
                                                        <div key={comment.id} className={`flex gap-3 ${comment.author_id === currentUserId ? 'flex-row-reverse' : ''}`}>
                                                            <div className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${comment.author_id === currentUserId
                                                                ? 'bg-primary-500/20 text-primary-400'
                                                                : 'bg-dark-700 text-dark-300'
                                                                }`}>
                                                                {comment.author?.name?.charAt(0).toUpperCase() || '?'}
                                                            </div>
                                                            <div className={`max-w-[80%] rounded-lg p-3 text-sm ${comment.author_id === currentUserId
                                                                ? 'bg-primary-500/10 text-dark-100 rounded-tr-none border border-primary-500/20'
                                                                : 'bg-dark-800 border border-dark-700 rounded-tl-none text-dark-300'
                                                                }`}>
                                                                <div className="flex items-center gap-2 mb-1">
                                                                    <span className="font-semibold text-xs">
                                                                        {comment.author?.name || 'Unknown'}
                                                                    </span>
                                                                    <span className="text-dark-500 text-[10px]">
                                                                        {new Date(comment.created_at).toLocaleString()}
                                                                    </span>
                                                                </div>
                                                                <p>{comment.body}</p>
                                                            </div>
                                                        </div>
                                                    ))
                                                )}
                                            </div>

                                            <div className="flex gap-2">
                                                <Input
                                                    type="text"
                                                    value={newComment}
                                                    onChange={(e) => setNewComment(e.target.value)}
                                                    placeholder="Write a comment..."
                                                    onKeyDown={(e) => {
                                                        if (e.key === 'Enter' && !e.shiftKey) {
                                                            e.preventDefault();
                                                            handlePostComment(expense.id);
                                                        }
                                                    }}
                                                />
                                                <Button
                                                    onClick={() => handlePostComment(expense.id)}
                                                    disabled={!newComment.trim()}
                                                >
                                                    <Send className="w-4 h-4" />
                                                </Button>
                                            </div>
                                        </div>
                                    </div>
                                )}
                            </Card>
                        );
                    })
                )}
            </div>

            {/* Pagination controls would go here (simplified for refactor) */}
            {
                totalPages > 1 && (
                    <div className="flex items-center justify-between">
                        <p className="text-sm text-dark-500">
                            Showing {(currentPage - 1) * pageSize + 1} to {Math.min(currentPage * pageSize, filteredExpenses.length)} of {filteredExpenses.length}
                        </p>
                        <div className="flex items-center gap-2">
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                                disabled={currentPage === 1}
                            >
                                <ChevronLeft className="w-4 h-4" />
                            </Button>
                            <span className="text-sm text-dark-400">
                                Page {currentPage} of {totalPages}
                            </span>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
                                disabled={currentPage === totalPages}
                            >
                                <ChevronRight className="w-4 h-4" />
                            </Button>
                        </div>
                    </div>
                )
            }

            {/* Rejection Modal */}
            {showRejectModal && (
                <div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50">
                    <Card className="w-full max-w-md mx-4">
                        <div className="p-6">
                            <h3 className="text-lg font-bold text-dark-50 mb-4">Reject Expense Claim</h3>
                            <p className="text-sm text-dark-400 mb-4">
                                Please provide a reason for rejecting this expense claim.
                            </p>
                            <textarea
                                value={rejectionReason}
                                onChange={(e) => setRejectionReason(e.target.value)}
                                placeholder="Enter rejection reason..."
                                className="w-full p-3 bg-dark-900 border border-dark-700 rounded-lg text-dark-50 focus:ring-2 focus:ring-red-500 focus:border-transparent outline-none transition-all"
                                rows={3}
                            />
                            <div className="flex gap-3 mt-4">
                                <Button
                                    variant="outline"
                                    onClick={() => {
                                        setShowRejectModal(null);
                                        setRejectionReason('');
                                    }}
                                    className="flex-1"
                                >
                                    Cancel
                                </Button>
                                <Button
                                    variant="primary" // Assuming primary assumes danger context if red styled or just primary
                                    onClick={() => handleReject(showRejectModal)}
                                    disabled={!rejectionReason.trim() || processingId === showRejectModal}
                                    className="flex-1 bg-red-600 hover:bg-red-700 text-white"
                                >
                                    Reject
                                </Button>
                            </div>
                        </div>
                    </Card>
                </div>
            )}
        </div>
    );
}
