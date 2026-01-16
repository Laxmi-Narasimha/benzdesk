// ============================================================================
// Admin Reports Page
// Basic reporting and metrics for admins
// ============================================================================

'use client';

import React, { useState, useEffect } from 'react';
import { clsx } from 'clsx';
import {
    BarChart3,
    PieChart,
    TrendingUp,
    Calendar,
    Download,
} from 'lucide-react';
import { Card, CardHeader, MetricCard, Button, Skeleton } from '@/components/ui';
import { getSupabaseClient } from '@/lib/supabaseClient';

// ============================================================================
// Component
// ============================================================================

export default function AdminReportsPage() {
    const [loading, setLoading] = useState(true);
    const [categoryData, setCategoryData] = useState<any[]>([]);
    const [dailyData, setDailyData] = useState<any[]>([]);

    useEffect(() => {
        async function fetchReports() {
            try {
                const supabase = getSupabaseClient();

                // Fetch category distribution
                const { data: categories } = await supabase
                    .from('v_category_distribution')
                    .select('*');

                if (categories) {
                    setCategoryData(categories);
                }

                // Fetch daily metrics
                const { data: daily } = await supabase
                    .from('v_daily_metrics')
                    .select('*')
                    .limit(14);

                if (daily) {
                    setDailyData(daily);
                }
            } catch (err) {
                console.error('Error fetching reports:', err);
            } finally {
                setLoading(false);
            }
        }

        fetchReports();
    }, []);

    // Calculate totals
    const totalCreated = dailyData.reduce((sum, d) => sum + (d.requests_created || 0), 0);
    const totalClosed = dailyData.reduce((sum, d) => sum + (d.requests_closed || 0), 0);

    return (
        <div className="max-w-7xl mx-auto space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold text-dark-50">Reports</h1>
                    <p className="text-dark-400 mt-1">
                        Request analytics and metrics
                    </p>
                </div>
                <Button variant="secondary" leftIcon={<Download className="w-4 h-4" />}>
                    Export
                </Button>
            </div>

            {/* Summary Stats */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <MetricCard
                    title="Created (14 days)"
                    value={loading ? '-' : totalCreated}
                    icon={<TrendingUp className="w-5 h-5" />}
                />
                <MetricCard
                    title="Closed (14 days)"
                    value={loading ? '-' : totalClosed}
                    icon={<BarChart3 className="w-5 h-5" />}
                />
                <MetricCard
                    title="Categories"
                    value={loading ? '-' : categoryData.length}
                    icon={<PieChart className="w-5 h-5" />}
                />
            </div>

            {/* Category Distribution */}
            <Card padding="lg">
                <CardHeader title="Requests by Category" />
                {loading ? (
                    <div className="space-y-3 mt-4">
                        {[1, 2, 3, 4, 5].map((i) => (
                            <Skeleton key={i} height={40} variant="rounded" />
                        ))}
                    </div>
                ) : (
                    <div className="mt-4 space-y-3">
                        {categoryData.map((cat) => {
                            const maxCount = Math.max(...categoryData.map(c => c.total_count));
                            const percentage = maxCount > 0 ? (cat.total_count / maxCount) * 100 : 0;

                            return (
                                <div key={cat.category} className="flex items-center gap-4">
                                    <div className="w-32 text-sm text-dark-300 capitalize truncate">
                                        {cat.category.replace(/_/g, ' ')}
                                    </div>
                                    <div className="flex-1 h-8 bg-dark-800/50 rounded-lg overflow-hidden">
                                        <div
                                            className="h-full bg-gradient-to-r from-primary-600 to-primary-500 rounded-lg transition-all duration-500"
                                            style={{ width: `${percentage}%` }}
                                        />
                                    </div>
                                    <div className="w-16 text-sm text-dark-400 text-right">
                                        {cat.total_count}
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                )}
            </Card>

            {/* Daily Trend */}
            <Card padding="lg">
                <CardHeader title="Daily Trend (Last 14 Days)" />
                {loading ? (
                    <Skeleton height={200} variant="rounded" className="mt-4" />
                ) : dailyData.length === 0 ? (
                    <div className="text-center py-12 text-dark-500">
                        No data available for the selected period
                    </div>
                ) : (
                    <div className="mt-4 overflow-x-auto">
                        <table className="data-table">
                            <thead>
                                <tr>
                                    <th>Date</th>
                                    <th>Created</th>
                                    <th>Closed</th>
                                    <th>Avg Priority</th>
                                </tr>
                            </thead>
                            <tbody>
                                {dailyData.map((day) => (
                                    <tr key={day.date}>
                                        <td className="font-medium">{day.date}</td>
                                        <td>{day.requests_created}</td>
                                        <td>{day.requests_closed}</td>
                                        <td>P{day.avg_priority?.toFixed(1) || '-'}</td>
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
