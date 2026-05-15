// MapMatcherProvider — provider-agnostic interface.
//
// We currently ship GoogleRoadsProvider. When migrating to self-hosted OSRM
// or Valhalla (typically at >500 employees, see docs/MAP_PROVIDER_MIGRATION.md),
// add a sibling implementation and swap the factory below.
//
// The interface intentionally hides the chunking, overlap, retry, and rate-
// limit details so the orchestrator in index.ts stays simple.

import {
    LatLng,
    TimedPoint,
    polylineLengthMeters,
    encodePolyline,
} from './geo.ts';

export interface MatchResult {
    /** Distance over the snapped polyline, in kilometres. */
    distanceKm: number;
    /** Encoded polyline (precision 5) of the snapped route. Empty if provider had no usable snap. */
    snappedPolyline: string;
    /** Decoded snapped points, in case caller needs them directly. */
    snappedPoints: LatLng[];
    /** Provider-specific diagnostic notes. */
    notes: string[];
    /** Provider name for audit (`'google_roads'`, `'osrm'`, etc.). */
    provider: string;
}

export interface MapMatcherProvider {
    readonly name: string;
    /**
     * Given a chronologically-ordered list of GPS points for a single
     * uninterrupted segment, return the snapped distance and polyline.
     * Provider handles chunking and retries internally.
     */
    matchSegment(points: TimedPoint[]): Promise<MatchResult>;
}

// =============================================================================
// Google Roads API implementation
// =============================================================================

const GOOGLE_ROADS_ENDPOINT = 'https://roads.googleapis.com/v1/snapToRoads';
const MAX_POINTS_PER_REQUEST = 100;
const OVERLAP_POINTS = 10; // overlap between consecutive chunks for continuity

export class GoogleRoadsProvider implements MapMatcherProvider {
    readonly name = 'google_roads';
    constructor(private readonly apiKey: string) {
        if (!apiKey) throw new Error('GoogleRoadsProvider requires apiKey');
    }

    async matchSegment(points: TimedPoint[]): Promise<MatchResult> {
        const notes: string[] = [];
        if (points.length < 2) {
            return {
                distanceKm: 0,
                snappedPolyline: '',
                snappedPoints: [],
                notes: ['segment_too_short'],
                provider: this.name,
            };
        }

        // Chunk with overlap so Roads API can infer continuity across chunk
        // boundaries (Google's "Advanced Concepts" guidance for long paths).
        const chunks: TimedPoint[][] = [];
        const stride = MAX_POINTS_PER_REQUEST - OVERLAP_POINTS;
        for (let i = 0; i < points.length; i += stride) {
            const chunk = points.slice(i, i + MAX_POINTS_PER_REQUEST);
            if (chunk.length >= 2) chunks.push(chunk);
            if (i + MAX_POINTS_PER_REQUEST >= points.length) break;
        }

        const allSnapped: LatLng[] = [];
        const seenPlaceIds = new Set<string>();
        let chunkIdx = 0;
        for (const chunk of chunks) {
            chunkIdx++;
            const snapped = await this.callSnapToRoads(chunk);
            // Dedupe by place_id when adjacent chunks overlap — placeId of a
            // road segment is stable, so this drops the overlap duplicates
            // before we sum distance.
            for (const sp of snapped) {
                const key = sp.placeId ?? `${sp.lat},${sp.lng}`;
                if (seenPlaceIds.has(key)) continue;
                seenPlaceIds.add(key);
                allSnapped.push({ lat: sp.lat, lng: sp.lng });
            }
            notes.push(`chunk_${chunkIdx}=${snapped.length}pts`);
        }

        if (allSnapped.length < 2) {
            return {
                distanceKm: 0,
                snappedPolyline: '',
                snappedPoints: [],
                notes: [...notes, 'no_snapped_points'],
                provider: this.name,
            };
        }

        const distanceM = polylineLengthMeters(allSnapped);
        return {
            distanceKm: distanceM / 1000,
            snappedPolyline: encodePolyline(allSnapped),
            snappedPoints: allSnapped,
            notes,
            provider: this.name,
        };
    }

    /**
     * Single call to Google Roads API "Snap to Roads".
     * Returns up to 100 snapped points + interpolated road geometry.
     * Retries on 429/5xx with exponential backoff (max 3 attempts).
     */
    private async callSnapToRoads(chunk: TimedPoint[]): Promise<
        Array<{ lat: number; lng: number; placeId?: string }>
    > {
        const path = chunk
            .map((p) => `${p.lat.toFixed(7)},${p.lng.toFixed(7)}`)
            .join('|');
        const url =
            `${GOOGLE_ROADS_ENDPOINT}` +
            `?interpolate=true&key=${encodeURIComponent(this.apiKey)}` +
            `&path=${encodeURIComponent(path)}`;

        let lastErr: unknown;
        for (let attempt = 1; attempt <= 3; attempt++) {
            try {
                const res = await fetch(url, { method: 'GET' });
                if (res.status === 429 || res.status >= 500) {
                    lastErr = new Error(`Roads API HTTP ${res.status}`);
                    await sleep(250 * Math.pow(2, attempt - 1));
                    continue;
                }
                if (!res.ok) {
                    const text = await res.text();
                    throw new Error(
                        `Roads API HTTP ${res.status}: ${text.slice(0, 200)}`,
                    );
                }
                const body = await res.json() as {
                    snappedPoints?: Array<{
                        location: { latitude: number; longitude: number };
                        placeId?: string;
                    }>;
                };
                return (body.snappedPoints ?? []).map((sp) => ({
                    lat: sp.location.latitude,
                    lng: sp.location.longitude,
                    placeId: sp.placeId,
                }));
            } catch (e) {
                lastErr = e;
                await sleep(250 * Math.pow(2, attempt - 1));
            }
        }
        throw lastErr ?? new Error('Roads API failed after retries');
    }
}

function sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
}

// =============================================================================
// Factory
// =============================================================================

export function makeMapMatcherProvider(): MapMatcherProvider {
    const provider = Deno.env.get('MAP_MATCHER_PROVIDER') ?? 'google_roads';
    switch (provider) {
        case 'google_roads': {
            const key = Deno.env.get('GOOGLE_MAPS_SERVER_KEY');
            if (!key) {
                throw new Error(
                    'GOOGLE_MAPS_SERVER_KEY missing — see docs/MAP_PROVIDER_MIGRATION.md',
                );
            }
            return new GoogleRoadsProvider(key);
        }
        // case 'osrm': return new OsrmProvider(Deno.env.get('OSRM_BASE_URL')!);
        // case 'valhalla': return new ValhallaProvider(Deno.env.get('VALHALLA_BASE_URL')!);
        default:
            throw new Error(`Unknown MAP_MATCHER_PROVIDER: ${provider}`);
    }
}
