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
    Route,
    Target,
    Activity,
    Search,
    ChevronRight,
    AlertCircle,
} from 'lucide-react';

import ErrorBoundary from '@/components/ErrorBoundary';

// Map provider switch.
//
// NEXT_PUBLIC_MAP_PROVIDER=google  → Google Maps (required to render Roads-API
//                                    snapped polyline per Google ToS).
// NEXT_PUBLIC_MAP_PROVIDER=osm     → Legacy Leaflet/OSM (raw GPS only; cannot
//                                    legally display Google-snapped geometry).
// Default: google. See docs/MAP_PROVIDER_MIGRATION.md to revert.
const _mapProvider = (process.env.NEXT_PUBLIC_MAP_PROVIDER ?? 'google').toLowerCase();
const MapComponent = dynamic(
    () =>
        _mapProvider === 'osm'
            ? import('./MapComponent')
            : import('./MapComponentGoogle'),
    {
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
    purpose?: string | null;
}

interface SessionRollup {
    session_id: string;
    distance_km: number;
    point_count: number;
}

interface TimelineEvent {
    id: string;
    event_type:
        | 'start'
        | 'end'
        | 'stop'
        | 'move'
        | 'break_start'
        | 'break_end'
        // Synthesised from `session_stops` rows (NOT from the
        // `timeline_events` table). Carries `kind = 'indoor_walking'`
        // when the StopDetector classified the stop as inside-a-building.
        | 'indoor_walking';
    start_time: string;
    end_time: string | null;
    duration_sec: number | null;
    distance_km: number | null;
    center_lat: number | null;
    center_lng: number | null;
    address: string | null;
    metadata?: any;
    /** True for entries sourced from session_stops rather than timeline_events. */
    fromStopDetector?: boolean;
}

interface DailyRollup {
    day: string;
    distance_km: number;
    session_count: number;
    point_count: number;
}

interface TrackingAlert {
    id: string;
    session_id: string | null;
    code: string;
    message: string | null;
    latitude: number | null;
    longitude: number | null;
    created_at: string;
    resolved_at: string | null;
}

const TRACKING_ALERT_LABEL: Record<string, { label: string; tone: 'warn' | 'error' | 'info' }> = {
    location_services_disabled: { label: 'Location turned off', tone: 'error' },
    location_permission_denied: { label: 'Location permission revoked', tone: 'error' },
    no_gps_fix_60s: { label: 'GPS could not fix', tone: 'warn' },
    session_stopped_unexpectedly: { label: 'Session stopped unexpectedly', tone: 'error' },
    session_ended: { label: 'Session ended', tone: 'info' },
};

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
    const [trackingAlerts, setTrackingAlerts] = useState<TrackingAlert[]>([]);
    // Latest 10 sessions for the selected employee across ANY date.
    // Lets the admin spot a session that exists but landed on a
    // different day (e.g. crossed midnight, started offline + synced
    // hours later) without manually scanning every date picker.
    const [recentSessions, setRecentSessions] = useState<Session[]>([]);

    const [mapReady, setMapReady] = useState(false);
    const [fetchError, setFetchError] = useState<string | null>(null);

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
        setFetchError(null);
        setFocusedSession(null);

        try {
            const supabase = getSupabaseClient();
            const validDate = selectedDate && selectedDate.length >= 10 ? selectedDate : getIstDateString();
            const startOfDay = `${validDate}T00:00:00+05:30`;
            const endOfDay = `${validDate}T23:59:59+05:30`;

            // Parallel fetch for speed.
            //
            // CRITICAL FIX: Supabase clients enforce a default response cap
            // of 1000 rows when no .range() is specified. A 4-hour session
            // with 6-second GPS intervals produces ~2,400 points — the old
            // code silently dropped everything past row 1000, which is why
            // the route polyline visibly cut off at ~100km for long trips.
            // We page through location_points in 1,000-row chunks until
            // exhausted so the rendered polyline matches reality.
            const fetchAllPoints = async (): Promise<LocationPoint[]> => {
                const pageSize = 1000;
                const all: LocationPoint[] = [];
                let from = 0;
                // Hard cap of 50,000 points/day so a misconfigured client
                // can't accidentally pull millions of rows.
                const HARD_CAP = 50000;
                while (from < HARD_CAP) {
                    const { data, error } = await supabase
                        .from('location_points')
                        .select('id, latitude, longitude, recorded_at, speed, accuracy')
                        .eq('employee_id', selectedEmployee)
                        .gte('recorded_at', startOfDay)
                        .lte('recorded_at', endOfDay)
                        .order('recorded_at', { ascending: true })
                        .range(from, from + pageSize - 1);
                    if (error) {
                        console.error('Error paging location_points:', error);
                        break;
                    }
                    const batch = (data as LocationPoint[]) || [];
                    all.push(...batch);
                    if (batch.length < pageSize) break;
                    from += pageSize;
                }
                return all;
            };

            const [sessionsRes, allPoints, eventsRes, alertsRes, stopsRes] = await Promise.all([
                supabase
                    .from('shift_sessions')
                    .select('id, session_name, start_time, end_time, status, purpose')
                    .eq('employee_id', selectedEmployee)
                    .gte('start_time', startOfDay)
                    .lte('start_time', endOfDay)
                    .order('start_time', { ascending: true }),
                fetchAllPoints(),
                supabase
                    .from('timeline_events')
                    .select('*, metadata')
                    .eq('employee_id', selectedEmployee)
                    .gte('start_time', startOfDay)
                    .lte('start_time', endOfDay)
                    .order('start_time', { ascending: true }),
                // Tracking-failure events that the mobile client wrote
                // for this employee on this date. We show them in the
                // sidebar so the admin can see "what went wrong" without
                // having to dig through logs.
                supabase
                    .from('tracking_alerts')
                    .select('id, session_id, code, message, latitude, longitude, created_at, resolved_at')
                    .eq('employee_id', selectedEmployee)
                    .gte('created_at', startOfDay)
                    .lte('created_at', endOfDay)
                    .order('created_at', { ascending: false }),
                // Stops and indoor-walking segments detected by the
                // mobile StopDetector. Folded into timelineEvents below
                // so the existing render path picks them up.
                supabase
                    .from('session_stops')
                    .select('id, session_id, kind, started_at, ended_at, duration_sec, center_lat, center_lng, address, point_count')
                    .eq('employee_id', selectedEmployee)
                    .gte('started_at', startOfDay)
                    .lte('started_at', endOfDay)
                    .order('started_at', { ascending: true }),
            ]);

            if (sessionsRes.error) {
                console.error('[timeline] sessions error:', sessionsRes.error);
                setFetchError(`Sessions: ${sessionsRes.error.message}`);
            }
            if (eventsRes.error) console.error('[timeline] events error:', eventsRes.error);
            if (alertsRes.error) console.error('[timeline] alerts error:', alertsRes.error);
            if (stopsRes.error) console.error('[timeline] stops error:', stopsRes.error);

            setSessions(sessionsRes.data || []);
            setPoints(allPoints);

            // Fold session_stops rows into the timeline event stream so the
            // existing render path picks them up. We synthesise a
            // TimelineEvent per stop with event_type='stop' or
            // 'indoor_walking', tagged with fromStopDetector=true so we
            // can tell them apart from legacy timeline_events stop rows.
            const stopRows = (stopsRes.data || []) as Array<{
                id: string;
                session_id: string;
                kind: 'stop' | 'indoor_walking';
                started_at: string;
                ended_at: string;
                duration_sec: number;
                center_lat: number;
                center_lng: number;
                address: string | null;
                point_count: number;
            }>;
            const stopEvents: TimelineEvent[] = stopRows.map((s) => ({
                id: `stop-${s.id}`,
                event_type: s.kind,
                start_time: s.started_at,
                end_time: s.ended_at,
                duration_sec: s.duration_sec,
                distance_km: null,
                center_lat: s.center_lat,
                center_lng: s.center_lng,
                address: s.address,
                metadata: { source: 'stop_detector', point_count: s.point_count },
                fromStopDetector: true,
            }));

            // Merge with timeline_events from the DB and sort chronologically.
            const merged: TimelineEvent[] = [
                ...((eventsRes.data || []) as TimelineEvent[]),
                ...stopEvents,
            ].sort((a, b) =>
                new Date(a.start_time).getTime() - new Date(b.start_time).getTime(),
            );
            setTimelineEvents(merged);
            setTrackingAlerts((alertsRes.data as TrackingAlert[] | null) || []);

            // Fallback: pull the most recent 10 sessions for this
            // employee across ANY date. If a session is missing from
            // the day-view above (cross-midnight session, offline-
            // synced session landed on a different IST day, etc.)
            // the admin can still find it here in one click.
            try {
                const { data: recent } = await supabase
                    .from('shift_sessions')
                    .select(
                        'id, session_name, start_time, end_time, status, purpose'
                    )
                    .eq('employee_id', selectedEmployee)
                    .order('start_time', { ascending: false })
                    .limit(10);
                setRecentSessions((recent as Session[] | null) || []);
            } catch (e) {
                console.warn('Recent-sessions fallback fetch failed:', e);
                setRecentSessions([]);
            }

            // Per-session billing distance. We deliberately read
            // shift_sessions.final_km (the device-filtered total locked at
            // session end, or Roads-API-verified once the finalizer runs)
            // and NOT session_rollups.distance_km (raw haversine, always
            // inflated). This is Stage 1 of the distance rewrite — see
            // docs/DISTANCE_TRACKING_METHODOLOGY.md.
            if (sessionsRes.data && sessionsRes.data.length > 0) {
                const sessionIds = sessionsRes.data.map((s) => s.id);
                const { data: kmRows } = await supabase
                    .from('shift_sessions')
                    .select('id, final_km, total_km')
                    .in('id', sessionIds);
                // Shape into the legacy {session_id, distance_km, point_count}
                // structure that the rest of the page expects, so nothing
                // else has to change.
                const shaped = (kmRows ?? []).map((r) => {
                    const fk = (r as any).final_km as number | null;
                    const tk = (r as any).total_km as number | null;
                    const km = fk != null && fk > 0 ? fk : (tk ?? 0);
                    return { session_id: (r as any).id, distance_km: km, point_count: 0 };
                });
                setRollups(shaped);
            } else {
                setRollups([]);
            }

            setDailyRollup(null);
        } catch (error: any) {
            console.error('[timeline] unexpected error:', error);
            setFetchError(error?.message || String(error));
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
    //
    // NOTE: a naive `Math.min(...lats)` blows the JS argument-count limit
    // (~64k on V8) for very long sessions. We compute the bounding box
    // in a single linear pass so we stay safe up to the 50k point cap.
    const mapConfig = useMemo(() => {
        if (points.length === 0) return { center: [20.5937, 78.9629] as [number, number], zoom: 5 };
        let minLat = points[0].latitude;
        let maxLat = points[0].latitude;
        let minLng = points[0].longitude;
        let maxLng = points[0].longitude;
        for (let i = 1; i < points.length; i++) {
            const lat = points[i].latitude;
            const lng = points[i].longitude;
            if (lat < minLat) minLat = lat;
            else if (lat > maxLat) maxLat = lat;
            if (lng < minLng) minLng = lng;
            else if (lng > maxLng) maxLng = lng;
        }
        const centerLat = (minLat + maxLat) / 2;
        const centerLng = (minLng + maxLng) / 2;
        const maxSpan = Math.max(maxLat - minLat, maxLng - minLng);
        let zoom = 15;
        if (maxSpan > 2) zoom = 8;
        else if (maxSpan > 0.5) zoom = 10;
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

    // Decimate the polyline if we have more than 3,000 points so Leaflet
    // doesn't choke trying to draw every vertex. Visually 3,000 points is
    // more than enough fidelity for any zoom level a human can read. We
    // always keep the first and last point so the start/end markers line
    // up exactly with the route.
    const decimate = (
        arr: LocationPoint[],
        maxPts: number,
    ): [number, number][] => {
        if (arr.length <= maxPts) {
            return arr.map((p) => [p.latitude, p.longitude] as [number, number]);
        }
        const step = arr.length / maxPts;
        const result: [number, number][] = [];
        for (let i = 0; i < maxPts; i++) {
            const idx = Math.min(Math.floor(i * step), arr.length - 1);
            const p = arr[idx];
            result.push([p.latitude, p.longitude]);
        }
        // Always preserve the exact endpoint.
        const last = arr[arr.length - 1];
        result.push([last.latitude, last.longitude]);
        return result;
    };

    const filteredRoutePositions = useMemo(
        () => decimate(filteredPoints, 3000),
        [filteredPoints],
    );
    const routePositions = useMemo(
        () => decimate(points, 3000),
        [points],
    );

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

            {/* Error Banner */}
            {fetchError && (
                <div className="flex items-start gap-3 p-4 bg-red-50 border border-red-200 rounded-xl text-red-800 shrink-0">
                    <AlertCircle className="w-5 h-5 mt-0.5 flex-shrink-0 text-red-500" />
                    <div>
                        <p className="font-semibold">Failed to load timeline data</p>
                        <p className="text-sm mt-1">{fetchError}</p>
                        <p className="text-xs mt-2 text-red-600">Open browser console (F12) for full details.</p>
                    </div>
                </div>
            )}

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
                                                <div className="min-w-0">
                                                    <h4 className={`font-semibold ${isFocused ? 'text-primary-700' : 'text-slate-900'}`}>
                                                        {session.purpose || session.session_name || 'Regular Session'}
                                                    </h4>
                                                    <span className={`text-xs ${isFocused ? 'text-primary-600/80' : 'text-gray-500'}`}>
                                                        {formatTime(session.start_time)} - {session.end_time ? formatTime(session.end_time) : 'Active'}
                                                    </span>
                                                    {session.purpose && session.session_name && (
                                                        <div className="text-[11px] text-gray-400 italic truncate mt-0.5">
                                                            {session.session_name}
                                                        </div>
                                                    )}
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

                    {/* Recent-sessions fallback (any date). Surfaces
                        sessions that exist on the server but didn't
                        land on the currently selected date — common
                        when a session crossed midnight, or when an
                        offline session synced hours after end and
                        ended up timestamped on a different IST day.
                        Click any row to jump to that day's view. */}
                    {recentSessions.length > 0 && (
                        <div className="bg-white dark:bg-dark-800 rounded-2xl border border-gray-200 dark:border-dark-700 overflow-hidden flex flex-col shadow-sm">
                            <div className="px-5 py-3 border-b border-gray-100 dark:border-dark-700 bg-gray-50/50 dark:bg-dark-800/50 flex justify-between items-center">
                                <h3 className="font-semibold text-slate-900 dark:text-slate-100 flex items-center gap-2">
                                    <Clock className="w-4 h-4 text-primary-500" />
                                    Recent sessions (any date)
                                </h3>
                                <Badge variant="subtle" color="gray" size="sm">{recentSessions.length}</Badge>
                            </div>
                            <div className="max-h-[220px] overflow-y-auto p-3 scrollbar-thin space-y-1.5">
                                {recentSessions.map((s) => {
                                    const dayIst = new Date(s.start_time).toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
                                    const isOnSelectedDay = dayIst === selectedDate;
                                    return (
                                        <button
                                            key={s.id}
                                            type="button"
                                            onClick={() => setSelectedDate(dayIst)}
                                            className={`w-full text-left flex items-center justify-between gap-3 px-3 py-2 rounded-lg border ${isOnSelectedDay ? 'border-primary-300 bg-primary-50/40 dark:bg-primary-900/20' : 'border-gray-100 dark:border-dark-700 hover:bg-gray-50 dark:hover:bg-dark-700/40'} transition-colors`}
                                        >
                                            <div className="min-w-0">
                                                <div className="text-sm font-medium text-slate-900 dark:text-slate-100 truncate">
                                                    {s.purpose || s.session_name || 'Regular Session'}
                                                </div>
                                                <div className="text-[11px] text-gray-500 font-mono">
                                                    {dayIst} · {formatTime(s.start_time)}
                                                    {s.end_time ? ` → ${formatTime(s.end_time)}` : ' · Active'}
                                                </div>
                                            </div>
                                            <ChevronRight className="w-4 h-4 text-gray-400 flex-shrink-0" />
                                        </button>
                                    );
                                })}
                            </div>
                        </div>
                    )}

                    {/* Tracking issue log — populated by the mobile
                        client whenever the user's tracking is interrupted
                        (location turned off, permission revoked, GPS not
                        fixing, session ended unexpectedly, etc.). The
                        admin needs a single place to see WHY a session
                        looks broken without digging through device logs. */}
                    {trackingAlerts.length > 0 && (
                        <div className="bg-white dark:bg-dark-800 rounded-2xl border border-amber-200 dark:border-amber-900/30 overflow-hidden flex flex-col shadow-sm">
                            <div className="px-5 py-3 border-b border-amber-100 dark:border-amber-900/30 bg-amber-50/60 dark:bg-amber-950/20 flex justify-between items-center">
                                <h3 className="font-semibold text-slate-900 dark:text-slate-100 flex items-center gap-2">
                                    <Activity className="w-4 h-4 text-amber-600" />
                                    Tracking Issues
                                </h3>
                                <Badge variant="subtle" color="orange" size="sm">{trackingAlerts.length}</Badge>
                            </div>
                            <div className="max-h-[260px] overflow-y-auto p-3 scrollbar-thin space-y-2">
                                {trackingAlerts.map((alert) => {
                                    const meta = TRACKING_ALERT_LABEL[alert.code] ?? { label: alert.code, tone: 'warn' as const };
                                    const dotColor =
                                        meta.tone === 'error'
                                            ? 'bg-red-500'
                                            : meta.tone === 'warn'
                                                ? 'bg-amber-500'
                                                : 'bg-blue-500';
                                    return (
                                        <div
                                            key={alert.id}
                                            className="flex gap-3 items-start px-3 py-2 rounded-lg border border-gray-100 dark:border-dark-700 hover:bg-gray-50 dark:hover:bg-dark-700/40 transition-colors"
                                        >
                                            <span className={`mt-1.5 inline-block w-2.5 h-2.5 rounded-full ${dotColor}`} />
                                            <div className="flex-1 min-w-0">
                                                <div className="flex items-center justify-between gap-2">
                                                    <p className="text-sm font-medium text-slate-900 dark:text-slate-100 truncate">
                                                        {meta.label}
                                                    </p>
                                                    <span className="text-xs text-gray-500 dark:text-gray-400 flex-shrink-0">
                                                        {formatTime(alert.created_at)}
                                                    </span>
                                                </div>
                                                {alert.message && (
                                                    <p className="text-xs text-gray-600 dark:text-gray-300 mt-0.5 break-words">
                                                        {alert.message}
                                                    </p>
                                                )}
                                                {(alert.latitude != null && alert.longitude != null) && (
                                                    <p className="text-[11px] text-gray-400 dark:text-gray-500 mt-0.5 font-mono">
                                                        {alert.latitude.toFixed(5)}, {alert.longitude.toFixed(5)}
                                                    </p>
                                                )}
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>
                        </div>
                    )}

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
                                    {filteredEvents.map((event, i) => {
                                        const titleMap: Record<TimelineEvent['event_type'], string> = {
                                            start: 'Session started',
                                            end: 'Session ended',
                                            stop: 'Stopped',
                                            move: 'Moving',
                                            break_start: 'Paused',
                                            break_end: 'Resumed',
                                            indoor_walking: 'Walking inside building',
                                        };
                                        const reason = event.metadata?.reason as string | undefined;
                                        const reasonLabel = reason ? ` (${reason.replace(/_/g, ' ')})` : '';
                                        // TimelineItem's prop only accepts the legacy event set.
                                        // Map our synthetic 'indoor_walking' onto 'stop' for the
                                        // visual marker; the distinct title above already tells
                                        // the admin what's different.
                                        const visualType: 'start' | 'end' | 'stop' | 'move' | 'break_start' | 'break_end' =
                                            event.event_type === 'indoor_walking' ? 'stop' : event.event_type;
                                        const isStopLike = event.event_type === 'stop' || event.event_type === 'indoor_walking';
                                        return (
                                            <TimelineItem
                                                key={event.id}
                                                type={visualType}
                                                title={titleMap[event.event_type] ?? 'Event'}
                                                subtitle={
                                                    isStopLike && event.duration_sec
                                                        ? `${formatDuration(event.duration_sec / 60)}`
                                                        : event.event_type === 'break_end' && event.duration_sec
                                                            ? `${formatDuration(event.duration_sec / 60)} on break${reasonLabel}`
                                                            : (event.event_type === 'break_start' || event.event_type === 'break_end')
                                                                ? reasonLabel.trim()
                                                                : undefined
                                                }
                                                time={formatTime(event.start_time)}
                                                address={event.address}
                                                isLast={i === filteredEvents.length - 1}
                                            />
                                        );
                                    })}
                                </div>
                            )}
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
}
