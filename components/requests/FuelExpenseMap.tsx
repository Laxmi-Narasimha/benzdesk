'use client';

import React, { useEffect, useState, useMemo } from 'react';
import dynamic from 'next/dynamic';
import { getSupabaseClient } from '@/lib/supabaseClient';
import { Card, Spinner } from '@/components/ui';
import { MapPin, Navigation, Route, AlertCircle, RefreshCw } from 'lucide-react';

const MapComponent = dynamic(() => import('@/app/director/mobitraq/timeline/MapComponent'), {
    ssr: false,
    loading: () => <div className="h-64 flex items-center justify-center bg-gray-50 rounded-xl"><Spinner size="md" /></div>
});

interface FuelExpenseMapProps {
    sessionId: string;
    description: string;
    employeeId: string;
}

export function FuelExpenseMap({ sessionId, description, employeeId }: FuelExpenseMapProps) {
    const [loading, setLoading] = useState(true);
    const [points, setPoints] = useState<any[]>([]);
    const [events, setEvents] = useState<any[]>([]);
    const [error, setError] = useState<string | null>(null);

    const [startAddress, setStartAddress] = useState<string>('Loading...');
    const [endAddress, setEndAddress] = useState<string>('Loading...');

    // Extract distance and vehicle from description
    const { distance, vehicleType } = useMemo(() => {
        let d = 0;
        let v = 'Vehicle';
        const match = description.match(/([0-9.]+) km \((Car|Bike)\)/i);
        if (match) {
            d = parseFloat(match[1]);
            v = match[2];
        }
        return { distance: d, vehicleType: v };
    }, [description]);

    const [rate, setRate] = useState<number>(0);

    const fetchData = async () => {
        setLoading(true);
        try {
            const supabase = getSupabaseClient();
            
            // 1. Fetch Session bounds & Employee Band
            const [sessionRes, empRes] = await Promise.all([
                supabase.from('shift_sessions').select('*').eq('id', sessionId).single(),
                supabase.from('employees').select('band').eq('id', employeeId).single()
            ]);
                
            if (sessionRes.error || !sessionRes.data) throw new Error('Could not find session data');

            const startT = sessionRes.data.start_time;
            const endT = sessionRes.data.end_time || new Date().toISOString();
            
            // Fetch band limit for calculated rate
            if (empRes.data?.band) {
                const category = vehicleType.toLowerCase() === 'car' ? 'fuel_car' : 'fuel_bike';
                const { data: limitData } = await supabase
                    .from('band_limits')
                    .select('daily_limit')
                    .eq('band', empRes.data.band)
                    .eq('category', category)
                    .maybeSingle();
                
                if (limitData) {
                    setRate(limitData.daily_limit);
                } else {
                    setRate(vehicleType.toLowerCase() === 'car' ? 7.5 : 5.0); // app default fallback
                }
            } else {
                setRate(vehicleType.toLowerCase() === 'car' ? 7.5 : 5.0);
            }

            // 2. Fetch Location Points
            const { data: pointsData } = await supabase
                .from('location_points')
                .select('*')
                .eq('employee_id', employeeId)
                .gte('recorded_at', startT)
                .lte('recorded_at', endT)
                .order('recorded_at', { ascending: true });

            setPoints(pointsData || []);

            // 3. Fetch Timeline events (stops)
            const { data: eventsData } = await supabase
                .from('timeline_events')
                .select('*')
                .eq('employee_id', employeeId)
                .gte('start_time', startT)
                .lte('start_time', endT)
                .order('start_time', { ascending: true });

            setEvents(eventsData || []);

            // Handle Reverse Geocoding
            if (pointsData && pointsData.length > 0) {
                reverseGeocode(pointsData[0].latitude, pointsData[0].longitude, setStartAddress);
                if (pointsData.length > 1) {
                    const last = pointsData[pointsData.length - 1];
                    reverseGeocode(last.latitude, last.longitude, setEndAddress);
                } else {
                    setEndAddress('Same as start');
                }
            } else {
                setStartAddress('No GPS data');
                setEndAddress('No GPS data');
            }

        } catch (err: any) {
            console.error('Map Load Error:', err);
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        if (sessionId && employeeId) {
            fetchData();
        }
    }, [sessionId, employeeId]);

    const reverseGeocode = async (lat: number, lng: number, setter: (val: string) => void) => {
        try {
            const res = await fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1`);
            const data = await res.json();
            if (data && data.display_name) {
                // Return a simplified version of the address
                const parts = data.display_name.split(',').map((p: string) => p.trim());
                setter(parts.slice(0, 3).join(', '));
            } else {
                setter(`${lat.toFixed(4)}, ${lng.toFixed(4)}`);
            }
        } catch (e) {
            setter(`${lat.toFixed(4)}, ${lng.toFixed(4)}`);
        }
    };

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

    const routePositions = useMemo(() => points.map((p) => [p.latitude, p.longitude] as [number, number]), [points]);

    if (loading) {
        return (
            <Card padding="md" className="mt-6 border-blue-100 bg-blue-50/30">
                <div className="flex items-center gap-3 text-blue-600 mb-4">
                    <Navigation className="w-5 h-5" />
                    <h3 className="font-semibold">Loading GPS Session Map...</h3>
                </div>
                <div className="h-64 flex items-center justify-center bg-white/50 rounded-xl border border-blue-100/50">
                    <Spinner size="md" />
                </div>
            </Card>
        );
    }

    if (error) {
        return (
            <Card padding="md" className="mt-6 border-red-100 bg-red-50/30">
                <div className="flex items-center gap-2 text-red-600">
                    <AlertCircle className="w-5 h-5" />
                    <span>Failed to load map data: {error}</span>
                </div>
            </Card>
        );
    }

    return (
        <Card padding="md" className="mt-6 border-blue-100 bg-blue-50/10 overflow-hidden relative">
            <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-4 gap-4">
                <div className="flex items-center gap-3 text-slate-800">
                    <div className="bg-blue-100 p-2 rounded-lg text-blue-600">
                        <Route className="w-5 h-5" />
                    </div>
                    <div>
                        <h3 className="font-bold text-lg">GPS Track & Calculations</h3>
                        <p className="text-xs text-slate-500">Session ID: {sessionId.substring(0, 8)}...</p>
                    </div>
                </div>

                <div className="bg-white px-4 py-2 border border-gray-100 shadow-sm rounded-xl text-right">
                    <div className="text-[10px] uppercase font-bold text-gray-400 tracking-wider">Calculated Fuel</div>
                    <div className="text-lg font-black text-slate-800 flex items-baseline gap-1 justify-end">
                        <span className="text-sm font-semibold text-slate-500">{distance.toFixed(1)} km ×</span>
                        <span className="text-blue-600">₹{rate.toFixed(2)}</span>
                        <span className="text-sm text-slate-400 font-normal ml-1">= ₹{(distance * rate).toFixed(2)}</span>
                    </div>
                    <div className="text-xs text-slate-500 mt-0.5">({vehicleType} Transport)</div>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3 mb-6">
                <div className="flex gap-3 bg-white border border-gray-100 p-3 rounded-xl shadow-sm items-start">
                    <div className="bg-green-100 text-green-600 p-1.5 rounded-md mt-0.5">
                        <MapPin className="w-4 h-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                        <div className="text-[10px] font-bold tracking-wider text-gray-400 uppercase">Start Location</div>
                        <div className="text-sm font-medium text-slate-700 leading-snug">{startAddress}</div>
                    </div>
                </div>
                <div className="flex gap-3 bg-white border border-gray-100 p-3 rounded-xl shadow-sm items-start">
                    <div className="bg-red-100 text-red-600 p-1.5 rounded-md mt-0.5">
                        <MapPin className="w-4 h-4" />
                    </div>
                    <div className="flex-1 min-w-0">
                        <div className="text-[10px] font-bold tracking-wider text-gray-400 uppercase">End Location</div>
                        <div className="text-sm font-medium text-slate-700 leading-snug">{endAddress}</div>
                    </div>
                </div>
            </div>

            <div className="h-[300px] w-full rounded-xl overflow-hidden shadow-inner border border-gray-200 isolation-auto bg-gray-100 relative">
                {points.length > 0 ? (
                    <MapComponent
                        center={mapConfig.center}
                        zoom={mapConfig.zoom}
                        routePositions={routePositions}
                        points={points}
                        timelineEvents={events}
                        formatTime={(iso: string) => {
                            if (!iso) return '';
                            return new Date(iso).toLocaleTimeString('en-IN', { timeZone: 'Asia/Kolkata', hour: '2-digit', minute: '2-digit' });
                        }}
                    />
                ) : (
                    <div className="absolute inset-0 flex flex-col items-center justify-center text-gray-400">
                        <MapPin className="w-8 h-8 opacity-20 mb-2" />
                        <p className="text-sm">No GPS track recorded for this session.</p>
                    </div>
                )}
            </div>
            
            <div className="mt-3 text-xs text-gray-400 text-right w-full flex align-center justify-end pr-1">
                 Addresses via OpenStreetMap Internet Geocoding
            </div>
        </Card>
    );
}
