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
    AlertCircle,
} from 'lucide-react';
import { Card, CardHeader, MetricCard, Skeleton, StatusBadge, Badge } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';

// SLA threshold in hours for first response (medium priority default)
const FIRST_RESPONSE_SLA_HOURS = 8;

export default function SLATrackingPage() {
    const [loading, setLoading] = useState(true);
    const [firstResponse, setFirstResponse] = useState<any[]>([]);
    const [timeToClose, setTimeToClose] = useState<any[]>([]);

    useEffect(() => {
        async function fetchData() {
            try {
                const supabase = getSupabaseClient();

                const { data: fr } = await supabase
                    .from('v_sla_first_response')
                    .select('*')
                    .limit(20);

                if (fr) setFirstResponse(fr);

                const { data: ttc } = await supabase
                    .from('v_sla_time_to_close')
                    .select('*')
                    .limit(20);

                if (ttc) setTimeToClose(ttc);
            } catch (err) {
                console.error('Error fetching SLA data:', err);
            } finally {
                setLoading(false);
            }
        }

        fetchData();
    }, []);

    // Calculate metrics
    const breachedCount = firstResponse.filter((r) => r.breached_first_response_sla).length;
    const avgFirstResponse = firstResponse.length > 0
        ? firstResponse.reduce((sum, r) => sum + (r.hours_to_first_response || 0), 0) / firstResponse.length
        : 0;
    const avgResolution = timeToClose.length > 0
        ? timeToClose.reduce((sum, r) => sum + (r.hours_to_close || 0), 0) / timeToClose.length
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
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-4">
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
                    title="Avg Resolution"
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
                                    <th>Hours to Response</th>
                                    <th>SLA Status</th>
                                </tr>
                            </thead>
                            <tbody>
                                {firstResponse.map((r) => (
                                    <tr key={r.id}>
                                        <td className="max-w-xs truncate font-medium">{r.title}</td>
                                        <td>
                                            <StatusBadge status={r.status} size="sm" />
                                        </td>
                                        <td>
                                            {r.hours_to_first_response
                                                ? r.hours_to_first_response.toFixed(1)
                                                : '-'}
                                        </td>
                                        <td>
                                            {r.breached_first_response_sla ? (
                                                <Badge color="red" dot>
                                                    Breached
                                                </Badge>
                                            ) : r.hours_to_first_response ? (
                                                <Badge color="green" dot>
                                                    OK
                                                </Badge>
                                            ) : (
                                                <Badge color="yellow" dot>
                                                    Pending
                                                </Badge>
                                            )}
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </Card>

            {/* Resolution Times */}
            <Card padding="lg">
                <CardHeader
                    title="Resolution Times"
                    description="Time from creation to closure for closed requests"
                />
                {loading ? (
                    <Skeleton height={300} variant="rounded" className="mt-4" />
                ) : timeToClose.length === 0 ? (
                    <div className="text-center py-8 text-dark-500">No closed requests</div>
                ) : (
                    <div className="mt-4 overflow-x-auto">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Request</th>
                                    <th>Priority</th>
                                    <th>Hours to Close</th>
                                    <th>Closed By</th>
                                </tr>
                            </thead>
                            <tbody>
                                {timeToClose.map((r) => (
                                    <tr key={r.id}>
                                        <td className="max-w-xs truncate font-medium">{r.title}</td>
                                        <td>P{r.priority}</td>
                                        <td>{r.hours_to_close?.toFixed(1) || '-'}</td>
                                        <td className="text-dark-400">{r.closed_by_email || '-'}</td>
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
