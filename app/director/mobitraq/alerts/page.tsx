// ============================================================================
// MobiTraq Alerts Page
// Real-time alerts management for stuck, no-signal, and other conditions
// ============================================================================

'use client';

import React, { useEffect, useState } from 'react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { PageLoader, Card } from '@/components/ui';
import {
    AlertTriangle,
    Bell,
    CheckCircle,
    Clock,
    MapPin,
    Signal,
    SignalZero,
    User,
    Filter,
    RefreshCw,
} from 'lucide-react';

interface Alert {
    id: string;
    employee_id: string;
    session_id: string | null;
    alert_type: 'stuck' | 'no_signal' | 'mock_location' | 'clock_drift';
    severity: 'info' | 'warning' | 'critical';
    message: string;
    is_open: boolean;
    created_at: string;
    acknowledged_at: string | null;
    acknowledged_by: string | null;
    employee?: {
        name: string;
        phone: string;
    };
}

const alertTypeConfig = {
    stuck: { icon: MapPin, color: 'text-amber-400', bg: 'bg-amber-500/20', label: 'Stuck' },
    no_signal: { icon: SignalZero, color: 'text-red-400', bg: 'bg-red-500/20', label: 'No Signal' },
    mock_location: { icon: AlertTriangle, color: 'text-purple-400', bg: 'bg-purple-500/20', label: 'Mock Location' },
    clock_drift: { icon: Clock, color: 'text-blue-400', bg: 'bg-blue-500/20', label: 'Clock Drift' },
};

const severityConfig = {
    info: { color: 'bg-blue-500', label: 'Info' },
    warning: { color: 'bg-amber-500', label: 'Warning' },
    critical: { color: 'bg-red-500', label: 'Critical' },
};

export default function AlertsPage() {
    const [alerts, setAlerts] = useState<Alert[]>([]);
    const [loading, setLoading] = useState(true);
    const [filter, setFilter] = useState<'all' | 'open' | 'acknowledged'>('all');
    const [typeFilter, setTypeFilter] = useState<string>('all');
    const [refreshing, setRefreshing] = useState(false);

    useEffect(() => {
        loadAlerts();

        // Set up real-time subscription
        const supabase = getSupabaseClient();
        const subscription = supabase
            .channel('mobitraq_alerts_changes')
            .on(
                'postgres_changes',
                { event: '*', schema: 'public', table: 'mobitraq_alerts' },
                () => {
                    loadAlerts();
                }
            )
            .subscribe();

        return () => {
            subscription.unsubscribe();
        };
    }, []);

    async function loadAlerts() {
        setRefreshing(true);
        const supabase = getSupabaseClient();

        const { data, error } = await supabase
            .from('mobitraq_alerts')
            .select(`
                *,
                employee:employees!employee_id (
                    name,
                    phone
                )
            `)
            .order('created_at', { ascending: false })
            .limit(100);

        if (data) {
            setAlerts(data);
        }
        setLoading(false);
        setRefreshing(false);
    }

    async function acknowledgeAlert(alertId: string) {
        const supabase = getSupabaseClient();
        const { data: { user } } = await supabase.auth.getUser();

        const { error } = await supabase
            .from('mobitraq_alerts')
            .update({
                is_open: false,
                acknowledged_at: new Date().toISOString(),
                acknowledged_by: user?.id,
            })
            .eq('id', alertId);

        if (!error) {
            loadAlerts();
        }
    }

    // Filter alerts
    const filteredAlerts = alerts.filter((alert) => {
        if (filter === 'open' && !alert.is_open) return false;
        if (filter === 'acknowledged' && alert.is_open) return false;
        if (typeFilter !== 'all' && alert.alert_type !== typeFilter) return false;
        return true;
    });

    // Stats
    const openCount = alerts.filter((a) => a.is_open).length;
    const criticalCount = alerts.filter((a) => a.is_open && a.severity === 'critical').length;

    // Format time
    const formatTime = (isoString: string) => {
        const date = new Date(isoString);
        const now = new Date();
        const diffMs = now.getTime() - date.getTime();
        const diffMins = Math.floor(diffMs / 60000);
        const diffHours = Math.floor(diffMins / 60);
        const diffDays = Math.floor(diffHours / 24);

        if (diffMins < 60) return `${diffMins}m ago`;
        if (diffHours < 24) return `${diffHours}h ago`;
        if (diffDays < 7) return `${diffDays}d ago`;
        return date.toLocaleDateString('en-IN');
    };

    if (loading) {
        return <PageLoader message="Loading alerts..." />;
    }

    return (
        <div className="space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold text-dark-100 flex items-center gap-2">
                        <Bell className="w-6 h-6 text-primary-500" />
                        Alerts
                    </h1>
                    <p className="text-dark-400 mt-1">
                        Monitor and respond to employee tracking issues
                    </p>
                </div>
                <button
                    onClick={loadAlerts}
                    disabled={refreshing}
                    className="px-4 py-2 bg-dark-800 hover:bg-dark-700 rounded-lg flex items-center gap-2 text-dark-200 transition-colors"
                >
                    <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
                    Refresh
                </button>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <Card className="p-4">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-red-500/20 rounded-lg">
                            <AlertTriangle className="w-5 h-5 text-red-400" />
                        </div>
                        <div>
                            <div className="text-2xl font-bold text-dark-100">{criticalCount}</div>
                            <div className="text-sm text-dark-400">Critical</div>
                        </div>
                    </div>
                </Card>
                <Card className="p-4">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-amber-500/20 rounded-lg">
                            <Bell className="w-5 h-5 text-amber-400" />
                        </div>
                        <div>
                            <div className="text-2xl font-bold text-dark-100">{openCount}</div>
                            <div className="text-sm text-dark-400">Open</div>
                        </div>
                    </div>
                </Card>
                <Card className="p-4">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-green-500/20 rounded-lg">
                            <CheckCircle className="w-5 h-5 text-green-400" />
                        </div>
                        <div>
                            <div className="text-2xl font-bold text-dark-100">
                                {alerts.length - openCount}
                            </div>
                            <div className="text-sm text-dark-400">Acknowledged</div>
                        </div>
                    </div>
                </Card>
                <Card className="p-4">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-blue-500/20 rounded-lg">
                            <Signal className="w-5 h-5 text-blue-400" />
                        </div>
                        <div>
                            <div className="text-2xl font-bold text-dark-100">{alerts.length}</div>
                            <div className="text-sm text-dark-400">Total</div>
                        </div>
                    </div>
                </Card>
            </div>

            {/* Filters */}
            <Card className="p-4">
                <div className="flex flex-wrap gap-4 items-center">
                    <Filter className="w-4 h-4 text-dark-400" />

                    {/* Status Filter */}
                    <div className="flex gap-2">
                        {['all', 'open', 'acknowledged'].map((f) => (
                            <button
                                key={f}
                                onClick={() => setFilter(f as typeof filter)}
                                className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${filter === f
                                    ? 'bg-primary-600 text-white'
                                    : 'bg-dark-800 text-dark-300 hover:bg-dark-700'
                                    }`}
                            >
                                {f.charAt(0).toUpperCase() + f.slice(1)}
                            </button>
                        ))}
                    </div>

                    <div className="w-px h-6 bg-dark-700" />

                    {/* Type Filter */}
                    <select
                        value={typeFilter}
                        onChange={(e) => setTypeFilter(e.target.value)}
                        className="bg-dark-900 border border-dark-700 rounded-lg px-3 py-1.5 text-dark-200 text-sm focus:outline-none focus:border-primary-500"
                    >
                        <option value="all">All Types</option>
                        <option value="stuck">Stuck</option>
                        <option value="no_signal">No Signal</option>
                        <option value="mock_location">Mock Location</option>
                        <option value="clock_drift">Clock Drift</option>
                    </select>
                </div>
            </Card>

            {/* Alerts List */}
            <div className="space-y-3">
                {filteredAlerts.length === 0 && (
                    <Card className="p-8 text-center">
                        <CheckCircle className="w-12 h-12 text-green-500 mx-auto mb-4" />
                        <h3 className="text-lg font-medium text-dark-300">No Alerts</h3>
                        <p className="text-dark-500 mt-2">
                            {filter === 'open'
                                ? 'All alerts have been acknowledged!'
                                : 'No alerts match your filters.'}
                        </p>
                    </Card>
                )}

                {filteredAlerts.map((alert) => {
                    const config = alertTypeConfig[alert.alert_type] || alertTypeConfig.stuck;
                    const severity = severityConfig[alert.severity] || severityConfig.warning;
                    const Icon = config.icon;

                    return (
                        <Card
                            key={alert.id}
                            className={`p-4 ${alert.is_open
                                ? 'border-l-4 border-' + severity.color.replace('bg-', '')
                                : 'opacity-60'
                                }`}
                        >
                            <div className="flex items-start gap-4">
                                <div className={`p-2 rounded-lg ${config.bg}`}>
                                    <Icon className={`w-5 h-5 ${config.color}`} />
                                </div>

                                <div className="flex-1 min-w-0">
                                    <div className="flex items-center gap-2 flex-wrap">
                                        <span className="font-medium text-dark-100">
                                            {config.label}
                                        </span>
                                        <span
                                            className={`px-2 py-0.5 rounded-full text-xs font-medium text-white ${severity.color}`}
                                        >
                                            {severity.label}
                                        </span>
                                        {!alert.is_open && (
                                            <span className="px-2 py-0.5 rounded-full text-xs font-medium bg-green-500/20 text-green-400">
                                                Acknowledged
                                            </span>
                                        )}
                                    </div>

                                    <p className="text-dark-300 mt-1">{alert.message}</p>

                                    <div className="flex items-center gap-4 mt-2 text-sm text-dark-500">
                                        <span className="flex items-center gap-1">
                                            <User className="w-3.5 h-3.5" />
                                            {alert.employee?.name || 'Unknown'}
                                        </span>
                                        <span className="flex items-center gap-1">
                                            <Clock className="w-3.5 h-3.5" />
                                            {formatTime(alert.created_at)}
                                        </span>
                                    </div>
                                </div>

                                {alert.is_open && (
                                    <button
                                        onClick={() => acknowledgeAlert(alert.id)}
                                        className="px-4 py-2 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-medium transition-colors flex items-center gap-2"
                                    >
                                        <CheckCircle className="w-4 h-4" />
                                        Acknowledge
                                    </button>
                                )}
                            </div>
                        </Card>
                    );
                })}
            </div>
        </div>
    );
}
