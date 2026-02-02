'use client';

import React from 'react';
import { MapContainer, TileLayer, Polyline, CircleMarker, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';

// Fix for default marker icon in Leaflet
import L from 'leaflet';
import markerIcon2x from 'leaflet/dist/images/marker-icon-2x.png';
import markerIcon from 'leaflet/dist/images/marker-icon.png';
import markerShadow from 'leaflet/dist/images/marker-shadow.png';

// Delete the default icon configuration to fix the "missing icon" issue
// @ts-ignore
delete L.Icon.Default.prototype._getIconUrl;

L.Icon.Default.mergeOptions({
    iconRetinaUrl: markerIcon2x.src,
    iconUrl: markerIcon.src,
    shadowUrl: markerShadow.src,
});

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
    duration_min: number | null;
    center_lat: number | null;
    center_lng: number | null;
    address: string | null;
}

interface MapComponentProps {
    center: [number, number];
    zoom: number;
    routePositions: [number, number][];
    points: LocationPoint[];
    timelineEvents: TimelineEvent[];
    formatTime: (isoString: string) => string;
}

const MapComponent: React.FC<MapComponentProps> = ({
    center,
    zoom,
    routePositions,
    points,
    timelineEvents,
    formatTime,
}) => {
    return (
        <MapContainer
            center={center}
            zoom={zoom}
            className="h-full w-full"
            style={{ background: '#1a1a2e', height: '100%', width: '100%' }}
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

            {/* Stop markers from TimelineEvents */}
            {timelineEvents
                .filter((e) => e.event_type === 'stop' && e.center_lat && e.center_lng)
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
                            Duration: {stop.duration_min ? Math.round(stop.duration_min) : 0} mins
                            <br />
                            {stop.address && <span className="text-xs text-gray-500">{stop.address}</span>}
                        </Popup>
                    </CircleMarker>
                ))}

            {/* Individual location points (small dots) */}
            {points.map((p) => (
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
    );
};

export default MapComponent;
