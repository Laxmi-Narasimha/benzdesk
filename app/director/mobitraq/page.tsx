'use client';

import React, { useEffect, useState } from 'react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import {
    MapPin,
    Users,
    Clock,
    Gauge,
    Activity,
    Calendar
} from 'lucide-react';

interface Session {
    id: string;
    employee_id: string;
    start_time: string;
    end_time: string | null;
    total_km: number;
    employees: {
        name: string;
        email: string;
    } | null;
}

interface EmployeeStats {
    id: string;
    name: string;
    email: string;
    totalSessions: number;
    totalDistance: number; // in km
    totalDuration: number;
    isActive: boolean;
}

export default function MobitraqDashboard() {
    const [sessions, setSessions] = useState<Session[]>([]);
    const [employeeStats, setEmployeeStats] = useState<EmployeeStats[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [todayStats, setTodayStats] = useState({
        activeSessions: 0,
        totalEmployees: 0,
        totalKmToday: 0,
        totalHoursToday: 0,
    });

    useEffect(() => {
        fetchData();
    }, []);

    const fetchData = async () => {
        setIsLoading(true);
        try {
            const supabase = getSupabaseClient();
            const today = new Date().toISOString().split('T')[0];

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
                        email
                    )
                `)
                .gte('start_time', `${today}T00:00:00`)
                .order('start_time', { ascending: false });

            if (sessionsError) throw sessionsError;

            // Transform data to handle Supabase relation format
            const transformedSessions: Session[] = (sessionsData || []).map((s: any) => ({
                ...s,
                employees: Array.isArray(s.employees) ? s.employees[0] : s.employees
            }));

            setSessions(transformedSessions);

            // Calculate stats
            const activeSessions = transformedSessions.filter(s => !s.end_time).length;
            const totalKm = transformedSessions.reduce((sum, s) => sum + (s.total_km || 0), 0);

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
                totalKmToday: totalKm,
                totalHoursToday: Math.round(totalMinutes / 60 * 10) / 10,
            });

            // Aggregate by employee
            const statsMap = new Map<string, EmployeeStats>();
            transformedSessions.forEach(session => {
                const emp = session.employees;
                if (!emp) return;

                const existing = statsMap.get(session.employee_id) || {
                    id: session.employee_id,
                    name: emp.name,
                    email: emp.email,
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

                statsMap.set(session.employee_id, existing);
            });

            setEmployeeStats(Array.from(statsMap.values()));

        } catch (error) {
            console.error('Error fetching mobitraq data:', error);
        } finally {
            setIsLoading(false);
        }
    };

    const formatDuration = (minutes: number) => {
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
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold text-gray-900">BenzMobiTraq</h1>
                    <p className="text-gray-500">Field force tracking overview</p>
                </div>
                <div className="flex items-center gap-2 text-sm text-gray-500">
                    <Calendar className="w-4 h-4" />
                    {new Date().toLocaleDateString('en-IN', {
                        weekday: 'long',
                        year: 'numeric',
                        month: 'long',
                        day: 'numeric'
                    })}
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
            </div>

            {/* Employee Stats Table */}
            <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
                <div className="px-6 py-4 border-b border-gray-200">
                    <h2 className="text-lg font-semibold text-gray-900">Today&apos;s Field Activity</h2>
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
                                                    <div className="text-sm text-gray-500">{emp.email}</div>
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
