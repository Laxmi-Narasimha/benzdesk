'use client';

import { useEffect, useMemo, useState } from 'react';
import { getSupabaseClient } from '@/lib/supabaseClient';
import type { DistanceAdjustment } from './AdjustedDistance';

/**
 * Sibling helper: when the caller has request IDs (e.g. an expense
 * claim list, where rows are NOT keyed by session_id), fetch
 * adjustments whose `affected_request_ids` array includes any of
 * those IDs. Returns a Record keyed by request_id → adjustment.
 *
 * Same "latest wins" semantic as useDistanceAdjustments.
 */
export function useDistanceAdjustmentsByRequest(
    requestIds: string[],
): Record<string, DistanceAdjustment & { affected_request_ids: string[] }> {
    const idsKey = useMemo(
        () => requestIds.filter(Boolean).sort().join(','),
        [requestIds],
    );
    const [map, setMap] = useState<
        Record<string, DistanceAdjustment & { affected_request_ids: string[] }>
    >({});
    useEffect(() => {
        let cancelled = false;
        if (!idsKey) {
            setMap({});
            return;
        }
        (async () => {
            try {
                const sb = getSupabaseClient();
                const { data, error } = await sb
                    .from('mobitraq_distance_adjustments')
                    .select(
                        'session_id, old_km, corrected_km, delta_km, reason, created_at, affected_request_ids',
                    )
                    .overlaps('affected_request_ids', idsKey.split(','))
                    .order('created_at', { ascending: false });
                if (error) {
                    console.warn('[useDistanceAdjustmentsByRequest]', error);
                    return;
                }
                if (cancelled) return;
                const next: Record<
                    string,
                    DistanceAdjustment & { affected_request_ids: string[] }
                > = {};
                for (const row of (data || []) as (DistanceAdjustment & {
                    affected_request_ids: string[] | null;
                })[]) {
                    const requestIds = row.affected_request_ids ?? [];
                    for (const reqId of requestIds) {
                        // Latest wins (ordered DESC)
                        if (!next[reqId]) {
                            next[reqId] = {
                                ...row,
                                affected_request_ids: requestIds,
                            };
                        }
                    }
                }
                setMap(next);
            } catch (e) {
                console.warn('[useDistanceAdjustmentsByRequest]', e);
            }
        })();
        return () => {
            cancelled = true;
        };
    }, [idsKey]);
    return map;
}

/**
 * Batch-fetch the latest admin distance correction for each session id
 * in `sessionIds`. Returns a Record keyed by session_id so any
 * `<AdjustedDistance>` instance can look its own up in O(1).
 *
 * Only one row per session is returned (the most recent). If you need
 * the full edit history, query `mobitraq_distance_adjustments`
 * directly — this hook is for "is the displayed number admin-edited?"
 * not the audit timeline.
 */
export function useDistanceAdjustments(
    sessionIds: string[],
): Record<string, DistanceAdjustment> {
    const idsKey = useMemo(
        () => sessionIds.filter(Boolean).sort().join(','),
        [sessionIds],
    );
    const [map, setMap] = useState<Record<string, DistanceAdjustment>>({});
    useEffect(() => {
        let cancelled = false;
        if (!idsKey) {
            setMap({});
            return;
        }
        (async () => {
            try {
                const sb = getSupabaseClient();
                const { data, error } = await sb
                    .from('mobitraq_distance_adjustments')
                    .select(
                        'session_id, old_km, corrected_km, delta_km, reason, created_at',
                    )
                    .in('session_id', idsKey.split(','))
                    .order('created_at', { ascending: false });
                if (error) {
                    console.warn('[useDistanceAdjustments]', error);
                    return;
                }
                if (cancelled) return;
                const next: Record<string, DistanceAdjustment> = {};
                for (const row of (data || []) as DistanceAdjustment[]) {
                    // Latest wins: ordered DESC, only set if not seen yet.
                    if (!next[row.session_id]) next[row.session_id] = row;
                }
                setMap(next);
            } catch (e) {
                console.warn('[useDistanceAdjustments]', e);
            }
        })();
        return () => {
            cancelled = true;
        };
    }, [idsKey]);
    return map;
}
