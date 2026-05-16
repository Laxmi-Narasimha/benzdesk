'use client';

import React from 'react';
import { Edit3 } from 'lucide-react';

/**
 * Display a distance for a session that may have been admin-corrected
 * via the Discrepancies page.
 *
 * Cases:
 *   - No adjustment for this session → render plain "X.X km".
 *   - Adjustment exists → render "old+delta = corrected km" with an
 *     edited badge. Tooltip carries the admin's reason.
 *
 * Example display when old=46, delta=+10, corrected=56:
 *     "46 + 10 = 56 km" + small ✎ edit pill
 *
 * Negative deltas render with "−" instead of "+".
 */
export interface DistanceAdjustment {
    session_id: string;
    old_km: number;
    corrected_km: number;
    delta_km: number;
    reason: string | null;
    created_at: string;
}

export function AdjustedDistance({
    sessionId,
    rawKm,
    adjustment,
    className,
    compact,
}: {
    sessionId: string;
    /** Pre-correction km (final_km from shift_sessions). Shown only if no
     *  adjustment row exists for this session. */
    rawKm: number;
    /** The adjustment row for this session, if any. Caller looks it up
     *  by sessionId from useDistanceAdjustments(). */
    adjustment?: DistanceAdjustment | null;
    className?: string;
    /** When true, render in a single compact line with smaller badge. */
    compact?: boolean;
}) {
    if (!adjustment) {
        return (
            <span className={className}>
                {rawKm.toFixed(2)} km
            </span>
        );
    }
    const sign = adjustment.delta_km >= 0 ? '+' : '−';
    const deltaAbs = Math.abs(adjustment.delta_km).toFixed(2);
    const old = adjustment.old_km.toFixed(2);
    const corrected = adjustment.corrected_km.toFixed(2);
    if (compact) {
        return (
            <span
                className={`inline-flex items-center gap-1.5 ${className ?? ''}`}
                title={
                    adjustment.reason
                        ? `Admin correction: ${adjustment.reason}`
                        : 'Admin correction'
                }
            >
                <span className="font-semibold">{corrected} km</span>
                <span
                    className="inline-flex items-center gap-0.5 px-1.5 py-0.5 text-[10px] font-semibold rounded-full bg-amber-50 text-amber-800 border border-amber-200"
                    aria-label="Admin-edited"
                >
                    <Edit3 className="w-2.5 h-2.5" />
                    {sign}{deltaAbs}
                </span>
            </span>
        );
    }
    return (
        <span className={`inline-flex items-center gap-2 ${className ?? ''}`}>
            <span className="text-xs text-slate-500">
                {old} {sign} {deltaAbs} =
            </span>
            <span className="font-semibold">{corrected} km</span>
            <span
                className="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold rounded-full bg-amber-50 text-amber-800 border border-amber-200"
                title={
                    adjustment.reason
                        ? `Reason: ${adjustment.reason}`
                        : 'Admin-edited distance'
                }
            >
                <Edit3 className="w-3 h-3" />
                Admin edit
            </span>
        </span>
    );
}

/** Optional standalone reason chip — render under a session card if you
 *  want the reason visible without hovering. */
export function AdjustmentReasonChip({
    reason,
}: {
    reason: string | null | undefined;
}) {
    if (!reason || !reason.trim()) return null;
    return (
        <div className="mt-1 text-[11px] text-amber-700 bg-amber-50 border border-amber-100 rounded-md px-2 py-1 inline-block">
            <span className="font-semibold">Edit reason:</span> {reason}
        </div>
    );
}
