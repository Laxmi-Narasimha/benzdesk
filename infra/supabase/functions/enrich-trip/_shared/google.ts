// Google Maps Platform helpers shared by enrich-trip.
//
// All calls run server-side with GOOGLE_MAPS_SERVER_KEY (the same key
// used by finalize-trip for Roads API). Each helper retries 429/5xx
// with exponential backoff and never throws on the happy path —
// callers get null/[] back so a single Google outage can't poison the
// whole job. We log to console.warn so failures show up in Supabase
// function logs.

const BACKOFF_BASE_MS = 250;
const MAX_ATTEMPTS = 3;

async function sleep(ms: number) {
    return new Promise<void>((r) => setTimeout(r, ms));
}

async function fetchRetry(url: string): Promise<Response | null> {
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
        try {
            const res = await fetch(url, { method: 'GET' });
            if (res.status === 429 || res.status >= 500) {
                await sleep(BACKOFF_BASE_MS * Math.pow(2, attempt - 1));
                continue;
            }
            return res;
        } catch (e) {
            console.warn(`google fetch attempt ${attempt} threw: ${(e as Error).message}`);
            await sleep(BACKOFF_BASE_MS * Math.pow(2, attempt - 1));
        }
    }
    return null;
}

// ============================================================================
// Reverse geocode — lat/lng → human-readable address
// ============================================================================
//
// Free under Geocoding India free cap (70k/month). We cap result_type
// to street_address|premise|point_of_interest so we don't return
// administrative-area-only matches like "Haryana, India" for a
// suburban GPS fix.

export async function reverseGeocode(
    apiKey: string,
    lat: number,
    lng: number,
): Promise<string | null> {
    const url =
        `https://maps.googleapis.com/maps/api/geocode/json` +
        `?latlng=${lat},${lng}` +
        `&result_type=street_address|premise|point_of_interest|subpremise|neighborhood` +
        `&key=${encodeURIComponent(apiKey)}`;
    const res = await fetchRetry(url);
    if (!res) return null;
    if (!res.ok) {
        console.warn(`reverseGeocode HTTP ${res.status}`);
        return null;
    }
    const body = (await res.json()) as {
        status: string;
        results?: Array<{ formatted_address: string }>;
    };
    if (body.status !== 'OK' && body.status !== 'ZERO_RESULTS') {
        console.warn(`reverseGeocode status=${body.status}`);
    }
    if (!body.results || body.results.length === 0) return null;
    return body.results[0].formatted_address;
}

// ============================================================================
// Nearby Search — top establishment within radius of lat/lng
// ============================================================================
//
// Returns the closest meaningful Place (we sort by rank=distance with
// type=establishment). Used to label stops with what's actually there
// (e.g. "Maxim SMT Technologies Pvt Ltd"). When the same lat/lng
// happens to be a customer in OUR DB, the caller separately checks
// the customers table by place_id and binds customer_id.

export interface NearbyPlace {
    placeId: string;
    name: string;
    vicinity?: string;
    distanceMeters?: number; // not returned by Google; computed by caller
}

export async function nearestPlace(
    apiKey: string,
    lat: number,
    lng: number,
    /** Max radius to consider. 100m default — tight enough to avoid
     *  cross-street false positives. */
    radiusM = 100,
): Promise<NearbyPlace | null> {
    // Nearby Search Pro (rank by distance, max 1 result we care about).
    // Note: when rankby=distance, radius is not allowed; we filter on
    // the client by computing geodesic distance.
    const url =
        `https://maps.googleapis.com/maps/api/place/nearbysearch/json` +
        `?location=${lat},${lng}` +
        `&rankby=distance` +
        `&type=establishment` +
        `&key=${encodeURIComponent(apiKey)}`;
    const res = await fetchRetry(url);
    if (!res) return null;
    if (!res.ok) {
        console.warn(`nearestPlace HTTP ${res.status}`);
        return null;
    }
    const body = (await res.json()) as {
        status: string;
        results?: Array<{
            place_id: string;
            name: string;
            vicinity?: string;
            geometry?: { location?: { lat: number; lng: number } };
        }>;
    };
    if (!body.results || body.results.length === 0) return null;

    // Cap by radius client-side. Google sorts by distance already, so
    // the first result is closest — if it's > radiusM we skip entirely.
    const top = body.results[0];
    const loc = top.geometry?.location;
    if (loc) {
        const d = haversineMeters(lat, lng, loc.lat, loc.lng);
        if (d > radiusM) return null;
        return {
            placeId: top.place_id,
            name: top.name,
            vicinity: top.vicinity,
            distanceMeters: d,
        };
    }
    return { placeId: top.place_id, name: top.name, vicinity: top.vicinity };
}

// ============================================================================
// Place Details (IDs Only — unlimited free under India pricing)
// ============================================================================
//
// Used when we want to backfill a customer row from a Place ID alone
// (e.g. admin pasted a Google Maps URL). Bumps to full Place Details
// only when the caller asks for name/address fields.

export interface PlaceDetails {
    placeId: string;
    name?: string;
    formattedAddress?: string;
    latitude?: number;
    longitude?: number;
    phone?: string;
    website?: string;
}

export async function placeDetails(
    apiKey: string,
    placeId: string,
): Promise<PlaceDetails | null> {
    const fields =
        'place_id,name,formatted_address,geometry/location,formatted_phone_number,website';
    const url =
        `https://maps.googleapis.com/maps/api/place/details/json` +
        `?place_id=${encodeURIComponent(placeId)}` +
        `&fields=${encodeURIComponent(fields)}` +
        `&key=${encodeURIComponent(apiKey)}`;
    const res = await fetchRetry(url);
    if (!res) return null;
    if (!res.ok) {
        console.warn(`placeDetails HTTP ${res.status}`);
        return null;
    }
    const body = (await res.json()) as {
        status: string;
        result?: {
            place_id: string;
            name?: string;
            formatted_address?: string;
            geometry?: { location?: { lat: number; lng: number } };
            formatted_phone_number?: string;
            website?: string;
        };
    };
    const r = body.result;
    if (!r) return null;
    return {
        placeId: r.place_id,
        name: r.name,
        formattedAddress: r.formatted_address,
        latitude: r.geometry?.location?.lat,
        longitude: r.geometry?.location?.lng,
        phone: r.formatted_phone_number,
        website: r.website,
    };
}

// ============================================================================
// Geometry helper (avoid a separate import)
// ============================================================================

export function haversineMeters(
    lat1: number,
    lon1: number,
    lat2: number,
    lon2: number,
): number {
    const R = 6371000;
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos((lat1 * Math.PI) / 180) *
            Math.cos((lat2 * Math.PI) / 180) *
            Math.sin(dLon / 2) *
            Math.sin(dLon / 2);
    return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
