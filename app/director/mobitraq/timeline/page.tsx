'use client';

import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { PageLoader, Card, StatCard, TimelineItem, Badge } from '@/components/ui';
import dynamic from 'next/dynamic';

import {
    MapPin,
    Calendar,
    User,
    Clock,
    Navigation,
    Route,
    Target,
    Activity,
    Search,
    ChevronRight,
    Play,
    Square
} from 'lucide-react';

import ErrorBoundary from '@/components/ErrorBoundary';

// Dynamic import for map to prevent SSR issues with Leaflet
const MapComponent = dynamic(() => import('./MapComponent'), {
    ssr: false,
    loading: () => (
        <div className="h-full w-full flex items-center justify-center bg-gray-50 dark:bg-dark-900 text-gray-400">
            <div className="animate-spin w-5 h-5 border-2 border-primary-500 border-t-transparent rounded-full" />
        </div>
    )
});

// Types
interface Employee {
    id: string;
    name: string;
    phone: string;
}

interface LocationPoint {
    id: string;
    latitude: number;
    longitude: number;
    recorded_at: string;
    speed: number | null;
    accuracy: number | null;
}

interface Session {
    id: string;
    session_name: string | null;
    start_time: string;
    end_time: string | null;
    status: string;
}

interface SessionRollup {
    session_id: string;
    distance_km: number;
    point_count: number;
}

interface TimelineEvent {
    id: string;
    event_type: 'start' | 'end' | 'stop' | 'move';
    start_time: string;
    end_time: string | null;
    duration_sec: number | null;
    distance_km: number | null;
    center_lat: number | null;
    center_lng: number | null;
    address: string | null;
}

interface DailyRollup {
    day: string;
    distance_km: number;
    session_count: number;
    point_count: number;
}

const getIstDateString = (date: Date = new Date()) =>
    date.toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });

const isValidDateString = (value: string | null | undefined) =>
    !!value && /^\d{4}-\d{2}-\d{2}$/.test(value);

const STORAGE_KEYS = {
    employeeId: 'mobitraq.timeline.employeeId',
    date: 'mobitraq.timeline.date',
} as const;

export default function TimelinePage() {
    const router = useRouter();
    const searchParams = useSearchParams();
    const empIdParam = searchParams?.get('employeeId') ?? searchParams?.get('employee');
    const dateParam = searchParams?.get('date');

    const [employees, setEmployees] = useState<Employee[]>([]);
    const [selectedEmployee, setSelectedEmployee] = useState<string>('');
    const [selectedDate, setSelectedDate] = useState<string>('');
    const [loading, setLoading] = useState(true);
    const [dataLoading, setDataLoading] = useState(false);

    // Data states
    const [points, setPoints] = useState<LocationPoint[]>([]);
    const [sessions, setSessions] = useState<Session[]>([]);
    const [rollups, setRollups] = useState<SessionRollup[]>([]);
    const [timelineEvents, setTimelineEvents] = useState<TimelineEvent[]>([]);
    const [dailyRollup, setDailyRollup] = useState<DailyRollup | null>(null);

    const [mapReady, setMapReady] = useState(false);

    // Focused Session logic
    const [focusedSession, setFocusedSession] = useState<string | null>(null);

    // Set date on client side
    useEffect(() => {
        const stored = typeof window !== 'undefined' ? localStorage.getItem(STORAGE_KEYS.date) : null;
        const initial = isValidDateString(dateParam)
            ? dateParam!
            : isValidDateString(stored)
                ? stored!
                : getIstDateString();
        setSelectedDate(initial);
    }, []);

    // Load employees
    useEffect(() => {
        loadEmployees();
        setTimeout(() => setMapReady(true), 100);
    }, []);

    // Real-time tracking
    useEffect(() => {
        const today = getIstDateString();
        const isToday = selectedDate === today;

        if (!selectedEmployee || !isToday) return;

        const supabase = getSupabaseClient();
        const channelName = `tracking_${selectedEmployee}`;

        const channel = supabase
            .channel(channelName)
            .on(
                'postgres_changes',
                {
                    event: 'INSERT',
                    schema: 'public',
                    table: 'location_points',
                    filter: `employee_id=eq.${selectedEmployee}`
                },
                (payload) => {
                    const newPoint = payload.new as LocationPoint;
                    setPoints(prev => [...prev, newPoint]);
                }
            )
            .subscribe();

        return () => {
            supabase.removeChannel(channel);
        };
    }, [selectedEmployee, selectedDate]);

    async function loadEmployees() {
        const supabase = getSupabaseClient();
        const { data } = await supabase.from('employees').select('id, name, phone').order('name');

        if (data) {
            setEmployees(data);
            const storedEmployeeId = typeof window !== 'undefined' ? localStorage.getItem(STORAGE_KEYS.employeeId) : null;
            const candidate = empIdParam ?? storedEmployeeId ?? selectedEmployee;

            if (candidate && data.find((e) => e.id === candidate)) {
                setSelectedEmployee(candidate);
            } else if (data.length > 0 && !selectedEmployee) {
                setSelectedEmployee(data[0].id);
            }
        }
        setLoading(false);
    }

    const handleEmployeeChange = (e: React.ChangeEvent<HTMLSelectElement>) => {
        const newId = e.target.value;
        setSelectedEmployee(newId);
        const params = new URLSearchParams(searchParams?.toString());
        params.set('employeeId', newId);
        params.delete('employee');
        if (isValidDateString(selectedDate)) params.set('date', selectedDate);
        router.replace(`?${params.toString()}`);
    };

    const handleDateChange = (e: React.ChangeEvent<HTMLInputElement>) => {
        const nextDate = e.target.value;
        setSelectedDate(nextDate);
        const params = new URLSearchParams(searchParams?.toString());
        if (selectedEmployee) params.set('employeeId', selectedEmployee);
        params.delete('employee');
        if (isValidDateString(nextDate)) params.set('date', nextDate);
        router.replace(`?${params.toString()}`);
    };

    useEffect(() => {
        if (!selectedEmployee) return;
        localStorage.setItem(STORAGE_KEYS.employeeId, selectedEmployee);
    }, [selectedEmployee]);

    useEffect(() => {
        if (!isValidDateString(selectedDate)) return;
        localStorage.setItem(STORAGE_KEYS.date, selectedDate);
    }, [selectedDate]);

    const loadTimelineData = useCallback(async () => {
        setDataLoading(true);
        setFocusedSession(null); // Reset focus on new data load

        try {
            const supabase = getSupabaseClient();
            const validDate = selectedDate && selectedDate.length >= 10 ? selectedDate : getIstDateString();
            const startOfDay = `${validDate}T00:00:00+05:30`;
            const endOfDay = `${validDate}T23:59:59+05:30`;

            // Parallel fetch for speed
            const [sessionsRes, pointsRes, eventsRes] = await Promise.all([
                supabase
                    .from('shift_sessions')
                    .select('id, session_name, start_time, end_time, status')
                    .eq('employee_id', selectedEmployee)
                    .gte('start_time', startOfDay)
                    .lte('start_time', endOfDay)
                    .order('start_time', { ascending: true }),
                supabase
                    .from('location_points')
                    .select('id, latitude, longitude, recorded_at, speed, accuracy')
                    .eq('employee_id', selectedEmployee)
                    .gte('recorded_at', startOfDay)
                    .lte('recorded_at', endOfDay)
                    .order('recorded_at', { ascending: true }),
                supabase
                    .from('timeline_events')
                    .select('*')
                    .eq('employee_id', selectedEmployee)
                    .gte('start_time', startOfDay)
                    .lte('start_time', endOfDay)
                    .order('start_time', { ascending: true })
            ]);

            setSessions(sessionsRes.data || []);
            setPoints(pointsRes.data || []);
            setTimelineEvents(eventsRes.data || []);

            // Rollups
            if (sessionsRes.data && sessionsRes.data.length > 0) {
                const sessionIds = sessionsRes.data.map((s) => s.id);
                const { data: rollupsData } = await supabase
                    .from('session_rollups')
                    .select('session_id, distance_km, point_count')
                    .in('session_id', sessionIds);
                setRollups(rollupsData || []);
            } else {
                setRollups([]);
            }

            setDailyRollup(null);
        } catch (error) {
            console.error('Error loading timeline data:', error);
        } finally {
            setDataLoading(false);
        }
    }, [selectedEmployee, selectedDate]);

    useEffect(() => {
        if (selectedEmployee && selectedDate) {
            void loadTimelineData();
        }
    }, [selectedEmployee, selectedDate, loadTimelineData]);

    // Map Configuration
    const mapConfig = useMemo(() => {
        if (points.length === 0) return { center: [20.5937, 78.9629] as [number, number], zoom: 5 };
        const lats = points.map((p) => p.latitude);
        const lngs = points.map((p) => p.longitude);
        const minLat = Math.min(...lats), maxLat = Math.max(...lats);
        const minLng = Math.min(...lngs), maxLng = Math.max(...lngs);
        const centerLat = (minLat + maxLat) / 2;
        const centerLng = (minLng + maxLng) / 2;
        const maxSpan = Math.max(maxLat - minLat, maxLng - minLng);
        let zoom = 15;
        if (maxSpan > 0.5) zoom = 10;
        else if (maxSpan > 0.1) zoom = 12;
        else if (maxSpan > 0.05) zoom = 13;
        else if (maxSpan > 0.01) zoom = 14;
        return { center: [centerLat, centerLng] as [number, number], zoom };
    }, [points]);

    // Filter Logic
    const { filteredPoints, filteredEvents, focusedSessionData } = useMemo(() => {
        if (!focusedSession) {
            return { filteredPoints: points, filteredEvents: timelineEvents, focusedSessionData: null };
        }
        const session = sessions.find(s => s.id === focusedSession);
        if (!session) {
            return { filteredPoints: points, filteredEvents: timelineEvents, focusedSessionData: null };
        }

        const startMs = new Date(session.start_time).getTime();
        const endMs = session.end_time ? new Date(session.end_time).getTime() : Date.now();

        const filtered = points.filter(p => {
            const recordedMs = new Date(p.recorded_at).getTime();
            return recordedMs >= startMs && recordedMs <= endMs;
        });

        const events = timelineEvents.filter(e => {
            const eventMs = new Date(e.start_time).getTime();
            return eventMs >= startMs && eventMs <= endMs;
        });

        const rollup = rollups.find(r => r.session_id === focusedSession);
        const distanceKm = rollup?.distance_km || 0;
        const durationMin = (endMs - startMs) / 60000;
        const avgSpeedKmh = durationMin > 0 ? (distanceKm / (durationMin / 60)) : 0;
        const stopsCount = events.filter(e => e.event_type === 'stop').length;

        return {
            filteredPoints: filtered,
            filteredEvents: events,
            focusedSessionData: {
                session,
                distanceKm,
                durationMin,
                avgSpeedKmh,
                stopsCount,
                pointCount: filtered.length,
            }
        };
    }, [focusedSession, points, sessions, timelineEvents, rollups]);

    const focusedMapConfig = useMemo(() => {
        const pts = filteredPoints;
        if (pts.length === 0) return { center: [20.5937, 78.9629] as [number, number], zoom: 5 };
        const lats = pts.map((p) => p.latitude);
        const lngs = pts.map((p) => p.longitude);
        const minLat = Math.min(...lats), maxLat = Math.max(...lats);
        const minLng = Math.min(...lngs), maxLng = Math.max(...lngs);
        const centerLat = (minLat + maxLat) / 2;
        const centerLng = (minLng + maxLng) / 2;
        const maxSpan = Math.max(maxLat - minLat, maxLng - minLng);
        let zoom = 15;
        if (maxSpan > 0.5) zoom = 10;
        else if (maxSpan > 0.1) zoom = 12;
        else if (maxSpan > 0.05) zoom = 13;
        else if (maxSpan > 0.01) zoom = 14;
        return { center: [centerLat, centerLng] as [number, number], zoom };
    }, [filteredPoints]);

    const filteredRoutePositions = useMemo(() => filteredPoints.map((p) => [p.latitude, p.longitude] as [number, number]), [filteredPoints]);
    const routePositions = useMemo(() => points.map((p) => [p.latitude, p.longitude] as [number, number]), [points]);

    const stats = useMemo(() => {
        const totalKm = dailyRollup?.distance_km || rollups.reduce((sum, r) => sum + r.distance_km, 0);
        const totalPoints = dailyRollup?.point_count || rollups.reduce((sum, r) => sum + r.point_count, 0);
        const stopsCount = timelineEvents.filter((e) => e.event_type === 'stop').length;
        let totalMinutes = 0;
        sessions.forEach((s) => {
            if (s.end_time) {
                const start = new Date(s.start_time).getTime();
                const end = new Date(s.end_time).getTime();
                totalMinutes += (end - start) / 60000;
            }
        });
        return { totalKm, totalPoints, stopsCount, totalMinutes };
    }, [dailyRollup, rollups, timelineEvents, sessions]);

    const formatTime = (isoString: string) => new Date(isoString).toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit' });
    const formatDuration = (minutes: number) => {
        if (minutes < 0 || !isFinite(minutes)) return '0m';
        const hrs = Math.floor(minutes / 60);
        const mins = Math.round(minutes % 60);
        if (hrs > 0) return `${hrs}h ${mins}m`;
        return `${mins}m`;
    };

    if (loading) return <PageLoader message="Loading employees..." />;

    return (
        <div className="space-y-6 h-[calc(100vh-100px)] flex flex-col">
            {/* Header & Filters */}
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 shrink-0">
                <div>
                    <h1 className="text-2xl font-bold text-slate-900">Activity Timeline</h1>
                    <p className="text-slate-500">Track field movements and sessions</p>
                </div>
                <Card padding="sm" className="flex items-center gap-4 bg-white/50 dark:bg-dark-900/50">
                    <div className="flex items-center gap-2">
                        <User className="w-4 h-4 text-gray-500" />
                        <select
                            value={selectedEmployee}
                            onChange={handleEmployeeChange}
                            className="bg-transparent border-none text-slate-900 focus:ring-0 font-medium cursor-pointer"
                        >
                            {employees.map((emp) => (
                                <option key={emp.id} value={emp.id}>{emp.name}</option>
                            ))}
                        </select>
                    </div>
                    <div className="h-4 w-px bg-gray-300 dark:bg-dark-700" />
                    <div className="flex items-center gap-2">
                        <Calendar className="w-4 h-4 text-gray-500" />
                        <input
                            type="date"
                            value={selectedDate}
                            onChange={handleDateChange}
                            className="bg-transparent border-none text-slate-900 focus:ring-0 font-medium cursor-pointer"
                        />
                    </div>
                </Card>
            </div>

            {/* Stats Overview */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4 shrink-0">
                <StatCard
                    title="Total Distance"
                    value={`${stats.totalKm.toFixed(1)} km`}
                    icon={<Route />}
                    color="info"
                />
                <StatCard
                    title="Total Stops"
                    value={stats.stopsCount}
                    icon={<Target />}
                    color="danger"
                />
                <StatCard
                    title="Active Time"
                    value={formatDuration(stats.totalMinutes)}
                    icon={<Clock />}
                    color="success"
                />
                <StatCard
                    title="Data Points"
                    value={stats.totalPoints}
                    icon={<Activity />}
                    color="primary"
                />
            </div>

            {/* Main Content Grid */}
            <div className="flex-1 grid grid-cols-1 lg:grid-cols-12 gap-6 min-h-0">
                {/* Left Sidebar - Sessions List */}
                <div className="lg:col-span-4 flex flex-col gap-4 min-h-0 max-h-full overflow-hidden">
                    <div className="font-semibold text-gray-900 dark:text-white flex items-center justify-between">
                        <span>Sessions ({sessions.length})</span>
                        {focusedSession && (
                            <button
                                onClick={() => setFocusedSession(null)}
                                className="text-xs text-primary-500 hover:text-primary-600 font-medium"
                            >
                                Show All
                            </button>
                        )}
                    </div>

                    <div className="flex-1 overflow-y-auto space-y-3 pr-2 scrollbar-thin">
                        {sessions.length === 0 ? (
                            <div className="text-center py-10 text-gray-500 border border-dashed border-gray-200 rounded-xl">
                                <Search className="w-8 h-8 mx-auto mb-2 opacity-50" />
                                <p>No sessions recorded</p>
                            </div>
                        ) : (
                            sessions.map((session, idx) => {
                                const rollup = rollups.find((r) => r.session_id === session.id);
                                const isFocused = focusedSession === session.id;
                                const startTime = new Date(session.start_time);
                                const endTime = session.end_time ? new Date(session.end_time) : new Date();
                                const durationMin = (endTime.getTime() - startTime.getTime()) / 60000;

                                return (
                                    <div
                                        key={session.id}
                                        onClick={() => setFocusedSession(isFocused ? null : session.id)}
                                        className={`
                                            group relative p-4 rounded-xl border cursor-pointer transition-all duration-200
                                            ${isFocused
                                                ? 'bg-primary-50 border-primary-500/50 dark:bg-primary-900/10 dark:border-primary-500/30 shadow-md'
                                                : 'bg-white dark:bg-dark-800 border-gray-200 dark:border-dark-700 hover:border-primary-300 dark:hover:border-dark-600 shadow-sm'
                                            }
                                        `}
                                    >
                                        <div className="flex justify-between items-start mb-2">
                                            <div className="flex items-center gap-3">
                                                <div className={`
                                                    w-8 h-8 rounded-lg flex items-center justify-center font-bold text-sm
                                                    ${isFocused
                                                        ? 'bg-primary-500 text-white'
                                                        : 'bg-gray-100 dark:bg-dark-700 text-gray-500 dark:text-gray-400 group-hover:bg-primary-100 dark:group-hover:bg-primary-900/20 group-hover:text-primary-600'
                                                    }
                                                `}>
                                                    #{idx + 1}
                                                </div>
                                                <div>
                                                    <h4 className={`font-semibold ${isFocused ? 'text-primary-700' : 'text-slate-900'}`}>
                                                        {session.session_name || 'Regular Session'}
                                                    </h4>
                                                    <span className={`text-xs ${isFocused ? 'text-primary-600/80' : 'text-gray-500'}`}>
                                                        {formatTime(session.start_time)} - {session.end_time ? formatTime(session.end_time) : 'Active'}
                                                    </span>
                                                </div>
                                            </div>
                                            <ChevronRight className={`w-5 h-5 transition-transform ${isFocused ? 'rotate-90 text-primary-500' : 'text-gray-400'}`} />
                                        </div>


                                        <div className="grid grid-cols-2 gap-2 mt-3 pt-3 border-t border-gray-100 dark:border-dark-700/50">
                                            <div>
                                                <div className="text-xs text-slate-500 font-bold">Distance</div>
                                                <div className="font-semibold text-slate-900">
                                                    {rollup?.distance_km?.toFixed(1) || '0.0'} <span className="text-xs font-normal text-slate-500">km</span>
                                                </div>
                                            </div>
                                            <div>
                                                <div className="text-xs text-slate-500 font-bold">Duration</div>
                                                <div className="font-semibold text-slate-900">
                                                    {formatDuration(durationMin)}
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                );
                            })
                        )}
                    </div>
                </div>

                {/* Right Content - Map & Events */}
                <div className="lg:col-span-8 flex flex-col gap-4 min-h-0 h-full">
                    {/* Map Section - Using direct div to ensure height propagation */}
                    <div className="flex-1 min-h-[400px] relative p-0 overflow-hidden shadow-card border border-gray-200 dark:border-dark-700 rounded-2xl bg-white dark:bg-dark-800">
                        {dataLoading ? (
                            <div className="absolute inset-0 bg-gray-50/80 dark:bg-dark-900/80 flex items-center justify-center z-10 backdrop-blur-sm">
                                <div className="flex flex-col items-center gap-3 text-gray-500">
                                    <div className="animate-spin w-8 h-8 border-2 border-primary-500 border-t-transparent rounded-full" />
                                    Loading map data...
                                </div>
                            </div>
                        ) : mapReady && filteredPoints.length > 0 ? (
                            <ErrorBoundary fallback={<div className="p-10 text-center">Map Error</div>}>
                                <MapComponent
                                    center={focusedSession ? focusedMapConfig.center : mapConfig.center}
                                    zoom={focusedSession ? focusedMapConfig.zoom : mapConfig.zoom}
                                    routePositions={focusedSession ? filteredRoutePositions : routePositions}
                                    points={filteredPoints}
                                    timelineEvents={filteredEvents}
                                    formatTime={formatTime}
                                />
                                {/* Overlay Stats */}
                                <div className="absolute top-4 right-4 bg-white/90 dark:bg-dark-900/90 backdrop-blur p-3 rounded-xl shadow-lg border border-gray-100 dark:border-dark-700 z-[400] text-right">
                                    <div className="text-xs text-gray-500 uppercase tracking-wider font-semibold mb-1">
                                        {focusedSession ? 'Session Stats' : 'Day Summary'}
                                    </div>
                                    <div className="flex gap-4">
                                        <div>
                                            <div className="text-lg font-bold text-slate-900">
                                                {(focusedSessionData?.distanceKm ?? stats.totalKm).toFixed(1)} <span className="text-xs font-normal">km</span>
                                            </div>
                                            <div className="text-[10px] text-slate-600 font-bold">Distance</div>
                                        </div>
                                        <div>
                                            <div className="text-lg font-bold text-slate-900">
                                                {(focusedSessionData?.avgSpeedKmh ?? 0).toFixed(1)} <span className="text-xs font-normal">km/h</span>
                                            </div>
                                            <div className="text-[10px] text-slate-600 font-bold">Avg Speed</div>
                                        </div>
                                    </div>
                                </div>
                            </ErrorBoundary>
                        ) : (
                            <div className="h-full flex items-center justify-center bg-gray-50 dark:bg-dark-900 text-gray-400">
                                <div className="text-center">
                                    <MapPin className="w-12 h-12 mx-auto mb-3 opacity-20" />
                                    <p>No location data available for this selection</p>
                                </div>
                            </div>
                        )}
                    </div>

                    {/* Timeline Events Log */}
                    <div className="h-1/3 min-h-[250px] bg-white dark:bg-dark-800 rounded-2xl border border-gray-200 dark:border-dark-700 overflow-hidden flex flex-col shadow-sm">
                        <div className="px-5 py-3 border-b border-gray-100 dark:border-dark-700 bg-gray-50/50 dark:bg-dark-800/50 flex justify-between items-center">
                            <h3 className="font-semibold text-slate-900 flex items-center gap-2">
                                <Activity className="w-4 h-4 text-primary-500" />
                                Timeline Log
                            </h3>
                            <Badge variant="subtle" color="gray" size="sm">{filteredEvents.length} Events</Badge>
                        </div>
                        <div className="flex-1 overflow-y-auto p-5 scrollbar-thin">
                            {filteredEvents.length === 0 ? (
                                <p className="text-center text-gray-500 py-10 text-sm">No events recorded yet</p>
                            ) : (
                                <div className="max-w-3xl">
                                    {filteredEvents.map((event, i) => (
                                        <TimelineItem
                                            key={event.id}
                                            type={event.event_type}
                                            title={event.event_type === 'start' ? 'Details Started' : event.event_type === 'end' ? 'Session Ended' : event.event_type === 'stop' ? 'Stopped' : 'Moving'}
                                            subtitle={event.event_type === 'stop' && event.duration_sec ? `${formatDuration(event.duration_sec / 60)}` : undefined}
                                            time={formatTime(event.start_time)}
                                            address={event.address}
                                            isLast={i === filteredEvents.length - 1}
                                        />
                                    ))}
                                </div>
                            )}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
