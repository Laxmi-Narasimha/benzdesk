// ============================================================================
// SLA Tracking Page
// First response and resolution time metrics
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { clsx } from 'clsx';
import {
    Clock,
    AlertTriangle,
    CheckCircle,
    TrendingUp,
} from 'lucide-react';
import { Card, CardHeader, MetricCard, Skeleton, StatusBadge, Badge } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { FRESH_START_DATE } from '@/types';

// SLA threshold in hours for first response (medium priority default)
const FIRST_RESPONSE_SLA_HOURS = 8;

// Filter out outliers: requests older than this were before launch and skew metrics
const MAX_MEANINGFUL_HOURS = 500;

export default function SLATrackingPage() {
    const [loading, setLoading] = useState(true);
    const [firstResponse, setFirstResponse] = useState<any[]>([]);
    const [timeToClose, setTimeToClose] = useState<any[]>([]);

    useEffect(() => {
        async function fetchData() {
            try {
                const supabase = getSupabaseClient();

                // First response — filter to post-launch requests only
                const { data: fr } = await supabase
                    .from('v_sla_first_response')
                    .select('*')
                    .gte('created_at', FRESH_START_DATE)
                    .order('created_at', { ascending: false })
                    .limit(50);

                if (fr) {
                    // Filter out extreme outliers (>500h = essentially stale pre-launch data)
                    setFirstResponse(
                        fr.filter((r) => !r.response_time_hours || r.response_time_hours <= MAX_MEANINGFUL_HOURS)
                    );
                }

                // Time to close (admin resolution = pending_closure time)
                const { data: ttc } = await supabase
                    .from('v_sla_time_to_close')
                    .select('*')
                    .gte('created_at', FRESH_START_DATE)
                    .order('admin_resolved_at', { ascending: false })
                    .limit(50);

                if (ttc) {
                    // Filter outliers
                    setTimeToClose(
                        ttc.filter((r) => !r.admin_resolution_hours || r.admin_resolution_hours <= MAX_MEANINGFUL_HOURS)
                    );
                }
            } catch (err) {
                console.error('Error fetching SLA data:', err);
            } finally {
                setLoading(false);
            }
        }

        fetchData();
    }, []);

    // Calculate metrics using correct field names from DB view
    const breachedCount = firstResponse.filter((r) => r.is_breached).length;
    const pendingCount = firstResponse.filter((r) => !r.first_admin_response_at).length;
    const avgFirstResponse = firstResponse.filter(r => r.response_time_hours).length > 0
        ? firstResponse
            .filter(r => r.response_time_hours && r.first_admin_response_at) // Only count responded ones
            .reduce((sum, r) => sum + (r.response_time_hours || 0), 0) /
        Math.max(1, firstResponse.filter(r => r.first_admin_response_at).length)
        : 0;
    const avgResolution = timeToClose.filter(r => r.admin_resolution_hours).length > 0
        ? timeToClose.reduce((sum, r) => sum + (r.admin_resolution_hours || 0), 0) /
        timeToClose.filter(r => r.admin_resolution_hours).length
        : 0;

    return (
        <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <div>
                <h1 className="text-2xl font-bold text-dark-50">SLA Tracking</h1>
                <p className="text-dark-400 mt-1">
                    Service level agreement metrics and breach tracking
                </p>
            </div>

            {/* Summary */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                <MetricCard
                    title="First Response SLA"
                    value={`${FIRST_RESPONSE_SLA_HOURS}h`}
                    icon={<Clock className="w-5 h-5" />}
                />
                <MetricCard
                    title="Avg First Response"
                    value={`${avgFirstResponse.toFixed(1)}h`}
                    icon={<TrendingUp className="w-5 h-5" />}
                    className={avgFirstResponse > FIRST_RESPONSE_SLA_HOURS ? 'border-l-4 border-red-500' : ''}
                />
                <MetricCard
                    title="SLA Breaches"
                    value={breachedCount}
                    icon={<AlertTriangle className="w-5 h-5" />}
                    className={breachedCount > 0 ? 'border-l-4 border-red-500' : ''}
                />
                <MetricCard
                    title="Avg Admin Resolution"
                    value={`${avgResolution.toFixed(1)}h`}
                    icon={<CheckCircle className="w-5 h-5" />}
                />
            </div>

            {/* First Response Table */}
            <Card padding="lg">
                <CardHeader
                    title="First Response Times"
                    description="Time from request creation to first admin response"
                />
                {loading ? (
                    <Skeleton height={300} variant="rounded" className="mt-4" />
                ) : firstResponse.length === 0 ? (
                    <div className="text-center py-8 text-dark-500">No data available</div>
                ) : (
                    <div className="mt-4 overflow-x-auto">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Request</th>
                                    <th>Status</th>
                                    <th>Response Time (h)</th>
                                    <th>SLA Status</th>
                                </tr>
                            </thead>
                            <tbody>
                                {firstResponse.map((r) => (
                                    <tr key={r.request_id}>
                                        <td className="max-w-xs truncate font-medium">{r.title}</td>
                                        <td>
                                            <StatusBadge status={r.status} size="sm" />
                                        </td>
                                        <td>
                                            {r.first_admin_response_at
                                                ? `${r.response_time_hours?.toFixed(1)}h`
                                                : <span className="text-dark-500 italic">Not responded</span>}
                                        </td>
                                        <td>
                                            {r.is_breached ? (
                                                <Badge color="red" dot>Breached</Badge>
                                            ) : r.first_admin_response_at ? (
                                                <Badge color="green" dot>OK</Badge>
                                            ) : (
                                                <Badge color="yellow" dot>Pending</Badge>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </Card>

            {/* Resolution Times (Admin SLA = time until Pending Closure) */}
            <Card padding="lg">
                <CardHeader
                    title="Admin Resolution Times"
                    description="Time from creation to admin marking Pending Closure — excludes time waiting for employee confirmation"
                />
                {loading ? (
                    <Skeleton height={300} variant="rounded" className="mt-4" />
                ) : timeToClose.length === 0 ? (
                    <div className="text-center py-8 text-dark-500">No resolved requests yet</div>
                ) : (
                    <div className="mt-4 overflow-x-auto">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Request</th>
                                    <th>Priority</th>
                                    <th>Admin Resolution (h)</th>
                                    <th>Resolved By</th>
                                </tr>
                            </thead>
                            <tbody>
                                {timeToClose.map((r) => (
                                    <tr key={r.request_id}>
                                        <td className="max-w-xs truncate font-medium">{r.title}</td>
                                        <td>P{r.priority}</td>
                                        <td>{r.admin_resolution_hours != null ? `${r.admin_resolution_hours.toFixed(1)}h` : '-'}</td>
                                        <td className="text-dark-400">{r.resolved_by_email || '-'}</td>
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
