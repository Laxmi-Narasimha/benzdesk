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
        <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">Request Queue</h1>
                    <p className="text-gray-500 mt-1">
                        Manage and respond to all incoming requests
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
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <MetricCard
                    title="Open"
                    value={stats.open}
                    icon={<AlertTriangle className="w-5 h-5" />}
                    className={clsx(
                        "border-l-4 border-green-500 cursor-pointer transition-all active:scale-95",
                        currentStatusFilter === 'open' ? 'ring-2 ring-green-500 shadow-md transform scale-[1.02]' : 'hover:shadow-md'
                    )}
                    onClick={() => setCurrentStatusFilter(currentStatusFilter === 'open' ? 'not_closed' : 'open')}
                    hover
                />
                <MetricCard
                    title="In Progress"
                    value={stats.in_progress}
                    icon={<Clock className="w-5 h-5" />}
                    className={clsx(
                        "border-l-4 border-blue-500 cursor-pointer transition-all active:scale-95",
                        currentStatusFilter === 'in_progress' ? 'ring-2 ring-blue-500 shadow-md transform scale-[1.02]' : 'hover:shadow-md'
                    )}
                    onClick={() => setCurrentStatusFilter(currentStatusFilter === 'in_progress' ? 'not_closed' : 'in_progress')}
                    hover
                />
                <MetricCard
                    title="Waiting on Requester"
                    value={stats.waiting}
                    icon={<Users className="w-5 h-5" />}
                    className={clsx(
                        "border-l-4 border-amber-500 cursor-pointer transition-all active:scale-95",
                        currentStatusFilter === 'waiting_on_requester' ? 'ring-2 ring-amber-500 shadow-md transform scale-[1.02]' : 'hover:shadow-md'
                    )}
                    onClick={() => setCurrentStatusFilter(currentStatusFilter === 'waiting_on_requester' ? 'not_closed' : 'waiting_on_requester')}
                    hover
                />
                <MetricCard
                    title="Pending Closure"
                    value={stats.closed_today}
                    icon={<CheckCircle className="w-5 h-5" />}
                    className={clsx(
                        "border-l-4 border-purple-500 cursor-pointer transition-all active:scale-95",
                        currentStatusFilter === 'pending_closure' ? 'ring-2 ring-purple-500 shadow-md transform scale-[1.02]' : 'hover:shadow-md'
                    )}
                    onClick={() => setCurrentStatusFilter(currentStatusFilter === 'pending_closure' ? 'not_closed' : 'pending_closure')}
                    hover
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

