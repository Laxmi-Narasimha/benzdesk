'use client';

import React, { useCallback, useEffect, useState } from 'react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import {
    MapPin, Search, Check, X, AlertTriangle, ChevronDown,
    Clock, CheckCircle, XCircle, Navigation, RefreshCw, Car,
    Calendar, User, IndianRupee, Eye,
} from 'lucide-react';

// ============================================================================
// Types
// ============================================================================

interface Trip {
    id: string;
    employee_id: string;
    from_location: string;
    to_location: string;
    reason: string | null;
    vehicle_type: string;
    status: string;
    created_at: string;
    approved_at: string | null;
    started_at: string | null;
    ended_at: string | null;
    total_km: number;
    total_expenses: number;
    notes: string | null;
    // joined
    employee_name?: string;
    employee_band?: string;
}

interface TripExpense {
    id: string;
    category: string;
    amount: number;
    description: string | null;
    date: string;
    status: string;
    limit_amount: number | null;
    exceeds_limit: boolean;
}

// ============================================================================
// Constants
// ============================================================================

const STATUS_CONFIG: Record<string, { label: string; color: string; icon: React.ReactNode }> = {
    requested: { label: 'Requested', color: 'bg-yellow-100 text-yellow-700', icon: <Clock className="w-3 h-3" /> },
    approved: { label: 'Approved', color: 'bg-blue-100 text-blue-700', icon: <Check className="w-3 h-3" /> },
    active: { label: 'Active', color: 'bg-green-100 text-green-700', icon: <Navigation className="w-3 h-3" /> },
    completed: { label: 'Completed', color: 'bg-gray-100 text-gray-600', icon: <CheckCircle className="w-3 h-3" /> },
    cancelled: { label: 'Cancelled', color: 'bg-red-100 text-red-600', icon: <XCircle className="w-3 h-3" /> },
    rejected: { label: 'Rejected', color: 'bg-red-100 text-red-700', icon: <XCircle className="w-3 h-3" /> },
};

const CATEGORY_LABELS: Record<string, string> = {
    hotel: '🏨 Hotel',
    food_da: '🍽️ Food DA',
    local_travel: '🚗 Local Travel',
    fuel: '⛽ Fuel',
    toll: '🛣️ Toll/Parking',
    laundry: '👕 Laundry',
    internet: '📶 Internet',
    other: '📦 Other',
};

const VEHICLE_LABELS: Record<string, string> = {
    car: '🚗 Car', bike: '🏍️ Bike', bus: '🚌 Bus',
    train: '🚆 Train', flight: '✈️ Flight', auto: '🛺 Auto',
};

// ============================================================================
// Page Component
// ============================================================================

export default function TripManagementPage() {
    const [trips, setTrips] = useState<Trip[]>([]);
    const [loading, setLoading] = useState(true);
    const [search, setSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState('all');
    const [selectedTrip, setSelectedTrip] = useState<Trip | null>(null);
    const [tripExpenses, setTripExpenses] = useState<TripExpense[]>([]);
    const [loadingExpenses, setLoadingExpenses] = useState(false);
    const [toast, setToast] = useState<{ msg: string; ok: boolean } | null>(null);

    const flash = useCallback((msg: string, ok: boolean) => {
        setToast({ msg, ok });
        setTimeout(() => setToast(null), 3500);
    }, []);

    // ── Load Trips ─────────────────────────────────────────────────────
    const loadTrips = useCallback(async () => {
        setLoading(true);
        try {
            const sb = getSupabaseClient();
            // Fetch trips without the ambiguous join
            const { data, error } = await sb
                .from('trips')
                .select('*')
                .order('created_at', { ascending: false });

            if (error) throw error;

            // Fetch employee names separately to avoid ambiguous FK errors
            const employeeIds = Array.from(new Set((data || []).map((t: Record<string, unknown>) => t.employee_id as string)));
            let empMap: Record<string, { name: string; band: string }> = {};
            
            if (employeeIds.length > 0) {
                const { data: empData } = await sb
                    .from('employees')
                    .select('id, name, band')
                    .in('id', employeeIds);
                
                if (empData) {
                    empMap = Object.fromEntries(
                        empData.map((e: Record<string, unknown>) => [e.id, { name: e.name as string || 'Unknown', band: e.band as string || 'executive' }])
                    );
                }
            }

            const mapped = (data || []).map((t: Record<string, unknown>) => ({
                ...t,
                employee_name: empMap[t.employee_id as string]?.name || 'Unknown',
                employee_band: empMap[t.employee_id as string]?.band || 'executive',
            })) as Trip[];

            setTrips(mapped);
        } catch (e) {
            console.error(e);
            flash('Failed to load trips', false);
        } finally {
            setLoading(false);
        }
    }, [flash]);

    useEffect(() => { void loadTrips(); }, [loadTrips]);

    // ── Load Trip Expenses ─────────────────────────────────────────────
    const loadExpenses = async (tripId: string) => {
        setLoadingExpenses(true);
        try {
            const sb = getSupabaseClient();
            const { data, error } = await sb
                .from('trip_expenses')
                .select('*')
                .eq('trip_id', tripId)
                .order('date', { ascending: false });
            if (error) throw error;
            setTripExpenses((data || []) as TripExpense[]);
        } catch (e) {
            console.error(e);
        } finally {
            setLoadingExpenses(false);
        }
    };

    // ── Update Trip Status ─────────────────────────────────────────────
    const updateTripStatus = async (tripId: string, newStatus: string) => {
        try {
            const sb = getSupabaseClient();
            const updates: Record<string, unknown> = { status: newStatus };
            if (newStatus === 'approved') updates.approved_at = new Date().toISOString();
            if (newStatus === 'active') updates.started_at = new Date().toISOString();
            if (newStatus === 'completed') updates.ended_at = new Date().toISOString();

            const { error } = await sb.from('trips').update(updates).eq('id', tripId);
            if (error) throw error;

            flash(`Trip ${newStatus} ✓`, true);
            await loadTrips();
            if (selectedTrip?.id === tripId) {
                setSelectedTrip(prev => prev ? { ...prev, status: newStatus } : null);
            }
        } catch (e) {
            console.error(e);
            flash('Failed to update trip', false);
        }
    };

    // ── Update Expense Status ──────────────────────────────────────────
    const updateExpenseStatus = async (expenseId: string, status: string) => {
        try {
            const sb = getSupabaseClient();
            const updates: Record<string, unknown> = { status };
            if (status === 'approved') updates.approved_at = new Date().toISOString();

            const { error } = await sb.from('trip_expenses').update(updates).eq('id', expenseId);
            if (error) throw error;

            flash(`Expense ${status} ✓`, true);
            if (selectedTrip) await loadExpenses(selectedTrip.id);
        } catch (e) {
            console.error(e);
            flash('Failed to update expense', false);
        }
    };

    // ── Filter ─────────────────────────────────────────────────────────
    const q = search.toLowerCase();
    const filtered = trips.filter(t => {
        const matchSearch = !q ||
            t.from_location.toLowerCase().includes(q) ||
            t.to_location.toLowerCase().includes(q) ||
            (t.employee_name?.toLowerCase().includes(q)) ||
            (t.reason?.toLowerCase().includes(q));
        const matchStatus = statusFilter === 'all' || t.status === statusFilter;
        return matchSearch && matchStatus;
    });

    const pendingCount = trips.filter(t => t.status === 'requested').length;
    const activeCount = trips.filter(t => t.status === 'active').length;

    // ── Render ─────────────────────────────────────────────────────────
    return (
        <div className="max-w-6xl mx-auto space-y-5">
            {/* Toast */}
            {toast && (
                <div className={`fixed top-4 right-4 z-50 flex items-center gap-2 px-4 py-2.5 rounded-lg shadow-lg text-sm font-medium ${
                    toast.ok ? 'bg-green-600 text-white' : 'bg-red-600 text-white'
                }`}>
                    {toast.ok ? <Check className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />}
                    {toast.msg}
                </div>
            )}

            {/* Header */}
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-xl font-bold text-gray-900 flex items-center gap-2">
                        <MapPin className="w-5 h-5 text-primary-600" /> Trip Management
                    </h1>
                    <p className="text-gray-500 text-xs mt-0.5">
                        {pendingCount > 0 && <span className="text-yellow-600 font-medium">{pendingCount} pending · </span>}
                        {activeCount} active · {trips.length} total trips
                    </p>
                </div>
                <button onClick={() => loadTrips()} className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-white border border-gray-200 rounded-lg hover:bg-gray-50">
                    <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} /> Refresh
                </button>
            </div>

            {/* Search + Filter */}
            <div className="flex gap-2">
                <div className="relative flex-1">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                    <input type="text" placeholder="Search trips..." value={search} onChange={e => setSearch(e.target.value)}
                        className="w-full pl-9 pr-3 py-2 bg-white border border-gray-200 rounded-lg text-sm outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent" />
                </div>
                <div className="relative">
                    <select value={statusFilter} onChange={e => setStatusFilter(e.target.value)}
                        className="appearance-none pl-3 pr-7 py-2 bg-white border border-gray-200 rounded-lg text-sm outline-none focus:ring-2 focus:ring-primary-500 cursor-pointer">
                        <option value="all">All Status</option>
                        <option value="requested">Pending</option>
                        <option value="approved">Approved</option>
                        <option value="active">Active</option>
                        <option value="completed">Completed</option>
                        <option value="cancelled">Cancelled</option>
                    </select>
                    <ChevronDown className="absolute right-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400 pointer-events-none" />
                </div>
            </div>

            <div className="flex gap-5">
                {/* Trip List */}
                <div className={`${selectedTrip ? 'w-1/2' : 'w-full'} transition-all`}>
                    {loading ? (
                        <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary-500" /></div>
                    ) : filtered.length === 0 ? (
                        <div className="text-center py-16 bg-white rounded-xl border border-gray-200">
                            <MapPin className="w-10 h-10 mx-auto text-gray-300 mb-2" />
                            <p className="text-gray-500 text-sm">No trips found</p>
                            <p className="text-gray-400 text-xs mt-1">Trips will appear here when employees create them from the mobile app</p>
                        </div>
                    ) : (
                        <div className="space-y-2">
                            {filtered.map(trip => {
                                const sc = STATUS_CONFIG[trip.status] || STATUS_CONFIG.requested;
                                const isSelected = selectedTrip?.id === trip.id;

                                return (
                                    <div key={trip.id}
                                        className={`bg-white rounded-xl border p-4 transition-all cursor-pointer ${
                                            isSelected ? 'border-primary-400 ring-1 ring-primary-200 shadow-sm' : 'border-gray-200 hover:shadow-sm'
                                        }`}
                                        onClick={() => { setSelectedTrip(trip); void loadExpenses(trip.id); }}
                                    >
                                        <div className="flex items-start justify-between mb-2">
                                            <div className="flex items-center gap-2">
                                                <User className="w-4 h-4 text-gray-400" />
                                                <span className="font-medium text-sm text-gray-900">{trip.employee_name}</span>
                                                <span className="text-xs text-gray-400">{trip.employee_band}</span>
                                            </div>
                                            <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium ${sc.color}`}>
                                                {sc.icon} {sc.label}
                                            </span>
                                        </div>

                                        <div className="flex items-center gap-2 text-sm">
                                            <span className="text-gray-700">{trip.from_location}</span>
                                            <span className="text-gray-300">→</span>
                                            <span className="text-gray-700">{trip.to_location}</span>
                                        </div>

                                        <div className="flex items-center gap-3 mt-2 text-xs text-gray-400">
                                            <span className="flex items-center gap-1"><Car className="w-3 h-3" /> {VEHICLE_LABELS[trip.vehicle_type] || trip.vehicle_type}</span>
                                            <span className="flex items-center gap-1"><Calendar className="w-3 h-3" /> {new Date(trip.created_at).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })}</span>
                                            {trip.total_km > 0 && <span>{trip.total_km.toFixed(1)} km</span>}
                                        </div>

                                        {trip.reason && (
                                            <p className="text-xs text-gray-400 mt-1 truncate italic">{trip.reason}</p>
                                        )}

                                        {/* Quick Actions */}
                                        {trip.status === 'requested' && (
                                            <div className="flex items-center gap-2 mt-3 pt-2 border-t border-gray-100">
                                                <button onClick={(e) => { e.stopPropagation(); updateTripStatus(trip.id, 'approved'); }}
                                                    className="px-3 py-1 text-xs font-medium text-white bg-green-600 rounded hover:bg-green-700">
                                                    ✓ Approve
                                                </button>
                                                <button onClick={(e) => { e.stopPropagation(); updateTripStatus(trip.id, 'rejected'); }}
                                                    className="px-3 py-1 text-xs font-medium text-red-600 bg-red-50 rounded hover:bg-red-100">
                                                    ✕ Reject
                                                </button>
                                            </div>
                                        )}
                                        {trip.status === 'approved' && (
                                            <div className="flex items-center gap-2 mt-3 pt-2 border-t border-gray-100">
                                                <button onClick={(e) => { e.stopPropagation(); updateTripStatus(trip.id, 'active'); }}
                                                    className="px-3 py-1 text-xs font-medium text-white bg-blue-600 rounded hover:bg-blue-700">
                                                    ▶ Start Trip
                                                </button>
                                            </div>
                                        )}
                                        {trip.status === 'active' && (
                                            <div className="flex items-center gap-2 mt-3 pt-2 border-t border-gray-100">
                                                <button onClick={(e) => { e.stopPropagation(); updateTripStatus(trip.id, 'completed'); }}
                                                    className="px-3 py-1 text-xs font-medium text-white bg-gray-600 rounded hover:bg-gray-700">
                                                    ■ Complete Trip
                                                </button>
                                            </div>
                                        )}
                                    </div>
                                );
                            })}
                        </div>
                    )}
                </div>

                {/* Trip Details Panel */}
                {selectedTrip && (
                    <div className="w-1/2 bg-white rounded-xl border border-gray-200 overflow-hidden sticky top-4 self-start">
                        <div className="p-4 border-b border-gray-100 flex items-center justify-between">
                            <h3 className="font-semibold text-gray-900 flex items-center gap-2">
                                <Eye className="w-4 h-4 text-primary-500" /> Trip Details
                            </h3>
                            <button onClick={() => setSelectedTrip(null)} className="p-1 text-gray-400 hover:text-gray-600 rounded">
                                <X className="w-4 h-4" />
                            </button>
                        </div>

                        <div className="p-4 space-y-4 max-h-[70vh] overflow-y-auto">
                            {/* Route */}
                            <div>
                                <p className="text-xs text-gray-400 mb-1">Route</p>
                                <p className="font-medium text-gray-900">{selectedTrip.from_location} → {selectedTrip.to_location}</p>
                            </div>

                            {/* Details Grid */}
                            <div className="grid grid-cols-2 gap-3 text-sm">
                                <div><p className="text-xs text-gray-400">Employee</p><p className="font-medium">{selectedTrip.employee_name}</p></div>
                                <div><p className="text-xs text-gray-400">Band</p><p className="font-medium capitalize">{selectedTrip.employee_band?.replace('_', ' ')}</p></div>
                                <div><p className="text-xs text-gray-400">Vehicle</p><p>{VEHICLE_LABELS[selectedTrip.vehicle_type]}</p></div>
                                <div><p className="text-xs text-gray-400">Distance</p><p>{selectedTrip.total_km.toFixed(1)} km</p></div>
                            </div>

                            {selectedTrip.reason && (
                                <div><p className="text-xs text-gray-400 mb-1">Reason</p><p className="text-sm text-gray-700">{selectedTrip.reason}</p></div>
                            )}

                            {/* Expenses */}
                            <div>
                                <p className="text-xs text-gray-400 mb-2 flex items-center gap-1">
                                    <IndianRupee className="w-3 h-3" /> Trip Expenses
                                </p>

                                {loadingExpenses ? (
                                    <p className="text-xs text-gray-400">Loading...</p>
                                ) : tripExpenses.length === 0 ? (
                                    <div className="text-center py-4 bg-gray-50 rounded-lg">
                                        <p className="text-xs text-gray-400">No expenses submitted yet</p>
                                    </div>
                                ) : (
                                    <div className="space-y-2">
                                        {tripExpenses.map(exp => (
                                            <div key={exp.id} className={`p-3 rounded-lg border ${exp.exceeds_limit ? 'border-red-200 bg-red-50' : 'border-gray-100 bg-gray-50'}`}>
                                                <div className="flex items-center justify-between mb-1">
                                                    <span className="text-sm font-medium">{CATEGORY_LABELS[exp.category] || exp.category}</span>
                                                    <span className="text-sm font-bold">₹{exp.amount}</span>
                                                </div>
                                                {exp.description && <p className="text-xs text-gray-500">{exp.description}</p>}
                                                <div className="flex items-center justify-between mt-2">
                                                    <span className="text-xs text-gray-400">{new Date(exp.date).toLocaleDateString('en-IN', { day: '2-digit', month: 'short' })}</span>
                                                    <div className="flex items-center gap-1">
                                                        {exp.exceeds_limit && (
                                                            <span className="text-xs text-red-600 font-medium">Over limit (₹{exp.limit_amount})</span>
                                                        )}
                                                        {exp.status === 'pending' && (
                                                            <>
                                                                <button onClick={() => updateExpenseStatus(exp.id, 'approved')}
                                                                    className="px-2 py-0.5 text-xs text-green-700 bg-green-100 rounded hover:bg-green-200">✓</button>
                                                                <button onClick={() => updateExpenseStatus(exp.id, 'rejected')}
                                                                    className="px-2 py-0.5 text-xs text-red-700 bg-red-100 rounded hover:bg-red-200">✕</button>
                                                            </>
                                                        )}
                                                        {exp.status === 'approved' && <span className="text-xs text-green-600">✓ Approved</span>}
                                                        {exp.status === 'rejected' && <span className="text-xs text-red-600">✕ Rejected</span>}
                                                    </div>
                                                </div>
                                            </div>
                                        ))}
                                        <div className="pt-2 border-t border-gray-200 text-right">
                                            <span className="text-sm font-bold text-gray-900">
                                                Total: ₹{tripExpenses.reduce((s, e) => s + Number(e.amount), 0).toLocaleString('en-IN')}
                                            </span>
                                        </div>
                                    </div>
                                )}
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
}
