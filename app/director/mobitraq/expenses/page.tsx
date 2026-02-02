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
    Download,
    Eye,
    AlertTriangle,
    User,
    BadgeCheck
} from 'lucide-react';

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
        email: string;
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
    const pageSize = 15;

    useEffect(() => {
        fetchExpenses();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [statusFilter]);

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
                    employees (
                        name,
                        email,
                        band
                    ),
                    expense_items (
                        id,
                        category,
                        amount,
                        description,
                        receipt_url,
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

            // Transform data to handle Supabase relation format
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

    const handleApprove = async (id: string) => {
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

    // Filter by search term
    const filteredExpenses = expenses.filter(expense => {
        if (!searchTerm) return true;
        const empName = expense.employees?.name?.toLowerCase() || '';
        const empEmail = expense.employees?.email?.toLowerCase() || '';
        const notes = expense.notes?.toLowerCase() || '';
        return empName.includes(searchTerm.toLowerCase()) ||
            empEmail.includes(searchTerm.toLowerCase()) ||
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
                <h1 className="text-2xl font-bold text-gray-900">Field Expense Approval</h1>
                <p className="text-gray-500">Review and approve expense claims from field employees</p>
            </div>

            {/* Stats Cards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-4">
                    <div className="flex items-center gap-3">
                        <Clock className="w-8 h-8 text-yellow-600" />
                        <div>
                            <p className="text-sm text-yellow-700">Pending Review</p>
                            <p className="text-xl font-bold text-yellow-800">{stats.pending}</p>
                            <p className="text-xs text-yellow-600">{formatCurrency(stats.pendingAmount)}</p>
                        </div>
                    </div>
                </div>
                <div className="bg-green-50 border border-green-200 rounded-xl p-4">
                    <div className="flex items-center gap-3">
                        <Check className="w-8 h-8 text-green-600" />
                        <div>
                            <p className="text-sm text-green-700">Approved</p>
                            <p className="text-xl font-bold text-green-800">{stats.approved}</p>
                            <p className="text-xs text-green-600">{formatCurrency(stats.approvedAmount)}</p>
                        </div>
                    </div>
                </div>
                <div className="bg-red-50 border border-red-200 rounded-xl p-4">
                    <div className="flex items-center gap-3">
                        <X className="w-8 h-8 text-red-600" />
                        <div>
                            <p className="text-sm text-red-700">Rejected</p>
                            <p className="text-xl font-bold text-red-800">{stats.rejected}</p>
                        </div>
                    </div>
                </div>
                {stats.exceedsLimit > 0 && (
                    <div className="bg-orange-50 border border-orange-200 rounded-xl p-4">
                        <div className="flex items-center gap-3">
                            <AlertTriangle className="w-8 h-8 text-orange-600" />
                            <div>
                                <p className="text-sm text-orange-700">Exceeds Limit</p>
                                <p className="text-xl font-bold text-orange-800">{stats.exceedsLimit}</p>
                                <p className="text-xs text-orange-600">Needs skip-level approval</p>
                            </div>
                        </div>
                    </div>
                )}
            </div>

            {/* Filters */}
            <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
                <div className="relative w-full sm:w-72">
                    <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
                    <input
                        type="text"
                        placeholder="Search by employee name..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        className="w-full pl-10 pr-4 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                    />
                </div>

                <div className="flex items-center gap-2">
                    <Filter className="w-4 h-4 text-gray-400" />
                    <select
                        value={statusFilter}
                        onChange={(e) => setStatusFilter(e.target.value as typeof statusFilter)}
                        className="border border-gray-200 rounded-lg px-3 py-2 focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                    >
                        <option value="all">All Status</option>
                        <option value="submitted">Pending Review</option>
                        <option value="in_review">In Review</option>
                        <option value="approved">Approved</option>
                        <option value="rejected">Rejected</option>
                    </select>
                </div>
            </div>

            {/* Expense Claims List */}
            <div className="space-y-4">
                {paginatedExpenses.length === 0 ? (
                    <div className="bg-white rounded-xl border border-gray-200 p-8 text-center text-gray-500">
                        <Receipt className="w-12 h-12 mx-auto text-gray-300 mb-3" />
                        <p>No expense claims found</p>
                    </div>
                ) : (
                    paginatedExpenses.map((expense) => {
                        const isExpanded = expandedId === expense.id;
                        const hasExceedsLimit = expense.expense_items?.some(i => i.exceeds_limit);

                        return (
                            <div
                                key={expense.id}
                                className={`bg-white rounded-xl border transition-all ${hasExceedsLimit
                                        ? 'border-orange-300 bg-orange-50/30'
                                        : 'border-gray-200'
                                    }`}
                            >
                                {/* Main Row */}
                                <div
                                    className="p-4 cursor-pointer hover:bg-gray-50"
                                    onClick={() => setExpandedId(isExpanded ? null : expense.id)}
                                >
                                    <div className="flex items-center gap-4">
                                        {/* Employee Info */}
                                        <div className="flex items-center gap-3 flex-1">
                                            <div className="w-10 h-10 rounded-full bg-primary-100 flex items-center justify-center">
                                                <span className="text-primary-600 font-semibold">
                                                    {expense.employees?.name?.charAt(0).toUpperCase() || '?'}
                                                </span>
                                            </div>
                                            <div>
                                                <div className="font-medium text-gray-900 flex items-center gap-2">
                                                    {expense.employees?.name || 'Unknown'}
                                                    <span className="text-xs px-2 py-0.5 bg-gray-100 text-gray-600 rounded">
                                                        {getBandName(expense.employees?.band)}
                                                    </span>
                                                </div>
                                                <div className="text-xs text-gray-500 flex items-center gap-2">
                                                    <Calendar className="w-3 h-3" />
                                                    {formatDate(expense.claim_date)}
                                                </div>
                                            </div>
                                        </div>

                                        {/* Amount */}
                                        <div className="text-right">
                                            <div className="font-bold text-lg text-gray-900">
                                                {formatCurrency(expense.total_amount)}
                                            </div>
                                            <div className="text-xs text-gray-500">
                                                {expense.expense_items?.length || 0} items
                                            </div>
                                        </div>

                                        {/* Status Badge */}
                                        <div>
                                            {expense.status === 'submitted' && (
                                                <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-700">
                                                    <Clock className="w-3 h-3" />
                                                    Pending
                                                </span>
                                            )}
                                            {expense.status === 'in_review' && (
                                                <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-700">
                                                    <Eye className="w-3 h-3" />
                                                    In Review
                                                </span>
                                            )}
                                            {expense.status === 'approved' && (
                                                <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-green-100 text-green-700">
                                                    <Check className="w-3 h-3" />
                                                    Approved
                                                </span>
                                            )}
                                            {expense.status === 'rejected' && (
                                                <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-red-100 text-red-700">
                                                    <X className="w-3 h-3" />
                                                    Rejected
                                                </span>
                                            )}
                                        </div>

                                        {/* Exceeds Limit Warning */}
                                        {hasExceedsLimit && (
                                            <span className="inline-flex items-center gap-1 px-2 py-1 rounded text-xs font-medium bg-orange-100 text-orange-700">
                                                <AlertTriangle className="w-3 h-3" />
                                                Over Limit
                                            </span>
                                        )}

                                        {/* Actions */}
                                        {(expense.status === 'submitted' || expense.status === 'in_review') && (
                                            <div className="flex items-center gap-2" onClick={e => e.stopPropagation()}>
                                                <button
                                                    onClick={() => handleApprove(expense.id)}
                                                    disabled={processingId === expense.id}
                                                    className="p-2 rounded-lg bg-green-50 text-green-600 hover:bg-green-100 disabled:opacity-50"
                                                    title="Approve"
                                                >
                                                    <Check className="w-5 h-5" />
                                                </button>
                                                <button
                                                    onClick={() => setShowRejectModal(expense.id)}
                                                    disabled={processingId === expense.id}
                                                    className="p-2 rounded-lg bg-red-50 text-red-600 hover:bg-red-100 disabled:opacity-50"
                                                    title="Reject"
                                                >
                                                    <X className="w-5 h-5" />
                                                </button>
                                            </div>
                                        )}

                                        {/* Expand Button */}
                                        <button className="p-2 text-gray-400 hover:text-gray-600">
                                            {isExpanded ? <ChevronUp className="w-5 h-5" /> : <ChevronDown className="w-5 h-5" />}
                                        </button>
                                    </div>
                                </div>

                                {/* Expanded Details */}
                                {isExpanded && (
                                    <div className="border-t border-gray-200 p-4 bg-gray-50">
                                        {/* Notes */}
                                        {expense.notes && (
                                            <div className="mb-4 p-3 bg-white rounded-lg border border-gray-200">
                                                <div className="text-xs text-gray-500 mb-1">Notes</div>
                                                <div className="text-sm text-gray-700">{expense.notes}</div>
                                            </div>
                                        )}

                                        {/* Rejection Reason */}
                                        {expense.rejection_reason && (
                                            <div className="mb-4 p-3 bg-red-50 rounded-lg border border-red-200">
                                                <div className="text-xs text-red-600 mb-1">Rejection Reason</div>
                                                <div className="text-sm text-red-800">{expense.rejection_reason}</div>
                                            </div>
                                        )}

                                        {/* Expense Items */}
                                        <div className="text-xs text-gray-500 uppercase font-medium mb-2">Expense Items</div>
                                        <div className="space-y-2">
                                            {expense.expense_items?.map((item) => {
                                                const catInfo = getCategoryInfo(item.category);
                                                return (
                                                    <div
                                                        key={item.id}
                                                        className={`flex items-center gap-4 p-3 bg-white rounded-lg border ${item.exceeds_limit ? 'border-orange-300' : 'border-gray-200'
                                                            }`}
                                                    >
                                                        <span className="text-xl">{catInfo.icon}</span>
                                                        <div className="flex-1">
                                                            <div className="font-medium text-gray-900 flex items-center gap-2">
                                                                {catInfo.label}
                                                                {item.exceeds_limit && (
                                                                    <span className="text-xs px-1.5 py-0.5 bg-orange-100 text-orange-700 rounded">
                                                                        Exceeds Limit
                                                                    </span>
                                                                )}
                                                            </div>
                                                            {item.description && (
                                                                <div className="text-xs text-gray-500">{item.description}</div>
                                                            )}
                                                        </div>
                                                        <div className="font-semibold text-gray-900">
                                                            {formatCurrency(item.amount)}
                                                        </div>
                                                        {item.receipt_url && (
                                                            <a
                                                                href={item.receipt_url}
                                                                target="_blank"
                                                                rel="noopener noreferrer"
                                                                className="p-2 text-primary-600 hover:bg-primary-50 rounded-lg"
                                                                onClick={e => e.stopPropagation()}
                                                            >
                                                                <FileText className="w-4 h-4" />
                                                            </a>
                                                        )}
                                                    </div>
                                                );
                                            })}
                                        </div>
                                    </div>
                                )}
                            </div>
                        );
                    })
                )}
            </div>

            {/* Pagination */}
            {totalPages > 1 && (
                <div className="flex items-center justify-between">
                    <p className="text-sm text-gray-500">
                        Showing {(currentPage - 1) * pageSize + 1} to {Math.min(currentPage * pageSize, filteredExpenses.length)} of {filteredExpenses.length}
                    </p>
                    <div className="flex items-center gap-2">
                        <button
                            onClick={() => setCurrentPage(p => Math.max(1, p - 1))}
                            disabled={currentPage === 1}
                            className="p-2 rounded-lg border border-gray-200 disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-50"
                        >
                            <ChevronLeft className="w-4 h-4" />
                        </button>
                        <span className="text-sm text-gray-600">
                            Page {currentPage} of {totalPages}
                        </span>
                        <button
                            onClick={() => setCurrentPage(p => Math.min(totalPages, p + 1))}
                            disabled={currentPage === totalPages}
                            className="p-2 rounded-lg border border-gray-200 disabled:opacity-50 disabled:cursor-not-allowed hover:bg-gray-50"
                        >
                            <ChevronRight className="w-4 h-4" />
                        </button>
                    </div>
                </div>
            )}

            {/* Rejection Modal */}
            {showRejectModal && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
                    <div className="bg-white rounded-xl p-6 w-full max-w-md mx-4">
                        <h3 className="text-lg font-bold text-gray-900 mb-4">Reject Expense Claim</h3>
                        <p className="text-sm text-gray-600 mb-4">
                            Please provide a reason for rejecting this expense claim.
                        </p>
                        <textarea
                            value={rejectionReason}
                            onChange={(e) => setRejectionReason(e.target.value)}
                            placeholder="Enter rejection reason..."
                            className="w-full p-3 border border-gray-200 rounded-lg focus:ring-2 focus:ring-red-500 focus:border-transparent"
                            rows={3}
                        />
                        <div className="flex gap-3 mt-4">
                            <button
                                onClick={() => {
                                    setShowRejectModal(null);
                                    setRejectionReason('');
                                }}
                                className="flex-1 px-4 py-2 border border-gray-200 rounded-lg hover:bg-gray-50"
                            >
                                Cancel
                            </button>
                            <button
                                onClick={() => handleReject(showRejectModal)}
                                disabled={!rejectionReason.trim() || processingId === showRejectModal}
                                className="flex-1 px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 disabled:opacity-50"
                            >
                                Reject
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
