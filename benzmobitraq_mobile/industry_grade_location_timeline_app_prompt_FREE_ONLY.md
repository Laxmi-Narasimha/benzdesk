# Industry‑Grade Build Prompt (FREE‑ONLY, No Choices Left to the AI)
**Project:** Field Force Attendance + Distance + Timeline Map + “Stuck” Alerts + Expenses  
**Platform:** **Android-only** (APK sideload).  
**Users:** 20–25 internal users.  
**Retention:** keep **35 days** of location history, then delete automatically.  
**Budget requirement:** **Use only free/open-source libraries and free-tier services. Do NOT use paid SDKs/plugins.**  
**Reliability requirement:** Must be production-grade within the real constraints of Android (cannot defeat OS force-stop). Must include robust error handling, offline-first, retries, and clear user guidance for battery optimization.

---

## 0) Your role
You are a **senior Android/Flutter engineer + backend engineer**. Build this end-to-end with a tight, testable architecture.  
Do not leave decisions open. Follow this exact stack and plan.

---

## 1) Fixed tech stack (MANDATORY)

### Mobile (Flutter, Android)
- Flutter (stable channel)
- **Maps:** `mapbox_maps_flutter` (Mapbox map rendering; expected free at this scale)
- **Background execution:** `flutter_background_service` (Android foreground service mode)  
- **Foreground notification:** use `flutter_local_notifications` (persistent “Tracking ON” notification)
- **Location:** `geolocator` (high-level location; request permission + stream positions)
- **Local persistence (offline queue):** `drift` (SQLite)
- **Networking:** `dio` (timeouts + interceptors + retries)
- **State management:** `flutter_riverpod`

### Backend (Supabase)
- Supabase Auth + Postgres + Storage (receipts)
- Supabase Edge Functions (rollups, stuck detection, retention cleanup)
- Scheduled job: Supabase Cron/pg_cron calling Edge Function daily/5-min

### Notifications (Admin alert)
- **Firebase Cloud Messaging (FCM)** using `firebase_messaging` on Android
- Use Supabase Edge Function to call FCM HTTP API (or a lightweight server key integration)

**Important:** No paid tracking SDKs (HyperTrack/Radar/Transistorsoft/etc.). No Google Maps billing requirements.

---

## 2) Product requirements (MUST-HAVE)

### Employee app
1) Login
2) Tap **Present / Start session**
3) App starts background tracking immediately (foreground service + persistent notification)
4) App computes:
   - **distance this session**
   - **distance today**
5) Tap **Work done / End session** → stop tracking, close session
6) Expenses:
   - Create claim (date, notes)
   - Add line items (category, amount, merchant, spent time)
   - Attach receipt photo(s)
   - Submit claim

### Admin app (can be role-based screens in same app)
1) Employee list + status:
   - in session? last location time? today km?
2) **Timeline by date**:
   - Select employee + date
   - Route polyline on map
   - Start/end markers
   - Stop list with timestamps (start, end, duration)
3) Alerts:
   - Admin gets alert if employee is **stuck** for configured time during active session
   - Admin gets alert if **no signal** (no location points) for X minutes during active session
   - Alerts appear in admin feed and also as push notifications via FCM

---

## 3) Non-negotiable Android realities (must document & handle)
You MUST explicitly handle and document these:
- If the user **force-stops** the app from Settings, Android will stop background work until user opens the app again. You cannot bypass this. Show “Tracking stopped due to force stop” when detected.
- Many OEMs (Xiaomi/Realme/Samsung) may kill background services unless users whitelist the app. You must show an in-app “Battery Optimization Setup” screen with steps and deep links where possible.
- Background location requires explicit permission flows and a running foreground service for continuous tracking.

---

## 4) Architecture (MANDATORY MODULES)

### 4.1 App layers
- **UI layer** (screens)
- **Domain layer** (use cases)
- **Data layer** (Supabase + local DB + services)

### 4.2 Required modules/classes
1) `AuthRepository`
2) `SessionRepository`
3) `TrackingService` (wraps background service + location stream)
4) `LocationQueueRepository` (Drift)
5) `SyncWorker` (batch upload + retry)
6) `DistanceEngine` (filter + haversine)
7) `TimelineEngine` (stop detection + segments)
8) `AlertsEngine` (client-side health + server alerts feed)
9) `ExpensesRepository` (claims/items/receipts)

All must be unit-testable (dependency injection via Riverpod providers).

---

## 5) Supabase schema (MANDATORY)
Create SQL migrations for these (UUID PKs everywhere).

### 5.1 `profiles`
- `id uuid pk references auth.users`
- `full_name text`
- `role text check in ('employee','admin')`
- `is_active boolean default true`
- `created_at timestamptz default now()`

### 5.2 `sessions`
- `id uuid pk`
- `employee_id uuid references profiles(id)`
- `start_time timestamptz not null`
- `end_time timestamptz null`
- `status text check in ('active','closed')`
- `created_at timestamptz default now()`
Enforce: one active session per employee via partial unique index.

### 5.3 `location_points`
- `id uuid pk`
- `employee_id uuid not null`
- `session_id uuid not null`
- `recorded_at timestamptz not null` (device timestamp converted to UTC)
- `server_received_at timestamptz default now()`
- `lat double precision not null`
- `lng double precision not null`
- `accuracy_m real null`
- `speed_mps real null`
- `heading_deg real null`
- `provider text null` (gps/network/fused)
- `hash text unique not null` (idempotency)
Indexes:
- `(session_id, recorded_at)`
- `(employee_id, recorded_at)`

### 5.4 Rollups
`session_rollups` (PK session_id): distance_km, last_point_time, last_lat, last_lng, updated_at  
`daily_rollups` (PK employee_id, day): distance_km, updated_at  
**Day** must be computed using Asia/Kolkata local date.

### 5.5 Timeline
`timeline_events`
- `id uuid pk`
- `employee_id uuid`
- `session_id uuid`
- `day date`
- `type text check in ('stop','move')`
- `start_time timestamptz`
- `end_time timestamptz`
- `duration_sec int`
- `distance_km real null`
- `center_lat/center_lng` for stops
- `start_lat/start_lng/end_lat/end_lng` for segments

### 5.6 Alerts
`alerts`
- `id uuid pk`
- `employee_id uuid`
- `session_id uuid null`
- `type text check in ('stuck','no_signal','mock_location','clock_drift','other')`
- `severity text check in ('info','warn','critical')`
- `message text`
- `start_time timestamptz`
- `end_time timestamptz null`
- `is_open boolean default true`
- `created_at timestamptz default now()`

### 5.7 Expenses
`expense_claims`, `expense_items`, `expense_receipts` (as in earlier prompt: draft/submitted/approved/rejected, receipts in storage)

---

## 6) Security (MANDATORY RLS)
Enable RLS on all tables.
- Employees: read/write only their own rows
- Admin: read all; can update expense approvals; can read alerts for all
- Validate `session_id` belongs to `employee_id` server-side (Edge Functions)
- Never trust client totals

---

## 7) Location tracking implementation (FREE‑ONLY, RELIABLE PATTERN)

### 7.1 Permissions & settings (Android)
Must request and handle:
- Location permission (fine)
- Background location permission (Android 10+)
- Foreground service permission (Android 9+ requirements vary by SDK)
- Show user flows when permissions are denied or changed

### 7.2 Foreground service (required)
When session is active:
- Start `flutter_background_service` in **foreground mode**
- Show persistent notification:
  - “Tracking ON — Session active”
  - last sync time
  - “Tap to open app”

If session ends, stop service and remove notification.

### 7.3 Update policy (bikes + cars)
Implement adaptive sampling (simple, deterministic):

**Moving mode**
- Request high enough accuracy for road travel but not “always highest”
- Use distance-based throttling:
  - if speed_mps <= 8 (bike-like): accept new point when moved ≥ 30m
  - else (car-like): accept new point when moved ≥ 60m
- Also enforce a minimum time gate: do not accept more than 1 point per 5 seconds.

**Stationary mode**
- If for last 3 accepted points the displacement from anchor < 30m and speed ~0:
  - switch to “stationary checks” every 2 minutes (one-shot getCurrentPosition)
- When movement resumes (displacement ≥ 30m), go back to moving mode.

### 7.4 Idempotency + dedupe (mandatory)
Client must compute `hash` per point:
- `hash = sha256(employeeId + sessionId + recordedAtRoundedToSecond + latRounded5 + lngRounded5)`
Server enforces unique hash; client retries safely.

### 7.5 Offline-first queue (mandatory)
- Every accepted point is inserted into Drift queue immediately
- SyncWorker uploads in batches of 25–100 points
- On success: delete uploaded rows
- On failure: keep and retry with exponential backoff
- Never lose points due to app backgrounding or network loss

### 7.6 Clock drift handling (mandatory)
Compare `recorded_at` to server time:
- If device time is >10 minutes ahead/behind server:
  - still store point but flag it and create `clock_drift` alert
  - for timeline/day rollups, use `server_received_at` as fallback ordering if drift extreme

---

## 8) Distance calculation (MANDATORY quality rules)
Implement Haversine distance between consecutive **accepted** points.
Apply filters:
- Reject points where `accuracy_m` is null? (allow, but treat as “unknown”)
- Reject points where `accuracy_m > 50` (tunable constant)
- Ignore jitter: if delta_distance_m < max(10, 2*accuracy_m) → treat as 0
- Teleport suppression:
  - if implied speed > 160 km/h and not confirmed by next point → ignore segment and log an alert

Rollups:
- Update `session_rollups` and `daily_rollups` server-side via Edge Function or trigger logic
- Client displays totals from server rollups (source of truth)

---

## 9) Timeline + timestamps (MANDATORY “Google‑style”)
### 9.1 Route polyline
For (employee, day):
- Fetch points sorted by `recorded_at`
- Downsample for rendering (keep one every 10–20 seconds OR 30–50m)
- Render polyline + start/end markers in Mapbox

### 9.2 Stop detection (robust default)
Constants:
- `STOP_RADIUS_M = 120`
- `STOP_MIN_DURATION_SEC = 600` (10 min)

Algorithm:
- Iterate points in time order
- Build cluster anchored at first point
- If next point within radius → extend cluster
- If cluster duration >= min duration → emit STOP event (center = average)
- When radius breaks → close stop and create MOVE segment (distance computed from filtered points)

Store results into `timeline_events` so admin timeline loads fast.

### 9.3 Timestamps displayed
Timeline UI must show:
- Stop start time (local IST)
- Stop end time (local IST)
- Duration (minutes)
- Move segments (optional): start, end, distance

---

## 10) Alerts (MANDATORY)
### 10.1 Stuck alert (server-side truth)
During active session:
- If employee stays within `STUCK_RADIUS_M = 150` for `STUCK_MIN = 30` minutes → open stuck alert
- If movement resumes (break radius for sustained period) → close stuck alert

### 10.2 No signal alert
If no location points received for 20 minutes during active session:
- open `no_signal` alert
- close when points resume

### 10.3 Delivery method
- Create alerts in `alerts` table
- Admin app subscribes/polls alerts feed
- Send push notification via FCM for new alerts

---

## 11) Data retention (MANDATORY)
- Daily cron (Edge Function or DB cron):
  - delete `location_points` older than 35 days
  - delete `timeline_events` older than 35 days
  - optionally keep `alerts` longer (or also purge older than 90 days)

---

## 12) Full error handling (MANDATORY)
### 12.1 In-app states (must implement)
- Tracking OFF (permission missing)
- Tracking LIMITED (background not allowed)
- Offline (queueing)
- Battery optimization risk (show instructions)
- Service running (foreground notification)

### 12.2 Common errors and required handling
- Permission denied/revoked mid-session → stop tracking safely + alert + UI banner
- GPS disabled → show banner + still keep service running; generate no-signal if persists
- Network failures → keep queue, retry
- Auth refresh failure → prompt re-login; keep queue
- Duplicate points → safe due to hash unique + retry
- Multiple sessions → block start; show error; enforce server constraint
- App updated while session active → service restarts; session continues; ensure continuity

---

## 13) Testing plan (MANDATORY; you must provide this in output)

### 13.1 Unit tests
- Haversine correctness
- Jitter filtering
- Teleport suppression
- Stop detection with synthetic data
- Timezone conversion IST day boundaries

### 13.2 Integration tests
- Supabase insert/query for points
- Batch upload idempotency (replay same batch; no duplicates)
- Retention cleanup removes old rows

### 13.3 Manual device tests (must include checklist)
Test on Samsung + Xiaomi/Realme + one Pixel:
1) Start session → lock screen → ride 15 min → verify route
2) Background 1 hour → still logging
3) Toggle airplane mode 30 min → queue then upload
4) Disable GPS mid-session → no-signal behavior
5) Turn on battery saver → verify warnings + behavior
6) Force-close app → document limitation; ensure user sees tracking stopped after reopening
7) Reboot device during active session → service restarts; session continuity rules
8) Change device time → clock drift alert triggered

Acceptance criteria:
- No silent data loss across offline/kill/background (except force-stop limitation)
- Daily route loads under 3 seconds for a day’s data
- Distance within ±5–10% for typical sampling
- Timeline stops appear correctly for known test routes

---

## 14) Deliverables (MANDATORY)
1) Flutter app source with module separation and providers
2) Supabase SQL migrations + RLS policies
3) Edge Functions:
   - rollups update
   - timeline events generation
   - stuck/no-signal alerts
   - retention cleanup
4) Setup documentation:
   - Mapbox token config
   - Supabase keys and environment setup
   - Android permissions + foreground service explanation
   - OEM battery optimization instructions
5) “Known limitations” section (must include force-stop limitation)

---

## 15) Milestone plan (follow exactly)
1) Auth + roles + session start/stop
2) Foreground service + location capture + queue
3) Batch sync + server rollups + show km
4) Timeline map by date (polyline + markers)
5) Stop detection + timeline list with timestamps
6) Stuck/no-signal alerts + admin feed + FCM push
7) Expenses + receipts + approvals
8) Retention cleanup + hardening + full test pass

---

## 16) Output format required from you
Return in your response:
- Architecture diagram (ASCII)
- Folder/repo structure tree
- SQL migration scripts + RLS policy statements
- Edge Function pseudo/code outlines
- Pseudocode for:
  - point acceptance + filtering
  - stop detection
  - stuck detection
- Full test plan + checklists + acceptance criteria
- Known limitations (explicit)

**Do not ask follow-up questions. Use the defaults stated above.**
