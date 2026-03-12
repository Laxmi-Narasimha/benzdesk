// ============================================================================
// Request List Component
// Filterable list of requests with status, priority, and search filters
// ============================================================================

'use client';

import React, { useState, useEffect, useMemo, useDeferredValue, useRef } from 'react';
import Link from 'next/link';
import { formatDistanceToNow } from 'date-fns';
import {
    Search,
    Filter,
    ChevronRight,
    Clock,
    User,
    SortAsc,
    SortDesc,
    Trash2,
} from 'lucide-react';
import {
    Card,
    Input,
    Select,
    Button,
    StatusBadge,
    PriorityBadge,
    RequestListSkeleton,
} from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import type { Request, RequestStatus, Priority } from '@/types';
import { REQUEST_STATUS_LABELS, REQUEST_CATEGORY_LABELS, FRESH_START_DATE, getDisplayName } from '@/types';

// Extended type with creator email and name
interface RequestWithCreator extends Request {
    creator_email?: string | null;
    creator_name?: string | null;
}

// ============================================================================
// Types
// ============================================================================

interface RequestListProps {
    showFilters?: boolean;
    showAssignee?: boolean;
    defaultStatus?: RequestStatus | 'all' | 'not_closed';
    limit?: number;
    linkPrefix?: string;
}

type SortField = 'created_at' | 'priority' | 'last_activity_at' | 'deadline';
type SortOrder = 'asc' | 'desc';

// ============================================================================
// Filter Options
// ============================================================================

const statusOptions = [
    { value: 'all', label: 'All Statuses' },
    { value: 'not_closed', label: 'Active (Not Closed)' },
    ...Object.entries(REQUEST_STATUS_LABELS).map(([value, label]) => ({
        value,
        label,
    })),
];

const categoryOptions = [
    { value: 'all', label: 'All Categories' },
    ...Object.entries(REQUEST_CATEGORY_LABELS).map(([value, label]) => ({
        value,
        label,
    })),
];

const priorityOptions = [
    { value: 'all', label: 'All Priorities' },
    { value: '1', label: 'P1 - Critical' },
    { value: '2', label: 'P2 - High' },
    { value: '3', label: 'P3 - Medium' },
    { value: '4', label: 'P4 - Low' },
    { value: '5', label: 'P5 - Minimal' },
];

// ============================================================================
// Component
// ============================================================================

export function RequestList({
    showFilters = true,
    showAssignee = false,
    defaultStatus = 'all',
    limit,
    linkPrefix = '/app/request',
}: RequestListProps) {
    const { user, isAdmin, isDirector } = useAuth();

    const [requests, setRequests] = useState<RequestWithCreator[]>([]);
    const [loading, setLoading] = useState(true);
    const [isRefreshing, setIsRefreshing] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const hasLoadedOnceRef = useRef(false);

    // Filters
    const [search, setSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState(defaultStatus);
    const [categoryFilter, setCategoryFilter] = useState('all');
    const [priorityFilter, setPriorityFilter] = useState('all');
    const [employeeFilter, setEmployeeFilter] = useState('all');
    const [employeeOptions, setEmployeeOptions] = useState([
        { value: 'all', label: 'All Employees' },
    ]);
    const [sortField, setSortField] = useState<SortField>('created_at');
    const [sortOrder, setSortOrder] = useState<SortOrder>('desc');
    const [showFilterPanel, setShowFilterPanel] = useState(false);
    const deferredSearch = useDeferredValue(search);
    const canFilterByEmployee = isAdmin || isDirector;

    // Sync status filter when defaultStatus changes
    useEffect(() => {
        setStatusFilter(defaultStatus);
    }, [defaultStatus]);

    useEffect(() => {
        if (!canFilterByEmployee) {
            setEmployeeFilter('all');
            setEmployeeOptions([{ value: 'all', label: 'All Employees' }]);
            return;
        }

        let cancelled = false;

        async function fetchEmployeeOptions() {
            try {
                const supabase = getSupabaseClient();
                const { data, error: fetchError } = await (supabase
                    .from('requests_with_creator')
                    .select('creator_email, creator_name') as any)
                    .gte('created_at', FRESH_START_DATE)
                    .not('creator_email', 'is', null);

                if (fetchError) throw fetchError;
                if (cancelled) return;

                const uniqueEmployees = Array.from(
                    new Map(
                        (data || [])
                            .map((row: any) => ({
                                email: row.creator_email as string,
                                name: row.creator_name as string | null,
                            }))
                            .filter((emp: { email: string; name: string | null }): emp is { email: string; name: string | null } =>
                                Boolean(emp.email)
                            )
                            .map((emp: { email: string; name: string | null }) => [
                                emp.email.toLowerCase(),
                                {
                                    value: emp.email,
                                    label: emp.name || getDisplayName(emp.email),
                                },
                            ] as [string, { value: string; label: string }])
                    ).values()
                ) as { value: string; label: string }[];
                
                uniqueEmployees.sort((a, b) => a.label.localeCompare(b.label));

                setEmployeeOptions([
                    { value: 'all', label: 'All Employees' },
                    ...uniqueEmployees,
                ]);
            } catch (err) {
                console.error('Error fetching employee filter options:', err);
            }
        }

        fetchEmployeeOptions();

        return () => {
            cancelled = true;
        };
    }, [canFilterByEmployee]);

    // ============================================================================
    // Fetch Requests
    // ============================================================================

    useEffect(() => {
        let cancelled = false;

        async function fetchRequests() {
            if (!user) return;

            const isInitialLoad = !hasLoadedOnceRef.current;
            if (isInitialLoad) {
                setLoading(true);
            } else {
                setIsRefreshing(true);
            }
            setError(null);

            try {
                const supabase = getSupabaseClient();
                // Use view that includes creator email for admin/director views
                const tableName = (isAdmin || isDirector) ? 'requests_with_creator' : 'requests';
                let query = supabase.from(tableName).select('*');

                // Apply filters
                if (statusFilter === 'not_closed') {
                    // Show all except closed
                    query = query.neq('status', 'closed');
                } else if (statusFilter !== 'all') {
                    query = query.eq('status', statusFilter);
                }

                if (categoryFilter !== 'all') {
                    query = query.eq('category', categoryFilter);
                }

                if (priorityFilter !== 'all') {
                    query = query.eq('priority', parseInt(priorityFilter));
                }

                if (canFilterByEmployee && employeeFilter !== 'all') {
                    query = query.eq('creator_email', employeeFilter);
                }

                // Fresh start filter - only show requests after the fresh start date
                query = query.gte('created_at', FRESH_START_DATE);

                // Apply sorting
                query = query.order(sortField, { ascending: sortOrder === 'asc' });

                // Apply limit if specified
                if (limit) {
                    query = query.limit(limit);
                }

                const { data, error: fetchError } = await query;

                if (fetchError) throw fetchError;
                if (cancelled) return;

                setRequests(data || []);
            } catch (err: any) {
                if (cancelled) return;
                console.error('Error fetching requests:', err);
                setError('Failed to load requests');
            } finally {
                if (cancelled) return;
                hasLoadedOnceRef.current = true;
                setLoading(false);
                setIsRefreshing(false);
            }
        }

        fetchRequests();
        return () => {
            cancelled = true;
        };
    }, [
        user,
        isAdmin,
        isDirector,
        canFilterByEmployee,
        statusFilter,
        categoryFilter,
        priorityFilter,
        employeeFilter,
        sortField,
        sortOrder,
        limit,
    ]);

    const normalizedSearch = deferredSearch.trim().toLowerCase();
    const filteredRequests = useMemo(() => {
        if (!normalizedSearch) {
            return requests;
        }

        return requests.filter((request) => {
            const searchableFields = [
                request.title,
                request.description,
                REQUEST_CATEGORY_LABELS[request.category as keyof typeof REQUEST_CATEGORY_LABELS] || request.category,
            ];

            if (canFilterByEmployee) {
                if (request.creator_name) searchableFields.push(request.creator_name);
                if (request.creator_email) {
                    searchableFields.push(request.creator_email, getDisplayName(request.creator_email));
                }
            }

            return searchableFields.some((value) => value.toLowerCase().includes(normalizedSearch));
        });
    }, [canFilterByEmployee, normalizedSearch, requests]);

    const hasActiveFilters = Boolean(
        search.trim() ||
        categoryFilter !== 'all' ||
        priorityFilter !== 'all' ||
        employeeFilter !== 'all' ||
        statusFilter !== defaultStatus
    );

    // ============================================================================
    // Render
    // ============================================================================

    if (loading) {
        return <RequestListSkeleton count={5} />;
    }

    if (error && requests.length === 0) {
        return (
            <Card className="text-center py-12">
                <p className="text-red-400">{error}</p>
                <Button
                    variant="secondary"
                    onClick={() => window.location.reload()}
                    className="mt-4"
                >
                    Retry
                </Button>
            </Card>
        );
    }

    return (
        <div className="space-y-4">
            {/* Filters */}
            {showFilters && (
                <Card padding="sm">
                    {/* Main filter row */}
                    <div className="flex flex-wrap items-center gap-3">
                        {/* Search */}
                        <div className="flex-1 min-w-[200px]">
                            <Input
                                placeholder="Search requests..."
                                value={search}
                                onChange={(e) => setSearch(e.target.value)}
                                leftIcon={<Search className="w-4 h-4" />}
                                size="sm"
                            />
                        </div>

                        {/* Status filter */}
                        <Select
                            options={statusOptions}
                            value={statusFilter}
                            onChange={(e) => setStatusFilter(e.target.value as RequestStatus | 'all')}
                            size="sm"
                            fullWidth={false}
                            className="w-36"
                        />

                        {/* Category filter */}
                        <Select
                            options={categoryOptions}
                            value={categoryFilter}
                            onChange={(e) => setCategoryFilter(e.target.value)}
                            size="sm"
                            fullWidth={false}
                            className="w-44"
                        />

                        {/* Priority filter */}
                        <Select
                            options={priorityOptions}
                            value={priorityFilter}
                            onChange={(e) => setPriorityFilter(e.target.value)}
                            size="sm"
                            fullWidth={false}
                            className="w-36"
                        />

                        {/* Employee filter for admins/directors */}
                        {canFilterByEmployee && (
                            <Select
                                options={employeeOptions}
                                value={employeeFilter}
                                onChange={(e) => setEmployeeFilter(e.target.value)}
                                size="sm"
                                fullWidth={false}
                                className="w-44"
                            />
                        )}

                        {/* Toggle more filters */}
                        <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setShowFilterPanel(!showFilterPanel)}
                            leftIcon={<Filter className="w-4 h-4" />}
                        >
                            {showFilterPanel ? 'Less' : 'More'}
                        </Button>

                        {isRefreshing && (
                            <span className="text-xs text-dark-500 ml-auto">
                                Updating...
                            </span>
                        )}
                    </div>

                    {/* Expanded filter panel */}
                    {showFilterPanel && (
                        <div className="flex flex-wrap items-center gap-3 pt-3 mt-3 border-t border-dark-700">
                            {/* Sort field selector */}
                            <div className="flex items-center gap-2">
                                <span className="text-xs text-dark-400">Sort by:</span>
                                <Select
                                    options={[
                                        { value: 'created_at', label: 'Created Date' },
                                        { value: 'priority', label: 'Priority' },
                                        { value: 'last_activity_at', label: 'Last Activity' },
                                        { value: 'deadline', label: 'Deadline' },
                                    ]}
                                    value={sortField}
                                    onChange={(e) => setSortField(e.target.value as SortField)}
                                    size="sm"
                                    fullWidth={false}
                                    className="w-32"
                                />
                                <Button
                                    variant="ghost"
                                    size="sm"
                                    onClick={() => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')}
                                    leftIcon={
                                        sortOrder === 'desc' ? (
                                            <SortDesc className="w-4 h-4" />
                                        ) : (
                                            <SortAsc className="w-4 h-4" />
                                        )
                                    }
                                >
                                    {sortOrder === 'desc' ? 'Newest' : 'Oldest'}
                                </Button>
                            </div>

                            {/* Clear filters */}
                            {hasActiveFilters && (
                                <Button
                                    variant="ghost"
                                    size="sm"
                                    onClick={() => {
                                        setStatusFilter(defaultStatus);
                                        setCategoryFilter('all');
                                        setPriorityFilter('all');
                                        setEmployeeFilter('all');
                                        setSearch('');
                                    }}
                                    className="text-red-400 hover:text-red-300"
                                >
                                    Clear Filters
                                </Button>
                            )}
                        </div>
                    )}

                    {error && requests.length > 0 && (
                        <p className="pt-3 mt-3 border-t border-dark-700 text-sm text-red-400">
                            {error}
                        </p>
                    )}
                </Card>
            )}

            {/* Request List */}
            {filteredRequests.length === 0 ? (
                <Card className="text-center py-12">
                    <div className="text-dark-500 mb-2">
                        <Search className="w-12 h-12 mx-auto opacity-50" />
                    </div>
                    <p className="text-dark-400">No requests found</p>
                    <p className="text-sm text-dark-500 mt-1">
                        {hasActiveFilters
                            ? 'Try adjusting your filters'
                            : 'Create your first request to get started'}
                    </p>
                </Card>
            ) : (
                <div className="space-y-3">
                    {filteredRequests.map((request) => (
                        <Link
                            key={request.id}
                            href={`${linkPrefix}?id=${request.id}`}
                            className="block group"
                        >
                            <Card hover padding="sm" className="bg-white/60 backdrop-blur-md border border-gray-100 shadow-sm transition-all duration-300 hover:-translate-y-1 hover:shadow-lg hover:bg-white/90 group-hover:border-blue-200">
                                <div className="flex items-start justify-between gap-4">
                                    {/* Main content */}
                                    <div className="flex-1 min-w-0">
                                        <div className="flex items-center gap-3 mb-2">
                                            <h3 className="text-base font-semibold text-gray-900 truncate group-hover:text-blue-600 transition-colors">
                                                {request.title}
                                            </h3>
                                            <StatusBadge status={request.status} />
                                        </div>

                                        <p className="text-sm text-gray-500 line-clamp-2 mb-3">
                                            {request.description}
                                        </p>

                                        <div className="flex flex-wrap items-center gap-3 text-xs text-gray-500">
                                            <PriorityBadge priority={request.priority as Priority} size="sm" />

                                            <span className="flex items-center gap-1 font-mono text-xs text-blue-600 font-medium">
                                                #{request.reference_id || request.id.substring(0, 6).toUpperCase()}
                                            </span>

                                            <span className="flex items-center gap-1">
                                                <span className="px-2 py-0.5 rounded bg-gray-100 text-gray-600 font-medium">
                                                    {REQUEST_CATEGORY_LABELS[request.category as keyof typeof REQUEST_CATEGORY_LABELS] || request.category}
                                                </span>
                                            </span>

                                            <span className="flex items-center gap-1 text-gray-700 font-medium" suppressHydrationWarning>
                                                <Clock className="w-3.5 h-3.5" />
                                                {new Date(request.created_at).toLocaleString('en-IN', {
                                                    day: '2-digit', month: 'short', year: 'numeric',
                                                    hour: '2-digit', minute: '2-digit', hour12: true
                                                })}
                                            </span>

                                            {/* Show requester name for admin/director */}
                                            {(isAdmin || isDirector) && (request.creator_name || request.creator_email) && (
                                                <span className="flex items-center gap-1 text-gray-500 font-medium ml-1">
                                                    <User className="w-3.5 h-3.5" />
                                                    {request.creator_name || getDisplayName(request.creator_email)}
                                                </span>
                                            )}

                                            {showAssignee && request.assigned_to && (
                                                <span className="flex items-center gap-1 text-blue-500 font-medium">
                                                    <User className="w-3.5 h-3.5" />
                                                    Assigned
                                                </span>
                                            )}
                                        </div>
                                    </div>

                                    {/* Delete button (admin/director only) */}
                                    {(isAdmin || isDirector) && request.status === 'closed' && (
                                        <button
                                            onClick={(e) => {
                                                e.preventDefault();
                                                e.stopPropagation();
                                                if (confirm('Are you sure you want to delete this closed request? This action cannot be undone.')) {
                                                    const supabase = getSupabaseClient();
                                                    supabase
                                                        .from('requests')
                                                        .delete()
                                                        .eq('id', request.id)
                                                        .then(({ error }) => {
                                                            if (error) {
                                                                console.error('Delete failed:', error);
                                                                alert('Failed to delete request');
                                                            } else {
                                                                setRequests(prev => prev.filter(r => r.id !== request.id));
                                                            }
                                                        });
                                                }
                                            }}
                                            className="flex-shrink-0 p-2 text-red-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors"
                                            title="Delete closed request"
                                        >
                                            <Trash2 className="w-4 h-4" />
                                        </button>
                                    )}

                                    {/* Arrow indicator */}
                                    <div className="flex-shrink-0 text-gray-400 group-hover:text-blue-500 transition-colors mt-1">
                                        <ChevronRight className="w-5 h-5" />
                                    </div>
                                </div>
                            </Card>
                        </Link>
                    ))}
                </div>
            )}

            {/* Load more (if limit applied) */}
            {limit && requests.length >= limit && (
                <div className="text-center pt-4">
                    <Button variant="ghost" size="sm">
                        View All Requests
                    </Button>
                </div>
            )}
        </div>
    );
}

export default RequestList;