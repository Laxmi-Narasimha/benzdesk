// ============================================================================
// Admin Performance Page
// Detailed metrics per admin — uses pending_closure events as "admin done" time
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import {
    Users,
    Clock,
    TrendingUp,
    Award,
    UserCheck,
} from 'lucide-react';
import { Card, CardHeader, MetricCard, Skeleton } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { FRESH_START_DATE, USER_NAMES } from '@/types';

interface AdminStat {
    admin_id: string;
    admin_email: string;
    display_name: string;
    open_count: number;
    in_progress_count: number;
    waiting_count: number;
    total_active: number;
    pending_closure_last_30: number;
    avg_resolution_hours: number | null;
}

function getDisplayName(email: string) {
    return USER_NAMES[email.toLowerCase()] || email.split('@')[0];
}

export default function AdminPerformancePage() {
    const [loading, setLoading] = useState(true);
    const [adminStats, setAdminStats] = useState<AdminStat[]>([]);

    useEffect(() => {
        async function fetchData() {
            try {
                const supabase = getSupabaseClient();

                // 1. Fetch all active admins
                const { data: adminRoles } = await supabase
                    .from('user_roles')
                    .select('user_id')
                    .eq('role', 'accounts_admin')
                    .eq('is_active', true);

                if (!adminRoles || adminRoles.length === 0) {
                    setLoading(false);
                    return;
                }

                // 2. Fetch backlog (assigned requests per admin that are not closed)
                const { data: backlog } = await supabase
                    .from('v_admin_backlog')
                    .select('*');

                // 3. Fetch pending_closure events from last 30 days (this is when admin "finishes" their work)
                const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString();
                const { data: closureEvents } = await supabase
                    .from('request_events')
                    .select('actor_id, created_at, request_id, new_data')
                    .eq('event_type', 'status_changed')
                    .gte('created_at', thirtyDaysAgo);

                // Only keep events where new status = pending_closure or closed
                const adminClosures = (closureEvents || []).filter(
                    (e) =>
                        e.new_data?.status === 'pending_closure' ||
                        e.new_data?.status === 'closed'
                );

                // 4. Fetch resolution times: when admin set pending_closure, compute hours since created_at
                const { data: requests } = await supabase
                    .from('requests')
                    .select('id, created_at')
                    .gte('created_at', FRESH_START_DATE);

                const requestCreatedMap: Record<string, string> = {};
                (requests || []).forEach((r) => {
                    requestCreatedMap[r.id] = r.created_at;
                });

                // 5. Fetch admin emails (from auth.users proxy via v_admin_backlog)
                const backlogMap: Record<string, any> = {};
                (backlog || []).forEach((b) => {
                    backlogMap[b.admin_id] = b;
                });

                // Build per-admin closure stats
                const closureByAdmin: Record<string, { count: number; totalHours: number }> = {};
                adminClosures.forEach((event) => {
                    if (!event.actor_id) return;
                    const createdAt = requestCreatedMap[event.request_id];
                    if (!createdAt) return;
                    const hours =
                        (new Date(event.created_at).getTime() -
                            new Date(createdAt).getTime()) /
                        3600000;
                    // Only count meaningful resolution times (not outliers)
                    if (hours > 0 && hours <= 500) {
                        if (!closureByAdmin[event.actor_id]) {
                            closureByAdmin[event.actor_id] = { count: 0, totalHours: 0 };
                        }
                        closureByAdmin[event.actor_id].count++;
                        closureByAdmin[event.actor_id].totalHours += hours;
                    }
                });

                // Combine into final stats
                const stats: AdminStat[] = Object.entries(backlogMap).map(([adminId, bl]) => {
                    const closures = closureByAdmin[adminId];
                    return {
                        admin_id: adminId,
                        admin_email: bl.admin_email,
                        display_name: getDisplayName(bl.admin_email),
                        open_count: bl.open_count || 0,
                        in_progress_count: bl.in_progress_count || 0,
                        waiting_count: bl.waiting_count || 0,
                        total_active: bl.total_active || 0,
                        pending_closure_last_30: closures?.count || 0,
                        avg_resolution_hours: closures
                            ? closures.totalHours / closures.count
                            : null,
                    };
                });

                // Also add admins not in backlog map (they have no assigned requests)
                adminRoles.forEach((role) => {
                    if (!backlogMap[role.user_id]) {
                        const closures = closureByAdmin[role.user_id];
                        stats.push({
                            admin_id: role.user_id,
                            admin_email: role.user_id,
                            display_name: role.user_id,
                            open_count: 0,
                            in_progress_count: 0,
                            waiting_count: 0,
                            total_active: 0,
                            pending_closure_last_30: closures?.count || 0,
                            avg_resolution_hours: closures
                                ? closures.totalHours / closures.count
                                : null,
                        });
                    }
                });

                setAdminStats(stats);
            } catch (err) {
                console.error('Error fetching admin performance data:', err);
            } finally {
                setLoading(false);
            }
        }

        fetchData();
    }, []);

    const totalResolved = adminStats.reduce((s, a) => s + a.pending_closure_last_30, 0);
    const adminsWithData = adminStats.filter((a) => a.avg_resolution_hours !== null);
    const avgResolution =
        adminsWithData.length > 0
            ? adminsWithData.reduce((s, a) => s + (a.avg_resolution_hours || 0), 0) /
            adminsWithData.length
            : 0;

    const sorted = [...adminStats].sort(
        (a, b) => b.pending_closure_last_30 - a.pending_closure_last_30
    );

    return (
        <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <div>
                <h1 className="text-2xl font-bold text-dark-50">Admin Performance</h1>
                <p className="text-dark-400 mt-1">
                    Individual admin metrics and workload distribution
                </p>
            </div>

            {/* Summary Stats */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <MetricCard
                    title="Total Admins"
                    value={loading ? '-' : adminStats.length}
                    icon={<Users className="w-5 h-5" />}
                />
                <MetricCard
                    title="Resolved (30 days)"
                    value={loading ? '-' : totalResolved}
                    icon={<TrendingUp className="w-5 h-5" />}
                />
                <MetricCard
                    title="Avg Resolution (hrs)"
                    value={loading ? '-' : avgResolution.toFixed(1)}
                    icon={<Clock className="w-5 h-5" />}
                />
            </div>

            {/* Current Workload — assigned requests per admin */}
            <Card padding="lg">
                <CardHeader
                    title="Current Workload"
                    description="Active requests assigned to each admin"
                />
                {loading ? (
                    <div className="space-y-3 mt-4">
                        {[1, 2, 3].map((i) => (
                            <Skeleton key={i} height={80} variant="rounded" />
                        ))}
                    </div>
                ) : adminStats.length === 0 ? (
                    <div className="text-center py-8 text-dark-500">No admin data available</div>
                ) : (
                    <div className="mt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                        {adminStats.map((admin) => (
                            <div
                                key={admin.admin_id}
                                className="p-4 rounded-xl bg-dark-800/50 border border-dark-700/50"
                            >
                                <div className="flex items-center gap-3 mb-4">
                                    <div className="w-10 h-10 rounded-full bg-primary-500/20 flex items-center justify-center text-primary-400 font-semibold">
                                        {admin.display_name?.charAt(0).toUpperCase() || 'A'}
                                    </div>
                                    <div className="flex-1 min-w-0">
                                        <p className="font-medium text-dark-100 truncate">
                                            {admin.display_name}
                                        </p>
                                        <p className="text-xs text-dark-500 truncate">{admin.admin_email}</p>
                                        <p className="text-xs text-dark-500">{admin.total_active} active</p>
                                    </div>
                                </div>

                                <div className="grid grid-cols-3 gap-2 text-center">
                                    <div className="p-2 rounded-lg bg-green-500/10">
                                        <p className="text-lg font-bold text-green-400">{admin.open_count}</p>
                                        <p className="text-xs text-dark-500">Open</p>
                                    </div>
                                    <div className="p-2 rounded-lg bg-blue-500/10">
                                        <p className="text-lg font-bold text-blue-400">{admin.in_progress_count}</p>
                                        <p className="text-xs text-dark-500">In Prog</p>
                                    </div>
                                    <div className="p-2 rounded-lg bg-amber-500/10">
                                        <p className="text-lg font-bold text-amber-400">{admin.waiting_count}</p>
                                        <p className="text-xs text-dark-500">Waiting</p>
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                )}
            </Card>

            {/* Throughput — based on pending_closure events */}
            <Card padding="lg">
                <CardHeader
                    title="Throughput (Last 30 Days)"
                    description="Requests resolved per admin (counted when admin sets Pending Closure)"
                />
                {loading ? (
                    <Skeleton height={200} variant="rounded" className="mt-4" />
                ) : (
                    <div className="mt-4 overflow-x-auto">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Admin</th>
                                    <th>Resolved</th>
                                    <th>Avg Resolution (hrs)</th>
                                </tr>
                            </thead>
                            <tbody>
                                {sorted.map((t, i) => (
                                    <tr key={t.admin_id}>
                                        <td className="flex items-center gap-2">
                                            {i === 0 && t.pending_closure_last_30 > 0 && (
                                                <Award className="w-4 h-4 text-amber-400" />
                                            )}
                                            <div>
                                                <span className="font-medium">{t.display_name}</span>
                                                <div className="text-xs text-dark-500">{t.admin_email}</div>
                                            </div>
                                        </td>
                                        <td>
                                            <span className="font-bold text-primary-400">
                                                {t.pending_closure_last_30}
                                            </span>
                                        </td>
                                        <td>
                                            {t.avg_resolution_hours != null
                                                ? `${t.avg_resolution_hours.toFixed(1)}h`
                                                : '-'}
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
