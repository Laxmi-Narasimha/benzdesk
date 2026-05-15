// Supabase Edge Function: finalize-trip
//
// Orchestrates the post-session distance verification pipeline.
//
//   1. Claim a pending job (claim_next_finalization_job RPC)
//   2. Load all GPS points for the session (filter mock + bad accuracy + still)
//   3. Split on gaps > 120s OR spacing > 300m (don't interpolate huge gaps)
//   4. Per segment: downsample to ~30m, snap via MapMatcherProvider
//   5. Sum snapped distances → final_km
//   6. UPDATE shift_sessions with final_km, distance_source, snapped polyline
//   7. Mark job done (or failed → backoff retry, up to max_attempts)
//
// Scheduling: invoked on a cron tick (1/min) and on-demand via POST.
// The function is idempotent on session_id — running it twice for the same
// job is safe.
//
// See docs/DISTANCE_TRACKING_METHODOLOGY.md §3.7 and §6 acceptance criteria.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

import {
    downsampleByDistance,
    polylineLengthMeters,
    splitOnGaps,
    TimedPoint,
} from './_shared/geo.ts';
import {
    makeMapMatcherProvider,
    MapMatcherProvider,
    MatchResult,
} from './_shared/map_matcher.ts';

// Tunables.
const GAP_SPLIT_SECONDS = 120;
const GAP_SPLIT_METERS = 300;
const DOWNSAMPLE_SPACING_M = 30;
const MAX_GPS_ACCURACY_M = 50;
const POINT_UPLOAD_WAIT_TICKS = 5; // wait this many short polls before snapping
const POINT_UPLOAD_WAIT_DELAY_MS = 3000;
const POLYLINE_RETENTION_DAYS = 25; // 5-day safety margin under Google's 30-day ToS
const MAX_JOBS_PER_TICK = 5;

interface LocationRow {
    latitude: number;
    longitude: number;
    accuracy: number | null;
    is_mock: boolean | null;
    activity_type: string | null;
    activity_confidence: number | null;
    recorded_at: string;
    counts_for_distance: boolean | null;
}

interface SessionRow {
    id: string;
    employee_id: string;
    estimated_km: number | null;
    final_km: number | null;
    confidence: string | null;
}

serve(async (_req) => {
    let processed = 0;
    let failed = 0;

    try {
        const supabase = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
        );

        const provider = makeMapMatcherProvider();

        for (let i = 0; i < MAX_JOBS_PER_TICK; i++) {
            const claimed = await claimNextJob(supabase);
            if (!claimed) break;

            try {
                await finalizeOne(supabase, provider, claimed);
                processed++;
            } catch (e) {
                failed++;
                await markJobFailed(supabase, claimed.id, claimed.attempts, e);
            }
        }

        // Best-effort polyline purge (in case pg_cron isn't enabled on this instance).
        try {
            await supabase.rpc('purge_expired_snapped_polylines');
        } catch (_) {
            /* fine — the RPC may not exist on older DBs */
        }

        return new Response(JSON.stringify({ processed, failed }), {
            headers: { 'Content-Type': 'application/json' },
        });
    } catch (e) {
        console.error('finalize-trip fatal:', e);
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
// Job lifecycle helpers
// =============================================================================

interface JobRow {
    id: string;
    session_id: string;
    attempts: number;
    max_attempts: number;
}

async function claimNextJob(supabase: SupabaseClient): Promise<JobRow | null> {
    const { data, error } = await supabase.rpc('claim_next_finalization_job');
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

async function markJobDone(
    supabase: SupabaseClient,
    jobId: string,
): Promise<void> {
    const { error } = await supabase
        .from('trip_finalization_jobs')
        .update({ status: 'done', completed_at: new Date().toISOString(), error: null })
        .eq('id', jobId);
    if (error) throw error;
}

async function markJobFailed(
    supabase: SupabaseClient,
    jobId: string,
    attempts: number,
    e: unknown,
): Promise<void> {
    const msg = (e as Error).message?.slice(0, 1000) ?? String(e);
    // Exponential backoff: 30s, 2m, 8m, 32m, 2h.
    const backoffSec = 30 * Math.pow(4, Math.max(0, attempts - 1));
    const nextAttempt = new Date(Date.now() + backoffSec * 1000).toISOString();
    await supabase
        .from('trip_finalization_jobs')
        .update({
            status: 'failed',
            error: msg,
            next_attempt_at: nextAttempt,
        })
        .eq('id', jobId);
}

// =============================================================================
// Core finalize routine
// =============================================================================

async function finalizeOne(
    supabase: SupabaseClient,
    provider: MapMatcherProvider,
    job: JobRow,
): Promise<void> {
    const sessionId = job.session_id;

    // 1. Load session
    const { data: sessionRows, error: sErr } = await supabase
        .from('shift_sessions')
        .select('id, employee_id, estimated_km, final_km, confidence')
        .eq('id', sessionId)
        .limit(1);
    if (sErr) throw sErr;
    if (!sessionRows || sessionRows.length === 0) {
        throw new Error('Session not found');
    }
    const session = sessionRows[0] as SessionRow;

    // 2. Wait briefly for GPS points to finish uploading (offline trips
    //    may still be syncing batches when the job fires).
    let points: LocationRow[] = [];
    for (let tick = 0; tick < POINT_UPLOAD_WAIT_TICKS; tick++) {
        points = await loadPoints(supabase, sessionId);
        if (points.length >= 2) {
            const newest = new Date(points[points.length - 1].recorded_at);
            if (Date.now() - newest.getTime() > POINT_UPLOAD_WAIT_DELAY_MS) {
                // Newest point is old enough → no fresh inserts in flight.
                break;
            }
        }
        await new Promise((r) => setTimeout(r, POINT_UPLOAD_WAIT_DELAY_MS));
    }

    if (points.length < 2) {
        // No GPS data — keep estimated_km, mark unverified.
        await supabase
            .from('shift_sessions')
            .update({
                final_km: session.estimated_km ?? 0,
                distance_source: 'device_gps_filtered',
                confidence: 'unverified_no_gps',
                reason_codes: ['INSUFFICIENT_POINTS_FOR_SNAP'],
                finalized_at: new Date().toISOString(),
            })
            .eq('id', sessionId);
        await markJobDone(supabase, job.id);
        return;
    }

    // 3. Filter at server side: drop mocks, drop low-accuracy bursts, drop still bursts.
    const filtered: TimedPoint[] = [];
    for (const p of points) {
        if (p.is_mock === true) continue;
        if (p.accuracy != null && p.accuracy > MAX_GPS_ACCURACY_M) continue;
        if (
            p.activity_type === 'still' &&
            (p.activity_confidence ?? 0) >= 75
        ) {
            // STILL with confidence — almost certainly parked-car jitter
            continue;
        }
        filtered.push({
            lat: p.latitude,
            lng: p.longitude,
            timestampMs: new Date(p.recorded_at).getTime(),
        });
    }

    if (filtered.length < 2) {
        await supabase
            .from('shift_sessions')
            .update({
                final_km: session.estimated_km ?? 0,
                distance_source: 'device_gps_filtered',
                confidence: 'low',
                reason_codes: ['ALL_POINTS_FILTERED'],
                finalized_at: new Date().toISOString(),
            })
            .eq('id', sessionId);
        await markJobDone(supabase, job.id);
        return;
    }

    // 4. Split into segments on real-world gaps.
    const segments = splitOnGaps(filtered, GAP_SPLIT_SECONDS, GAP_SPLIT_METERS);
    if (segments.length === 0) {
        await supabase
            .from('shift_sessions')
            .update({
                final_km: session.estimated_km ?? 0,
                distance_source: 'device_gps_filtered',
                confidence: 'low',
                reason_codes: ['SEGMENTATION_PRODUCED_NO_USABLE_SEGMENTS'],
                finalized_at: new Date().toISOString(),
            })
            .eq('id', sessionId);
        await markJobDone(supabase, job.id);
        return;
    }

    // 5. Per segment: downsample, snap, accumulate.
    let totalKm = 0;
    const polylinePieces: string[] = [];
    const providerNotes: string[] = [];
    const reasonCodes = new Set<string>();
    if (segments.length > 1) {
        reasonCodes.add('GPS_GAP_OVER_120S');
    }

    for (const segment of segments) {
        const ds = downsampleByDistance(segment, DOWNSAMPLE_SPACING_M);
        const dsTimed: TimedPoint[] = ds.map((p, i) => ({
            lat: p.lat,
            lng: p.lng,
            // After downsampling we lose timestamps for intermediate points; the
            // Roads API doesn't need them anyway, but the interface wants them.
            timestampMs: segment[Math.min(i, segment.length - 1)].timestampMs,
        }));
        let match: MatchResult;
        try {
            match = await provider.matchSegment(dsTimed);
        } catch (e) {
            // Roads API failed for this segment — fall back to raw geodesic
            // length for the segment so we don't lose the whole trip.
            const rawM = polylineLengthMeters(ds);
            totalKm += rawM / 1000;
            providerNotes.push(`segment_failed:${(e as Error).message.slice(0, 80)}`);
            reasonCodes.add('ROADS_API_PARTIAL_FAILURE');
            continue;
        }
        totalKm += match.distanceKm;
        if (match.snappedPolyline) polylinePieces.push(match.snappedPolyline);
        providerNotes.push(...match.notes);
        if (match.distanceKm <= 0) {
            reasonCodes.add('SEGMENT_EMPTY_AFTER_SNAP');
        }
    }

    // 6. Compute updated confidence using raw-vs-snapped diff.
    const estimated = session.estimated_km ?? 0;
    const existingFinal = session.final_km ?? 0;
    if (estimated > 0) {
        const diff = Math.abs(totalKm - estimated) / estimated;
        if (diff > 0.15) reasonCodes.add('RAW_SNAPPED_DIFF_OVER_15_PERCENT');
    }
    const confidence = computeConfidence(
        reasonCodes,
        points.length,
        estimated,
        totalKm,
    );

    // 7. Write back. ToS: polyline_expires_at = NOW + 25 days.
    const expiresAt = new Date(
        Date.now() + POLYLINE_RETENTION_DAYS * 24 * 3600 * 1000,
    ).toISOString();

    const snappedPolyline = polylinePieces[0] ?? null;

    // RULE: Roads API may only RAISE final_km, never lower it.
    //
    // Snap-to-roads tends to straighten curvy real-world driven paths
    // — a 12 km drive with twisty roads can come back as 9.7 km
    // because the snapped polyline takes shortcuts through the road
    // network. Lowering the rep's billed distance based on that would
    // cost them real money on a single trip and break trust.
    //
    // If Roads-API result is LOWER than what the device already
    // recorded, keep the device value. We still store the snapped
    // polyline + reason code for the audit trail (admin can see the
    // diff on the discrepancies page).
    const deviceBaseline = Math.max(existingFinal, estimated);
    let writtenFinalKm: number;
    let writtenSource: string;
    if (totalKm > deviceBaseline) {
        writtenFinalKm = totalKm;
        writtenSource = 'roads_api_verified';
    } else {
        writtenFinalKm = deviceBaseline;
        writtenSource = session.confidence ? 'device_gps_filtered' : 'device_gps_filtered';
        reasonCodes.add('ROADS_API_LOWER_THAN_DEVICE');
        console.log(
            `finalize-trip session=${sessionId} keeping device value: ` +
                `device=${deviceBaseline.toFixed(3)} roads=${totalKm.toFixed(3)}`,
        );
    }

    const { error: uErr } = await supabase
        .from('shift_sessions')
        .update({
            final_km: writtenFinalKm,
            distance_source: writtenSource,
            confidence,
            reason_codes: Array.from(reasonCodes),
            finalized_at: new Date().toISOString(),
            snapped_polyline: snappedPolyline,
            polyline_expires_at: snappedPolyline ? expiresAt : null,
        })
        .eq('id', sessionId);
    if (uErr) throw uErr;

    console.log(
        `finalize-trip session=${sessionId} ` +
            `estimated=${estimated.toFixed(3)} final=${totalKm.toFixed(3)} ` +
            `segments=${segments.length} provider=${provider.name} ` +
            `confidence=${confidence} notes=${providerNotes.join(';')}`,
    );

    await markJobDone(supabase, job.id);
}

async function loadPoints(
    supabase: SupabaseClient,
    sessionId: string,
): Promise<LocationRow[]> {
    const { data, error } = await supabase
        .from('location_points')
        .select(
            'latitude, longitude, accuracy, is_mock, activity_type, activity_confidence, recorded_at, counts_for_distance',
        )
        .eq('session_id', sessionId)
        .order('recorded_at', { ascending: true });
    if (error) throw error;
    return (data ?? []) as LocationRow[];
}

function computeConfidence(
    reasons: Set<string>,
    pointCount: number,
    estimatedKm: number,
    finalKm: number,
): string {
    if (pointCount === 0) return 'unverified_no_gps';
    if (reasons.has('MOCK_LOCATION_DETECTED')) return 'low';

    let score = 100;
    if (pointCount < 10) score -= 30;
    if (reasons.has('GPS_GAP_OVER_120S')) score -= 25;
    if (reasons.has('ROADS_API_PARTIAL_FAILURE')) score -= 20;
    if (reasons.has('RAW_SNAPPED_DIFF_OVER_15_PERCENT')) score -= 15;
    if (reasons.has('SEGMENT_EMPTY_AFTER_SNAP')) score -= 10;
    if (estimatedKm > 0 && finalKm === 0) score -= 50;

    if (score >= 80) return 'high';
    if (score >= 50) return 'medium';
    return 'low';
}
