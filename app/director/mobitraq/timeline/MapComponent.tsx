'use client';

import React, { useEffect } from 'react';
import { MapContainer, TileLayer, Polyline, CircleMarker, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

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
    /** Road-snapped route from Google Maps Directions API. When provided,
     *  it is drawn in green on top of the raw GPS track. */
    roadRoute?: [number, number][];
    /** Actual road distance in km returned from Google Maps (shown in popup). */
    roadDistanceKm?: number;
    /** Encoded Roads-API-snapped polyline. NOT rendered here per Google ToS
     *  (snapped geometry must not be displayed on a non-Google map). Prop is
     *  accepted only so the same call-site works for both providers; this
     *  component silently ignores it. See docs/MAP_PROVIDER_MIGRATION.md. */
    snappedPolyline?: string | null;
}

const MapComponent: React.FC<MapComponentProps> = ({
    center,
    zoom,
    routePositions,
    points,
    timelineEvents,
    formatTime,
    roadRoute,
    roadDistanceKm,
}) => {
    useEffect(() => {
        (async function () {
            const L = await import('leaflet');
            // @ts-ignore
            delete L.Icon.Default.prototype._getIconUrl;
            L.Icon.Default.mergeOptions({
                iconRetinaUrl: 'leaflet/images/marker-icon-2x.png',
                iconUrl: 'leaflet/images/marker-icon.png',
                shadowUrl: 'leaflet/images/marker-shadow.png',
            });
        })();
    }, []);

    return (
        <div className="h-full w-full relative bg-gray-50 dark:bg-dark-900 border-none rounded-2xl overflow-hidden">
            <MapContainer
                center={center}
                zoom={zoom}
                className="h-full w-full z-0"
                scrollWheelZoom={true}
            >
                <TileLayer
                    attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
                    url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
                />

                {/* Raw GPS track — blue, shown as base layer */}
                {routePositions.length > 1 && (
                    <Polyline
                        positions={routePositions}
                        color="#1e40af"
                        weight={7}
                        opacity={0.25}
                    />
                )}
                {routePositions.length > 1 && (
                    <Polyline
                        positions={routePositions}
                        color="#3b82f6"
                        weight={3}
                        opacity={roadRoute && roadRoute.length > 1 ? 0.5 : 1}
                    />
                )}

                {/* Road-snapped route from Google Maps — green, drawn on top */}
                {roadRoute && roadRoute.length > 1 && (
                    <>
                        <Polyline
                            positions={roadRoute}
                            color="#15803d"
                            weight={7}
                            opacity={0.3}
                        />
                        <Polyline
                            positions={roadRoute}
                            color="#22c55e"
                            weight={4}
                            opacity={1}
                        />
                    </>
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
                            {roadDistanceKm != null && (
                                <>
                                    <br />
                                    <span className="text-green-700 font-semibold">
                                        Road dist: {roadDistanceKm.toFixed(2)} km
                                    </span>
                                </>
                            )}
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

                {/* Stop markers from TimelineEvents */}
                {timelineEvents
                    .filter((e) => (e.event_type === 'stop' || e.event_type === 'indoor_walking') && e.center_lat && e.center_lng)
                    .map((stop) => (
                        <CircleMarker
                            key={stop.id}
                            center={[stop.center_lat!, stop.center_lng!]}
                            radius={8}
                            fillColor="#f59e0b"
                            fillOpacity={0.8}
                            color="#fff"
                            weight={1}
                        >
                            <Popup>
                                <strong>Stop</strong>
                                <br />
                                Duration: {stop.duration_sec ? Math.round(stop.duration_sec / 60) : 0} mins
                                <br />
                                {stop.address && <span className="text-xs text-gray-500">{stop.address}</span>}
                            </Popup>
                        </CircleMarker>
                    ))}

                {/* Individual location points — only show when sparse to avoid clutter */}
                {points.length <= 150 && points.map((p) => (
                    <CircleMarker
                        key={p.id}
                        center={[p.latitude, p.longitude]}
                        radius={3}
                        fillColor="#3b82f6"
                        fillOpacity={0.4}
                        stroke={false}
                    >
                        <Popup>
                            {formatTime(p.recorded_at)}
                            <br />
                            Speed: {p.speed ? Math.round(p.speed * 3.6) : 0} km/h
                            <br />
                            Acc: {Math.round(p.accuracy || 0)}m
                        </Popup>
                    </CircleMarker>
                ))}
            </MapContainer>
        </div>
    );
};

export default MapComponent;
