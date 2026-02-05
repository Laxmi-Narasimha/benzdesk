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
    AlertTriangle,
    MessageCircle,
    Send,
    Eye,
    MoreHorizontal
} from 'lucide-react';
import {
    Card,
    Button,
    Input,
    Select,
    Badge,
    Drawer,
    StatCard
} from '@/components/ui';

// ... (Types remain the same as before, copying them for completeness)
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
    const [selectedClaim, setSelectedClaim] = useState<ExpenseClaim | null>(null);
    const [rejectionReason, setRejectionReason] = useState('');
    const [showRejectInput, setShowRejectInput] = useState(false);
    const [comments, setComments] = useState<ExpenseClaimComment[]>([]);
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
        if (selectedClaim) {
            fetchComments(selectedClaim.id);
            // Reset reject state when opening new claim
            setShowRejectInput(false);
            setRejectionReason('');
        }
    }, [selectedClaim]);

    const fetchComments = async (claimId: string) => {
        try {
            const supabase = getSupabaseClient();
            const { data, error } = await supabase
                .from('expense_claim_comments')
                .select(`
                    *,
                    author:employees!author_id (name, role)
                `)
                .eq('claim_id', claimId)
                .order('created_at', { ascending: true });

            if (error) throw error;

            const transformedComments = (data || []).map((c: any) => ({
                ...c,
                author: Array.isArray(c.author) ? c.author[0] : c.author
            }));

            setComments(transformedComments);
        } catch (error) {
            console.error('Error fetching comments:', error);
        }
    };

    const handlePostComment = async () => {
        if (!newComment.trim() || !currentUserId || !selectedClaim) return;

        try {
            const supabase = getSupabaseClient();
            const { error } = await supabase
                .from('expense_claim_comments')
                .insert({
                    claim_id: selectedClaim.id,
                    author_id: currentUserId,
                    body: newComment.trim(),
                    is_internal: false
                });

            if (error) throw error;

            setNewComment('');
            fetchComments(selectedClaim.id);
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
            .channel('expense_claims_changes_v2')
            .on(
                'postgres_changes',
                { event: '*', schema: 'public', table: 'expense_claims' },
                () => fetchExpenses()
            )
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [statusFilter]);

    const fetchExpenses = async () => {
        setIsLoading(true);
        try {
            const supabase = getSupabaseClient();
            let query = supabase
                .from('expense_claims')
                .select(`
                    id, employee_id, total_amount, status, notes, claim_date, reviewed_at, created_at, rejection_reason,
                    employees!employee_id (name, phone, band),
                    expense_items (id, category, amount, description, exceeds_limit, receipt_url:receipt_path)
                `)
                .neq('status', 'draft')
                .order('created_at', { ascending: false });

            if (statusFilter !== 'all') {
                query = query.eq('status', statusFilter);
            }

            const { data, error } = await query;
            if (error) throw error;

            const transformedExpenses: ExpenseClaim[] = (data || []).map((e: any) => ({
                ...e,
                employees: Array.isArray(e.employees) ? e.employees[0] : e.employees,
                expense_items: e.expense_items || []
            }));

            setExpenses(transformedExpenses);
        } catch (error: any) {
            console.error('Error fetching expenses:', error.message || error);
        } finally {
            setIsLoading(false);
        }
    };

    const handleApprove = async () => {
        if (!selectedClaim) return;
        setProcessingId(selectedClaim.id);
        try {
            const supabase = getSupabaseClient();
            const { error } = await supabase
                .from('expense_claims')
                .update({
                    status: 'approved',
                    reviewed_at: new Date().toISOString()
                })
                .eq('id', selectedClaim.id);

            if (error) throw error;

            // Update local state and close drawer
            setExpenses(prev => prev.map(exp =>
                exp.id === selectedClaim.id ? { ...exp, status: 'approved' as const, reviewed_at: new Date().toISOString() } : exp
            ));
            setSelectedClaim(null);
        } catch (error) {
            console.error('Error approving expense:', error);
        } finally {
            setProcessingId(null);
        }
    };

    const handleReject = async () => {
        if (!selectedClaim || !rejectionReason.trim()) return;

        setProcessingId(selectedClaim.id);
        try {
            const supabase = getSupabaseClient();
            const { error } = await supabase
                .from('expense_claims')
                .update({
                    status: 'rejected',
                    reviewed_at: new Date().toISOString(),
                    rejection_reason: rejectionReason
                })
                .eq('id', selectedClaim.id);

            if (error) throw error;

            setExpenses(prev => prev.map(exp =>
                exp.id === selectedClaim.id ? {
                    ...exp,
                    status: 'rejected' as const,
                    reviewed_at: new Date().toISOString(),
                    rejection_reason: rejectionReason
                } : exp
            ));
            setSelectedClaim(null);
        } catch (error) {
            console.error('Error rejecting expense:', error);
        } finally {
            setProcessingId(null);
        }
    };

    const formatDate = (dateStr: string) => {
        return new Date(dateStr).toLocaleDateString('en-IN', {
            day: '2-digit', month: 'short', year: 'numeric'
        });
    };

    const formatCurrency = (amount: number) => {
        return new Intl.NumberFormat('en-IN', {
            style: 'currency', currency: 'INR', maximumFractionDigits: 0
        }).format(amount);
    };

    const getCategoryInfo = (category: string) => {
        return CATEGORY_INFO[category] || { icon: '📋', label: category };
    };

    const getStatusBadge = (status: string) => {
        switch (status) {
            case 'submitted': return <Badge color="yellow" dot>Pending Review</Badge>;
            case 'in_review': return <Badge color="blue" dot>In Review</Badge>;
            case 'approved': return <Badge color="green" dot>Approved</Badge>;
            case 'rejected': return <Badge color="red" dot>Rejected</Badge>;
            default: return <Badge color="gray">{status}</Badge>;
        }
    };

    // Filter by search term
    const filteredExpenses = expenses.filter(expense => {
        if (!searchTerm) return true;
        const empName = expense.employees?.name?.toLowerCase() || '';
        return empName.includes(searchTerm.toLowerCase());
    });

    // Stats
    const stats = {
        pending: expenses.filter(e => e.status === 'submitted' || e.status === 'in_review').length,
        approvedAmount: expenses.filter(e => e.status === 'approved').reduce((sum, e) => sum + e.total_amount, 0),
        rejected: expenses.filter(e => e.status === 'rejected').length,
        exceedsLimit: expenses.filter(e => e.expense_items?.some(i => i.exceeds_limit)).length,
    };

    // Pagination
    const totalPages = Math.ceil(filteredExpenses.length / pageSize);
    const paginatedExpenses = filteredExpenses.slice((currentPage - 1) * pageSize, currentPage * pageSize);

    if (isLoading) {
        return (
            <div className="flex items-center justify-center min-h-[400px]">
                <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-500"></div>
            </div>
        );
    }

    return (
        <div className="space-y-6">
            {/* Header Area */}
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900 dark:text-white">Field Expenses</h1>
                    <p className="text-gray-500 dark:text-gray-400">Manage and approve reimbursement claims</p>
                </div>
            </div>

            {/* Stats Overview Using New StatCards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <StatCard
                    title="Pending Review"
                    value={stats.pending}
                    icon={<Clock />}
                    color="warning"
                />
                <StatCard
                    title="Approved Amount"
                    value={formatCurrency(stats.approvedAmount)}
                    icon={<Check />}
                    color="success"
                />
                <StatCard
                    title="Rejected Claims"
                    value={stats.rejected}
                    icon={<X />}
                    color="danger"
                />
                <StatCard
                    title="Policy Violations"
                    value={stats.exceedsLimit}
                    icon={<AlertTriangle />}
                    color="danger"
                    trend={{ value: 0, label: 'needs review', direction: 'neutral' }}
                />
            </div>

            {/* Main Content Area */}
            <Card className="min-h-[500px]" padding="none">
                {/* Filters Bar */}
                <div className="p-4 border-b border-gray-200 dark:border-dark-700 flex flex-col sm:flex-row gap-4 justify-between items-center bg-gray-50/50 dark:bg-dark-800/50">
                    <div className="w-full sm:w-72">
                        <Input
                            placeholder="Search employee..."
                            value={searchTerm}
                            onChange={(e) => setSearchTerm(e.target.value)}
                            leftIcon={<Search className="w-4 h-4" />}
                        />
                    </div>
                    <div className="flex items-center gap-2">
                        <Select
                            value={statusFilter}
                            onChange={(e) => setStatusFilter(e.target.value as any)}
                            options={[
                                { value: 'all', label: 'All Status' },
                                { value: 'submitted', label: 'Pending' },
                                { value: 'approved', label: 'Approved' },
                                { value: 'rejected', label: 'Rejected' },
                            ]}
                        />
                    </div>
                </div>

                {/* Table View */}
                <div className="overflow-x-auto">
                    <table className="w-full text-sm text-left">
                        <thead className="bg-gray-50 text-slate-600 uppercase font-semibold border-b border-gray-200">
                            <tr>
                                <th className="px-6 py-4 text-xs tracking-wider">Employee</th>
                                <th className="px-6 py-4 text-xs tracking-wider">Claim Date</th>
                                <th className="px-6 py-4 text-xs tracking-wider">Items</th>
                                <th className="px-6 py-4 text-right text-xs tracking-wider">Amount</th>
                                <th className="px-6 py-4 text-xs tracking-wider">Status</th>
                                <th className="px-6 py-4 w-10"></th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-gray-100">
                            {paginatedExpenses.length === 0 ? (
                                <tr>
                                    <td colSpan={6} className="px-6 py-12 text-center text-gray-500">
                                        <div className="flex flex-col items-center gap-2">
                                            <Receipt className="w-8 h-8 opacity-40" />
                                            <p>No claims found matching your filters</p>
                                        </div>
                                    </td>
                                </tr>
                            ) : (
                                paginatedExpenses.map((expense) => (
                                    <tr
                                        key={expense.id}
                                        onClick={() => setSelectedClaim(expense)}
                                        className="hover:bg-gray-50 cursor-pointer transition-colors group"
                                    >
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-3">
                                                <div className="w-8 h-8 rounded-full bg-primary-100 flex items-center justify-center text-primary-700 font-bold text-xs ring-2 ring-white">
                                                    {expense.employees?.name?.charAt(0).toUpperCase()}
                                                </div>
                                                <div>
                                                    <div className="font-semibold text-slate-900">{expense.employees?.name}</div>
                                                    <div className="text-xs text-slate-500 font-medium">{expense.employees?.phone}</div>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4 text-slate-600 font-medium">
                                            {formatDate(expense.claim_date)}
                                        </td>
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-1">
                                                <Badge variant="subtle" color="gray" size="sm">
                                                    {expense.expense_items?.length} Items
                                                </Badge>
                                                {expense.expense_items?.some(i => i.exceeds_limit) && (
                                                    <AlertTriangle className="w-4 h-4 text-amber-500" />
                                                )}
                                            </div>
                                        </td>
                                        <td className="px-6 py-4 text-right font-bold text-slate-900">
                                            {formatCurrency(expense.total_amount)}
                                        </td>
                                        <td className="px-6 py-4">
                                            {getStatusBadge(expense.status)}
                                        </td>
                                        <td className="px-6 py-4 text-gray-400">
                                            <Eye className="w-4 h-4 opacity-0 group-hover:opacity-100 transition-opacity" />
                                        </td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>

                {/* Pagination */}
                {totalPages > 1 && (
                    <div className="p-4 border-t border-gray-200 dark:border-dark-700 flex items-center justify-between">
                        <span className="text-sm text-gray-500">
                            Page {currentPage} of {totalPages}
                        </span>
                        <div className="flex gap-2">
                            <Button
                                variant="outline"
                                size="sm"
                                disabled={currentPage === 1}
                                onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                            >
                                <ChevronLeft className="w-4 h-4" />
                            </Button>
                            <Button
                                variant="outline"
                                size="sm"
                                disabled={currentPage === totalPages}
                                onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
                            >
                                <ChevronRight className="w-4 h-4" />
                            </Button>
                        </div>
                    </div>
                )}
            </Card>

            {/* Claim Details Drawer */}
            <Drawer
                isOpen={!!selectedClaim}
                onClose={() => setSelectedClaim(null)}
                title={selectedClaim ? `Claim #${selectedClaim.id.slice(0, 8)}` : 'Details'}
                size="lg"
                footer={
                    selectedClaim?.status === 'submitted' && (
                        <div className="flex w-full gap-3">
                            {showRejectInput ? (
                                <div className="w-full space-y-3">
                                    <Input
                                        placeholder="Reason for rejection..."
                                        value={rejectionReason}
                                        onChange={(e) => setRejectionReason(e.target.value)}
                                        className="w-full"
                                    />
                                    <div className="flex gap-2">
                                        <Button
                                            variant="outline"
                                            onClick={() => setShowRejectInput(false)}
                                            className="flex-1"
                                        >
                                            Cancel
                                        </Button>
                                        <Button
                                            className="flex-1 bg-red-600 hover:bg-red-700 text-white"
                                            onClick={handleReject}
                                            disabled={!rejectionReason.trim() || !!processingId}
                                        >
                                            Confirm Reject
                                        </Button>
                                    </div>
                                </div>
                            ) : (
                                <>
                                    <Button
                                        className="flex-1 bg-red-50 text-red-600 hover:bg-red-100 border-red-200"
                                        onClick={() => setShowRejectInput(true)}
                                    >
                                        Reject
                                    </Button>
                                    <Button
                                        className="flex-1 bg-green-600 hover:bg-green-700 text-white"
                                        onClick={handleApprove}
                                        disabled={!!processingId}
                                    >
                                        Approve Claim
                                    </Button>
                                </>
                            )}
                        </div>
                    )
                }
            >
                {selectedClaim && (
                    <div className="space-y-6">
                        {/* Summary Header */}
                        <div className="p-4 bg-gray-50 dark:bg-dark-800 rounded-xl flex items-center justify-between">
                            <div>
                                <p className="text-sm text-slate-500 font-medium">Total Claim Amount</p>
                                <p className="text-2xl font-bold text-slate-900">
                                    {formatCurrency(selectedClaim.total_amount)}
                                </p>
                            </div>
                            <div className="text-right">
                                <div className="flex items-center gap-2 justify-end mb-1">
                                    <span className="text-sm font-bold text-slate-900">{selectedClaim.employees?.name}</span>
                                    <Badge variant="outline" size="sm">{selectedClaim.employees?.band || 'NA'}</Badge>
                                </div>
                                <p className="text-xs text-slate-500 font-medium">{formatDate(selectedClaim.claim_date)}</p>
                            </div>
                        </div>

                        {/* Status/Notes */}
                        <div className="space-y-3">
                            {selectedClaim.status === 'rejected' && selectedClaim.rejection_reason && (
                                <div className="p-3 bg-red-50 border border-red-100 rounded-lg text-sm text-red-700">
                                    <span className="font-semibold">Rejected:</span> {selectedClaim.rejection_reason}
                                </div>
                            )}
                            {selectedClaim.notes && (
                                <div className="text-sm text-slate-700 font-medium bg-white p-3 border border-gray-200 rounded-lg italic">
                                    "{selectedClaim.notes}"
                                </div>
                            )}
                        </div>

                        {/* Line Items */}
                        <div>
                            <h3 className="text-sm font-bold uppercase tracking-wider text-slate-500 mb-3">Line Items</h3>
                            <div className="space-y-3">
                                {selectedClaim.expense_items?.map((item) => {
                                    const cat = getCategoryInfo(item.category);
                                    return (
                                        <div key={item.id} className="flex gap-4 p-4 border border-gray-200 rounded-xl hover:border-primary-200 transition-colors bg-white">
                                            <div className="text-2xl pt-1">{cat.icon}</div>
                                            <div className="flex-1">
                                                <div className="flex justify-between items-start">
                                                    <div>
                                                        <p className="font-bold text-slate-900">{cat.label}</p>
                                                        {item.description && <p className="text-sm text-slate-500 font-medium">{item.description}</p>}
                                                    </div>
                                                    <p className="font-bold text-slate-900">{formatCurrency(item.amount)}</p>
                                                </div>
                                                <div className="flex items-center gap-2 mt-2">
                                                    {item.receipt_url && (
                                                        <a
                                                            href={item.receipt_url}
                                                            target="_blank"
                                                            rel="noopener noreferrer"
                                                            className="inline-flex items-center gap-1 text-xs text-primary-600 hover:text-primary-700 bg-primary-50 px-2 py-1 rounded"
                                                        >
                                                            <FileText className="w-3 h-3" /> View Receipt
                                                        </a>
                                                    )}
                                                    {item.exceeds_limit && (
                                                        <Badge color="yellow" size="sm" variant="subtle">Exceeds Policy Limit</Badge>
                                                    )}
                                                </div>
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>
                        </div>

                        {/* Discussion */}
                        <div className="border-t border-gray-200 pt-6">
                            <h3 className="text-sm font-bold uppercase tracking-wider text-slate-500 mb-4 flex items-center gap-2">
                                <MessageCircle className="w-4 h-4" /> Discussion history
                            </h3>
                            <div className="space-y-4 max-h-[300px] overflow-y-auto mb-4 p-1">
                                {comments.length === 0 ? (
                                    <p className="text-sm text-gray-400 italic">No comments yet.</p>
                                ) : (
                                    comments.map((comment) => (
                                        <div key={comment.id} className={`flex gap-3 ${comment.author_id === currentUserId ? 'flex-row-reverse' : ''}`}>
                                            <div className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${comment.author_id === currentUserId ? 'bg-primary-100 text-primary-700' : 'bg-gray-100 text-slate-600'
                                                }`}>
                                                {comment.author?.name?.charAt(0).toUpperCase()}
                                            </div>
                                            <div className={`max-w-[85%] p-3 rounded-2xl text-sm border border-transparent ${comment.author_id === currentUserId
                                                ? 'bg-primary-50 text-slate-900 rounded-tr-none'
                                                : 'bg-gray-100 text-slate-900 rounded-tl-none border-gray-200'
                                                }`}>
                                                <p className="font-bold text-xs opacity-70 mb-1">{comment.author?.name}</p>
                                                <p>{comment.body}</p>
                                            </div>
                                        </div>
                                    ))
                                )}
                            </div>
                            <div className="flex gap-2">
                                <Input
                                    placeholder="Add internal note..."
                                    value={newComment}
                                    onChange={(e) => setNewComment(e.target.value)}
                                    onKeyDown={(e) => e.key === 'Enter' && handlePostComment()}
                                    className="flex-1"
                                />
                                <Button onClick={handlePostComment} disabled={!newComment.trim()}>
                                    <Send className="w-4 h-4" />
                                </Button>
                            </div>
                        </div>
                    </div>
                )}
            </Drawer>
        </div>
    );
}
