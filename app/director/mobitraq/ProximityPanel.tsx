'use client';

/**
 * Closest active teammates — Route Matrix proximity panel.
 *
 * For each currently-active employee (status='active', latest GPS fix
 * within last 30 min — see active_employee_locations view), shows the
 * driving-time of their nearest other active teammate. Useful when a
 * customer call comes in and the admin needs to know "who is actually
 * closest right now?"
 *
 * Runs at most one Routes API Compute Route Matrix call per dashboard
 * load. Pairs scale as N² but Compute Routes Essentials is 70k free /
 * month on India pricing and Route Matrix supports up to 625 elements
 * per call, so N=25 employees (625 pairs) fits comfortably.
 *
 * Re-runs when the user clicks Refresh on the dashboard.
 */

import React, { useCallback, useEffect, useState } from 'react';
import { Navigation, RefreshCw, AlertCircle } from 'lucide-react';
import { getSupabaseClient } from '@/lib/supabaseClient';

interface ActiveLoc {
    employee_id: string;
    employee_name: string;
    employee_phone: string | null;
    latitude: number;
    longitude: number;
    fix_at: string;
    accuracy: number | null;
}

interface MatrixCell {
    originIndex: number;
    destinationIndex: number;
    distanceMeters?: number;
    duration?: string; // "1234s"
    condition?: string;
}

interface ProximityRow {
    employee: ActiveLoc;
    nearest: ActiveLoc | null;
    distanceKm: number | null;
    durationMin: number | null;
}

const GOOGLE_MAPS_BROWSER_KEY =
    process.env.NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY ?? '';

export default function ProximityPanel() {
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [rows, setRows] = useState<ProximityRow[]>([]);
    const [lastRunAt, setLastRunAt] = useState<Date | null>(null);

    const compute = useCallback(async () => {
        setLoading(true);
        setError(null);
        try {
            // 1. Pull the active-employees view.
            const sb = getSupabaseClient();
            const { data, error: e } = await sb
                .from('active_employee_locations')
                .select('*');
            if (e) throw e;
            const locs = (data ?? []) as ActiveLoc[];

            if (locs.length < 2) {
                setRows(
                    locs.map((l) => ({
                        employee: l,
                        nearest: null,
                        distanceKm: null,
                        durationMin: null,
                    })),
                );
                setLastRunAt(new Date());
                return;
            }

            if (!GOOGLE_MAPS_BROWSER_KEY) {
                setError(
                    'NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY is not set. Proximity disabled.',
                );
                return;
            }

            // 2. Compute Route Matrix (NxN). Self-pairs (i==j) are
            //    filtered out client-side after we get the response.
            const matrix = await callComputeRouteMatrix(
                GOOGLE_MAPS_BROWSER_KEY,
                locs,
            );

            // 3. For each origin, pick the destination with the smallest
            //    duration (excluding self). Translate to a row.
            const out: ProximityRow[] = locs.map((emp, i) => {
                let bestCell: MatrixCell | null = null;
                for (const cell of matrix) {
                    if (cell.originIndex !== i) continue;
                    if (cell.destinationIndex === i) continue;
                    if (cell.condition && cell.condition !== 'ROUTE_EXISTS') {
                        continue;
                    }
                    if (cell.duration == null) continue;
                    if (
                        !bestCell ||
                        parseDurationSeconds(cell.duration) <
                            parseDurationSeconds(bestCell.duration!)
                    ) {
                        bestCell = cell;
                    }
                }
                if (!bestCell) {
                    return {
                        employee: emp,
                        nearest: null,
                        distanceKm: null,
                        durationMin: null,
                    };
                }
                const nearest = locs[bestCell.destinationIndex];
                return {
                    employee: emp,
                    nearest,
                    distanceKm:
                        bestCell.distanceMeters != null
                            ? bestCell.distanceMeters / 1000
                            : null,
                    durationMin:
                        bestCell.duration != null
                            ? Math.round(
                                  parseDurationSeconds(bestCell.duration) / 60,
                              )
                            : null,
                };
            });
            // Sort: closest pair first; employees without a pair go last.
            out.sort((a, b) => {
                if (a.durationMin == null && b.durationMin == null) return 0;
                if (a.durationMin == null) return 1;
                if (b.durationMin == null) return -1;
                return a.durationMin - b.durationMin;
            });
            setRows(out);
            setLastRunAt(new Date());
        } catch (e: any) {
            setError(e?.message || String(e));
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        void compute();
    }, [compute]);

    if (loading && rows.length === 0) {
        return (
            <div className="bg-white rounded-xl border border-gray-200 p-6">
                <div className="flex items-center gap-2 text-gray-500 text-sm">
                    <RefreshCw className="w-4 h-4 animate-spin" />
                    Calculating live proximity…
                </div>
            </div>
        );
    }

    if (rows.length === 0) {
        return null;
    }

    return (
        <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <div className="px-6 py-4 border-b border-gray-200 flex items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                    <Navigation className="w-4 h-4 text-primary-600" />
                    <h2 className="text-lg font-semibold text-gray-900">
                        Live proximity
                    </h2>
                    <span className="text-xs text-gray-500">
                        ({rows.filter((r) => r.nearest != null).length}/{rows.length} matched)
                    </span>
                </div>
                <div className="flex items-center gap-3 text-xs text-gray-500">
                    {lastRunAt && (
                        <span>
                            Updated {lastRunAt.toLocaleTimeString('en-IN', {
                                hour: '2-digit',
                                minute: '2-digit',
                            })}
                        </span>
                    )}
                    <button
                        onClick={() => void compute()}
                        className="inline-flex items-center gap-1 px-2 py-1 rounded-md hover:bg-gray-100"
                    >
                        <RefreshCw className="w-3.5 h-3.5" />
                        Refresh
                    </button>
                </div>
            </div>
            {error && (
                <div className="mx-6 my-3 flex items-start gap-2 p-3 bg-amber-50 border border-amber-200 rounded-lg text-amber-800 text-xs">
                    <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                    <span>{error}</span>
                </div>
            )}
            <div className="overflow-x-auto">
                <table className="w-full text-sm">
                    <thead className="bg-gray-50">
                        <tr>
                            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                                Employee (active now)
                            </th>
                            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                                Closest teammate
                            </th>
                            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                                Drive time
                            </th>
                            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                                Distance
                            </th>
                            <th className="px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                                Last fix
                            </th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-gray-100">
                        {rows.map((r) => (
                            <tr key={r.employee.employee_id} className="hover:bg-gray-50">
                                <td className="px-4 py-3 font-medium text-gray-900">
                                    {r.employee.employee_name}
                                </td>
                                <td className="px-4 py-3 text-gray-700">
                                    {r.nearest ? r.nearest.employee_name : '—'}
                                </td>
                                <td className="px-4 py-3 text-gray-900 font-medium">
                                    {r.durationMin != null
                                        ? `${r.durationMin} min`
                                        : '—'}
                                </td>
                                <td className="px-4 py-3 text-gray-700">
                                    {r.distanceKm != null
                                        ? `${r.distanceKm.toFixed(1)} km`
                                        : '—'}
                                </td>
                                <td className="px-4 py-3 text-xs text-gray-500 font-mono">
                                    {new Date(r.employee.fix_at).toLocaleTimeString(
                                        'en-IN',
                                        { hour: '2-digit', minute: '2-digit' },
                                    )}
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </div>
    );
}

// =============================================================================
// Compute Route Matrix call
// =============================================================================

async function callComputeRouteMatrix(
    apiKey: string,
    locs: ActiveLoc[],
): Promise<MatrixCell[]> {
    const waypoints = locs.map((l) => ({
        waypoint: {
            location: {
                latLng: { latitude: l.latitude, longitude: l.longitude },
            },
        },
    }));

    const body = {
        origins: waypoints,
        destinations: waypoints,
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_AWARE',
    };

    const res = await fetch(
        'https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix',
        {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Goog-Api-Key': apiKey,
                'X-Goog-FieldMask':
                    'originIndex,destinationIndex,duration,distanceMeters,condition',
            },
            body: JSON.stringify(body),
        },
    );
    if (!res.ok) {
        const txt = await res.text();
        throw new Error(`Route Matrix HTTP ${res.status}: ${txt.slice(0, 200)}`);
    }
    const data = (await res.json()) as MatrixCell[];
    if (!Array.isArray(data)) {
        throw new Error('Route Matrix returned non-array');
    }
    return data;
}

function parseDurationSeconds(d: string): number {
    // Google returns "120s" — strip trailing 's' and parse.
    if (!d) return Infinity;
    return parseInt(d.replace(/s$/, ''), 10) || Infinity;
}
