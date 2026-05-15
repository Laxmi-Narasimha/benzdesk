// Geodesic + polyline helpers used by the finalization pipeline.
// Pure functions, no I/O. Keep this file dependency-free.

export interface LatLng {
    lat: number;
    lng: number;
}

const EARTH_R_M = 6371000;

export function toRadians(deg: number): number {
    return (deg * Math.PI) / 180;
}

export function haversineMeters(a: LatLng, b: LatLng): number {
    const dLat = toRadians(b.lat - a.lat);
    const dLng = toRadians(b.lng - a.lng);
    const sinDLat = Math.sin(dLat / 2);
    const sinDLng = Math.sin(dLng / 2);
    const h =
        sinDLat * sinDLat +
        Math.cos(toRadians(a.lat)) *
            Math.cos(toRadians(b.lat)) *
            sinDLng *
            sinDLng;
    return 2 * EARTH_R_M * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
}

export function polylineLengthMeters(points: LatLng[]): number {
    if (points.length < 2) return 0;
    let total = 0;
    for (let i = 1; i < points.length; i++) {
        total += haversineMeters(points[i - 1], points[i]);
    }
    return total;
}

/**
 * Downsample a polyline so consecutive kept points are >= minSpacingM apart.
 * Always keeps the first and last point.
 * This is what we feed to Roads API to control cost and stay under the
 * 100-point-per-request limit gracefully.
 */
export function downsampleByDistance(
    points: LatLng[],
    minSpacingM: number,
): LatLng[] {
    if (points.length <= 2) return [...points];
    const out: LatLng[] = [points[0]];
    let last = points[0];
    for (let i = 1; i < points.length - 1; i++) {
        const d = haversineMeters(last, points[i]);
        if (d >= minSpacingM) {
            out.push(points[i]);
            last = points[i];
        }
    }
    out.push(points[points.length - 1]);
    return out;
}

/**
 * Split a polyline into segments at time gaps > maxGapSec OR spacing > maxSpacingM.
 * Splitting (rather than interpolating) prevents Roads API from inventing
 * geometry across actual outages (tunnel, app killed, etc.).
 */
export interface TimedPoint extends LatLng {
    timestampMs: number;
}

export function splitOnGaps(
    points: TimedPoint[],
    maxGapSec: number,
    maxSpacingM: number,
): TimedPoint[][] {
    if (points.length === 0) return [];
    const segments: TimedPoint[][] = [[]];
    for (let i = 0; i < points.length; i++) {
        const p = points[i];
        if (i === 0) {
            segments[0].push(p);
            continue;
        }
        const prev = points[i - 1];
        const gapSec = (p.timestampMs - prev.timestampMs) / 1000;
        const spacingM = haversineMeters(prev, p);
        if (gapSec > maxGapSec || spacingM > maxSpacingM) {
            segments.push([p]);
        } else {
            segments[segments.length - 1].push(p);
        }
    }
    return segments.filter((s) => s.length >= 2);
}

/**
 * Encode a polyline using Google's algorithm (precision 5).
 * https://developers.google.com/maps/documentation/utilities/polylinealgorithm
 *
 * We store the snapped result as an encoded polyline string in
 * shift_sessions.snapped_polyline to keep DB payload small.
 */
export function encodePolyline(points: LatLng[]): string {
    let out = '';
    let prevLat = 0;
    let prevLng = 0;
    for (const p of points) {
        const lat = Math.round(p.lat * 1e5);
        const lng = Math.round(p.lng * 1e5);
        out += encodeSignedNumber(lat - prevLat);
        out += encodeSignedNumber(lng - prevLng);
        prevLat = lat;
        prevLng = lng;
    }
    return out;
}

function encodeSignedNumber(num: number): string {
    let sgn = num << 1;
    if (num < 0) sgn = ~sgn;
    return encodeNumber(sgn);
}

function encodeNumber(num: number): string {
    let out = '';
    while (num >= 0x20) {
        out += String.fromCharCode((0x20 | (num & 0x1f)) + 63);
        num >>= 5;
    }
    out += String.fromCharCode(num + 63);
    return out;
}
