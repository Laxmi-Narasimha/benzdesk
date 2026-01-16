// ============================================================================
// Director Dashboard
// Executive overview with key metrics
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { clsx } from 'clsx';
import {
    BarChart3,
    Clock,
    Users,
    AlertTriangle,
    CheckCircle,
    TrendingUp,
    ArrowRight,
    FileText,
} from 'lucide-react';
import { Card, CardHeader, MetricCard, Button, Skeleton, StatusBadge, PriorityBadge } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { formatDistanceToNow } from 'date-fns';
import type { Priority } from '@/types';

// ============================================================================
// Component
// ============================================================================

export default function DirectorDashboardPage() {
    const [loading, setLoading] = useState(true);
    const [stats, setStats] = useState({
        total_open: 0,
        in_progress: 0,
        waiting: 0,
        closed_30d: 0,
        unassigned: 0,
    });
    const [adminBacklog, setAdminBacklog] = useState<any[]>([]);
    const [staleRequests, setStaleRequests] = useState<any[]>([]);
    const [recentRequests, setRecentRequests] = useState<any[]>([]);

    useEffect(() => {
        async function fetchDashboard() {
            try {
                const supabase = getSupabaseClient();

                // Fetch overview stats
                const { data: overview } = await supabase
                    .from('v_requests_overview')
                    .select('*');

                if (overview) {
                    const statsMap: Record<string, number> = {};
                    overview.forEach((row: any) => {
                        statsMap[row.status] = row.count;
                    });
                    setStats({
                        total_open: (statsMap['open'] || 0) + (statsMap['in_progress'] || 0) + (statsMap['waiting_on_requester'] || 0),
                        in_progress: statsMap['in_progress'] || 0,
                        waiting: statsMap['waiting_on_requester'] || 0,
                        closed_30d: statsMap['closed'] || 0,
                        unassigned: 0,
                    });
                }

                // Fetch admin backlog
                const { data: backlog } = await supabase
                    .from('v_admin_backlog')
                    .select('*');

                if (backlog) {
                    setAdminBacklog(backlog);
                }

                // Fetch stale requests
                const { data: stale } = await supabase
                    .from('v_stale_requests')
                    .select('*')
                    .limit(5);

                if (stale) {
                    setStaleRequests(stale);
                }

                // Fetch unassigned count
                const { data: unassigned } = await supabase
                    .from('v_unassigned_requests')
                    .select('*');

                if (unassigned) {
                    setStats(prev => ({ ...prev, unassigned: unassigned.length }));
                }

                // Fetch recent requests
                const { data: recent } = await supabase
                    .from('requests')
                    .select('*')
                    .order('created_at', { ascending: false })
                    .limit(5);

                if (recent) {
                    setRecentRequests(recent);
                }
            } catch (err) {
                console.error('Error fetching dashboard:', err);
            } finally {
                setLoading(false);
            }
        }

        fetchDashboard();
    }, []);

    return (
        <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <div>
                <h1 className="text-2xl font-bold text-dark-50">Director Dashboard</h1>
                <p className="text-dark-400 mt-1">
                    Executive overview of accounts requests
                </p>
            </div>

            {/* Key Metrics */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
                <MetricCard
                    title="Total Active"
                    value={loading ? '-' : stats.total_open}
                    icon={<FileText className="w-5 h-5" />}
                />
                <MetricCard
                    title="In Progress"
                    value={loading ? '-' : stats.in_progress}
                    icon={<Clock className="w-5 h-5" />}
                />
                <MetricCard
                    title="Waiting"
                    value={loading ? '-' : stats.waiting}
                    icon={<AlertTriangle className="w-5 h-5" />}
                />
                <MetricCard
                    title="Unassigned"
                    value={loading ? '-' : stats.unassigned}
                    icon={<Users className="w-5 h-5" />}
                    className={stats.unassigned > 0 ? 'border-l-4 border-red-500' : ''}
                />
                <MetricCard
                    title="Closed (30d)"
                    value={loading ? '-' : stats.closed_30d}
                    icon={<CheckCircle className="w-5 h-5" />}
                />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* Admin Workload */}
                <Card padding="lg">
                    <CardHeader
                        title="Admin Workload"
                        action={
                            <Link href="/director/admin-performance">
                                <Button variant="ghost" size="sm" rightIcon={<ArrowRight className="w-4 h-4" />}>
                                    View Details
                                </Button>
                            </Link>
                        }
                    />
                    {loading ? (
                        <div className="space-y-3 mt-4">
                            {[1, 2, 3].map((i) => (
                                <Skeleton key={i} height={48} variant="rounded" />
                            ))}
                        </div>
                    ) : adminBacklog.length === 0 ? (
                        <div className="text-center py-8 text-dark-500">
                            No admin data available
                        </div>
                    ) : (
                        <div className="mt-4 space-y-3">
                            {adminBacklog.map((admin) => (
                                <div
                                    key={admin.admin_id}
                                    className="flex items-center justify-between p-3 rounded-lg bg-dark-800/50"
                                >
                                    <div className="flex items-center gap-3">
                                        <div className="w-8 h-8 rounded-full bg-primary-500/20 flex items-center justify-center text-primary-400 text-sm font-semibold">
                                            {admin.admin_email?.charAt(0).toUpperCase() || 'A'}
                                        </div>
                                        <div>
                                            <p className="text-sm font-medium text-dark-200">
                                                {admin.admin_email}
                                            </p>
                                            <p className="text-xs text-dark-500">
                                                {admin.total_active} active requests
                                            </p>
                                        </div>
                                    </div>
                                    <div className="flex items-center gap-2">
                                        <span className="px-2 py-1 rounded bg-green-500/20 text-green-400 text-xs">
                                            {admin.open_count} open
                                        </span>
                                        <span className="px-2 py-1 rounded bg-blue-500/20 text-blue-400 text-xs">
                                            {admin.in_progress_count} prog
                                        </span>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </Card>

                {/* Stale Requests */}
                <Card padding="lg">
                    <CardHeader
                        title="Stale Requests"
                        description="No activity in 3+ days"
                        action={
                            <Link href="/director/stale">
                                <Button variant="ghost" size="sm" rightIcon={<ArrowRight className="w-4 h-4" />}>
                                    View All
                                </Button>
                            </Link>
                        }
                    />
                    {loading ? (
                        <div className="space-y-3 mt-4">
                            {[1, 2, 3].map((i) => (
                                <Skeleton key={i} height={48} variant="rounded" />
                            ))}
                        </div>
                    ) : staleRequests.length === 0 ? (
                        <div className="text-center py-8 text-dark-500">
                            <CheckCircle className="w-8 h-8 mx-auto mb-2 text-green-500" />
                            No stale requests
                        </div>
                    ) : (
                        <div className="mt-4 space-y-2">
                            {staleRequests.map((req) => (
                                <Link
                                    key={req.id}
                                    href={`/director/request/${req.id}`}
                                    className="block p-3 rounded-lg bg-dark-800/50 hover:bg-dark-700/50 transition-colors"
                                >
                                    <div className="flex items-center justify-between">
                                        <p className="text-sm font-medium text-dark-200 truncate flex-1 mr-4">
                                            {req.title}
                                        </p>
                                        <span className="text-xs text-red-400">
                                            {req.days_since_activity}d stale
                                        </span>
                                    </div>
                                    <div className="flex items-center gap-2 mt-1">
                                        <StatusBadge status={req.status} size="sm" />
                                    </div>
                                </Link>
                            ))}
                        </div>
                    )}
                </Card>
            </div>

            {/* Recent Requests */}
            <Card padding="lg">
                <CardHeader
                    title="Recent Requests"
                    action={
                        <Link href="/admin/queue">
                            <Button variant="ghost" size="sm" rightIcon={<ArrowRight className="w-4 h-4" />}>
                                View All
                            </Button>
                        </Link>
                    }
                />
                {loading ? (
                    <div className="space-y-3 mt-4">
                        {[1, 2, 3, 4, 5].map((i) => (
                            <Skeleton key={i} height={60} variant="rounded" />
                        ))}
                    </div>
                ) : (
                    <div className="mt-4 overflow-x-auto">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Title</th>
                                    <th>Status</th>
                                    <th>Priority</th>
                                    <th>Created</th>
                                </tr>
                            </thead>
                            <tbody>
                                {recentRequests.map((req) => (
                                    <tr key={req.id}>
                                        <td>
                                            <Link
                                                href={`/director/request/${req.id}`}
                                                className="text-dark-100 hover:text-primary-400 transition-colors"
                                            >
                                                {req.title}
                                            </Link>
                                        </td>
                                        <td>
                                            <StatusBadge status={req.status} size="sm" />
                                        </td>
                                        <td>
                                            <PriorityBadge priority={req.priority as Priority} size="sm" />
                                        </td>
                                        <td className="text-dark-400">
                                            {formatDistanceToNow(new Date(req.created_at), { addSuffix: true })}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </Card>
        </div>
    );
}
