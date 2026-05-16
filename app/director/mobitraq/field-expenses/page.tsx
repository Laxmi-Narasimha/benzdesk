'use client';

import React, { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { getSupabaseClient } from '@/lib/supabaseClient';
import {
    Card,
    Button,
    Spinner,
    StatusBadge,
} from '@/components/ui';
import {
    ArrowLeft,
    Users,
    IndianRupee,
    Receipt,
    ChevronRight,
    MapPin,
} from 'lucide-react';
import type { Request, RequestCategory } from '@/types';
import { REQUEST_CATEGORY_LABELS } from '@/types';
import { AdjustedDistance } from '@/components/mobitraq/AdjustedDistance';
import { useDistanceAdjustmentsByRequest } from '@/components/mobitraq/useDistanceAdjustments';

interface EmployeeGroup {
    employeeId: string;
    employeeName: string;
    employeeEmail: string;
    pendingCount: number;
    totalAmount: number;
    requests: (Request & { 
        calculatedAmount?: number; 
        parsedDistance?: number; 
        parsedVehicleType?: string; 
    })[];
}

const SESSION_CATEGORIES: RequestCategory[] = ['expense_claim', 'travel_allowance', 'transport_expense'];

export default function FieldExpensesPage() {
    const router = useRouter();
    const [groups, setGroups] = useState<EmployeeGroup[]>([]);
    const [loading, setLoading] = useState(true);
    const [expandedEmployee, setExpandedEmployee] = useState<string | null>(null);

    // Collect every request ID across every employee group so we can
    // batch-fetch admin distance corrections once and surface the
    // "old + delta = corrected" badge + reason on each row.
    const allRequestIds = React.useMemo(
        () => groups.flatMap((g) => g.requests.map((r) => r.id)),
        [groups],
    );
    const adjustmentsByRequestId = useDistanceAdjustmentsByRequest(allRequestIds);

    useEffect(() => {
        async function fetchData() {
            try {
                const supabase = getSupabaseClient();

                // 1. Fetch ALL field/session category requests
                const { data, error } = await supabase
                    .from('requests_with_creator')
                    .select('*')
                    .in('category', SESSION_CATEGORIES)
                    .order('created_at', { ascending: false });

                if (error) throw error;

                // Filter in memory: Only keep automated sessions (reference_id is NOT null)
                const validData = (data || []).filter((req: any) => req.reference_id !== null);

                // 2. Extract unique employee IDs to fetch their bands
                const employeeIds = Array.from(new Set(validData.map((r: any) => r.created_by).filter(Boolean)));
                let employeeBands: Record<string, string> = {};
                let bandLimits: Record<string, number> = {};

                if (employeeIds.length > 0) {
                    // Fetch employees
                    const { data: empData } = await supabase
                        .from('employees')
                        .select('id, band')
                        .in('id', employeeIds);
                    
                    if (empData) {
                        empData.forEach((e: any) => {
                            if (e.band) employeeBands[e.id] = e.band;
                        });
                    }

                    // Fetch all band limits for fuel
                    const { data: limitsData } = await supabase
                        .from('band_limits')
                        .select('band, category, daily_limit')
                        .in('category', ['fuel_car', 'fuel_bike']);
                    
                    if (limitsData) {
                        limitsData.forEach((l: any) => {
                            bandLimits[`${l.band}_${l.category}`] = l.daily_limit;
                        });
                    }
                }

                // Group by employee
                const grouped = new Map<string, EmployeeGroup>();
                validData.forEach((req: any) => {
                    const key = req.created_by || req.creator_email || 'unknown';
                    const existing = grouped.get(key);
                    
                    // Parse distance and vehicle from description
                    let calculatedAmount = req.amount || 0;
                    let distance = 0;
                    let vehicleType = 'Bike';
                    
                    if (req.description) {
                        const match = req.description.match(/([0-9.]+) km \((Car|Bike)\)/i);
                        if (match) {
                            distance = parseFloat(match[1]);
                            vehicleType = match[2].toLowerCase();
                            
                            // Determine rate
                            const band = req.created_by ? employeeBands[req.created_by] : null;
                            const category = vehicleType === 'car' ? 'fuel_car' : 'fuel_bike';
                            let rate = vehicleType === 'car' ? 7.5 : 5.0; // Fallback
                            
                            if (band && bandLimits[`${band}_${category}`]) {
                                rate = bandLimits[`${band}_${category}`];
                            }
                            
                            // Only override with calculated amount if DB amount is 0 or null
                            if (!req.amount) {
                                calculatedAmount = distance * rate;
                            }
                        }
                    }

                    // Attach calculated amount for rendering
                    req.calculatedAmount = calculatedAmount;
                    req.parsedDistance = distance;
                    req.parsedVehicleType = vehicleType;

                    const isPending = req.status !== 'closed' && req.status !== 'cancelled';

                    if (existing) {
                        existing.requests.push(req);
                        if (isPending) {
                            existing.pendingCount++;
                            existing.totalAmount += calculatedAmount;
                        }
                    } else {
                        grouped.set(key, {
                            employeeId: req.created_by || key,
                            employeeName: req.creator_name || req.creator_email?.split('@')[0] || 'Unknown',
                            employeeEmail: req.creator_email || '',
                            pendingCount: isPending ? 1 : 0,
                            totalAmount: isPending ? calculatedAmount : 0,
                            requests: [req],
                        });
                    }
                });

                // Sort by total amount descending
                setGroups(
                    Array.from(grouped.values()).sort((a, b) => b.totalAmount - a.totalAmount)
                );
            } catch (err) {
                console.error('Error fetching field expenses:', err);
            } finally {
                setLoading(false);
            }
        }

        fetchData();
    }, []);

    if (loading) {
        return (
            <div className="max-w-6xl mx-auto p-8 flex items-center justify-center min-h-[400px]">
                <Spinner size="lg" />
            </div>
        );
    }

    return (
        <div className="max-w-6xl mx-auto p-6 space-y-6">
            {/* Header */}
            <div className="flex items-center gap-4">
                <button
                    onClick={() => router.push('/director/mobitraq')}
                    className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
                >
                    <ArrowLeft className="w-5 h-5 text-gray-500" />
                </button>
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">Monthly Expenses</h1>
                    <p className="text-sm text-gray-500 mt-1">
                        Per-employee summary of session, travel & transport claims.
                        Distance numbers shown here reflect any admin corrections.
                    </p>
                </div>
            </div>

            {/* Summary Stats */}
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <Card className="p-4 flex items-center gap-4">
                    <div className="w-10 h-10 rounded-lg bg-blue-100 flex items-center justify-center">
                        <Users className="w-5 h-5 text-blue-600" />
                    </div>
                    <div>
                        <p className="text-2xl font-bold text-gray-900">{groups.length}</p>
                        <p className="text-sm text-gray-500">Employees</p>
                    </div>
                </Card>
                <Card className="p-4 flex items-center gap-4">
                    <div className="w-10 h-10 rounded-lg bg-amber-100 flex items-center justify-center">
                        <Receipt className="w-5 h-5 text-amber-600" />
                    </div>
                    <div>
                        <p className="text-2xl font-bold text-gray-900">
                            {groups.reduce((sum, g) => sum + g.pendingCount, 0)}
                        </p>
                        <p className="text-sm text-gray-500">Pending Expenses</p>
                    </div>
                </Card>
                <Card className="p-4 flex items-center gap-4">
                    <div className="w-10 h-10 rounded-lg bg-emerald-100 flex items-center justify-center">
                        <IndianRupee className="w-5 h-5 text-emerald-600" />
                    </div>
                    <div>
                        <p className="text-2xl font-bold text-gray-900">
                            ₹{groups.reduce((sum, g) => sum + g.totalAmount, 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })}
                        </p>
                        <p className="text-sm text-gray-500">Total Pending Amount</p>
                    </div>
                </Card>
            </div>

            {/* Employee Groups */}
            <div className="space-y-4">
                {groups.length === 0 && (
                    <div className="text-center py-16 bg-gray-50 rounded-2xl border border-gray-200">
                        <MapPin className="w-12 h-12 text-gray-300 mx-auto mb-4" />
                        <h3 className="text-lg font-semibold text-gray-700">No field expenses found</h3>
                        <p className="text-sm text-gray-500 mt-1">
                            Session and travel expenses will appear here when employees submit them.
                        </p>
                    </div>
                )}

                {groups.map((group) => {
                    const isExpanded = expandedEmployee === group.employeeId;
                    return (
                        <Card
                            key={group.employeeId}
                            className="overflow-hidden"
                        >
                            {/* Employee Header */}
                            <button
                                onClick={() => setExpandedEmployee(isExpanded ? null : group.employeeId)}
                                className="w-full p-5 flex items-center justify-between hover:bg-gray-50 transition-colors text-left"
                            >
                                <div className="flex items-center gap-4">
                                    <div className="w-10 h-10 rounded-full bg-primary-100 flex items-center justify-center text-primary-700 font-bold text-sm">
                                        {group.employeeName.charAt(0).toUpperCase()}
                                    </div>
                                    <div>
                                        <h3 className="font-semibold text-gray-900">{group.employeeName}</h3>
                                        <p className="text-sm text-gray-500">{group.employeeEmail}</p>
                                    </div>
                                </div>
                                <div className="flex items-center gap-4">
                                    {group.pendingCount > 0 && (
                                        <div className="flex items-center gap-2 px-3 py-1.5 bg-amber-50 text-amber-700 rounded-full text-sm font-medium">
                                            <Receipt className="w-3.5 h-3.5" />
                                            {group.pendingCount} pending
                                        </div>
                                    )}
                                    <div className="text-right">
                                        <p className="font-bold text-gray-900">
                                            ₹{group.totalAmount.toLocaleString('en-IN', { maximumFractionDigits: 0 })}
                                        </p>
                                        <p className="text-xs text-gray-500">pending amount</p>
                                    </div>
                                    <ChevronRight
                                        className={`w-5 h-5 text-gray-400 transition-transform ${isExpanded ? 'rotate-90' : ''}`}
                                    />
                                </div>
                            </button>

                            {/* Expanded Request List */}
                            {isExpanded && (
                                <div className="border-t border-gray-100">
                                    <div className="divide-y divide-gray-100">
                                        {group.requests.map((req) => (
                                            <div
                                                key={req.id}
                                                onClick={() => router.push(`/admin/request?id=${req.id}`)}
                                                className="p-4 flex items-center justify-between hover:bg-gray-50 cursor-pointer transition-colors"
                                            >
                                                <div className="flex-1 min-w-0">
                                                    <div className="flex items-center gap-2 mb-1">
                                                        <span className="text-sm font-medium text-gray-900 truncate">
                                                            {req.title}
                                                        </span>
                                                        <StatusBadge status={req.status} size="sm" />
                                                    </div>
                                                    <p className="text-xs text-gray-500 truncate">
                                                        {REQUEST_CATEGORY_LABELS[req.category as keyof typeof REQUEST_CATEGORY_LABELS] || req.category}
                                                        {' · '}
                                                        {new Date(req.created_at).toLocaleDateString('en-IN')}
                                                    </p>
                                                </div>
                                                <div className="text-right ml-4 flex-shrink-0">
                                                    <p className="font-semibold text-gray-900">
                                                        ₹{(req.calculatedAmount || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 })}
                                                    </p>
                                                    {(req.parsedDistance || 0) > 0 && (
                                                        <p className="text-[10px] text-gray-500 mt-0.5">
                                                            {adjustmentsByRequestId[req.id] ? (
                                                                <AdjustedDistance
                                                                    sessionId={req.id}
                                                                    rawKm={req.parsedDistance || 0}
                                                                    adjustment={adjustmentsByRequestId[req.id]}
                                                                    compact
                                                                />
                                                            ) : (
                                                                <>
                                                                    {(req.parsedDistance || 0).toFixed(1)} km × {req.parsedVehicleType === 'car' ? 'Car' : 'Bike'}
                                                                </>
                                                            )}
                                                        </p>
                                                    )}
                                                    {adjustmentsByRequestId[req.id]?.reason && (
                                                        <p className="text-[10px] text-amber-700 italic mt-1 max-w-[200px]" title={adjustmentsByRequestId[req.id].reason ?? undefined}>
                                                            {(() => {
                                                                const r = adjustmentsByRequestId[req.id].reason || '';
                                                                return r.length > 50 ? `${r.slice(0, 50)}…` : r;
                                                            })()}
                                                        </p>
                                                    )}
                                                </div>
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            )}
                        </Card>
                    );
                })}
            </div>
        </div>
    );
}
