// Supabase Edge Function: enrich-trip
//
// Drains trip_enrichment_jobs and enriches each session:
//
//   - reverse-geocode shift_sessions.start_address / end_address (if missing)
//   - for each session_stops row missing address: reverse-geocode it
//   - for each session_stops row missing customer_id: Nearby Search → if
//     the nearest establishment Place ID matches one of our customers,
//     bind it; otherwise just record place_id + place_name
//   - aggregate visited_customer_ids onto the parent shift_sessions row
//
// Runs on a cron tick (1/min). Same MAX_JOBS_PER_TICK pattern as
// finalize-trip. Idempotent on session_id: re-running produces the
// same enrichment.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
    haversineMeters,
    nearestPlace,
    reverseGeocode,
} from './_shared/google.ts';

const MAX_JOBS_PER_TICK = 10;
const CUSTOMER_MATCH_RADIUS_M = 100;
const STOP_NEARBY_RADIUS_M = 75;

interface JobRow {
    id: string;
    session_id: string;
    attempts: number;
    max_attempts: number;
}

interface SessionRow {
    id: string;
    employee_id: string;
    start_latitude: number | null;
    start_longitude: number | null;
    end_latitude: number | null;
    end_longitude: number | null;
    start_address: string | null;
    end_address: string | null;
    start_place_id: string | null;
    end_place_id: string | null;
    visited_customer_ids: string[] | null;
    primary_customer_id: string | null;
}

interface StopRow {
    id: string;
    session_id: string;
    center_lat: number;
    center_lng: number;
    address: string | null;
    place_id: string | null;
    place_name: string | null;
    customer_id: string | null;
}

interface CustomerRow {
    id: string;
    google_place_id: string | null;
    name: string;
    latitude: number | null;
    longitude: number | null;
}

serve(async (_req) => {
    let processed = 0;
    let failed = 0;

    try {
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
        );
        const apiKey = Deno.env.get('GOOGLE_MAPS_SERVER_KEY') ?? '';
        if (!apiKey) {
            return new Response(
                JSON.stringify({ error: 'GOOGLE_MAPS_SERVER_KEY missing' }),
                { status: 500, headers: { 'Content-Type': 'application/json' } },
            );
        }

        // Cache active customers in-memory for this tick. <500 rows
        // expected; refresh on every invocation so admin changes show
        // up within ~1 min.
        const customers = await loadActiveCustomers(supabase);

        for (let i = 0; i < MAX_JOBS_PER_TICK; i++) {
            const job = await claimNext(supabase);
            if (!job) break;
            try {
                await enrichOne(supabase, apiKey, customers, job);
                processed++;
            } catch (e) {
                failed++;
                await markFailed(supabase, job.id, job.attempts, e);
            }
        }

        return new Response(JSON.stringify({ processed, failed }), {
            headers: { 'Content-Type': 'application/json' },
        });
    } catch (e) {
        console.error('enrich-trip fatal:', e);
        return new Response(
            JSON.stringify({
                error: (e as Error).message,
                processed,
                failed,
            }),
            { status: 500, headers: { 'Content-Type': 'application/json' } },
        );
    }
});

// =============================================================================
// Core enrich routine
// =============================================================================

async function enrichOne(
    supabase: SupabaseClient,
    apiKey: string,
    customers: CustomerRow[],
    job: JobRow,
): Promise<void> {
    const sessionId = job.session_id;

    const { data: sessionRows, error: sErr } = await supabase
        .from('shift_sessions')
        .select(
            'id, employee_id, start_latitude, start_longitude, end_latitude, end_longitude, start_address, end_address, start_place_id, end_place_id, visited_customer_ids, primary_customer_id',
        )
        .eq('id', sessionId)
        .limit(1);
    if (sErr) throw sErr;
    if (!sessionRows || sessionRows.length === 0) {
        throw new Error('Session not found');
    }
    const session = sessionRows[0] as SessionRow;

    // -------------------------------------------------------------------------
    // 1. Reverse-geocode endpoints (only if missing).
    // -------------------------------------------------------------------------
    const sessionPatch: Record<string, unknown> = {};
    if (
        !session.start_address &&
        session.start_latitude != null &&
        session.start_longitude != null
    ) {
        const addr = await reverseGeocode(
            apiKey,
            session.start_latitude,
            session.start_longitude,
        );
        if (addr) sessionPatch.start_address = addr;
    }
    if (
        !session.end_address &&
        session.end_latitude != null &&
        session.end_longitude != null
    ) {
        const addr = await reverseGeocode(
            apiKey,
            session.end_latitude,
            session.end_longitude,
        );
        if (addr) sessionPatch.end_address = addr;
    }

    // -------------------------------------------------------------------------
    // 2. Enrich every session_stops row that still needs it.
    // -------------------------------------------------------------------------
    const { data: stopRows, error: stErr } = await supabase
        .from('session_stops')
        .select(
            'id, session_id, center_lat, center_lng, address, place_id, place_name, customer_id',
        )
        .eq('session_id', sessionId)
        .order('started_at', { ascending: true });
    if (stErr) throw stErr;
    const stops = (stopRows ?? []) as StopRow[];

    const visitedSet = new Set<string>(session.visited_customer_ids ?? []);

    for (const stop of stops) {
        const updates: Record<string, unknown> = {};

        // First pass: customer match by proximity. Cheap (no API call,
        // uses in-memory customer table). If we hit a customer within
        // 100m, we're done for this stop — no Nearby Search needed.
        if (!stop.customer_id) {
            const match = matchCustomer(
                customers,
                stop.center_lat,
                stop.center_lng,
                CUSTOMER_MATCH_RADIUS_M,
            );
            if (match) {
                updates.customer_id = match.id;
                if (match.google_place_id && !stop.place_id) {
                    updates.place_id = match.google_place_id;
                }
                if (!stop.place_name) {
                    updates.place_name = match.name;
                }
                visitedSet.add(match.id);
            }
        }

        // Second pass: if still no customer + no place_name, hit Nearby
        // Search so the admin at least sees a label like "Vaango Fortis
        // Hospital Manesar" for unknown stops.
        if (!updates.customer_id && !stop.customer_id && !stop.place_name) {
            const np = await nearestPlace(
                apiKey,
                stop.center_lat,
                stop.center_lng,
                STOP_NEARBY_RADIUS_M,
            );
            if (np) {
                updates.place_id = np.placeId;
                updates.place_name = np.name;
                // Did this Place happen to match a customer we hadn't
                // bound yet? (Customer added without coords but with
                // a Place ID — re-match here.)
                const byPlace = customers.find(
                    (c) => c.google_place_id === np.placeId,
                );
                if (byPlace) {
                    updates.customer_id = byPlace.id;
                    visitedSet.add(byPlace.id);
                }
            }
        }

        // Reverse-geocode if address still missing.
        if (!stop.address) {
            const addr = await reverseGeocode(
                apiKey,
                stop.center_lat,
                stop.center_lng,
            );
            if (addr) updates.address = addr;
        }

        if (Object.keys(updates).length > 0) {
            const { error: upErr } = await supabase
                .from('session_stops')
                .update(updates)
                .eq('id', stop.id);
            if (upErr) {
                console.warn(`stop ${stop.id} update failed: ${upErr.message}`);
            }
        }

        // Already-bound stops still contribute to visited set so the
        // aggregate is correct even on partial enrichments.
        if (stop.customer_id) visitedSet.add(stop.customer_id);
    }

    // -------------------------------------------------------------------------
    // 3. Aggregate visited_customer_ids on the parent session row.
    // -------------------------------------------------------------------------
    const visitedArr = Array.from(visitedSet);
    if (
        visitedArr.length !== (session.visited_customer_ids?.length ?? 0) ||
        visitedArr.some((id) => !(session.visited_customer_ids ?? []).includes(id))
    ) {
        sessionPatch.visited_customer_ids = visitedArr;
    }

    if (Object.keys(sessionPatch).length > 0) {
        const { error: spErr } = await supabase
            .from('shift_sessions')
            .update(sessionPatch)
            .eq('id', sessionId);
        if (spErr) throw spErr;
    }

    await markDone(supabase, job.id);
}

// =============================================================================
// Helpers
// =============================================================================

function matchCustomer(
    customers: CustomerRow[],
    lat: number,
    lng: number,
    radiusM: number,
): CustomerRow | null {
    let best: CustomerRow | null = null;
    let bestDist = Infinity;
    for (const c of customers) {
        if (c.latitude == null || c.longitude == null) continue;
        const d = haversineMeters(lat, lng, c.latitude, c.longitude);
        if (d <= radiusM && d < bestDist) {
            bestDist = d;
            best = c;
        }
    }
    return best;
}

async function loadActiveCustomers(
    supabase: SupabaseClient,
): Promise<CustomerRow[]> {
    const { data, error } = await supabase
        .from('customers')
        .select('id, google_place_id, name, latitude, longitude')
        .eq('is_active', true);
    if (error) throw error;
    return (data ?? []) as CustomerRow[];
}

async function claimNext(
    supabase: SupabaseClient,
): Promise<JobRow | null> {
    const { data, error } = await supabase.rpc('claim_next_enrichment_job');
    if (error) throw error;
    if (!data || (Array.isArray(data) && data.length === 0)) return null;
    const row = Array.isArray(data) ? data[0] : data;
    return {
        id: row.id,
        session_id: row.session_id,
        attempts: row.attempts,
        max_attempts: row.max_attempts,
    };
}

async function markDone(
    supabase: SupabaseClient,
    jobId: string,
): Promise<void> {
    const { error } = await supabase
        .from('trip_enrichment_jobs')
        .update({ status: 'done', completed_at: new Date().toISOString(), error: null })
        .eq('id', jobId);
    if (error) throw error;
}

async function markFailed(
    supabase: SupabaseClient,
    jobId: string,
    attempts: number,
    e: unknown,
): Promise<void> {
    const msg = (e as Error).message?.slice(0, 1000) ?? String(e);
    // 30s, 2m, 8m backoff — caps under max_attempts=3 quickly.
    const backoffSec = 30 * Math.pow(4, Math.max(0, attempts - 1));
    const next = new Date(Date.now() + backoffSec * 1000).toISOString();
    await supabase
        .from('trip_enrichment_jobs')
        .update({ status: 'failed', error: msg, next_attempt_at: next })
        .eq('id', jobId);
}
