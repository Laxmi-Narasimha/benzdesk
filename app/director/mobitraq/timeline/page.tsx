// ============================================================================
// MobiTraq Timeline Page with Map Visualization
// Shows employee routes, stops, and distance on LeafletJS map
// ============================================================================

'use client';

import React, { useEffect, useState, useMemo } from 'react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { PageLoader, Card } from '@/components/ui';
import dynamic from 'next/dynamic';
import {
    MapPin,
    Calendar,
    User,
    Clock,
    Navigation,
    Circle,
    ChevronDown,
    Activity,
    Route,
    Target,
} from 'lucide-react';

// Dynamic import for Leaflet (SSR incompatible)
// Must use default export for React components
const MapContainer = dynamic(
    () => import('react-leaflet').then((mod) => mod.MapContainer),
    { ssr: false, loading: () => <div className="h-[400px] bg-dark-900 flex items-center justify-center"><span className="text-dark-400">Loading map...</span></div> }
);
const TileLayer = dynamic(
    () => import('react-leaflet').then((mod) => mod.TileLayer),
    { ssr: false }
);
const Polyline = dynamic(
    () => import('react-leaflet').then((mod) => mod.Polyline),
    { ssr: false }
);
const CircleMarker = dynamic(
    () => import('react-leaflet').then((mod) => mod.CircleMarker),
    { ssr: false }
);
const Popup = dynamic(
    () => import('react-leaflet').then((mod) => mod.Popup),
    { ssr: false }
);

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
    event_type: 'stop' | 'move';
    start_time: string;
    end_time: string | null;
    duration_min: number | null;
    distance_km: number | null;
    center_lat: number | null;
    center_lng: number | null;
}

interface DailyRollup {
    day: string;
    distance_km: number;
    session_count: number;
    point_count: number;
}

interface DataError {
    message: string;
}

export default function TimelinePage() {
    const [employees, setEmployees] = useState<Employee[]>([]);
    const [selectedEmployee, setSelectedEmployee] = useState<string>('');
    const [selectedDate, setSelectedDate] = useState<string>(
        new Date().toISOString().split('T')[0]
    );
    const [loading, setLoading] = useState(true);
    const [dataLoading, setDataLoading] = useState(false);

    // Data states
    const [points, setPoints] = useState<LocationPoint[]>([]);
    const [sessions, setSessions] = useState<Session[]>([]);
    const [rollups, setRollups] = useState<SessionRollup[]>([]);
    const [timelineEvents, setTimelineEvents] = useState<TimelineEvent[]>([]);
    const [dailyRollup, setDailyRollup] = useState<DailyRollup | null>(null);

    const [mapReady, setMapReady] = useState(false);

    // Load employees on mount
    useEffect(() => {
        loadEmployees();
        // Delay map ready for SSR
        setTimeout(() => setMapReady(true), 100);
    }, []);

    // Real-time tracking subscription
    useEffect(() => {
        // Only track if a specific employee is selected and we are viewing "today"
        const today = new Date().toISOString().split('T')[0];
        const isToday = selectedDate === today;

        if (!selectedEmployee || !isToday) return;

        const supabase = getSupabaseClient();
        const channelName = `tracking_${selectedEmployee}`;

        console.log('Subscribing to realtime updates for:', selectedEmployee);

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
                    // console.log('New location point:', payload.new);
                    const newPoint = payload.new as LocationPoint;
                    setPoints(prev => [...prev, newPoint]);
                }
            )
            .subscribe();

        return () => {
            console.log('Unsubscribing from:', channelName);
            supabase.removeChannel(channel);
        };
    }, [selectedEmployee, selectedDate]);

    // Load data when employee or date changes
    useEffect(() => {
        if (selectedEmployee && selectedDate) {
            loadTimelineData();
        }
    }, [selectedEmployee, selectedDate]);

    async function loadEmployees() {
        const supabase = getSupabaseClient();
        const { data } = await supabase
            .from('employees')
            .select('id, name, phone')
            .order('name');

        if (data) {
            setEmployees(data);
            if (data.length > 0) {
                setSelectedEmployee(data[0].id);
            }
        }
        setLoading(false);
    }

    async function loadTimelineData() {
        setDataLoading(true);

        try {
            const supabase = getSupabaseClient();

            // Ensure date is valid
            const validDate = selectedDate && selectedDate.length >= 10 ? selectedDate : new Date().toISOString().split('T')[0];
            const startOfDay = `${validDate}T00:00:00`;
            const endOfDay = `${validDate}T23:59:59`;

            console.log('Loading timeline data for:', { employee: selectedEmployee, date: validDate });

            // Fetch sessions for the day
            const { data: sessionsData, error: sessionsError } = await supabase
                .from('shift_sessions')
                .select('id, session_name, start_time, end_time, status')
                .eq('employee_id', selectedEmployee)
                .gte('start_time', startOfDay)
                .lte('start_time', endOfDay)
                .order('start_time', { ascending: true });

            if (sessionsError) {
                console.error('Error fetching sessions:', sessionsError);
            }
            setSessions(sessionsData || []);

            // Fetch location points for the day
            const { data: pointsData, error: pointsError } = await supabase
                .from('location_points')
                .select('id, latitude, longitude, recorded_at, speed, accuracy')
                .eq('employee_id', selectedEmployee)
                .gte('recorded_at', startOfDay)
                .lte('recorded_at', endOfDay)
                .order('recorded_at', { ascending: true });

            if (pointsError) {
                console.error('Error fetching location points:', pointsError);
            }
            setPoints(pointsData || []);

            // Fetch session rollups (if sessions exist)
            if (sessionsData && sessionsData.length > 0) {
                const sessionIds = sessionsData.map((s) => s.id);
                const { data: rollupsData, error: rollupsError } = await supabase
                    .from('session_rollups')
                    .select('session_id, distance_km, point_count')
                    .in('session_id', sessionIds);

                if (rollupsError) {
                    console.error('Error fetching session rollups:', rollupsError);
                }
                setRollups(rollupsData || []);
            } else {
                setRollups([]);
            }

            // Fetch timeline events (table exists but may be empty)
            const { data: eventsData, error: eventsError } = await supabase
                .from('timeline_events')
                .select('*')
                .eq('employee_id', selectedEmployee)
                .gte('start_time', startOfDay)
                .lte('start_time', endOfDay)
                .order('start_time', { ascending: true });

            if (eventsError) {
                console.error('Error fetching timeline events:', eventsError);
            }
            setTimelineEvents(eventsData || []);

            // Skip daily_rollups - table doesn't exist in database
            // Calculate from session_rollups instead
            setDailyRollup(null);

        } catch (error) {
            console.error('Error loading timeline data:', error);
        } finally {
            setDataLoading(false);
        }
    }

    // Calculate map bounds and center
    const mapConfig = useMemo(() => {
        if (points.length === 0) {
            // Default to India center
            return { center: [20.5937, 78.9629] as [number, number], zoom: 5 };
        }

        const lats = points.map((p) => p.latitude);
        const lngs = points.map((p) => p.longitude);
        const minLat = Math.min(...lats);
        const maxLat = Math.max(...lats);
        const minLng = Math.min(...lngs);
        const maxLng = Math.max(...lngs);

        const centerLat = (minLat + maxLat) / 2;
        const centerLng = (minLng + maxLng) / 2;

        // Calculate appropriate zoom level
        const latSpan = maxLat - minLat;
        const lngSpan = maxLng - minLng;
        const maxSpan = Math.max(latSpan, lngSpan);
        let zoom = 15;
        if (maxSpan > 0.5) zoom = 10;
        else if (maxSpan > 0.1) zoom = 12;
        else if (maxSpan > 0.05) zoom = 13;
        else if (maxSpan > 0.01) zoom = 14;

        return { center: [centerLat, centerLng] as [number, number], zoom };
    }, [points]);

    // Calculate route polyline positions
    const routePositions = useMemo(() => {
        return points.map((p) => [p.latitude, p.longitude] as [number, number]);
    }, [points]);

    // Calculate total stats
    const stats = useMemo(() => {
        const totalKm = dailyRollup?.distance_km || rollups.reduce((sum, r) => sum + r.distance_km, 0);
        const totalPoints = dailyRollup?.point_count || rollups.reduce((sum, r) => sum + r.point_count, 0);
        const stopsCount = timelineEvents.filter((e) => e.event_type === 'stop').length;

        // Calculate total duration from sessions
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

    // Format time
    const formatTime = (isoString: string) => {
        return new Date(isoString).toLocaleTimeString('en-IN', {
            hour: '2-digit',
            minute: '2-digit',
        });
    };

    // Format duration
    const formatDuration = (minutes: number) => {
        const hrs = Math.floor(minutes / 60);
        const mins = Math.round(minutes % 60);
        if (hrs > 0) return `${hrs}h ${mins}m`;
        return `${mins}m`;
    };

    if (loading) {
        return <PageLoader message="Loading employees..." />;
    }

    return (
        <div className="space-y-6">
            {/* Header */}
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold text-dark-100">Timeline</h1>
                    <p className="text-dark-400 mt-1">
                        View employee routes and stops with distance tracking
                    </p>
                </div>
            </div>

            {/* Filters */}
            <Card className="p-4">
                <div className="flex flex-wrap gap-4">
                    {/* Employee Selector */}
                    <div className="flex items-center gap-2">
                        <User className="w-4 h-4 text-dark-400" />
                        <select
                            value={selectedEmployee}
                            onChange={(e) => setSelectedEmployee(e.target.value)}
                            className="bg-dark-900 border border-dark-700 rounded-lg px-3 py-2 text-dark-100 focus:outline-none focus:border-primary-500"
                        >
                            {employees.map((emp) => (
                                <option key={emp.id} value={emp.id}>
                                    {emp.name}
                                </option>
                            ))}
                        </select>
                    </div>

                    {/* Date Picker */}
                    <div className="flex items-center gap-2">
                        <Calendar className="w-4 h-4 text-dark-400" />
                        <input
                            type="date"
                            value={selectedDate}
                            onChange={(e) => setSelectedDate(e.target.value)}
                            className="bg-dark-900 border border-dark-700 rounded-lg px-3 py-2 text-dark-100 focus:outline-none focus:border-primary-500"
                        />
                    </div>
                </div>
            </Card>

            {/* Stats Cards */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <Card className="p-4">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-blue-500/20 rounded-lg">
                            <Route className="w-5 h-5 text-blue-400" />
                        </div>
                        <div>
                            <div className="text-2xl font-bold text-dark-100">
                                {stats.totalKm.toFixed(1)} km
                            </div>
                            <div className="text-sm text-dark-400">Distance</div>
                        </div>
                    </div>
                </Card>
                <Card className="p-4">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-red-500/20 rounded-lg">
                            <Target className="w-5 h-5 text-red-400" />
                        </div>
                        <div>
                            <div className="text-2xl font-bold text-dark-100">
                                {stats.stopsCount}
                            </div>
                            <div className="text-sm text-dark-400">Stops</div>
                        </div>
                    </div>
                </Card>
                <Card className="p-4">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-green-500/20 rounded-lg">
                            <Clock className="w-5 h-5 text-green-400" />
                        </div>
                        <div>
                            <div className="text-2xl font-bold text-dark-100">
                                {formatDuration(stats.totalMinutes)}
                            </div>
                            <div className="text-sm text-dark-400">Duration</div>
                        </div>
                    </div>
                </Card>
                <Card className="p-4">
                    <div className="flex items-center gap-3">
                        <div className="p-2 bg-purple-500/20 rounded-lg">
                            <Activity className="w-5 h-5 text-purple-400" />
                        </div>
                        <div>
                            <div className="text-2xl font-bold text-dark-100">
                                {stats.totalPoints}
                            </div>
                            <div className="text-sm text-dark-400">Points</div>
                        </div>
                    </div>
                </Card>
            </div>

            {/* Map */}
            <Card className="p-0 overflow-hidden">
                <div className="h-[400px] w-full relative">
                    {dataLoading && (
                        <div className="absolute inset-0 bg-dark-950/80 flex items-center justify-center z-10">
                            <div className="flex items-center gap-2 text-dark-400">
                                <div className="animate-spin w-5 h-5 border-2 border-primary-500 border-t-transparent rounded-full" />
                                Loading route...
                            </div>
                        </div>
                    )}
                    {mapReady && (
                        <MapContainer
                            key={`${mapConfig.center[0]}-${mapConfig.center[1]}-${mapConfig.zoom}`}
                            center={mapConfig.center}
                            zoom={mapConfig.zoom}
                            className="h-full w-full"
                            style={{ background: '#1a1a2e' }}
                        >
                            <TileLayer
                                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                            />

                            {/* Route polyline */}
                            {routePositions.length > 1 && (
                                <Polyline
                                    positions={routePositions}
                                    color="#3b82f6"
                                    weight={4}
                                    opacity={0.8}
                                />
                            )}

                            {/* Start marker */}
                            {points.length > 0 && (
                                <CircleMarker
                                    center={[points[0].latitude, points[0].longitude]}
                                    radius={10}
                                    fillColor="#22c55e"
                                    fillOpacity={1}
                                    color="#fff"
                                    weight={2}
                                >
                                    <Popup>
                                        <strong>Start</strong>
                                        <br />
                                        {formatTime(points[0].recorded_at)}
                                    </Popup>
                                </CircleMarker>
                            )}

                            {/* End marker */}
                            {points.length > 1 && (
                                <CircleMarker
                                    center={[
                                        points[points.length - 1].latitude,
                                        points[points.length - 1].longitude,
                                    ]}
                                    radius={10}
                                    fillColor="#ef4444"
                                    fillOpacity={1}
                                    color="#fff"
                                    weight={2}
                                >
                                    <Popup>
                                        <strong>End</strong>
                                        <br />
                                        {formatTime(points[points.length - 1].recorded_at)}
                                    </Popup>
                                </CircleMarker>
                            )}

                            {/* Stop markers */}
                            {timelineEvents
                                .filter((e) => e.event_type === 'stop' && e.center_lat && e.center_lng)
                                .map((stop) => (
                                    <CircleMarker
                                        key={stop.id}
                                        center={[stop.center_lat!, stop.center_lng!]}
                                        radius={8}
                                        fillColor="#f59e0b"
                                        fillOpacity={0.9}
                                        color="#fff"
                                        weight={2}
                                    >
                                        <Popup>
                                            <strong>Stop</strong>
                                            <br />
                                            {formatTime(stop.start_time)}
                                            {stop.duration_min && ` (${formatDuration(stop.duration_min)})`}
                                        </Popup>
                                    </CircleMarker>
                                ))}
                        </MapContainer>
                    )}
                </div>
            </Card>

            {/* Sessions List */}
            {sessions.length > 0 && (
                <Card className="p-4">
                    <h3 className="text-lg font-semibold text-dark-100 mb-4 flex items-center gap-2">
                        <Navigation className="w-5 h-5 text-primary-500" />
                        Sessions
                    </h3>
                    <div className="space-y-3">
                        {sessions.map((session) => {
                            const rollup = rollups.find((r) => r.session_id === session.id);
                            return (
                                <div
                                    key={session.id}
                                    className="p-3 bg-dark-900 rounded-lg flex items-center justify-between"
                                >
                                    <div>
                                        <div className="font-medium text-dark-100">
                                            {session.session_name || 'Unnamed Session'}
                                        </div>
                                        <div className="text-sm text-dark-400">
                                            {formatTime(session.start_time)}
                                            {session.end_time && ` - ${formatTime(session.end_time)}`}
                                        </div>
                                    </div>
                                    <div className="text-right">
                                        <div className="font-bold text-primary-400">
                                            {rollup?.distance_km?.toFixed(1) || '0.0'} km
                                        </div>
                                        <div className="text-xs text-dark-500">
                                            {rollup?.point_count || 0} points
                                        </div>
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                </Card>
            )}

            {/* Timeline Events */}
            <Card className="p-4">
                <h3 className="text-lg font-semibold text-dark-100 mb-4 flex items-center gap-2">
                    <Clock className="w-5 h-5 text-primary-500" />
                    Timeline Events
                </h3>
                {timelineEvents.length === 0 && !dataLoading && (
                    <div className="text-center text-dark-400 py-8">
                        No timeline events for this day
                    </div>
                )}
                <div className="space-y-2">
                    {timelineEvents.map((event, idx) => (
                        <div
                            key={event.id}
                            className={`flex items-center gap-4 p-3 rounded-lg ${event.event_type === 'stop'
                                ? 'bg-amber-500/10 border-l-4 border-amber-500'
                                : 'bg-blue-500/10 border-l-4 border-blue-500'
                                }`}
                        >
                            <div
                                className={`p-2 rounded-full ${event.event_type === 'stop'
                                    ? 'bg-amber-500/20'
                                    : 'bg-blue-500/20'
                                    }`}
                            >
                                {event.event_type === 'stop' ? (
                                    <MapPin className="w-4 h-4 text-amber-400" />
                                ) : (
                                    <Navigation className="w-4 h-4 text-blue-400" />
                                )}
                            </div>
                            <div className="flex-1">
                                <div className="font-medium text-dark-100">
                                    {event.event_type === 'stop' ? 'Stop' : 'Moving'}
                                </div>
                                <div className="text-sm text-dark-400">
                                    {formatTime(event.start_time)}
                                    {event.end_time && ` - ${formatTime(event.end_time)}`}
                                </div>
                            </div>
                            <div className="text-right">
                                {event.duration_min && (
                                    <div className="text-sm text-dark-300">
                                        {formatDuration(event.duration_min)}
                                    </div>
                                )}
                                {event.distance_km && event.distance_km > 0 && (
                                    <div className="text-sm font-medium text-primary-400">
                                        {event.distance_km.toFixed(1)} km
                                    </div>
                                )}
                            </div>
                        </div>
                    ))}
                </div>
            </Card>

            {/* No Data Message */}
            {!dataLoading && points.length === 0 && (
                <Card className="p-8 text-center">
                    <MapPin className="w-12 h-12 text-dark-600 mx-auto mb-4" />
                    <h3 className="text-lg font-medium text-dark-300">No Location Data</h3>
                    <p className="text-dark-500 mt-2">
                        No location points recorded for this employee on the selected date.
                    </p>
                </Card>
            )}
        </div>
    );
}
