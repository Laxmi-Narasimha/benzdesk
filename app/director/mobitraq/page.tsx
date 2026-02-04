'use client';

import React, { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { getSupabaseClient } from '@/lib/supabaseClient';
import {
    MapPin,
    Users,
    Clock,
    Gauge,
    Activity,
    Calendar,
    Map
} from 'lucide-react';

interface Session {
    id: string;
    employee_id: string;
    start_time: string;
    end_time: string | null;
    total_km: number;
    employees: {
        name: string;
        phone: string;
    } | null;
}

interface ExpenseClaim {
    id: string;
    employee_id: string;
    claim_date: string;
    total_amount: number;
    status: string;
    employees: {
        name: string;
        phone: string;
    } | null;
}

interface EmployeeStats {
    id: string;
    name: string;
    phone: string;
    totalSessions: number;
    totalDistance: number; // in km
    totalDuration: number;
    isActive: boolean;
}

const getIstDateString = (date: Date = new Date()) =>
    date.toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });

export default function MobitraqDashboard() {
    const searchParams = useSearchParams();
    const dateParam = searchParams.get('date');

    const [sessions, setSessions] = useState<Session[]>([]);
    const [expenses, setExpenses] = useState<ExpenseClaim[]>([]);
    const [employeeStats, setEmployeeStats] = useState<EmployeeStats[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [selectedDate, setSelectedDate] = useState<string>('');
    const [todayStats, setTodayStats] = useState({
        activeSessions: 0,
        totalEmployees: 0,
        totalKmToday: 0,
        totalHoursToday: 0,
        totalExpenses: 0,
        expenseCount: 0,
    });

    // Set date on client side only to prevent hydration mismatch
    useEffect(() => {
        const today = getIstDateString();
        setSelectedDate(dateParam || today);
    }, [dateParam]);

    const fetchData = useCallback(async (date: string) => {
        setIsLoading(true);
        try {
            const supabase = getSupabaseClient();

            // Ensure date is valid, fallback to today if empty
            const validDate = date && date.length >= 10 ? date : getIstDateString();

            // Start and end of selected date
            const startOfDay = `${validDate}T00:00:00+05:30`;
            const endOfDay = `${validDate}T23:59:59+05:30`;

            const { data: sessionsData, error: sessionsError } = await supabase
                .from('shift_sessions')
                .select(`
                    id,
                    employee_id,
                    start_time,
                    end_time,
                    total_km,
                    employees (
                        name,
                        phone
                    )
                `)
                .gte('start_time', startOfDay)
                .lte('start_time', endOfDay)
                .order('start_time', { ascending: false });

            if (sessionsError) throw sessionsError;

            // Transform data to handle Supabase relation format
            const transformedSessions: Session[] = (sessionsData || []).map((s: any) => ({
                ...s,
                employees: Array.isArray(s.employees) ? s.employees[0] : s.employees
            }));

            // Fetch Expenses
            const { data: expenseData, error: expenseError } = await supabase
                .from('expense_claims')
                .select(`
                    id,
                    employee_id,
                    claim_date,
                    total_amount,
                    status,
                    employees!expense_claims_employee_id_fkey (
                        name,
                        phone
                    )
                `)
                .eq('claim_date', date)
                .order('created_at', { ascending: false });

            if (expenseError) throw expenseError;

            const transformedExpenses: ExpenseClaim[] = (expenseData || []).map((e: any) => ({
                ...e,
                employees: Array.isArray(e.employees) ? e.employees[0] : e.employees
            }));

            setSessions(transformedSessions);
            setExpenses(transformedExpenses);

            // Calculate stats
            const activeSessions = transformedSessions.filter(s => !s.end_time).length;
            const totalKm = transformedSessions.reduce((sum, s) => sum + (s.total_km || 0), 0);

            // Expense Stats
            const totalExpenseAmount = transformedExpenses.reduce((sum, e) => sum + (e.total_amount || 0), 0);
            const expenseCount = transformedExpenses.length;

            // Calculate total hours
            let totalMinutes = 0;
            transformedSessions.forEach(session => {
                const start = new Date(session.start_time);
                const end = session.end_time ? new Date(session.end_time) : new Date();
                totalMinutes += (end.getTime() - start.getTime()) / (1000 * 60);
            });

            // Get unique employees count
            const uniqueEmployees = new Set(transformedSessions.map(s => s.employee_id)).size;

            setTodayStats({
                activeSessions,
                totalEmployees: uniqueEmployees,
                totalKmToday: Math.max(0, totalKm),
                totalHoursToday: Math.max(0, Math.round(totalMinutes / 60 * 10) / 10),
                totalExpenses: totalExpenseAmount,
                expenseCount: expenseCount,
            });

            // Aggregate by employee using plain object (Map causes runtime issues in minified bundle)
            const statsRecord: Record<string, EmployeeStats> = {};
            transformedSessions.forEach(session => {
                const emp = session.employees;
                if (!emp) return;

                const existing = statsRecord[session.employee_id] || {
                    id: session.employee_id,
                    name: emp.name,
                    phone: emp.phone || '',
                    totalSessions: 0,
                    totalDistance: 0,
                    totalDuration: 0,
                    isActive: false,
                };

                existing.totalSessions++;
                existing.totalDistance += session.total_km || 0;

                const start = new Date(session.start_time);
                const end = session.end_time ? new Date(session.end_time) : new Date();
                existing.totalDuration += (end.getTime() - start.getTime()) / (1000 * 60);

                if (!session.end_time) existing.isActive = true;

                statsRecord[session.employee_id] = existing;
            });

            // Sort: active employees first, then by name
            const sortedStats = Object.values(statsRecord).sort((a, b) => {
                if (a.isActive && !b.isActive) return -1;
                if (!a.isActive && b.isActive) return 1;
                return a.name.localeCompare(b.name);
            });
            setEmployeeStats(sortedStats);

        } catch (error) {
            console.error('Error fetching mobitraq data:', error);
        } finally {
            setIsLoading(false);
        }
    }, []);

    useEffect(() => {
        if (selectedDate) {
            void fetchData(selectedDate);
        }
    }, [selectedDate, fetchData]);

    const formatDuration = (minutes: number) => {
        if (minutes < 0 || !isFinite(minutes)) return 'Invalid';
        const hours = Math.floor(minutes / 60);
        const mins = Math.round(minutes % 60);
        return `${hours}h ${mins}m`;
    };

    if (isLoading) {
        return (
            <div className="flex items-center justify-center min-h-[400px]">
                <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary-500"></div>
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
                            onChange={(e) => setSelectedDate(e.target.value)}
                            className="outline-none text-sm text-gray-700 bg-transparent"
                        />
                    </div>
                </div>
            </div>

            {/* Stats Cards */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                <StatsCard
                    icon={<Activity className="w-6 h-6" />}
                    label="Active Sessions"
                    value={todayStats.activeSessions}
                    color="green"
                    subtitle="Currently tracking"
                />
                <StatsCard
                    icon={<Users className="w-6 h-6" />}
                    label="Field Employees"
                    value={todayStats.totalEmployees}
                    color="blue"
                    subtitle="Tracked today"
                />
                <StatsCard
                    icon={<Gauge className="w-6 h-6" />}
                    label="Total Distance"
                    value={`${todayStats.totalKmToday.toFixed(1)} km`}
                    color="purple"
                    subtitle="Covered today"
                />
                <StatsCard
                    icon={<Clock className="w-6 h-6" />}
                    label="Total Hours"
                    value={`${todayStats.totalHoursToday}h`}
                    color="orange"
                    subtitle="Field time today"
                />
                <StatsCard
                    icon={<div className="font-bold text-lg">₹</div>}
                    label="Total Expenses"
                    value={`₹${todayStats.totalExpenses.toLocaleString()}`}
                    color="green" // Using green for money? Or maybe separate color
                    subtitle={`${todayStats.expenseCount} claims lodged`}
                />
            </div>

            {/* Employee Stats Table */}
            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                <div className="px-6 py-4 border-b border-gray-200">
                    <h2 className="text-lg font-semibold text-gray-900">Field Activity - {selectedDate}</h2>
                </div>

                {employeeStats.length === 0 ? (
                    <div className="p-8 text-center text-gray-500">
                        <MapPin className="w-12 h-12 mx-auto text-gray-300 mb-3" />
                        <p>No field activity recorded today</p>
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
                                                    <span className="w-1.5 h-1.5 rounded-full bg-green-500 animate-pulse"></span>
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

            {/* Expenses List */}
            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                <div className="px-6 py-4 border-b border-gray-200">
                    <h2 className="text-lg font-semibold text-gray-900">Expense Claims - {selectedDate}</h2>
                </div>

                {expenses.length === 0 ? (
                    <div className="p-8 text-center text-gray-500">
                        <p>No expense claims lodged for this date</p>
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
                                            <div className="font-medium text-gray-900">{exp.employees?.name || 'Unknown'}</div>
                                            <div className="text-sm text-gray-500">{exp.employees?.phone || ''}</div>
                                        </td>
                                        <td className="px-6 py-4">
                                            <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium ${exp.status === 'approved' ? 'bg-green-100 text-green-800' :
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
                                                href="/director/mobitraq/expenses"
                                                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium text-primary-600 bg-primary-50 rounded-md hover:bg-primary-100 transition-colors"
                                            >
                                                {(exp.status === 'submitted' || exp.status === 'in_review') ? 'Review' : 'View'}
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

// Stats Card Component
function StatsCard({
    icon,
    label,
    value,
    color,
    subtitle
}: {
    icon: React.ReactNode;
    label: string;
    value: string | number;
    color: 'green' | 'blue' | 'purple' | 'orange';
    subtitle: string;
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
