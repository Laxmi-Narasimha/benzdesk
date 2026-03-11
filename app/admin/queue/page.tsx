// ============================================================================
// Admin Queue Page
// All requests for admin management
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { clsx } from 'clsx';
import {
    Search,
    Filter,
    Users,
    Clock,
    AlertTriangle,
    CheckCircle,
} from 'lucide-react';
import { Card, MetricCard, Button, Input, Select } from '@/components/ui';
import { RequestList } from '@/components/requests';
import { getSupabaseClient } from '@/lib/supabaseClient';

// ============================================================================
// Component
// ============================================================================

export default function AdminQueuePage() {
    const [stats, setStats] = useState({
        open: 0,
        in_progress: 0,
        waiting: 0,
        closed_today: 0,
    });
    const [loadingStats, setLoadingStats] = useState(true);

    // Fresh start date - only count requests after this date
    const FRESH_START_DATE = '2026-01-14T00:00:00.000Z';

    // Fetch quick stats - only counting requests after FRESH_START_DATE
    useEffect(() => {
        async function fetchStats() {
            try {
                const supabase = getSupabaseClient();

                // Query requests table directly with FRESH_START_DATE filter
                const { data, error } = await supabase
                    .from('requests')
                    .select('status')
                    .gte('created_at', FRESH_START_DATE);

                if (data) {
                    // Count by status manually
                    const counts: Record<string, number> = {
                        open: 0,
                        in_progress: 0,
                        waiting_on_requester: 0,
                        pending_closure: 0,
                        closed: 0,
                    };

                    data.forEach((row: any) => {
                        if (counts[row.status] !== undefined) {
                            counts[row.status]++;
                        }
                    });

                    setStats({
                        open: counts['open'],
                        in_progress: counts['in_progress'],
                        waiting: counts['waiting_on_requester'],
                        closed_today: counts['pending_closure'], // Repurpose as pending closure count
                    });
                }
            } catch (err) {
                console.error('Error fetching stats:', err);
            } finally {
                setLoadingStats(false);
            }
        }

        fetchStats();
    }, []);

    const [currentStatusFilter, setCurrentStatusFilter] = useState<'not_closed' | 'open' | 'in_progress' | 'waiting_on_requester' | 'pending_closure'>('not_closed');

    return (
        <div className="max-w-7xl mx-auto space-y-8 animate-in fade-in duration-500">
            {/* Header */}
            <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 bg-white/60 backdrop-blur-md p-6 rounded-3xl border border-white/40 shadow-[0_8px_30px_rgb(0,0,0,0.04)]">
                <div>
                    <h1 className="text-3xl font-extrabold text-transparent bg-clip-text bg-gradient-to-r from-gray-900 via-gray-800 to-gray-600 tracking-tight">
                        Master Request Queue
                    </h1>
                    <p className="text-gray-500 mt-2 font-medium">
                        Unified inbox for BenzDesk requests and MobiTraq expense claims
                    </p>
                </div>
                {/* Reset filter button */}
                {currentStatusFilter !== 'not_closed' && (
                    <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => setCurrentStatusFilter('not_closed')}
                        className="text-primary-600"
                    >
                        Reset Filter
                    </Button>
                )}
            </div>

            {/* Quick Stats */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-5">
                <MetricCard
                    title="Open Requests"
                    value={stats.open}
                    icon={<AlertTriangle className="w-6 h-6 text-emerald-500" />}
                    className={clsx(
                        "relative overflow-hidden cursor-pointer transition-all duration-300 rounded-2xl active:scale-[0.98]",
                        "bg-gradient-to-br from-white to-emerald-50/30 border border-emerald-100",
                        currentStatusFilter === 'open' ? 'ring-2 ring-emerald-500/50 shadow-lg shadow-emerald-500/10 transform scale-[1.02]' : 'hover:shadow-md hover:-translate-y-1'
                    )}
                    onClick={() => setCurrentStatusFilter(currentStatusFilter === 'open' ? 'not_closed' : 'open')}
                />
                <MetricCard
                    title="In Progress"
                    value={stats.in_progress}
                    icon={<Clock className="w-6 h-6 text-blue-500" />}
                    className={clsx(
                        "relative overflow-hidden cursor-pointer transition-all duration-300 rounded-2xl active:scale-[0.98]",
                        "bg-gradient-to-br from-white to-blue-50/30 border border-blue-100",
                        currentStatusFilter === 'in_progress' ? 'ring-2 ring-blue-500/50 shadow-lg shadow-blue-500/10 transform scale-[1.02]' : 'hover:shadow-md hover:-translate-y-1'
                    )}
                    onClick={() => setCurrentStatusFilter(currentStatusFilter === 'in_progress' ? 'not_closed' : 'in_progress')}
                />
                <MetricCard
                    title="Awaiting Reply"
                    value={stats.waiting}
                    icon={<Users className="w-6 h-6 text-amber-500" />}
                    className={clsx(
                        "relative overflow-hidden cursor-pointer transition-all duration-300 rounded-2xl active:scale-[0.98]",
                        "bg-gradient-to-br from-white to-amber-50/30 border border-amber-100",
                        currentStatusFilter === 'waiting_on_requester' ? 'ring-2 ring-amber-500/50 shadow-lg shadow-amber-500/10 transform scale-[1.02]' : 'hover:shadow-md hover:-translate-y-1'
                    )}
                    onClick={() => setCurrentStatusFilter(currentStatusFilter === 'waiting_on_requester' ? 'not_closed' : 'waiting_on_requester')}
                />
                <MetricCard
                    title="Pending Closure"
                    value={stats.closed_today}
                    icon={<CheckCircle className="w-6 h-6 text-purple-500" />}
                    className={clsx(
                        "relative overflow-hidden cursor-pointer transition-all duration-300 rounded-2xl active:scale-[0.98]",
                        "bg-gradient-to-br from-white to-purple-50/30 border border-purple-100",
                        currentStatusFilter === 'pending_closure' ? 'ring-2 ring-purple-500/50 shadow-lg shadow-purple-500/10 transform scale-[1.02]' : 'hover:shadow-md hover:-translate-y-1'
                    )}
                    onClick={() => setCurrentStatusFilter(currentStatusFilter === 'pending_closure' ? 'not_closed' : 'pending_closure')}
                />
            </div>

            {/* Request List - Default to NOT CLOSED (hide closed requests) */}
            <RequestList
                key={currentStatusFilter}
                showFilters={true}
                showAssignee={true}
                defaultStatus={currentStatusFilter}
                linkPrefix="/admin/request"
            />
        </div>
    );
}

