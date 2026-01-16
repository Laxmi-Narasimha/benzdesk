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

    // Fetch quick stats
    useEffect(() => {
        async function fetchStats() {
            try {
                const supabase = getSupabaseClient();

                const { data, error } = await supabase
                    .from('v_requests_overview')
                    .select('*');

                if (data) {
                    const statsMap: Record<string, number> = {};
                    data.forEach((row: any) => {
                        statsMap[row.status] = row.count;
                    });

                    setStats({
                        open: statsMap['open'] || 0,
                        in_progress: statsMap['in_progress'] || 0,
                        waiting: statsMap['waiting_on_requester'] || 0,
                        closed_today: 0, // Would need separate query
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

    return (
        <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <div>
                <h1 className="text-2xl font-bold text-gray-900">Request Queue</h1>
                <p className="text-gray-500 mt-1">
                    Manage and respond to all incoming requests
                </p>
            </div>

            {/* Quick Stats */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <MetricCard
                    title="Open"
                    value={stats.open}
                    icon={<AlertTriangle className="w-5 h-5" />}
                    className="border-l-4 border-green-500"
                />
                <MetricCard
                    title="In Progress"
                    value={stats.in_progress}
                    icon={<Clock className="w-5 h-5" />}
                    className="border-l-4 border-blue-500"
                />
                <MetricCard
                    title="Waiting on Requester"
                    value={stats.waiting}
                    icon={<Users className="w-5 h-5" />}
                    className="border-l-4 border-amber-500"
                />
                <MetricCard
                    title="Closed Today"
                    value={stats.closed_today}
                    icon={<CheckCircle className="w-5 h-5" />}
                    className="border-l-4 border-gray-500"
                />
            </div>

            {/* Request List - Default to NOT CLOSED (hide closed requests) */}
            <RequestList
                showFilters={true}
                showAssignee={true}
                defaultStatus="not_closed"
                linkPrefix="/admin/request"
            />
        </div>
    );
}

