'use client';

/**
 * Google Maps version of the admin timeline map.
 *
 * Activated when NEXT_PUBLIC_MAP_PROVIDER=google. Falls back to the legacy
 * Leaflet/OSM component (`./MapComponent`) when the flag is anything else.
 *
 * Why this exists:
 *   - The trip finalization pipeline (Edge Function `finalize-trip`) calls
 *     Google Roads API. Google Maps Platform Service Specific Terms forbid
 *     displaying Roads-API-snapped geometry on a non-Google map
 *     (e.g. Leaflet/OSM). So when we want to render the snapped polyline,
 *     we MUST be on a Google Map.
 *   - The legacy MapComponent (Leaflet) is retained intact — see
 *     docs/MAP_PROVIDER_MIGRATION.md for how to swap back if/when we
 *     migrate to self-hosted OSRM/Valhalla (typically at >500 employees).
 *
 * Raw GPS breadcrumbs are our first-party data and can be displayed on
 * either map. Only the Roads-API-derived geometry is restricted.
 */

import React, { useEffect, useRef, useState } from 'react';

interface LocationPoint {
    id: string;
    latitude: number;
    longitude: number;
    recorded_at: string;
    speed: number | null;
    accuracy: number | null;
}

interface TimelineEvent {
    id: string;
    event_type: string;
    start_time: string;
    end_time: string | null;
    duration_sec: number | null;
    center_lat: number | null;
    center_lng: number | null;
    address?: string | null;
}

interface MapComponentProps {
    center: [number, number];
    zoom: number;
    routePositions: [number, number][];
    points: LocationPoint[];
    timelineEvents: TimelineEvent[];
    formatTime: (isoString: string) => string;
    roadRoute?: [number, number][];
    roadDistanceKm?: number;
    /** Encoded polyline of the Roads-API-snapped route (from
     *  shift_sessions.snapped_polyline). Decoded and drawn in green on
     *  the Google Map. */
    snappedPolyline?: string | null;
}

const GOOGLE_MAPS_BROWSER_KEY =
    process.env.NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY ?? '';

const MapComponentGoogle: React.FC<MapComponentProps> = ({
    center,
    zoom,
    routePositions,
    points,
    timelineEvents,
    formatTime,
    roadRoute,
    roadDistanceKm,
    snappedPolyline,
}) => {
    const mapRef = useRef<HTMLDivElement | null>(null);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        let cancelled = false;
        let map: any;
        const overlays: any[] = [];

        async function loadGoogle() {
            if (!GOOGLE_MAPS_BROWSER_KEY) {
                setError(
                    'NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY is not configured. ' +
                        'Falling back to Leaflet via NEXT_PUBLIC_MAP_PROVIDER=osm.',
                );
                return;
            }
            await ensureGoogleScript(GOOGLE_MAPS_BROWSER_KEY);
            if (cancelled || !mapRef.current) return;
            const g = (window as any).google;

            map = new g.maps.Map(mapRef.current, {
                center: { lat: center[0], lng: center[1] },
                zoom,
                disableDefaultUI: false,
                streetViewControl: false,
                mapTypeControl: false,
            });

            // Raw GPS track (faint blue) — our first-party data.
            if (routePositions.length > 1) {
                overlays.push(
                    new g.maps.Polyline({
                        path: routePositions.map(([lat, lng]) => ({ lat, lng })),
                        strokeColor: '#3b82f6',
                        strokeOpacity: 0.55,
                        strokeWeight: 4,
                        map,
                    }),
                );
            }

            // Roads-API-snapped polyline (green) — only allowed on a Google Map per ToS.
            if (snappedPolyline) {
                const decoded = g.maps.geometry?.encoding?.decodePath(
                    snappedPolyline,
                ) as { lat: () => number; lng: () => number }[] | undefined;
                if (decoded && decoded.length > 1) {
                    overlays.push(
                        new g.maps.Polyline({
                            path: decoded,
                            strokeColor: '#16a34a',
                            strokeOpacity: 1,
                            strokeWeight: 5,
                            map,
                        }),
                    );
                }
            } else if (roadRoute && roadRoute.length > 1) {
                // Legacy directions-API route (start→end optimal). Kept for backwards
                // compatibility while the snapped polyline rolls out.
                overlays.push(
                    new g.maps.Polyline({
                        path: roadRoute.map(([lat, lng]) => ({ lat, lng })),
                        strokeColor: '#15803d',
                        strokeOpacity: 0.9,
                        strokeWeight: 4,
                        map,
                    }),
                );
            }

            // Start marker
            if (points.length > 0) {
                overlays.push(
                    new g.maps.Marker({
                        position: {
                            lat: points[0].latitude,
                            lng: points[0].longitude,
                        },
                        map,
                        title: `Start: ${formatTime(points[0].recorded_at)}` +
                            (roadDistanceKm != null
                                ? ` · Road ${roadDistanceKm.toFixed(2)} km`
                                : ''),
                        icon: dotIcon(g, '#22c55e'),
                    }),
                );
            }
            // End marker
            if (points.length > 1) {
                const last = points[points.length - 1];
                overlays.push(
                    new g.maps.Marker({
                        position: { lat: last.latitude, lng: last.longitude },
                        map,
                        title: `End: ${formatTime(last.recorded_at)}`,
                        icon: dotIcon(g, '#ef4444'),
                    }),
                );
            }
            // Stop / indoor-walking markers
            for (const stop of timelineEvents) {
                const isStop =
                    stop.event_type === 'stop' ||
                    stop.event_type === 'indoor_walking';
                if (isStop && stop.center_lat && stop.center_lng) {
                    const isIndoor = stop.event_type === 'indoor_walking';
                    overlays.push(
                        new g.maps.Marker({
                            position: {
                                lat: stop.center_lat,
                                lng: stop.center_lng,
                            },
                            map,
                            title:
                                (isIndoor ? 'Inside building' : 'Stop') +
                                ` ${Math.round((stop.duration_sec ?? 0) / 60)} min` +
                                (stop.address ? `\n${stop.address}` : ''),
                            // Indoor walking gets a violet dot to distinguish
                            // from regular orange "stopped outside" pins.
                            icon: dotIcon(g, isIndoor ? '#8b5cf6' : '#f59e0b'),
                        }),
                    );
                }
            }
        }

        loadGoogle().catch((e) => setError((e as Error).message));

        return () => {
            cancelled = true;
            for (const o of overlays) {
                try {
                    o.setMap(null);
                } catch {
                    /* noop */
                }
            }
        };
    }, [
        center,
        zoom,
        routePositions,
        points,
        timelineEvents,
        roadRoute,
        roadDistanceKm,
        snappedPolyline,
        formatTime,
    ]);

    if (error) {
        return (
            <div className="h-full w-full flex items-center justify-center bg-red-50 text-red-700 text-sm p-4 rounded-2xl">
                Map failed to load: {error}
            </div>
        );
    }

    return (
        <div className="h-full w-full relative bg-gray-50 border-none rounded-2xl overflow-hidden">
            <div ref={mapRef} className="h-full w-full" />
        </div>
    );
};

// =============================================================================
// Helpers
// =============================================================================

function dotIcon(g: any, color: string) {
    return {
        path: g.maps.SymbolPath.CIRCLE,
        scale: 8,
        fillColor: color,
        fillOpacity: 1,
        strokeColor: '#fff',
        strokeWeight: 2,
    };
}

let _googleScriptPromise: Promise<void> | null = null;
async function ensureGoogleScript(key: string): Promise<void> {
    if ((window as any).google?.maps?.geometry) return;
    if (_googleScriptPromise) return _googleScriptPromise;
    _googleScriptPromise = new Promise<void>((resolve, reject) => {
        const existing = document.getElementById('google-maps-script');
        if (existing) {
            existing.addEventListener('load', () => resolve());
            existing.addEventListener('error', () =>
                reject(new Error('Google Maps script failed to load')),
            );
            return;
        }
        const script = document.createElement('script');
        script.id = 'google-maps-script';
        script.src =
            `https://maps.googleapis.com/maps/api/js` +
            `?key=${encodeURIComponent(key)}&libraries=geometry`;
        script.async = true;
        script.defer = true;
        script.onload = () => resolve();
        script.onerror = () =>
            reject(new Error('Google Maps script failed to load'));
        document.body.appendChild(script);
    });
    return _googleScriptPromise;
}

export default MapComponentGoogle;
