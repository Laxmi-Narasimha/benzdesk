# Field-Force Attendance + Distance + “Stuck” Alerts App — Conversation Notes (Full Transcript)

_Date compiled:_ 2026-01-28 (Asia/Kolkata)

## Key points (complete, consolidated)

### Business workflow
- Employee taps **Present / Start work** in the morning to begin a **work session**.
- While the session is active, the app **tracks location in the background** and **calculates moving kilometers**.
- Employee taps **Work done / End work** to stop tracking and close the session.
- Admin receives a **notification/alert** when an employee is effectively **stationary (“stuck”)** for a configured duration.

### Core system components required
- **Mobile app** that can run **background location tracking** reliably on Android/iOS.
- **Backend** to store sessions and location points, compute distance, and evaluate “stuck” rules.
- **Notification delivery** for admin alerts (push notifications, and optionally SMS/email).

### Battery-efficient tracking approach (recommended pattern)
- Use **adaptive / motion-aware tracking**:
  - **Moving mode:** collect updates primarily by *distance* (not constant time), using balanced accuracy.
  - **Stationary mode:** reduce GPS usage drastically (low-power checks / geofence-like behavior) and only ramp up when movement resumes.
- Avoid inflated distance due to GPS jitter by filtering:
  - discard low-quality points (poor accuracy),
  - ignore very small deltas likely caused by drift,
  - optionally ignore unrealistic “teleport” jumps.

### PWA vs native app
- A **pure PWA** is not suitable for “Present → track all day” requirements because background tracking is not reliably possible via standard web app mechanisms.
- If you want a web-like UI, use a **native wrapper** (Capacitor/Cordova/WebView) with native background location.
- For best reliability, use **native** or **Flutter/React Native**.

### “Do we need 3rd-party tracking APIs?”
- You can build without a paid tracking vendor by using platform location APIs, but you still need:
  - a backend and
  - a push notification rail (e.g., APNs/FCM or a managed abstraction).
- Dedicated tracking SDK providers can reduce risk/edge cases if you want faster delivery with fewer OS quirks.

### Provider categories discussed
- **Location tracking SDKs** (to embed into the app): HyperTrack, Radar, Roam.ai, Transistorsoft Background Geolocation.
- **Telematics hardware (optional)** if you prefer device-independent tracking for vehicles: Teltonika trackers + platforms like Traccar/flespi.
- **Push notifications**: FCM/APNs (often via Expo for simplification).

### Supabase for a small user base (20–25 users)
- Supabase is suitable to keep engineering and operational complexity low:
  - Postgres database, Auth, Storage (receipt images), Edge Functions, and scheduling/cron patterns.
- Still need push notification delivery (FCM/APNs or an abstraction like Expo push).

### Adding expense tracking
- Add tables for expense claims/items/receipts.
- Store receipt images in backend storage (e.g., Supabase Storage) and implement an approval workflow (submitted/approved/rejected).

---

## Full transcript (no omissions)

### 1) User
> if i want to create something where an employee, marks his status as present in th moring, and then the app starts calculating his moving kilometers until he again taps another button like work done or something , and on top of it the admin should get notification if a particular employee is struct or stayed at a single place for a specific selectedtime, this is a brief of the app, let me know how can i build this, and let me know how is the most battery efficient way to do this , and if there are any api providers whom we can contact and integrate in the app ket me know

### 1) Assistant
Below is a practical, buildable blueprint for your app: (1) employee starts a “work session” (Present), (2) app tracks movement and computes kilometers until “Work done,” and (3) admin gets an alert if the employee remains effectively stationary for a configured duration.

---

## 1) What you’re building (functional breakdown)

**Employee app**
- Login (employee identity + device binding, optional).
- Button: **Present / Start work**
  - Starts a “shift session” and begins background location tracking.
- Live stats: **distance today / distance this session**, last sync time, GPS status.
- Button: **Work done / End work**
  - Stops tracking and closes the session.

**Admin app / dashboard**
- View employees: online/offline, last location time, today’s km, current session km.
- Map view (optional) + timeline playback (optional).
- Alerts rule: “Stationary for > X minutes within radius R meters” → push/SMS/email.

**Backend**
- Session management + location ingest + distance computation.
- Stationary detection + notification dispatch.
- Audit trail + retention policies.

---

## 2) High-level architecture (recommended)

### A. Mobile (Android + iOS)
- Uses OS-native background location correctly (this is the hardest part).
- Sends location “pings” to backend using batching (not every second).
- Uses motion/activity signals to reduce GPS usage whenever possible.

### B. Backend API
- REST endpoints:
  - `POST /sessions/start`
  - `POST /sessions/stop`
  - `POST /locations/batch` (bulk upload)
- Storage:
  - Postgres + PostGIS (recommended) or MongoDB with geo indexes.
- Processing:
  - A worker/job queue for distance + “stuck” rules + alerts.

### C. Notifications
- Push to admin mobile: **Firebase Cloud Messaging (FCM)** (works with Android/iOS apps). citeturn1search3  
- Optionally SMS/WhatsApp/email via providers (Twilio, etc.) if you want “cannot miss” alerts.

---

## 3) Battery-efficient tracking: what actually works

Continuous high-accuracy GPS in the background will drain battery quickly and may be throttled by the OS. Android explicitly recommends optimizing requests and using fused/geofencing patterns. citeturn0search0turn0search16turn1search4  
Apple also advises minimizing accuracy and duration, and avoiding unnecessary location usage. citeturn0search1

### Recommended tracking strategy (adaptive)
Use **two modes** and switch based on motion:

**Mode 1: Moving**
- Request location with *balanced power* and a **minimum displacement** (distance filter).
- Example policy:
  - Update every 15–30 seconds *or* every 25–50 meters (whichever occurs later).
  - If speed is high (vehicle), allow slightly more frequent updates.

**Mode 2: Stationary**
- Stop frequent GPS.
- Use a low-power approach:
  - “Significant change” updates / coarse updates, or
  - A “stationary geofence” around the last known location.
- Only wake up to high-power GPS when the user starts moving again.

This “motion-aware toggling” is a core battery-saving pattern; some tracking SDKs explicitly implement this philosophy using device motion sensors to decide when to turn location tracking on/off. citeturn1search14

### Android specifics (best practice)
- Use **Fused Location Provider** (Google Play services) to combine GPS/Wi-Fi/cell signals efficiently. citeturn0search4turn0search16  
- Use batching/deferred updates where possible to reduce wakeups and network chatter (supported patterns are discussed in Android’s battery guidance). citeturn0search0turn0search16  
- For reliable background tracking, you’ll typically need a **foreground service** while a session is active (with a persistent notification), otherwise the OS may stop delivery.

### iOS specifics (best practice)
- Avoid “always-on high accuracy.” Prefer reduced accuracy where acceptable and only escalate when needed. citeturn0search1  
- Consider “significant-change” style tracking for stationary periods and only use continuous updates when the user is moving.

### Network/battery optimization
- Upload locations in **batches** (e.g., every 1–5 minutes or when 10–30 points collected).
- Compress payloads (gzip) and avoid chatty per-point HTTP.
- Cache offline and upload later (important for field staff with weak coverage).

---

## 4) How to calculate “moving kilometers” correctly

**Common pitfall:** GPS jitter while stationary can falsely add distance.

Use rules like:
- Ignore points with poor accuracy (e.g., accuracy > 50m).
- Ignore tiny deltas:
  - Only add distance if `deltaDistance > max(10m, 2 × accuracy)` (practical anti-jitter rule).
- Optionally smooth using a simple filter (Kalman / rolling median).

Distance calculation:
- Haversine distance between accepted consecutive points.
- If you need “road distance” (more accurate for vehicles), you can add optional map-matching (Google/Mapbox/HERE), but it increases cost/latency.

---

## 5) “Stuck at one place” detection (robust approach)

Define:
- **Radius R** (e.g., 75–150m depending on GPS conditions)
- **Time T** (admin-configurable)

Logic (server-side or device-side):
- Track the last “movement anchor” point.
- If all points remain within R of the anchor for T minutes, trigger alert.
- To prevent false alerts:
  - Require acceptable accuracy (or expand R when accuracy is worse).
  - Optionally require “moving expected” hours or an assigned task.

**Where to compute it**
- **Server-side** (simpler, centralized, auditable): Needs regular pings.
- **Device-side** (can be more battery/data efficient): Device can decide “I’m stationary for T” and only send an “alert event.” Many teams still do server-side as the source of truth.

---

## 6) Build vs buy: fastest path with fewer edge cases

Background location tracking across Android/iOS versions is the hardest and most time-consuming part to get right. If speed-to-market and battery are priorities, strongly consider integrating a specialized location SDK and focusing your team on your business logic + admin workflows.

### API/SDK providers to evaluate (location + geofencing + trips)

**Purpose-built workforce / live tracking**
- **HyperTrack**: Emphasizes adaptive tracking density and reduced battery usage; claims the SDK does not emit updates when stationary and modulates updates based on movement. citeturn0search2turn0search14

**Geofencing + tracking platform**
- **Radar**: Cross-platform SDK for geofencing, tracking, trip tracking, etc. citeturn0search11turn0search3turn0search7

**Developer-friendly location SDK options**
- **Roam.ai**: SDKs for Android/iOS/React Native (positioned as high accuracy + battery efficiency). citeturn1search0turn1search12turn1search8  
- **Transistorsoft Background Geolocation** (React Native/Cordova/Capacitor and others): Implements motion-detection-led tracking to reduce battery drain. citeturn1search14turn1search25

**Maps + geofencing infrastructure**
- **Mapbox Geofencing**: Client-side geofencing with entry/exit/dwell events. citeturn1search24turn1search17turn1search1  
- **HERE Geofencing API**: Server-side geofencing checks and asset tracking (license-based). citeturn1search2

**Notifications**
- **Firebase Cloud Messaging (FCM)** for push notifications (admin alerts). citeturn1search3

---

## 7) Suggested implementation plan (practical MVP)

1. **MVP tracking session**
   - Present → start session; Work done → stop.
   - Batch upload locations + show “km today.”

2. **Battery-safe adaptive tracking**
   - Moving vs stationary modes.
   - Accuracy filtering + anti-jitter distance rules.

3. **Admin dashboard + alerts**
   - Employee list, last seen, km today.
   - Stationary rule engine + push notifications to admin.

4. **Hardening**
   - Offline queues, retries, tamper resistance (mock location detection), audit logs, retention policies.

---

## 8) Compliance and employee trust (do not skip)
Because this is employee location monitoring:
- Track **only during working sessions** (Present → Work done).
- Show clear indicators that tracking is ON.
- Define data retention and access controls.
- Document consent and policy.

This also reduces legal and HR risk, and improves user adoption.

---

If you tell me your preferred stack (Flutter vs React Native vs native) and whether employees are typically **walking, on bikes, or in vehicles**, I can recommend concrete tracking parameters (intervals, distance filters, stationary radius/time) that balance accuracy, battery, and cost.

---

### 2) User
> they typically go on bikes and cars only , and on top of it letme know if i should build an entire application for this or shall i just put it as a pwa and it starts working , accorindgly, and do not worry about hr and stuff, as our employees signed their contracts already , and see if there is any api or somethig for this directly like telenity or something, which we can inegrate into our code directly and get it done , see for the best possible way and let me know

### 2) Assistant
Given your use case (employee taps **Present** in the morning, you track **all day in the background** while they ride bikes/cars, and you alert if they are “stuck”), a **pure PWA is not the right vehicle**. You can still keep the UI web-first, but you will need **native background location**.

## 1) PWA vs full mobile app (what will actually work)

### Why a pure PWA will fail for your requirement
- Continuous location tracking requires background execution.
- On the web, **service workers do not have access to the Geolocation API**, so you cannot reliably track location while the PWA is closed. citeturn2search4turn1search12turn2search20  
- iOS Safari/PWA geolocation also has real-world reliability quirks reported by developers, even before you reach background-tracking requirements. citeturn2search2turn1search17

### Practical options (ranked)
1) **Native app (Android + iOS)** or **Flutter/React Native**  
   Best for reliability, background tracking, and battery control.

2) **“Web UI + thin native wrapper” (Capacitor/Cordova/React Native WebView)**
   - Your screens can still be HTML/React.
   - Background tracking is implemented natively via a plugin/SDK.
   - This is often the best compromise for speed-to-market.

3) **Pure PWA**
   - Only acceptable if you are okay with “tracking works only while the app is open in the foreground.”
   - That does not match your “Present → track all day” requirement.

## 2) Battery-efficient tracking for bikes + cars (recommended operating model)

For bikes/cars, you want **motion-aware tracking** (use sensors to decide when to turn GPS on/off), plus **distance-based sampling** to avoid per-second pings.

### Recommended policy (works well in the field)
**When moving**
- Track by **distanceFilter** instead of tight time intervals.
- Suggested starting point:
  - Bikes: distanceFilter **25–50m**
  - Cars: distanceFilter **50–100m**
- Use “balanced” location mode most of the time; temporarily bump accuracy when speed changes sharply or you detect route ambiguity (optional).

**When stationary**
- Stop frequent GPS entirely.
- Switch to a “stationary mode”:
  - only occasional low-power checks, or
  - a “stationary geofence” around the last known location.

This is the same principle used by dedicated background tracking SDKs: detect motion via accelerometer/gyroscope and power down GPS when stopped. citeturn3search0turn3search4turn0search3

### Distance calculation (avoid GPS jitter inflating km)
Implement these filters before accumulating distance:
- Drop points with poor accuracy (example: ignore if accuracy > 50m).
- Ignore tiny moves that are likely jitter (e.g., require deltaDistance > max(10m, 2×accuracy)).
- For cars, optionally ignore “teleport” jumps (e.g., > 500m in 5 seconds) unless confirmed by subsequent points.

## 3) “Stuck” detection (admin alert) that won’t false-trigger at signals

For bikes/cars, “stuck” should mean “not meaningfully changing location,” not “stopped at a traffic light.”

A solid default rule:
- If employee remains within **R = 100–200m** for **T = admin-selected minutes**, trigger alert.
- Add a guardrail: only consider it “stuck” if the app has observed the state consistently (e.g., last 3–5 samples) with reasonable accuracy.

You can compute this:
- **Server-side** (simpler auditing; requires regular uploads), or
- **Device-side** (most battery/data efficient; send an “I’m stuck” event).

## 4) “Is there an API like Telenity that does this directly?”

### First: “Telenity” is not the right category
Telenity is primarily a telecom/digital services provider for communications service providers, not a field-force location tracking SDK you embed for background GPS + stuck detection. citeturn0search1turn0search5

### What you actually want: dedicated location-tracking SDK providers
These are built exactly for “track in background + minimize battery + provide events.”

**A) Fastest path (SDK + backend + dashboards often included)**
- **HyperTrack**: explicitly describes motion-adaptive tracking (no emits when stationary; intelligent updates when moving). citeturn0search3turn0search11  
- **Radar**: full-stack location infrastructure (geofencing, trip tracking, fraud detection, etc.) via SDKs and APIs. citeturn1search2turn1search10  
- **Roam.ai**: SDKs positioned as battery-efficient continuous tracking; docs are available. citeturn1search7turn1search27  

**B) “Bring-your-own backend” but proven mobile tracking engine**
- **Transistorsoft Background Geolocation** (React Native/Cordova/Capacitor and others): implements motion-detection-led tracking and powers down location services when stationary. citeturn1search14turn1search25  
This is often ideal if you want full control of data + rules, while avoiding the painful OS edge cases.

### Alternative category: vehicle hardware telematics (if you control vehicles)
If you want tracking that does not depend on employee phone settings/battery:
- **Teltonika** (GPS tracker hardware ecosystem) citeturn0search6turn0search14  
- Use a platform like:
  - **Traccar** (open-source GPS tracking server with REST API; supports many device protocols) citeturn3search1turn3search5  
  - **flespi** (telematics hub with REST/MQTT APIs; commonly used to normalize tracker data) citeturn3search2turn3search6turn2search26  
This is excellent for cars, but for bikes it depends on whether you can mount/charge a tracker reliably.

## 5) Best possible way (recommendation)

If your goal is **minimum engineering risk + maximum battery efficiency + fast delivery**:

### Recommended approach
1) Build a **mobile app (Flutter or React Native)** OR **Capacitor wrapper for your web UI**.
2) Use a **battle-tested background tracking engine**:
   - If you want a managed solution: **HyperTrack** or **Radar**. citeturn0search3turn1search2  
   - If you want to own everything and keep vendor dependence low: **Transistorsoft** plugin + your backend. citeturn1search14turn1search25  
3) Backend does:
   - session start/stop
   - distance compute
   - stuck detection + notification (push)

This will deliver the “Present → track → Work done + stuck alerts” flow with realistic battery performance.

If you tell me your preferred build stack (React Native vs Flutter vs “web UI + wrapper”), I can give you:
- concrete parameter presets (distanceFilter, desiredAccuracy, stationary radius/time),
- a minimal API contract for your backend,
- and the simplest alerting pipeline for admins.

---

### 3) User
> if i create an app, will it work right away without any other apis? is this possible and tell me the best tech stack for this

### 3) Assistant
Yes—an app can do this without paying for any “tracking API provider,” but it will not be “just the app” in the literal sense. You will still need:

1) **OS location services** on the device (Android/iOS), and  
2) **A backend** to store sessions/locations and run “stuck” rules, and  
3) **A push notification path** to alert admins (or an SMS/email provider if you prefer).

### What you can avoid
- You can avoid paid tracking SDKs (HyperTrack/Radar/etc.) if you are willing to implement and maintain background tracking logic yourself.
- You can avoid paid map services if you do not need a map UI (distance + last known location is enough).

---

## Will it work “right away” with no external APIs?

### Location tracking: yes (using built-in platform APIs)
- **Android:** use the **Fused Location Provider** (Google Play services) for battery-efficient location. citeturn0search1turn0search10  
- **iOS:** use Core Location (native).

This is feasible with no third-party tracking vendor.

### Admin alerts: you still need push infrastructure
- On iOS, remote push requires **APNs registration**. citeturn0search0  
- A common approach is **Firebase Cloud Messaging (FCM)**, which supports Android/iOS and is widely used. citeturn0search2  

You are not “buying a tracking API,” but you are using the standard push notification rails.

### Backend: you still need a server somewhere
Even if you compute distance on-device, you need a backend to:
- persist sessions (Present → Work done),
- store last known location / daily kilometers,
- run “stuck” logic centrally (or at least receive “stuck events” from devices),
- deliver admin notifications.

You can minimize backend engineering by using Firebase managed services, but something server-side still exists.

---

## Best tech stack (practical recommendations)

### Option A — Best balance of speed, reliability, and cost (recommended for most teams)
**Mobile:** Flutter (single codebase)  
**Background tracking:** a proven background geolocation component (to avoid OS edge cases)  
**Backend:** Firebase + small serverless functions

Concrete stack:
- Flutter app (employee + optionally admin app)
- Firebase Authentication (employee identity)
- Firestore (sessions + latest state) or Postgres later
- Cloud Functions / Cloud Run for:
  - distance aggregation,
  - “stuck” rule evaluation,
  - alert dispatch
- FCM for push notifications citeturn0search2

Why this is best: fast build, fewer moving parts, and you still get robust push + auth + storage.

### Option B — Maximum control, maximum reliability (but more engineering)
**Mobile:** Native Android (Kotlin) + Native iOS (Swift)  
**Location:**
- Android Fused Location Provider citeturn0search1turn0search10  
- iOS Core Location
**Backend:** Node.js (NestJS) or Python (FastAPI)  
**Database:** Postgres + PostGIS  
**Queue:** Redis + BullMQ (Node) or Redis + Celery (Python)  
**Push:** APNs (iOS) + FCM (Android/iOS) citeturn0search0turn0search2

Why pick this: you want long-term ownership, custom optimizations, and you have (or will hire) strong mobile engineers.

### Option C — “Web UI but behaves like an app” (only if you still want web screens)
Use Capacitor/React Native WebView + native background location plugin.
- UI: React web
- Wrapper: Capacitor
- Native plugin handles background tracking
This gives you web development speed but does not suffer PWA background limits.

---

## Battery-efficient defaults for bikes + cars (starting parameters)
Whichever stack you choose, use an adaptive policy:
- **Moving:** distance-based updates (e.g., bikes 25–50m, cars 50–100m)
- **Stationary:** stop frequent GPS; rely on low-power checks/geofence-like behavior
- Upload in **batches** every 1–5 minutes (or every N points) to reduce battery + data

---

## Bottom line
- **Possible without paid “tracking APIs”**: Yes (use native location services).
- **Possible with no external services at all**: Not realistically, because admin alerts and centralized monitoring need a backend and a push pathway (APNs/FCM are the standard). citeturn0search0turn0search2  
- **Best stack for you** (bikes/cars, background tracking, fastest delivery): **Flutter + Firebase + proven background tracking component**.

If you want, I can outline:
- the exact table schema (SQL),
- RLS policies (so employees only see their data),
- and the “stuck detection” SQL + Edge Function flow that sends the admin notification.

---

### 4) User
> cant we just use supabase or any other backend services as you have to understand that there will be barely 20-25 users on this app thats it, and you can try to keep expense tracking also in it

### 4) Assistant
Yes—**Supabase is a very good fit** for a 20–25 user field-tracking + expenses app. You can keep your backend footprint small while still getting a real database, auth, storage (receipts), server logic, and realtime updates. Supabase bundles **Postgres + Auth + Storage + Edge Functions + Realtime**. citeturn0search0turn0search8turn0search16

The only “external” piece you still need is **push notification delivery** (FCM/APNs). Supabase can *trigger* notifications via Edge Functions, but the delivery rail is still FCM/APNs (often through Expo for simplicity). citeturn0search3

---

## Recommended low-cost, low-maintenance tech stack

### Mobile app (employee + admin)
- **Flutter** (single codebase for Android + iOS)
- Background location implemented natively (via Flutter plugins). For your use case, do not rely on a pure web/PWA approach.

### Backend
- **Supabase**
  - Auth for employee/admin logins citeturn0search0turn0search12
  - Postgres tables for sessions/locations/expenses
  - Storage for receipt images citeturn0search0turn0search16
  - Edge Functions for business logic (stuck alerts, validations) citeturn1search2
  - Cron jobs (pg_cron) to run periodic checks or invoke Edge Functions citeturn1search0turn1search1

### Admin dashboard
- Either:
  - A simple **web dashboard** (Next.js) using Supabase client, or
  - Build admin screens into the same Flutter app (role-based).

### Notifications
- Use **Expo push** (simplest cross-platform) or direct **FCM/APNs**.
- Supabase provides a push notification example flow using Edge Functions (Expo abstracts FCM/APNs complexity). citeturn0search3

Cost-wise, Supabase has a free tier and paid plans; for 20–25 users you’ll typically be in the lowest tier unless you store large media or stream extremely frequent location updates. citeturn0search2

---

## How the system works (clean, battery-aware)

### 1) “Present” starts a session
- App creates a `shift_session` row (start_time, employee_id, status=active).

### 2) Tracking during the session
- App records location points locally and uploads **in batches** (every 1–5 minutes or every N points).
- Distance is computed server-side (or device-side, then verified server-side).

### 3) “Work done” ends session
- App closes the session, stops background tracking, and uploads any remaining cached points.

### 4) “Stuck” alerting
Two practical Supabase-native ways:

**A) Trigger-on-location-insert (near real-time)**
- When new location points are inserted, a DB trigger updates an “employee_state” row and can invoke an Edge Function via a webhook. Supabase supports Database Webhooks. citeturn1search10turn0search0

**B) Scheduled checks (robust even if uploads are sparse)**
- Every X minutes, Supabase Cron runs a query to detect employees who are within radius R for time T, then calls an Edge Function to send notifications. Supabase documents Cron/pg_cron + scheduled Edge Function invocation. citeturn1search0turn1search1

For 20–25 users, option **B** is often the most stable because you’re not overly dependent on realtime delivery timing.

---

## Tracking policy for bikes + cars (good battery/accuracy defaults)

Use an adaptive mode:
- **Moving mode:** location updates primarily by **distance** rather than seconds  
  - Bikes: 25–50m distance filter  
  - Cars: 50–100m distance filter  
- **Stationary mode:** stop frequent GPS; rely on low-power checks and only “wake” GPS when movement is detected.

This keeps battery reasonable while still computing kilometers accurately.

“Stuck” rule defaults that work in practice (reduce false alerts at signals):
- Radius **R = 150m**
- Time **T = 30–45 minutes** (admin-configurable)
- Only count points with acceptable accuracy (e.g., discard very poor accuracy points).

---

## Adding expense tracking (fits naturally in Supabase)

Minimum data model:
- `expense_claims`: id, employee_id, date, total_amount, status (draft/submitted/approved/rejected), notes
- `expense_items`: claim_id, category, amount, merchant, paid_by, timestamp
- `expense_receipts`: claim_id, storage_path (Supabase Storage), metadata

Workflow:
- Employee creates claim + uploads receipts (Storage) citeturn0search0turn0search16
- Submits → admin gets push
- Admin approves/rejects → employee gets push

This is very manageable for your user count and keeps everything in one system.

---

## One important technical note about “Realtime”
Supabase supports realtime subscriptions, but their own guidance for new builds often prefers **broadcast via triggers** over raw “postgres_changes” for scalability/robustness. citeturn1search7turn1search18turn1search3  
For your size, either can work, but if you do realtime dashboards, follow Supabase’s recommended patterns.

---

## Bottom line recommendation
For your constraints (small user base, low maintenance, battery-efficient tracking, add expenses):

**Flutter app + Supabase (Postgres/Auth/Storage) + Supabase Edge Functions + Supabase Cron + Expo/FCM/APNs for notifications** citeturn0search0turn1search0turn0search3

If you want, I can outline:
- the exact table schema (SQL),
- RLS policies (so employees only see their data),
- and the “stuck detection” SQL + Edge Function flow that sends the admin notification.

---
