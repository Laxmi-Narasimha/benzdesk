// ============================================================================
// Admin Performance Page
// Detailed metrics per admin
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { clsx } from 'clsx';
import {
    Users,
    Clock,
    TrendingUp,
    Award,
    BarChart3,
} from 'lucide-react';
import { Card, CardHeader, MetricCard, Skeleton } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';

export default function AdminPerformancePage() {
    const [loading, setLoading] = useState(true);
    const [backlog, setBacklog] = useState<any[]>([]);
    const [throughput, setThroughput] = useState<any[]>([]);

    useEffect(() => {
        async function fetchData() {
            try {
                const supabase = getSupabaseClient();

                const { data: bl } = await supabase
                    .from('v_admin_backlog')
                    .select('*');

                if (bl) setBacklog(bl);

                const { data: tp } = await supabase
                    .from('v_admin_throughput')
                    .select('*');

                if (tp) setThroughput(tp);
            } catch (err) {
                console.error('Error fetching data:', err);
            } finally {
                setLoading(false);
            }
        }

        fetchData();
    }, []);

    // Aggregate stats
    const totalClosed = throughput.reduce((sum, t) => sum + (t.closed_last_30_days || 0), 0);
    const avgResolution = throughput.length > 0
        ? throughput.reduce((sum, t) => sum + (t.avg_resolution_hours || 0), 0) / throughput.length
        : 0;

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
                    value={loading ? '-' : backlog.length}
                    icon={<Users className="w-5 h-5" />}
                />
                <MetricCard
                    title="Closed (30 days)"
                    value={loading ? '-' : totalClosed}
                    icon={<TrendingUp className="w-5 h-5" />}
                />
                <MetricCard
                    title="Avg Resolution (hrs)"
                    value={loading ? '-' : avgResolution.toFixed(1)}
                    icon={<Clock className="w-5 h-5" />}
                />
            </div>

            {/* Current Backlog */}
            <Card padding="lg">
                <CardHeader title="Current Workload" description="Active requests per admin" />
                {loading ? (
                    <div className="space-y-3 mt-4">
                        {[1, 2, 3].map((i) => (
                            <Skeleton key={i} height={80} variant="rounded" />
                        ))}
                    </div>
                ) : backlog.length === 0 ? (
                    <div className="text-center py-8 text-dark-500">
                        No admin data available
                    </div>
                ) : (
                    <div className="mt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                        {backlog.map((admin) => (
                            <div
                                key={admin.admin_id}
                                className="p-4 rounded-xl bg-dark-800/50 border border-dark-700/50"
                            >
                                <div className="flex items-center gap-3 mb-4">
                                    <div className="w-10 h-10 rounded-full bg-primary-500/20 flex items-center justify-center text-primary-400 font-semibold">
                                        {admin.admin_email?.charAt(0).toUpperCase() || 'A'}
                                    </div>
                                    <div className="flex-1 min-w-0">
                                        <p className="font-medium text-dark-100 truncate">{admin.admin_email}</p>
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

                                {admin.avg_age_hours && (
                                    <p className="text-xs text-dark-500 mt-3 text-center">
                                        Avg age: {admin.avg_age_hours.toFixed(1)} hours
                                    </p>
                                )}
                            </div>
                        ))}
                    </div>
                )}
            </Card>

            {/* Throughput */}
            <Card padding="lg">
                <CardHeader title="Throughput (Last 30 Days)" description="Requests closed per admin" />
                {loading ? (
                    <Skeleton height={200} variant="rounded" className="mt-4" />
                ) : throughput.length === 0 ? (
                    <div className="text-center py-8 text-dark-500">
                        No throughput data available
                    </div>
                ) : (
                    <div className="mt-4 overflow-x-auto">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Admin</th>
                                    <th>Closed</th>
                                    <th>Avg Resolution (hrs)</th>
                                </tr>
                            </thead>
                            <tbody>
                                {throughput
                                    .sort((a, b) => (b.closed_last_30_days || 0) - (a.closed_last_30_days || 0))
                                    .map((t, i) => (
                                        <tr key={t.admin_id}>
                                            <td className="flex items-center gap-2">
                                                {i === 0 && t.closed_last_30_days > 0 && (
                                                    <Award className="w-4 h-4 text-amber-400" />
                                                )}
                                                <span className="font-medium">{t.admin_email}</span>
                                            </td>
                                            <td>
                                                <span className="font-bold text-primary-400">{t.closed_last_30_days}</span>
                                            </td>
                                            <td>
                                                {t.avg_resolution_hours ? t.avg_resolution_hours.toFixed(1) : '-'}
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
