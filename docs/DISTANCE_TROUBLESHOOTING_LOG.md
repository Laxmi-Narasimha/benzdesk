# Distance Tracking — Full Troubleshooting Log

**Honest, in-order history of every attempt to fix the GPS distance tracking
problem, what failed, why, and where we are right now.**

Last updated: 2026-05-17

---

## The original problem

A field rep starts a session on the BenzMobiTraq mobile app, drives somewhere,
ends the session. The km recorded should match what they actually drove. It
hasn't, in three different ways at different times:

- **Over-counting while stationary**: phone on a desk for 20 minutes recorded
  1.5 km of "movement". For 90 minutes it recorded 2.4 km. This is the bug
  the user is currently most upset about.
- **Under-counting while moving**: a real 12 km trip (verified on Google Maps)
  recorded as 9.7 km, then 357 km recorded as 260 km. Trust killer.
- **Three different numbers in three places**: live screen shows X, expense
  dialog files Y, admin panel shows Z. All for the same trip.

---

## What the system is supposed to do

```
GPS chip → Android FusedLocationProvider → Flutter background isolate
   → per-fix filter → SQLite local queue → server-side enrichment
   → final_km locked at session end
```

The filter has to reject GPS jitter (which always exists) while accepting
real movement. That's the whole game. Every bug below is some variant of
"the filter got that balance wrong."

---

## Attempt history

### Attempt 1 — Stage 1: lock `final_km` at session end
**Commit:** `b58338c`
**Idea:** create separate columns `estimated_km` (device output, locked) and
`final_km` (billed). Expense dialog reads only `final_km`. Admin reads only
`final_km`. No more "three different numbers."
**Result:** Correct in principle, but Android refused to install the new APK
because I never bumped `versionCode`. So the fix never reached the user's
phone. Every subsequent "fix" was layered on top of code that never shipped.
**Lesson:** Bump versionCode on every mobile commit. Verify with `aapt dump
badging` before claiming it's installed.

### Attempt 2 — Version bump enforcement (commit `53d37ab`)
**Idea:** Bump `pubspec.yaml` version on every mobile commit. Add visible
error display to Places Autocomplete so silent API key failures stop
masquerading as "no results."
**Result:** Bug surface visibility went up immediately. User saw real Google
API error: "API key with referer restrictions cannot be used with this API."
Root-caused: the Android-restricted key only works with Android SDK calls,
not REST. User created a new key with looser restrictions.
**Lesson:** Always surface the real error to the user. Silent failures are
the worst kind of bug.

### Attempt 3 — Filter tune #1 (commit `16bdeab`)
**Idea:** A 357 km trip was recording as 260 km. The per-fix filter was too
aggressive on slow city driving. Lowered:
- `jitterBaseM` 20 → 8 (minimum delta to count as movement)
- `jitterAccuracyMultiplier` 2.5 → 1.0
- `maxAccuracyThreshold` 50 → 100m
- Mode-aware thresholds halved
**Result:** Fixed the 357 km case. BROKE everything else. Phone on a desk
for 20 minutes started recording 1.5 km of phantom movement. The filter was
now too permissive — every 8-15m GPS noise spike counted as real motion.
**Lesson:** A single linear threshold can't distinguish "slow real movement"
from "stationary jitter." They have the same delta size.

### Attempt 4 — MAX-based reconciliation at session end (commit `9308034`)
**Idea:** At session end, take MAX of (authoritative recalc, running tally,
sum of accepted deltas, rollup raw haversine × 0.95). Never under-count.
**Result:** Fixed the 357 km case end-to-end. But the rollup × 0.95 term
made the stationary problem worse — even when the per-fix filter rejected
some jitter, the rollup includes ALL points and the × 0.95 was barely a
discount. A 90-minute stationary session went from 1.5 km → 2.4 km.
**Lesson:** Don't add a "fallback" that runs unconditionally. It always
seems safer than it is.

### Attempt 5 — Speed-based stationary gate (commit `4f4f161`)
**Idea:** Run a gate BEFORE the distance check. If GPS reports speed < 1.5 km/h
AND smoothed speed < 2 km/h, reject the fix's delta regardless of distance.
**Result:** Helped a little. Still failed for two real reasons:
1. **EMA-smoothed `calculatedSpeedKmh` is sticky.** After parking from 30 km/h
   the EMA decays slowly — takes ~10 fixes (50 seconds) to drop below 2. In
   that window, the gate doesn't fire and jitter accumulates.
2. **Android's reported speed is unreliable.** FusedLocationProvider can
   hallucinate 1-5 km/h "speed" when the phone is genuinely stationary,
   because it's computing velocity from coordinate jitter.
**Lesson:** Don't trust the GPS chip's speed field for stationary detection.
Don't trust EMA-smoothed speed because of decay lag.

### Attempt 6 — Cluster-based stationary gate (commit `602caa4`, current)
**Idea:** Maintain a ring buffer of the last 12 GPS coordinates. Compute their
centroid. If the maximum distance from any fix to the centroid is < 35m,
the rep hasn't actually moved — every coordinate is just GPS jitter
oscillating around one true position. Reject the fix's delta.
**Why this is architecturally better:** doesn't depend on GPS chip speed,
doesn't depend on EMA, doesn't depend on accuracy. Pure geometry.
**Result (user-reported):** Still failed. 90-minute stationary test still
recorded 2.4 km.
**Hypothesis for why this also failed:** The cluster gate is correct in
principle but isn't actually running for the user — either (a) the new APK
wasn't fully installed, (b) the bg-isolate code path is different from what
I think, or (c) a different code path adds distance that bypasses the gate.
**This is where we are right now.**

---

## Other things tried along the way

- **Migration 078** — Backfill historic sessions' `final_km` using the MAX
  of multiple signals. Helped admin display but didn't address root cause.
- **Migration 079** — Force-rebackfill any session where `final_km` was
  meaningfully lower than rollup × 0.95. Fixed the 357 km case retroactively.
- **Migration 080** — Re-enqueue all stops with `address=NULL` for
  reverse-geocoding. Fixed the "stops show coordinates" admin issue.
- **Migration 081** — Undo the over-eager 079 backfill for stationary sessions
  that 079 had inflated.
- **StopDetector double-emit fix** — `_persistStop` was firing both when the
  5-min threshold crossed AND when the rep left the radius. Now uses
  `persistedId` to UPDATE the existing row instead of INSERT-twice.
- **Map polyline clipping** — Admin map was opening at default center+zoom,
  cutting off 90% of long trips. Now calls `fitBounds()` over all rendered
  coordinates.
- **Routes API planned-route polyline** — Drawn as gray dashed line under the
  blue live trail on the in-app live map.
- **"Open in Google Maps" deep link** — Launches Google Maps directly in
  turn-by-turn nav mode to the picked destination. Tracking continues in
  the BG via the foreground service.
- **Places Autocomplete** — Customer search on session start.
- **AdjustedDistance component** — Shows admin-edited distance as
  "old + delta = corrected km" with edit reason on every distance surface.
- **OEM permissions popup** — One unified checklist with per-row deep-link
  Grant buttons and live status icons.

---

## What's wrong RIGHT NOW (open issues)

### Issue A — 90-min stationary still records 2.4 km
Even after the cluster gate. Possible causes I haven't proved/disproved yet:
- **New APK genuinely installed?** AAPT confirms versionCode=8 in the file,
  but Android version pinning is sometimes confused by signing-key
  mismatches. The user should verify in Settings → Apps → BenzMobiTraq.
- **Cluster gate fires but a DIFFERENT code path adds distance?** The
  running total in the BG isolate (`totalDistance`) is what gets persisted.
  If anything outside `_onPositionReceived` writes to it, our gate is
  bypassed.
- **Cluster gate has a bug?** Possible. Edge case I haven't tested: what
  if the buffer is empty/has 1 entry and we add a fix far from a previous
  cluster? The `_recentFixes` array grows quickly enough that the cluster
  test is meaningless for the first 6 fixes.

### Issue B — Permission buttons in the setup dialog don't open
The user reports tapping "Activity Recognition" / "Battery" / "Notifications"
does nothing. Likely causes:
- `permission_handler` package missing on some Android versions
- Intent doesn't resolve on certain OEM skins (Vivo, Oppo)
- `openAppSettings()` failing silently with no fallback

### Issue C — App killed from recents → can't reacquire GPS
This is the OEM auto-kill problem. When the user swipes the app from
recents:
1. The foreground service should keep running (Android contract).
2. On most stock Android, it does.
3. On Xiaomi MIUI / Vivo Funtouch / Oppo ColorOS / Samsung OneUI, the OEM
   kills the foreground service anyway unless the rep has gone through
   the OEM-specific autostart flow.

We have the `OemAutostartService` but it's brittle — the autostart-settings
intents change between OS versions, and the rep doesn't always complete the
manual flow.

### Issue D — GPS doesn't stream when paused
Currently `isPaused = true` causes the BG isolate to skip distance
accumulation but ALSO stops the position stream. So auto-resume (detecting
movement after a pause) doesn't get fresh position data. This is a real
bug — paused tracking should keep position updates flowing.

---

## What I'd do if I were honest with myself

I've been writing fix after fix, each addressing a symptom of the previous
fix. The right thing to do — which I haven't done — is:

1. **Get a debug build on the user's actual phone.** A real flutter logcat
   stream of `_onPositionReceived` for 5 minutes of stationary use. We'd
   see exactly which fix the cluster gate processes and why it doesn't reject.
   I've been guessing. The user's phone is the only authoritative source.

2. **Replace the per-fix filter with a fundamentally different architecture**:
   keep ALL raw fixes, run distance calculation only at session end using
   a robust post-hoc algorithm (Kalman + map matching). Accept that "live
   screen" and "final number" will differ — show the live as "Estimated"
   and the final as "Verified."

3. **Honest UX:** stop showing live distance during a session. Show "Tracking…"
   and the actual number only at end. The current approach of trying to
   compute correct live distance per-fix has failed three times — maybe
   the right answer is to not try.

I'm telling you this because patching attempt 7 likely won't be the last
attempt. The architecture is fragile.

---

## What I'll attempt next (attempt 7)

For the current commit, addressing the three bugs the user just reported:

1. **Make permission buttons actually open the right OS screen** — add
   explicit Android intent verification, fall back to `openAppSettings()`,
   surface errors visibly.

2. **Keep GPS streaming when paused** — only distance accumulation pauses,
   not the location stream itself.

3. **Foreground service hardening for "killed from recents" survival** —
   confirm `START_STICKY`, add a periodic WorkManager re-trigger as
   belt-and-suspenders, log explicit lifecycle events.

4. **Stationary cluster gate**: keep but lower the threshold further and
   add explicit logging that the user can show me in logcat to prove/disprove
   whether it's firing.

This is attempt 7. I'm not promising it solves the 2.4 km problem completely.
If it doesn't, the next step is real logcat data, not another guess.
