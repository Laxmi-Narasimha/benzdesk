// ============================================================================
// Stale Requests Page
// Requests with no recent activity
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { clsx } from 'clsx';
import { formatDistanceToNow } from 'date-fns';
import {
    AlertTriangle,
    Clock,
    User,
    RefreshCw,
    ExternalLink,
} from 'lucide-react';
import { Card, CardHeader, MetricCard, Button, StatusBadge, PriorityBadge, Skeleton } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import type { Priority } from '@/types';

export default function StaleRequestsPage() {
    const [loading, setLoading] = useState(true);
    const [staleRequests, setStaleRequests] = useState<any[]>([]);

    const fetchData = async () => {
        setLoading(true);
        try {
            const supabase = getSupabaseClient();

            const { data } = await supabase
                .from('v_stale_requests')
                .select('*')
                .order('days_since_activity', { ascending: false });

            if (data) setStaleRequests(data);
        } catch (err) {
            console.error('Error fetching stale requests:', err);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchData();
    }, []);

    // Group by severity
    const critical = staleRequests.filter((r) => r.days_since_activity >= 7);
    const warning = staleRequests.filter((r) => r.days_since_activity >= 5 && r.days_since_activity < 7);
    const attention = staleRequests.filter((r) => r.days_since_activity >= 3 && r.days_since_activity < 5);

    return (
        <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold text-dark-50">Stale Requests</h1>
                    <p className="text-dark-400 mt-1">
                        Requests with no activity for 3+ days
                    </p>
                </div>
                <Button
                    variant="secondary"
                    onClick={fetchData}
                    leftIcon={<RefreshCw className={clsx('w-4 h-4', loading && 'animate-spin')} />}
                    disabled={loading}
                >
                    Refresh
                </Button>
            </div>

            {/* Summary */}
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
                <MetricCard
                    title="Total Stale"
                    value={loading ? '-' : staleRequests.length}
                    icon={<AlertTriangle className="w-5 h-5" />}
                />
                <MetricCard
                    title="Critical (7+ days)"
                    value={loading ? '-' : critical.length}
                    icon={<AlertTriangle className="w-5 h-5" />}
                    className={critical.length > 0 ? 'border-l-4 border-red-500' : ''}
                />
                <MetricCard
                    title="Warning (5-7 days)"
                    value={loading ? '-' : warning.length}
                    icon={<Clock className="w-5 h-5" />}
                    className={warning.length > 0 ? 'border-l-4 border-amber-500' : ''}
                />
                <MetricCard
                    title="Attention (3-5 days)"
                    value={loading ? '-' : attention.length}
                    icon={<Clock className="w-5 h-5" />}
                />
            </div>

            {/* Stale List */}
            <Card padding="lg">
                <CardHeader title="All Stale Requests" />
                {loading ? (
                    <div className="space-y-3 mt-4">
                        {[1, 2, 3, 4, 5].map((i) => (
                            <Skeleton key={i} height={80} variant="rounded" />
                        ))}
                    </div>
                ) : staleRequests.length === 0 ? (
                    <div className="text-center py-12 text-dark-500">
                        <AlertTriangle className="w-12 h-12 mx-auto mb-4 text-green-500" />
                        <p className="text-lg font-medium text-dark-300">No stale requests!</p>
                        <p className="text-sm mt-1">All requests have recent activity.</p>
                    </div>
                ) : (
                    <div className="mt-4 space-y-3">
                        {staleRequests.map((req) => {
                            const severity =
                                req.days_since_activity >= 7
                                    ? 'critical'
                                    : req.days_since_activity >= 5
                                        ? 'warning'
                                        : 'attention';

                            return (
                                <Link
                                    key={req.id}
                                    href={`/director/request/${req.id}`}
                                    className="block"
                                >
                                    <div
                                        className={clsx(
                                            'p-4 rounded-xl border transition-all hover:shadow-lg',
                                            severity === 'critical' && 'bg-red-500/5 border-red-500/30 hover:border-red-500/50',
                                            severity === 'warning' && 'bg-amber-500/5 border-amber-500/30 hover:border-amber-500/50',
                                            severity === 'attention' && 'bg-dark-800/50 border-dark-700/50 hover:border-dark-600/50'
                                        )}
                                    >
                                        <div className="flex items-start justify-between gap-4">
                                            <div className="flex-1 min-w-0">
                                                <div className="flex items-center gap-3 mb-2">
                                                    <h3 className="font-semibold text-dark-100 truncate">
                                                        {req.title}
                                                    </h3>
                                                    <StatusBadge status={req.status} size="sm" />
                                                    <PriorityBadge priority={req.priority as Priority} size="sm" />
                                                </div>

                                                <div className="flex items-center gap-4 text-sm text-dark-400">
                                                    <span className="flex items-center gap-1">
                                                        <Clock className="w-3.5 h-3.5" />
                                                        {req.days_since_activity} days stale
                                                    </span>
                                                    <span className="flex items-center gap-1">
                                                        <User className="w-3.5 h-3.5" />
                                                        {req.assigned_to ? 'Assigned' : 'Unassigned'}
                                                    </span>
                                                    <span>
                                                        Last activity: {formatDistanceToNow(new Date(req.last_activity_at), { addSuffix: true })}
                                                    </span>
                                                </div>
                                            </div>

                                            <div
                                                className={clsx(
                                                    'flex-shrink-0 px-3 py-1.5 rounded-full text-xs font-semibold',
                                                    severity === 'critical' && 'bg-red-500/20 text-red-400',
                                                    severity === 'warning' && 'bg-amber-500/20 text-amber-400',
                                                    severity === 'attention' && 'bg-blue-500/20 text-blue-400'
                                                )}
                                            >
                                                {severity === 'critical' ? 'Critical' : severity === 'warning' ? 'Warning' : 'Needs Attention'}
                                            </div>
                                        </div>
                                    </div>
                                </Link>
                            );
                        })}
                    </div>
                )}
            </Card>
        </div>
    );
}
