# BenzMobiTraq Distance Tracking — Methodology, Problem, Research, Solution

**Status:** Authoritative reference for distance calculation in this product.
**Last updated:** 2026-05-15
**Owner:** Engineering

---

## 1. The Problem

Field-force employees use BenzMobiTraq to log travel for expense reimbursement. The flagship feature is per-trip distance tracking. We had two production incidents that triggered this rewrite:

### Incident A — On-screen vs. expense distance mismatch (online sessions)

A driver completed an online trip showing **11.92 km** on the device screen. When the post-session expense dialog opened, the same trip was reported as **12.25 km**. The driver claimed reimbursement for 12.25 km because that is what the system filed; but 11.92 km was the value they were shown live, which they had mentally accepted as "their trip distance." Trust eroded.

**Investigation showed two different distance values existed for the same trip:**

| Source | Value | How calculated |
|---|---|---|
| Device screen (DistanceEngine) | 11.92 km | Sum of `distance_delta_m` from accepted, jitter-rejected GPS points |
| `shift_sessions.total_km` | 11.92 km | Same as above (written by `endSession`) |
| `session_rollups.distance_km` | 12.25 km | Raw haversine between every GPS point, computed by DB trigger, ignored `counts_for_distance` |
| Expense dialog | 12.25 km | Was reading `session_rollups` first, only falling back to `total_km` if rollup was null |

So the trip really was 11.92 km. The expense dialog was reading the inflated rollup value. The dialog was wrong; the screen was right.

### Incident B — Offline sessions showing 0 km in admin (offline sessions)

Drivers who completed a trip with intermittent or no internet saw the trip filed at the correct local distance (e.g. 9.9 km) but the admin panel showed **0.0 km** for the same session. Investigation showed:

1. Session created offline → INSERT row queued
2. Session ended offline → STOP queued with `verifiedDistanceKm`
3. App regained internet → sync ran:
   - `_syncPendingSessionStart` INSERTed session with `total_km = 0`
   - `_syncPendingSessionStop` called `stopSession(...)` which UPDATEd `total_km = 9.9`
   - GPS points uploaded → trigger added haversine deltas on top → `total_km = 9.9 + sum(deltas)`
4. **However**, `stopSession` returns `null` on internal failure (catches exceptions silently). The caller did `clearPendingSessionEnd()` unconditionally — meaning a silent failure cleared the pending stop data forever, leaving `total_km = 0` in the database permanently.

This was a real bug — the pending-stop data was being thrown away on the first failed retry.

### Incident C — Mid-session connectivity loss

A session that starts online, loses connection mid-trip, and ends online (or vice versa) was producing inconsistent distance values depending on when the connectivity dropped and which sync path executed.

---

## 2. Research

We reviewed first-principles GPS tracking, Android location APIs, Google Maps Platform APIs and pricing, OSM/OSRM alternatives, and our own production data.

### 2.1 Phone GPS does not need internet

Android GPS receives one-way satellite signals; positions are calculated locally on the device. `requestLocationUpdates(...)` on `FusedLocationProvider` works offline. Internet is needed for *reverse geocoding* (address lookup), *map tiles*, *map matching*, and *sync to backend* — not for measuring position.

**Conclusion:** Mid-session internet loss is not a tracking problem; it's a sync problem. The phone keeps capturing GPS just fine; we only need to make sure those points reach the server eventually.

### 2.2 Phone GPS is not exact

GPS.gov states typical smartphone GPS accuracy is ~4.9m under open sky and degrades with signal blockage, multipath, and dense urban environments. Raw point-to-point distance summed from noisy points over-counts due to:

- Lateral jitter (position bouncing around within accuracy radius)
- Stationary drift (vehicle parked; GPS reports small movements)
- Multipath in dense urban areas (Gurgaon/Manesar service roads and flyovers)
- Spurious jumps after GPS reacquisition (tunnels, basements, app wake-up)

**Conclusion:** Raw GPS distance is unreliable for billing. Filtering is mandatory.

### 2.3 Google APIs evaluated

| API | Purpose | Verdict for our case |
|---|---|---|
| **Roads API — Snap to Roads / Route Traveled** | Takes up to 100 GPS points, snaps to nearest plausible road, optional `interpolate=true` returns road geometry between submitted points | **Correct API for map-matching final distance** |
| **Routes API — Compute Routes** | Returns optimal/planned route between two points (up to 25 intermediate waypoints) | Only useful as a cross-check for under-counted GPS; cannot reconstruct an actual driven path |
| **Places API** | Place details — names, addresses, ratings | Only for naming start/end locations. Cannot return travel distance. |

### 2.4 Google Maps Platform Terms of Service

This is non-obvious and load-bearing:

- **Roads API content must NOT be displayed in conjunction with a non-Google map** (e.g. Leaflet/OpenStreetMap). Source: Google Maps Platform Service Specific Terms.
- **Latitude/longitude values from Roads API may be cached for at most 30 consecutive calendar days**.
- **Place IDs may be cached indefinitely**.

**Implication for our product:**
- We use Leaflet + OSM tiles in the admin timeline view.
- We can call Roads API server-side to compute a final distance *number*.
- We **cannot** display the Roads-snapped polyline on Leaflet.
- We **can** display the raw GPS breadcrumbs (our first-party data) on Leaflet.
- We **must** purge stored snapped polyline geometry after ≤30 days.

### 2.5 Pricing (Google Maps Platform, India region)

| Service | Free monthly events | Beyond free tier |
|---|---|---|
| Roads — Route Traveled (Snap to Roads, ≤100 pts/call) | 35,000 | $3.00 / 1,000 |
| Routes — Compute Routes Essentials | 70,000 | $1.50 / 1,000 |

**At our current scale** (20 employees, ~4 trips/day, ~25 km/trip, 30m downsample → ~9 Roads API calls per trip):

- 2,400 trips/month × 9 calls = 21,600 calls/month
- Well under the 35,000 free tier → **₹0/month operating cost**

We remain free-tier even at 3× current scale.

### 2.6 Self-hosted alternatives (OSRM, Valhalla)

OSRM's Match service and Valhalla's `trace_route` both snap GPS traces to road networks using Hidden Markov Model / Viterbi-style map matching. Both are compatible with OSM data and Leaflet display (no Google ToS).

**Verdict:** Not for now. At 20 employees the server + maintenance cost exceeds Google's API cost. Re-evaluate at 500+ employees or if Google ToS becomes a blocker.

### 2.7 The honest accuracy ceiling

**There is no system that gives you ground-truth distance from a phone without an odometer.** Roads API improves on raw GPS in most cases, but introduces its own failure modes:

- ✅ Removes lateral jitter
- ✅ Cleans up stationary drift
- ❌ Cannot invent missing GPS data
- ❌ Can snap to wrong parallel road on flyovers / service roads
- ❌ Can undercount detours and U-turns (smooths them away)
- ❌ Multi-modal trips (drive → park → walk) snap walking onto roads

**Conclusion:** Roads API is a verification layer, not a magic accuracy guarantee.

---

## 3. Solution — Architecture

### 3.1 The principles

1. **The number shown to the user at session end is the number filed.** No silent recalculation between display and expense logging.
2. **Estimated vs. Final are separate fields.** `estimated_km` is locked at session end from the on-device DistanceEngine output. `final_km` defaults to `estimated_km` and is overwritten only by an authoritative verification (Roads API, admin correction).
3. **The same pipeline runs for online and offline trips.** The only difference is *when* finalization runs, not *how* distance is calculated.
4. **Roads API is invoked selectively, not universally.** Only when it adds genuine value: offline trips, low-confidence GPS, large gaps, disputed/admin-verified trips.
5. **All distance changes are auditable.** `distance_source`, `confidence`, `reason_codes`, `finalized_at` are persisted. Nothing changes silently.
6. **ToS-compliant from day one.** Snapped polyline geometry expires; raw GPS and final numeric values are kept forever.

### 3.2 Data model

```sql
-- shift_sessions additions (Stage 1 + 2 + 3)

ALTER TABLE shift_sessions ADD COLUMN estimated_km REAL;       -- locked at session end from device
ALTER TABLE shift_sessions ADD COLUMN final_km REAL;            -- billed distance; starts = estimated_km, may be overwritten by verification
ALTER TABLE shift_sessions ADD COLUMN distance_source TEXT;     -- 'device_gps_filtered' | 'roads_api_verified' | 'admin_corrected'
ALTER TABLE shift_sessions ADD COLUMN confidence TEXT;          -- 'high' | 'medium' | 'low' | 'unverified_no_gps'
ALTER TABLE shift_sessions ADD COLUMN reason_codes JSONB;       -- array: ['GPS_GAP_OVER_120S', 'MOCK_LOCATION_DETECTED', ...]
ALTER TABLE shift_sessions ADD COLUMN finalized_at TIMESTAMPTZ; -- when final_km was last written
ALTER TABLE shift_sessions ADD COLUMN snapped_polyline TEXT;    -- encoded polyline from Roads API; nullable
ALTER TABLE shift_sessions ADD COLUMN polyline_expires_at TIMESTAMPTZ; -- ≤30 days from polyline write; ToS

-- location_points additions (Stage 2)

ALTER TABLE location_points ADD COLUMN elapsed_realtime_nanos BIGINT; -- monotonic, clock-jump safe
ALTER TABLE location_points ADD COLUMN is_mock BOOLEAN DEFAULT FALSE;
ALTER TABLE location_points ADD COLUMN speed_accuracy_mps REAL;
ALTER TABLE location_points ADD COLUMN bearing_accuracy_deg REAL;
ALTER TABLE location_points ADD COLUMN activity_type TEXT;        -- 'in_vehicle' | 'still' | 'walking' | 'on_bicycle' | 'unknown'
ALTER TABLE location_points ADD COLUMN activity_confidence INT;    -- 0..100

-- trip_finalization_jobs (Stage 3)

CREATE TABLE trip_finalization_jobs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id    UUID NOT NULL REFERENCES shift_sessions(id) ON DELETE CASCADE,
  reason        TEXT NOT NULL,           -- 'offline_session' | 'low_confidence' | 'large_gap' | 'admin_verify' | 'disputed'
  status        TEXT NOT NULL DEFAULT 'pending', -- 'pending' | 'in_progress' | 'done' | 'failed' | 'skipped'
  attempts      INT NOT NULL DEFAULT 0,
  error         TEXT,
  enqueued_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at    TIMESTAMPTZ,
  completed_at  TIMESTAMPTZ,
  UNIQUE (session_id)                     -- idempotent: one job per session
);
```

### 3.3 Lifecycle of a session's distance number

```
Live session (online OR offline):
  ↓
  Device captures GPS → DistanceEngine filters + accumulates
  ↓
  User taps "Work Done"
  ↓
  Device computes verifiedDistanceKm (already does this today)
  ↓
  Session.estimated_km := verifiedDistanceKm    (LOCKED, never recalculated)
  Session.final_km     := verifiedDistanceKm    (default; may be overwritten)
  Session.distance_source := 'device_gps_filtered'
  Session.confidence   := computeConfidence(points, gaps, accuracy, mocks)
  Session.reason_codes := computeReasons(...)
  Session.finalized_at := now()
  ↓
  Expense dialog reads ONLY shift_sessions.final_km   ← fixes Incident A
  ↓
  IF (was_offline OR confidence='low' OR large_gap OR admin_verify):
    INSERT into trip_finalization_jobs (session_id, reason)
    Edge Function picks up → waits for all GPS points to upload
       → downsamples to ~30m
       → Roads API Snap to Roads in 100-pt chunks with overlap
       → computes snapped_distance_km
       → UPDATE shift_sessions SET
           final_km = snapped_distance_km,
           distance_source = 'roads_api_verified',
           confidence = recomputeWithSnap(...),
           snapped_polyline = encoded_polyline,
           polyline_expires_at = now() + 25 days,
           finalized_at = now()
```

### 3.4 Trigger discipline

The `update_session_rollup` trigger:
- ✅ Updates `session_rollups.distance_km` (for audit & cross-check)
- ✅ Updates `daily_rollups`
- ❌ **NEVER** touches `shift_sessions.final_km` or `shift_sessions.estimated_km`
- ⚠️ Still updates `shift_sessions.total_km` for backwards-compatibility, but `total_km` is deprecated for billing

The expense flow and admin UI must read `final_km` exclusively. `total_km` is retained transiently but will be removed once all reads are migrated.

### 3.5 Confidence scoring algorithm

```
score = 100
IF point_count < 10:        score -= 30, reason='SPARSE_POINTS'
IF median_accuracy > 30:    score -= 15, reason='POOR_ACCURACY'
IF max_gap_seconds > 120:   score -= 25, reason='GPS_GAP_OVER_120S'
IF max_gap_seconds > 300:   score -= 20  (additional)
IF any is_mock:             score -= 100, reason='MOCK_LOCATION_DETECTED'
IF max_spacing_meters > 300: score -= 15, reason='POINT_SPACING_OVER_300M'
IF stationary_ratio > 0.3:  score -= 10, reason='STATIONARY_DOMINATED'
IF raw_vs_filtered_diff > 0.15: score -= 10, reason='RAW_FILTERED_DIFF_HIGH'
IF distance_source='roads_api_verified':
  IF raw_vs_snapped_diff > 0.15: score -= 10, reason='RAW_SNAPPED_DIFF_HIGH'

confidence = 'high'   IF score >= 80
confidence = 'medium' IF 50 <= score < 80
confidence = 'low'    IF score < 50
confidence = 'unverified_no_gps' IF point_count == 0
```

### 3.6 Offline-resilient session lifecycle

The single largest reliability requirement: **a session that starts online, loses connection mid-trip, and ends offline must produce the same `final_km` as one that stayed online the whole time.**

Mechanisms (already in place after fixes 1-3 in this commit series):
1. **Session START** — if INSERT fails, store in `pending_session_start` (SharedPreferences). Sync timer retries on connectivity.
2. **Session STOP** — if UPDATE fails (returns `null`), keep `pending_session_end` (we no longer clear it on silent failure).
3. **GPS points** — captured to SQLite (`location_queue`) regardless of connectivity. Sync timer batches them up.
4. **Trigger discipline** — sync order is start → GPS points → stop, so trigger additions to `total_km` happen before `endSession` overwrites with the verified value.
5. **Idempotent finalization** — `trip_finalization_jobs` keyed by `session_id`; re-running is safe and even desired if more GPS points arrive after the first finalization.

### 3.7 Roads API server-side flow

The Edge Function (`infra/supabase/functions/finalize-trip`) does:

```
1. SELECT job FROM trip_finalization_jobs WHERE status='pending' LIMIT 1 FOR UPDATE SKIP LOCKED
2. SET status='in_progress', started_at=NOW(), attempts=attempts+1
3. Wait until pending GPS upload count for session_id == 0
   (poll location_points with retry budget; 5-minute timeout)
4. SELECT all location_points for session, ordered by recorded_at
5. Apply server-side filter: drop is_mock=true, drop accuracy>50, drop activity='still' bursts
6. Split into segments on gaps>120s or spacing>300m
7. For each segment >= 2 points:
   a. Downsample to ~30m spacing
   b. Chunk into ≤100-point batches with 10-point overlap
   c. Call Roads API Snap to Roads, interpolate=true
   d. Deduplicate overlap points in response
   e. Sum geodesic distance over snapped polyline
8. final_km = sum of all segments
9. UPDATE shift_sessions SET final_km=..., distance_source='roads_api_verified',
     confidence=..., snapped_polyline=..., polyline_expires_at=NOW()+25 days,
     finalized_at=NOW()
10. UPDATE trip_finalization_jobs SET status='done', completed_at=NOW()
On error: status='failed', error=..., retry up to 5 times with backoff
```

### 3.8 ToS-compliant retention

A nightly cron (Postgres `pg_cron` or scheduled Edge Function) runs:

```sql
UPDATE shift_sessions
SET snapped_polyline = NULL,
    polyline_expires_at = NULL
WHERE polyline_expires_at IS NOT NULL
  AND polyline_expires_at < NOW();
```

`final_km`, `confidence`, `reason_codes`, `distance_source`, raw `location_points` are kept forever.

### 3.9 UI behavior

**Live session (during trip):** show DistanceEngine value, no API calls.

**Right after "Work Done":** show `estimated_km` ("Estimated 11.92 km — verifying...").

**After finalization (within seconds for online; on next sync for offline):**
- High confidence: "Final distance: 12.08 km · Verified by road-matching"
- Medium confidence: "Final distance: 11.92 km · Moderate confidence"
- Low confidence: "Final distance: 11.92 km · Low confidence — admin review recommended"

**Admin timeline:** Leaflet + OSM tiles. Shows raw GPS breadcrumbs only (first-party data). Snapped polyline is never rendered here per Google ToS.

**Admin session detail:** confidence badge, reason codes list, "Verify Distance" button to re-enqueue finalization on demand.

---

## 4. What this fixes

| Incident | Root cause | Fix |
|---|---|---|
| A — 11.92 → 12.25 inflation | Expense dialog read `session_rollups` (raw haversine) instead of device-filtered value | Expense reads only `shift_sessions.final_km`. `final_km` is locked at session end. |
| B — Offline 0 km in admin | `_syncPendingSessionStop` cleared pending data even on silent failure (`stopSession` returned `null`) | Already fixed in prior commit: null check before clearing. Plus Stage 3 finalization queue gives a second authoritative path. |
| C — Mid-session disconnect | Sync order let trigger double-count after `endSession` UPDATE | Already fixed: sync order is now start → GPS points → stop. Plus trigger 071 skips completed sessions. |

---

## 5. What this does NOT fix (honest scope)

- We cannot get ground-truth distance from a phone. Roads API is a *better* number, not a *guaranteed-true* number.
- We cannot recover distance for periods when the phone had no GPS lock (tunnels, basements, location-off).
- We cannot detect every mis-snap (flyover vs service road).
- We do not promise "exact" distance in marketing or contracts. We promise "audited, road-matched, confidence-scored" distance.

---

## 6. Acceptance criteria

A change to this system is considered complete only if all of these hold:

1. A session that runs entirely online produces the same `final_km` regardless of how many GPS points the trigger processed.
2. A session that loses internet mid-trip produces the same `final_km` as the same trip with continuous internet.
3. A session that runs entirely offline produces a `final_km` that matches the device's `estimated_km` ± Roads-API-applied correction.
4. The expense dialog never shows a different number than `shift_sessions.final_km`.
5. `final_km` is never overwritten by the `update_session_rollup` trigger.
6. `snapped_polyline` is purged within 30 days of being written.
7. The admin timeline never renders Roads-API-derived geometry.
8. The Edge Function is idempotent on `session_id` — running it twice yields the same result.
9. `trip_finalization_jobs` retries up to 5 times with exponential backoff on transient errors.
10. The `confidence` field correctly transitions from `high`/`medium`/`low` based on the scoring algorithm.

---

## 7. Out-of-band considerations

- **Legal:** Confirm with Google reseller / counsel whether storing `final_km` (a number, not geometry) derived from Roads API has any restriction beyond the geometry-caching rule. Internal interpretation: numbers are first-party measurements computed from Google's response and may be retained as business records.
- **Migrate to OSRM** when employee count > 500 OR when Google API monthly cost exceeds engineering cost of OSRM maintenance.
- **Mock location policy:** if `is_mock` is detected during a session, set confidence to `low` and reason_code `MOCK_LOCATION_DETECTED`. Do NOT auto-reject the session — flag for admin review.
- **Activity Recognition fallback:** if Activity Recognition API is unavailable on a device, fall back to speed-based stationary detection (existing logic).
