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
    FileText
} from 'lucide-react';

interface ExpenseClaim {
    id: string;
    employee_id: string;
    total_amount: number;
    status: 'draft' | 'submitted' | 'approved' | 'rejected';
    notes: string | null;
    claim_date: string;
    reviewed_at: string | null;
    created_at: string;
    employees: {
        name: string;
        email: string;
    } | null;
}

export default function ExpensesPage() {
    const [expenses, setExpenses] = useState<ExpenseClaim[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [statusFilter, setStatusFilter] = useState<'all' | 'submitted' | 'approved' | 'rejected'>('all');
    const [currentPage, setCurrentPage] = useState(1);
    const [processingId, setProcessingId] = useState<string | null>(null);
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
                    employees (
                        name,
                        email
                    )
                `)
                .neq('status', 'draft') // Don't show drafts to admin
                .order('created_at', { ascending: false });

            if (statusFilter !== 'all') {
                query = query.eq('status', statusFilter);
            }

            const { data, error } = await query;

            if (error) throw error;

            // Transform data to handle Supabase relation format
            const transformedExpenses: ExpenseClaim[] = (data || []).map((e: any) => ({
                ...e,
                employees: Array.isArray(e.employees) ? e.employees[0] : e.employees
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

            // Update local state
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
        setProcessingId(id);
        try {
            const supabase = getSupabaseClient();
            const { error } = await supabase
                .from('expense_claims')
                .update({
                    status: 'rejected',
                    reviewed_at: new Date().toISOString()
                })
                .eq('id', id);

            if (error) throw error;

            // Update local state
            setExpenses(prev => prev.map(exp =>
                exp.id === id ? { ...exp, status: 'rejected' as const, reviewed_at: new Date().toISOString() } : exp
            ));
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
        pending: expenses.filter(e => e.status === 'submitted').length,
        pendingAmount: expenses.filter(e => e.status === 'submitted').reduce((sum, e) => sum + e.total_amount, 0),
        approved: expenses.filter(e => e.status === 'approved').length,
        approvedAmount: expenses.filter(e => e.status === 'approved').reduce((sum, e) => sum + e.total_amount, 0),
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
                <h1 className="text-2xl font-bold text-gray-900">Field Expenses</h1>
                <p className="text-gray-500">Manage expense claims from field employees</p>
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
            </div>

            {/* Filters */}
            <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
                {/* Search */}
                <div className="relative w-full sm:w-72">
                    <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
                    <input
                        type="text"
                        placeholder="Search expenses..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        className="w-full pl-10 pr-4 py-2 border border-gray-200 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                    />
                </div>

                {/* Status Filter */}
                <div className="flex items-center gap-2">
                    <Filter className="w-4 h-4 text-gray-400" />
                    <select
                        value={statusFilter}
                        onChange={(e) => setStatusFilter(e.target.value as 'all' | 'submitted' | 'approved' | 'rejected')}
                        className="border border-gray-200 rounded-lg px-3 py-2 focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                    >
                        <option value="all">All Status</option>
                        <option value="submitted">Pending Review</option>
                        <option value="approved">Approved</option>
                        <option value="rejected">Rejected</option>
                    </select>
                </div>
            </div>

            {/* Expenses Table */}
            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                {paginatedExpenses.length === 0 ? (
                    <div className="p-8 text-center text-gray-500">
                        <Receipt className="w-12 h-12 mx-auto text-gray-300 mb-3" />
                        <p>No expense claims found</p>
                    </div>
                ) : (
                    <>
                        <div className="overflow-x-auto">
                            <table className="w-full">
                                <thead className="bg-gray-50">
                                    <tr>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Employee</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Claim Date</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Notes</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Amount</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-200">
                                    {paginatedExpenses.map((expense) => (
                                        <tr key={expense.id} className="hover:bg-gray-50">
                                            <td className="px-6 py-4">
                                                <div className="flex items-center gap-3">
                                                    <div className="w-8 h-8 rounded-full bg-primary-100 flex items-center justify-center">
                                                        <span className="text-primary-600 font-semibold text-sm">
                                                            {expense.employees?.name?.charAt(0).toUpperCase() || '?'}
                                                        </span>
                                                    </div>
                                                    <div>
                                                        <div className="font-medium text-gray-900">{expense.employees?.name || 'Unknown'}</div>
                                                        <div className="text-xs text-gray-500">{expense.employees?.email}</div>
                                                    </div>
                                                </div>
                                            </td>
                                            <td className="px-6 py-4 text-gray-600">
                                                <div className="flex items-center gap-1">
                                                    <Calendar className="w-3 h-3" />
                                                    {formatDate(expense.claim_date)}
                                                </div>
                                            </td>
                                            <td className="px-6 py-4 text-gray-600 max-w-xs">
                                                {expense.notes ? (
                                                    <div className="flex items-center gap-1 truncate">
                                                        <FileText className="w-3 h-3 flex-shrink-0" />
                                                        <span className="truncate">{expense.notes}</span>
                                                    </div>
                                                ) : (
                                                    <span className="text-gray-400">—</span>
                                                )}
                                            </td>
                                            <td className="px-6 py-4 text-gray-900 font-semibold">
                                                {formatCurrency(expense.total_amount)}
                                            </td>
                                            <td className="px-6 py-4">
                                                {expense.status === 'submitted' && (
                                                    <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-yellow-100 text-yellow-700">
                                                        <Clock className="w-3 h-3" />
                                                        Pending
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
                                            </td>
                                            <td className="px-6 py-4">
                                                {expense.status === 'submitted' && (
                                                    <div className="flex items-center gap-2">
                                                        <button
                                                            onClick={() => handleApprove(expense.id)}
                                                            disabled={processingId === expense.id}
                                                            className="p-2 rounded-lg bg-green-50 text-green-600 hover:bg-green-100 disabled:opacity-50"
                                                            title="Approve"
                                                        >
                                                            <Check className="w-4 h-4" />
                                                        </button>
                                                        <button
                                                            onClick={() => handleReject(expense.id)}
                                                            disabled={processingId === expense.id}
                                                            className="p-2 rounded-lg bg-red-50 text-red-600 hover:bg-red-100 disabled:opacity-50"
                                                            title="Reject"
                                                        >
                                                            <X className="w-4 h-4" />
                                                        </button>
                                                    </div>
                                                )}
                                                {expense.status !== 'submitted' && (
                                                    <span className="text-xs text-gray-400">—</span>
                                                )}
                                            </td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>

                        {/* Pagination */}
                        {totalPages > 1 && (
                            <div className="px-6 py-4 border-t border-gray-200 flex items-center justify-between">
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
                    </>
                )}
            </div>
        </div>
    );
}
