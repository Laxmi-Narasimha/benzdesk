'use client';

import React, { useEffect, useState } from 'react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import {
    MapPin,
    Clock,
    Calendar,
    ChevronLeft,
    ChevronRight,
    Search,
    Filter
} from 'lucide-react';

interface Session {
    id: string;
    employee_id: string;
    start_time: string;
    end_time: string | null;
    total_km: number;
    status: 'active' | 'completed' | 'cancelled';
    employees: {
        name: string;
        phone: string;
    } | null;
}

export default function SessionsPage() {
    const [sessions, setSessions] = useState<Session[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [dateFilter, setDateFilter] = useState<'today' | 'week' | 'month' | 'all'>('week');
    const [currentPage, setCurrentPage] = useState(1);
    const pageSize = 20;

    useEffect(() => {
        fetchSessions();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [dateFilter]);

    const fetchSessions = async () => {
        setIsLoading(true);
        try {
            const supabase = getSupabaseClient();
            let query = supabase
                .from('shift_sessions')
                .select(`
                    id,
                    employee_id,
                    start_time,
                    end_time,
                    total_km,
                    status,
                    employees (
                        name,
                        phone
                    )
                `)
                .order('start_time', { ascending: false });

            // Apply date filter
            const now = new Date();
            if (dateFilter === 'today') {
                const today = now.toISOString().split('T')[0];
                query = query.gte('start_time', `${today}T00:00:00`);
            } else if (dateFilter === 'week') {
                const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
                query = query.gte('start_time', weekAgo.toISOString());
            } else if (dateFilter === 'month') {
                const monthAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
                query = query.gte('start_time', monthAgo.toISOString());
            }

            const { data, error } = await query;

            if (error) throw error;

            // Transform data to handle Supabase relation format
            const transformedSessions: Session[] = (data || []).map((s: any) => ({
                ...s,
                employees: Array.isArray(s.employees) ? s.employees[0] : s.employees
            }));

            setSessions(transformedSessions);
        } catch (error) {
            console.error('Error fetching sessions:', error);
        } finally {
            setIsLoading(false);
        }
    };

    const formatDuration = (startTime: string, endTime: string | null) => {
        const start = new Date(startTime);
        const end = endTime ? new Date(endTime) : new Date();
        const minutes = Math.round((end.getTime() - start.getTime()) / (1000 * 60));
        const hours = Math.floor(minutes / 60);
        const mins = minutes % 60;
        return `${hours}h ${mins}m`;
    };

    const formatDate = (dateStr: string) => {
        return new Date(dateStr).toLocaleDateString('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric',
        });
    };

    const formatTime = (dateStr: string) => {
        return new Date(dateStr).toLocaleTimeString('en-IN', {
            hour: '2-digit',
            minute: '2-digit',
        });
    };

    // Filter by search term
    const filteredSessions = sessions.filter(session => {
        if (!searchTerm) return true;
        const empName = session.employees?.name?.toLowerCase() || '';
        const empPhone = session.employees?.phone?.toLowerCase() || '';
        return empName.includes(searchTerm.toLowerCase()) || empPhone.includes(searchTerm.toLowerCase());
    });

    // Pagination
    const totalPages = Math.ceil(filteredSessions.length / pageSize);
    const paginatedSessions = filteredSessions.slice(
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
                <h1 className="text-2xl font-bold text-gray-900">Employee Sessions</h1>
                <p className="text-gray-500">Track all field employee sessions and kilometers</p>
            </div>

            {/* Filters */}
            <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
                {/* Search */}
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

                {/* Date Filter */}
                <div className="flex items-center gap-2">
                    <Filter className="w-4 h-4 text-gray-400" />
                    <select
                        value={dateFilter}
                        onChange={(e) => setDateFilter(e.target.value as 'today' | 'week' | 'month' | 'all')}
                        className="border border-gray-200 rounded-lg px-3 py-2 focus:ring-2 focus:ring-primary-500 focus:border-transparent"
                    >
                        <option value="today">Today</option>
                        <option value="week">Last 7 Days</option>
                        <option value="month">Last 30 Days</option>
                        <option value="all">All Time</option>
                    </select>
                </div>
            </div>

            {/* Sessions Table */}
            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                {paginatedSessions.length === 0 ? (
                    <div className="p-8 text-center text-gray-500">
                        <MapPin className="w-12 h-12 mx-auto text-gray-300 mb-3" />
                        <p>No sessions found</p>
                    </div>
                ) : (
                    <>
                        <div className="overflow-x-auto">
                            <table className="w-full">
                                <thead className="bg-gray-50">
                                    <tr>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Employee</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Date</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Start Time</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">End Time</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Duration</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Distance</th>
                                        <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-gray-200">
                                    {paginatedSessions.map((session) => (
                                        <tr key={session.id} className="hover:bg-gray-50">
                                            <td className="px-6 py-4">
                                                <div className="flex items-center gap-3">
                                                    <div className="w-8 h-8 rounded-full bg-primary-100 flex items-center justify-center">
                                                        <span className="text-primary-600 font-semibold text-sm">
                                                            {session.employees?.name?.charAt(0).toUpperCase() || '?'}
                                                        </span>
                                                    </div>
                                                    <div>
                                                        <div className="font-medium text-gray-900">{session.employees?.name || 'Unknown'}</div>
                                                        <div className="text-xs text-gray-500">{session.employees?.phone || ''}</div>
                                                    </div>
                                                </div>
                                            </td>
                                            <td className="px-6 py-4 text-gray-600">
                                                <div className="flex items-center gap-1">
                                                    <Calendar className="w-3 h-3" />
                                                    {formatDate(session.start_time)}
                                                </div>
                                            </td>
                                            <td className="px-6 py-4 text-gray-600">{formatTime(session.start_time)}</td>
                                            <td className="px-6 py-4 text-gray-600">
                                                {session.end_time ? formatTime(session.end_time) : '—'}
                                            </td>
                                            <td className="px-6 py-4 text-gray-900">
                                                <div className="flex items-center gap-1">
                                                    <Clock className="w-3 h-3 text-gray-400" />
                                                    {formatDuration(session.start_time, session.end_time)}
                                                </div>
                                            </td>
                                            <td className="px-6 py-4 text-gray-900 font-medium">
                                                {(session.total_km || 0).toFixed(2)} km
                                            </td>
                                            <td className="px-6 py-4">
                                                {session.status === 'active' ? (
                                                    <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium bg-green-100 text-green-700">
                                                        <span className="w-1.5 h-1.5 rounded-full bg-green-500 animate-pulse"></span>
                                                        Live
                                                    </span>
                                                ) : session.status === 'completed' ? (
                                                    <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
                                                        Completed
                                                    </span>
                                                ) : (
                                                    <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-red-100 text-red-600">
                                                        Cancelled
                                                    </span>
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
                                    Showing {(currentPage - 1) * pageSize + 1} to {Math.min(currentPage * pageSize, filteredSessions.length)} of {filteredSessions.length} sessions
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
