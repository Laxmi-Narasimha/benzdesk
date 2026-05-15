// ============================================================================
// Sales Manager — Pending Approvals Queue
// Full list of requests awaiting manager review
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { ClipboardList, IndianRupee } from 'lucide-react';
import { Card, CardHeader, Skeleton, StatusBadge, PriorityBadge } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { useAuth } from '@/lib/AuthContext';
import { formatDistanceToNow } from 'date-fns';
import { REQUEST_CATEGORY_LABELS } from '@/types';

export default function SalesManagerQueuePage() {
    const { user } = useAuth();
    const router = useRouter();
    const [loading, setLoading] = useState(true);
    const [requests, setRequests] = useState<any[]>([]);

    useEffect(() => {
        if (!user) return;
        async function fetchQueue() {
            try {
                const supabase = getSupabaseClient();
                const { data } = await supabase
                    .from('v_manager_queue')
                    .select('*')
                    .eq('manager_user_id', user!.id)
                    .order('priority', { ascending: true })
                    .order('created_at', { ascending: true });

                setRequests(data || []);
            } catch (err) {
                console.error('Error fetching queue:', err);
            } finally {
                setLoading(false);
            }
        }
        fetchQueue();
    }, [user]);

    return (
        <div className="max-w-5xl mx-auto space-y-6">
            <div>
                <h1 className="text-2xl font-bold text-dark-50">Pending Approvals</h1>
                <p className="text-dark-400 mt-1">All requests from your team waiting for your review</p>
            </div>

            <Card padding="lg">
                <CardHeader
                    title={`${loading ? '...' : requests.length} Requests Pending`}
                />
                {loading ? (
                    <div className="space-y-3 mt-4">
                        {[1, 2, 3, 4].map(i => <Skeleton key={i} height={64} variant="rounded" />)}
                    </div>
                ) : requests.length === 0 ? (
                    <div className="text-center py-16">
                        <ClipboardList className="w-14 h-14 text-dark-700 mx-auto mb-4" />
                        <p className="text-dark-400 font-medium">No pending approvals</p>
                        <p className="text-dark-600 text-sm mt-1">Your team hasn&apos;t submitted any requests yet, or all are already approved.</p>
                    </div>
                ) : (
                    <div className="mt-4 overflow-x-auto">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Request</th>
                                    <th>From</th>
                                    <th>Category</th>
                                    <th>Amount</th>
                                    <th>Priority</th>
                                    <th>Submitted</th>
                                </tr>
                            </thead>
                            <tbody>
                                {requests.map((req) => (
                                    <tr
                                        key={req.id}
                                        className="cursor-pointer hover:bg-dark-800/50 transition-colors"
                                        onClick={() => router.push(`/sales-manager/request?id=${req.id}`)}
                                    >
                                        <td className="font-medium text-dark-100 max-w-xs truncate">{req.title}</td>
                                        <td className="text-dark-400">{req.requester_email?.split('@')[0]}</td>
                                        <td className="text-dark-400 text-sm">
                                            {REQUEST_CATEGORY_LABELS[req.category as keyof typeof REQUEST_CATEGORY_LABELS] || req.category}
                                        </td>
                                        <td>
                                            {req.amount ? (
                                                <span className="text-green-400 font-semibold text-sm">
                                                    ₹{req.amount.toLocaleString('en-IN')}
                                                </span>
                                            ) : (
                                                <span className="text-dark-600 text-xs">—</span>
                                            )}
                                        </td>
                                        <td><PriorityBadge priority={req.priority} size="sm" /></td>
                                        <td className="text-dark-500 text-xs">
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
