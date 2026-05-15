'use client';

import React, { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { getSupabaseClient } from '@/lib/supabaseClient';
import {
    MapPin, Users, Clock, Gauge, Activity, Calendar, Map, AlertCircle, RefreshCw
} from 'lucide-react';

interface Session {
    id: string;
    employee_id: string;
    start_time: string;
    end_time: string | null;
    total_km: number;
    final_km: number | null;
}

interface Employee {
    id: string;
    name: string;
    phone: string | null;
}

interface EmployeeStats {
    id: string;
    name: string;
    phone: string;
    totalSessions: number;
    totalDistance: number;
    totalDuration: number;
    isActive: boolean;
}

interface ExpenseClaim {
    id: string;
    employee_id: string;
    claim_date: string;
    total_amount: number;
    status: string;
    employeeName: string;
    employeePhone: string;
}

const getIstDateString = (date: Date = new Date()) =>
    date.toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });

export default function MobitraqDashboard() {
    const router = useRouter();
    const searchParams = useSearchParams();
    const dateParam = searchParams.get('date');

    const [sessions, setSessions] = useState<Session[]>([]);
    const [expenses, setExpenses] = useState<ExpenseClaim[]>([]);
    const [employeeStats, setEmployeeStats] = useState<EmployeeStats[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [selectedDate, setSelectedDate] = useState<string>('');
    const [todayStats, setTodayStats] = useState({
        activeSessions: 0,
        totalEmployees: 0,
        totalKmToday: 0,
        totalHoursToday: 0,
        totalExpenses: 0,
        expenseCount: 0,
    });

    useEffect(() => {
        const today = getIstDateString();
        setSelectedDate(dateParam || today);
    }, [dateParam]);

    const fetchData = useCallback(async (date: string) => {
        setIsLoading(true);
        setError(null);
        try {
            const supabase = getSupabaseClient();
            const validDate = date && date.length >= 10 ? date : getIstDateString();
            const startOfDay = `${validDate}T00:00:00+05:30`;
            const endOfDay   = `${validDate}T23:59:59+05:30`;

            // ── 1. Fetch all employees (no join, standalone query) ──────────
            const { data: empData, error: empError } = await supabase
                .from('employees')
                .select('id, name, phone')
                .eq('is_active', true);

            if (empError) {
                console.error('[mobitraq] employees fetch error:', empError);
                setError(`Could not load employees: ${empError.message}`);
                setIsLoading(false);
                return;
            }

            const employeeMap: Record<string, Employee> = {};
            (empData || []).forEach((e: Employee) => { employeeMap[e.id] = e; });

            // ── 2. Fetch sessions for the selected date (NO join) ───────────
            const { data: sessionsData, error: sessionsError } = await supabase
                .from('shift_sessions')
                .select('id, employee_id, start_time, end_time, total_km, final_km, status')
                .gte('start_time', startOfDay)
                .lte('start_time', endOfDay)
                .order('start_time', { ascending: false });

            if (sessionsError) {
                console.error('[mobitraq] sessions fetch error:', sessionsError);
                setError(`Could not load sessions: ${sessionsError.message}`);
                setIsLoading(false);
                return;
            }

            const rawSessions: Session[] = sessionsData || [];
            setSessions(rawSessions);

            // ── 3. Fetch expense claims ─────────────────────────────────────
            const { data: expenseData, error: expenseError } = await supabase
                .from('expense_claims')
                .select('id, employee_id, claim_date, total_amount, status')
                .eq('claim_date', validDate)
                .order('created_at', { ascending: false });

            if (expenseError) {
                console.error('[mobitraq] expenses fetch error:', expenseError);
            }

            const rawExpenses = (expenseData || []).map((e: any) => ({
                ...e,
                employeeName: employeeMap[e.employee_id]?.name || 'Unknown',
                employeePhone: employeeMap[e.employee_id]?.phone || '',
            }));
            setExpenses(rawExpenses);

            // ── 4. Compute stats ────────────────────────────────────────────
            // Prefer the locked / road-matched final_km; fall back to legacy
            // total_km only if final_km is unset (pre-Stage-1 sessions).
            const billedKm = (s: Session) =>
                (s.final_km != null && s.final_km > 0 ? s.final_km : (s.total_km || 0));
            const activeSessions = rawSessions.filter((s: any) => !s.end_time).length;
            const totalKm = rawSessions.reduce((sum: number, s: Session) => sum + billedKm(s), 0);
            const totalExpenseAmount = rawExpenses.reduce((sum: number, e: any) => sum + (e.total_amount || 0), 0);

            let totalMinutes = 0;
            rawSessions.forEach((s: Session) => {
                const start = new Date(s.start_time);
                const end = s.end_time ? new Date(s.end_time) : new Date();
                totalMinutes += (end.getTime() - start.getTime()) / 60000;
            });

            const uniqueEmployees = new Set(rawSessions.map((s: Session) => s.employee_id)).size;

            setTodayStats({
                activeSessions,
                totalEmployees: uniqueEmployees,
                totalKmToday: Math.max(0, totalKm),
                totalHoursToday: Math.max(0, Math.round(totalMinutes / 60 * 10) / 10),
                totalExpenses: totalExpenseAmount,
                expenseCount: rawExpenses.length,
            });

            // ── 5. Aggregate by employee ────────────────────────────────────
            const statsRecord: Record<string, EmployeeStats> = {};
            rawSessions.forEach((s: Session) => {
                const emp = employeeMap[s.employee_id];
                const existing = statsRecord[s.employee_id] || {
                    id: s.employee_id,
                    name: emp?.name || `Unknown (${s.employee_id.slice(0, 8)})`,
                    phone: emp?.phone || '',
                    totalSessions: 0,
                    totalDistance: 0,
                    totalDuration: 0,
                    isActive: false,
                };
                existing.totalSessions++;
                existing.totalDistance += billedKm(s);
                const start = new Date(s.start_time);
                const end = s.end_time ? new Date(s.end_time) : new Date();
                existing.totalDuration += (end.getTime() - start.getTime()) / 60000;
                if (!s.end_time) existing.isActive = true;
                statsRecord[s.employee_id] = existing;
            });

            setEmployeeStats(
                Object.values(statsRecord).sort((a, b) => {
                    if (a.isActive && !b.isActive) return -1;
                    if (!a.isActive && b.isActive) return 1;
                    return a.name.localeCompare(b.name);
                })
            );
        } catch (err: any) {
            console.error('[mobitraq] unexpected error:', err);
            setError(`Unexpected error: ${err?.message || String(err)}`);
        } finally {
            setIsLoading(false);
        }
    }, []);

    useEffect(() => {
        if (selectedDate) void fetchData(selectedDate);
    }, [selectedDate, fetchData]);

    const formatDuration = (minutes: number) => {
        if (minutes < 0 || !isFinite(minutes)) return '0h 0m';
        const hours = Math.floor(minutes / 60);
        const mins = Math.round(minutes % 60);
        return `${hours}h ${mins}m`;
    };

    const formatTime = (dateStr: string) =>
        new Date(dateStr).toLocaleTimeString('en-IN', {
            timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit',
        });

    if (isLoading) {
        return (
            <div className="flex items-center justify-center min-h-[400px]">
                <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-500" />
            </div>
        );
    }

    return (
        <div className="space-y-6">
            {/* Header */}
            <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">BenzMobiTraq</h1>
                    <p className="text-gray-500">Field force tracking overview</p>
                </div>
                <div className="flex items-center gap-4">
                    <button
                        onClick={() => void fetchData(selectedDate)}
                        className="inline-flex items-center gap-2 px-3 py-2 text-sm bg-white border border-gray-200 rounded-lg hover:bg-gray-50 transition-colors"
                    >
                        <RefreshCw className="w-4 h-4" />
                        Refresh
                    </button>
                    <Link
                        href={`/director/mobitraq/timeline?date=${selectedDate}`}
                        className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors font-medium"
                    >
                        <Map className="w-4 h-4" />
                        View Timeline
                    </Link>
                    <div className="flex items-center gap-2 bg-white px-3 py-2 rounded-lg border border-gray-200">
                        <Calendar className="w-4 h-4 text-gray-500" />
                        <input
                            type="date"
                            value={selectedDate}
                            onChange={(e) => {
                                const newDate = e.target.value;
                                setSelectedDate(newDate);
                                const params = new URLSearchParams(searchParams.toString());
                                if (newDate) params.set('date', newDate);
                                else params.delete('date');
                                router.replace(`?${params.toString()}`);
                            }}
                            className="outline-none text-sm text-gray-700 bg-transparent"
                        />
                    </div>
                </div>
            </div>

            {/* Error Banner */}
            {error && (
                <div className="flex items-start gap-3 p-4 bg-red-50 border border-red-200 rounded-xl text-red-800">
                    <AlertCircle className="w-5 h-5 mt-0.5 flex-shrink-0 text-red-500" />
                    <div>
                        <p className="font-semibold">Failed to load data</p>
                        <p className="text-sm mt-1">{error}</p>
                        <p className="text-xs mt-2 text-red-600">Check browser console (F12) for full details.</p>
                    </div>
                </div>
            )}

            {/* Stats Cards */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-4">
                <StatsCard icon={<Activity className="w-6 h-6" />} label="Active Sessions"
                    value={todayStats.activeSessions} color="green" subtitle="Currently tracking" />
                <StatsCard icon={<Users className="w-6 h-6" />} label="Field Employees"
                    value={todayStats.totalEmployees} color="blue" subtitle="Tracked today" />
                <StatsCard icon={<Gauge className="w-6 h-6" />} label="Total Distance"
                    value={`${todayStats.totalKmToday.toFixed(1)} km`} color="purple" subtitle="Covered today" />
                <StatsCard icon={<Clock className="w-6 h-6" />} label="Total Hours"
                    value={`${todayStats.totalHoursToday}h`} color="orange" subtitle="Field time today" />
                <StatsCard icon={<div className="font-bold text-lg">₹</div>} label="Total Expenses"
                    value={`₹${todayStats.totalExpenses.toLocaleString()}`} color="green"
                    subtitle={`${todayStats.expenseCount} claims`} />
            </div>

            {/* Sessions count indicator */}
            <div className="text-sm text-gray-500 font-medium">
                {sessions.length === 0
                    ? `No sessions found for ${selectedDate}`
                    : `${sessions.length} session${sessions.length !== 1 ? 's' : ''} on ${selectedDate}`}
            </div>

            {/* Employee Stats Table */}
            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                <div className="px-6 py-4 border-b border-gray-200">
                    <h2 className="text-lg font-semibold text-gray-900">
                        Field Activity — {selectedDate}
                    </h2>
                </div>
                {employeeStats.length === 0 ? (
                    <div className="p-8 text-center text-gray-500">
                        <MapPin className="w-12 h-12 mx-auto text-gray-300 mb-3" />
                        <p className="font-medium">No field activity for this date</p>
                        <p className="text-sm mt-1 text-gray-400">
                            Try selecting a different date. Sessions exist in the database — use the date picker above.
                        </p>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full">
                            <thead className="bg-gray-50">
                                <tr>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Employee</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Sessions</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Distance</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Duration</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-200">
                                {employeeStats.map((emp) => (
                                    <tr key={emp.id} className="hover:bg-gray-50">
                                        <td className="px-6 py-4">
                                            <div className="flex items-center gap-3">
                                                <div className="w-10 h-10 rounded-full bg-primary-100 flex items-center justify-center">
                                                    <span className="text-primary-600 font-semibold">
                                                        {emp.name.charAt(0).toUpperCase()}
                                                    </span>
                                                </div>
                                                <div>
                                                    <div className="font-medium text-gray-900">{emp.name}</div>
                                                    <div className="text-sm text-gray-500">{emp.phone || 'No phone'}</div>
                                                </div>
                                            </div>
                                        </td>
                                        <td className="px-6 py-4">
                                            {emp.isActive ? (
                                                <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium bg-green-100 text-green-700">
                                                    <span className="w-1.5 h-1.5 rounded-full bg-green-500 animate-pulse" />
                                                    Active
                                                </span>
                                            ) : (
                                                <span className="inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium bg-gray-100 text-gray-600">
                                                    Inactive
                                                </span>
                                            )}
                                        </td>
                                        <td className="px-6 py-4 text-gray-900 font-medium">{emp.totalSessions}</td>
                                        <td className="px-6 py-4 text-gray-900">{emp.totalDistance.toFixed(2)} km</td>
                                        <td className="px-6 py-4 text-gray-900">{formatDuration(emp.totalDuration)}</td>
                                        <td className="px-6 py-4">
                                            <Link
                                                href={`/director/mobitraq/timeline?employeeId=${emp.id}&date=${selectedDate}`}
                                                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-primary-600 bg-primary-50 rounded-md hover:bg-primary-100 transition-colors"
                                            >
                                                <Map className="w-3.5 h-3.5" />
                                                View Timeline
                                            </Link>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

            {/* Raw sessions (for debugging — shows even if employee name is missing) */}
            {sessions.length > 0 && (
                <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                    <div className="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
                        <h2 className="text-lg font-semibold text-gray-900">All Sessions — {selectedDate}</h2>
                        <span className="text-sm text-gray-500">{sessions.length} total</span>
                    </div>
                    <div className="overflow-x-auto">
                        <table className="w-full text-sm">
                            <thead className="bg-gray-50">
                                <tr>
                                    <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Time</th>
                                    <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Employee</th>
                                    <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Distance</th>
                                    <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                                    <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">Timeline</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-100">
                                {sessions.map((s) => (
                                    <tr key={s.id} className="hover:bg-gray-50">
                                        <td className="px-4 py-2 text-gray-700 font-mono text-xs">
                                            {formatTime(s.start_time)}
                                            {s.end_time ? ` → ${formatTime(s.end_time)}` : ' (active)'}
                                        </td>
                                        <td className="px-4 py-2 text-gray-900">
                                            {employeeStats.find(e => e.id === s.employee_id)?.name
                                                || `ID: ${s.employee_id.slice(0, 8)}…`}
                                        </td>
                                        <td className="px-4 py-2 text-gray-700">{((s.final_km != null && s.final_km > 0 ? s.final_km : s.total_km) || 0).toFixed(2)} km</td>
                                        <td className="px-4 py-2">
                                            <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                                                !s.end_time ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-600'
                                            }`}>
                                                {!s.end_time ? 'Active' : 'Done'}
                                            </span>
                                        </td>
                                        <td className="px-4 py-2">
                                            <Link
                                                href={`/director/mobitraq/timeline?employeeId=${s.employee_id}&date=${selectedDate}`}
                                                className="text-primary-600 hover:underline text-xs"
                                            >
                                                View
                                            </Link>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </div>
            )}

            {/* Expense Claims */}
            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                <div className="px-6 py-4 border-b border-gray-200">
                    <h2 className="text-lg font-semibold text-gray-900">Expense Claims — {selectedDate}</h2>
                </div>
                {expenses.length === 0 ? (
                    <div className="p-8 text-center text-gray-500">
                        <p>No expense claims for this date</p>
                    </div>
                ) : (
                    <div className="overflow-x-auto">
                        <table className="w-full">
                            <thead className="bg-gray-50">
                                <tr>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Employee</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Status</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Amount</th>
                                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Actions</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-gray-200">
                                {expenses.map((exp) => (
                                    <tr key={exp.id} className="hover:bg-gray-50">
                                        <td className="px-6 py-4">
                                            <div className="font-medium text-gray-900">{exp.employeeName}</div>
                                            <div className="text-sm text-gray-500">{exp.employeePhone}</div>
                                        </td>
                                        <td className="px-6 py-4">
                                            <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium ${
                                                exp.status === 'approved' ? 'bg-green-100 text-green-800' :
                                                exp.status === 'rejected' ? 'bg-red-100 text-red-800' :
                                                'bg-yellow-100 text-yellow-800'
                                            }`}>
                                                {exp.status.charAt(0).toUpperCase() + exp.status.slice(1)}
                                            </span>
                                        </td>
                                        <td className="px-6 py-4 font-semibold text-gray-900">
                                            ₹{exp.total_amount.toLocaleString()}
                                        </td>
                                        <td className="px-6 py-4">
                                            <Link
                                                href={`/admin/request?id=${exp.id}`}
                                                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-primary-600 bg-primary-50 rounded-md hover:bg-primary-100 transition-colors"
                                            >
                                                {exp.status === 'submitted' ? 'Review' : 'View'}
                                            </Link>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>
        </div>
    );
}

function StatsCard({ icon, label, value, color, subtitle }: {
    icon: React.ReactNode; label: string; value: string | number;
    color: 'green' | 'blue' | 'purple' | 'orange'; subtitle: string;
}) {
    const colorClasses = {
        green: 'bg-green-50 text-green-600',
        blue: 'bg-blue-50 text-blue-600',
        purple: 'bg-purple-50 text-purple-600',
        orange: 'bg-orange-50 text-orange-600',
    };
    return (
        <div className="bg-white rounded-xl border border-gray-200 p-6">
            <div className="flex items-center gap-4">
                <div className={`w-12 h-12 rounded-lg ${colorClasses[color]} flex items-center justify-center`}>
                    {icon}
                </div>
                <div>
                    <p className="text-sm text-gray-500">{label}</p>
                    <p className="text-2xl font-bold text-gray-900">{value}</p>
                    <p className="text-xs text-gray-400">{subtitle}</p>
                </div>
            </div>
        </div>
    );
}
