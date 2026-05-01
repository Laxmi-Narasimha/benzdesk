// ============================================================================
// Sales Manager Dashboard
// Overview of pending approvals and team activity
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { ClipboardList, Users, Clock, CheckCircle, IndianRupee } from 'lucide-react';
import { Card, CardHeader, MetricCard, Skeleton, StatusBadge, PriorityBadge } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import { formatDistanceToNow } from 'date-fns';
import { useRouter } from 'next/navigation';
import { REQUEST_CATEGORY_LABELS } from '@/types';

export default function SalesManagerDashboard() {
    const { user } = useAuth();
    const router = useRouter();
    const [loading, setLoading] = useState(true);
    const [pendingRequests, setPendingRequests] = useState<any[]>([]);
    const [teamMembers, setTeamMembers] = useState<any[]>([]);
    const [stats, setStats] = useState({
        pending: 0,
        approvedThisMonth: 0,
        totalAmount: 0,
        teamCount: 0,
    });

    useEffect(() => {
        if (!user) return;
        async function fetchData() {
            try {
                const supabase = getSupabaseClient();

                // Fetch pending approvals from the manager queue view
                const { data: queue } = await supabase
                    .from('v_manager_queue')
                    .select('*')
                    .eq('manager_user_id', user!.id)
                    .order('priority', { ascending: true })
                    .order('created_at', { ascending: true })
                    .limit(10);

                setPendingRequests(queue || []);

                // Fetch team members
                const { data: team } = await supabase
                    .from('manager_team')
                    .select('member_user_id')
                    .eq('manager_user_id', user!.id);

                setTeamMembers(team || []);

                // Fetch approved this month
                const startOfMonth = new Date();
                startOfMonth.setDate(1);
                startOfMonth.setHours(0, 0, 0, 0);

                const { data: approved } = await supabase
                    .from('requests')
                    .select('amount, manager_adjusted_amount')
                    .eq('manager_approved_by', user!.id)
                    .gte('manager_approved_at', startOfMonth.toISOString());

                const totalAmount = (approved || []).reduce((sum, r) => {
                    return sum + (r.manager_adjusted_amount || r.amount || 0);
                }, 0);

                setStats({
                    pending: queue?.length || 0,
                    approvedThisMonth: approved?.length || 0,
                    totalAmount,
                    teamCount: team?.length || 0,
                });
            } catch (err) {
                console.error('Error fetching manager dashboard:', err);
            } finally {
                setLoading(false);
            }
        }
        fetchData();
    }, [user]);

    return (
        <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <div>
                <h1 className="text-2xl font-bold text-dark-50">Sales Manager Dashboard</h1>
                <p className="text-dark-400 mt-1">
                    Review and approve your team&apos;s requests before they go to Accounts
                </p>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                <MetricCard
                    title="Pending Approval"
                    value={loading ? '-' : stats.pending}
                    icon={<Clock className="w-5 h-5" />}
                    className={stats.pending > 0 ? 'border-l-4 border-amber-500' : ''}
                />
                <MetricCard
                    title="Approved This Month"
                    value={loading ? '-' : stats.approvedThisMonth}
                    icon={<CheckCircle className="w-5 h-5" />}
                />
                <MetricCard
                    title="Amount Approved (₹)"
                    value={loading ? '-' : `₹${stats.totalAmount.toLocaleString('en-IN')}`}
                    icon={<IndianRupee className="w-5 h-5" />}
                />
                <MetricCard
                    title="Team Members"
                    value={loading ? '-' : stats.teamCount}
                    icon={<Users className="w-5 h-5" />}
                />
            </div>

            {/* Pending Approval Queue */}
            <Card padding="lg">
                <CardHeader
                    title="Pending Approvals"
                    description="Requests from your team waiting for your review"
                />
                {loading ? (
                    <div className="space-y-3 mt-4">
                        {[1, 2, 3].map(i => (
                            <Skeleton key={i} height={64} variant="rounded" />
                        ))}
                    </div>
                ) : pendingRequests.length === 0 ? (
                    <div className="text-center py-12">
                        <ClipboardList className="w-12 h-12 text-dark-700 mx-auto mb-3" />
                        <p className="text-dark-400">No pending approvals — all caught up! 🎉</p>
                    </div>
                ) : (
                    <div className="mt-4 space-y-3">
                        {pendingRequests.map((req) => (
                            <button
                                key={req.id}
                                onClick={() => router.push(`/sales-manager/request?id=${req.id}`)}
                                className="w-full text-left p-4 rounded-xl bg-dark-800/50 border border-dark-700/50 hover:border-primary-500/50 hover:bg-dark-800 transition-all group"
                            >
                                <div className="flex items-start justify-between gap-3">
                                    <div className="flex-1 min-w-0">
                                        <p className="font-medium text-dark-100 truncate group-hover:text-primary-300 transition-colors">
                                            {req.title}
                                        </p>
                                        <div className="flex items-center gap-2 mt-1 flex-wrap">
                                            <span className="text-xs text-dark-500">
                                                {req.requester_email?.split('@')[0]}
                                            </span>
                                            <span className="text-xs text-dark-700">·</span>
                                            <span className="text-xs text-dark-500">
                                                {REQUEST_CATEGORY_LABELS[req.category as keyof typeof REQUEST_CATEGORY_LABELS] || req.category}
                                            </span>
                                            <span className="text-xs text-dark-700">·</span>
                                            <span className="text-xs text-dark-500">
                                                {formatDistanceToNow(new Date(req.created_at), { addSuffix: true })}
                                            </span>
                                        </div>
                                    </div>
                                    <div className="flex items-center gap-2 flex-shrink-0">
                                        {req.amount && (
                                            <span className="text-sm font-semibold text-green-400">
                                                ₹{req.amount.toLocaleString('en-IN')}
                                            </span>
                                        )}
                                        <PriorityBadge priority={req.priority} size="sm" />
                                    </div>
                                </div>
                            </button>
                        ))}
                    </div>
                )}
            </Card>
        </div>
    );
}
