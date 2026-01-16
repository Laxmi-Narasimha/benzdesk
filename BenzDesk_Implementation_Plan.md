# BenzDesk — Industry-Grade Internal Accounts Request Platform (Plan + Blueprint)

> **Goal:** Build a secure, auditable, role-based internal request/ticketing platform for Benz’s Accounts team.  
> **Scale:** ~35 requesters, 3 Accounts Admins, 1 Director. Typically 2–3 active users concurrently.  
> **Non‑negotiables:** strict isolation, no UI‑only security, complete audit trail, reliable auth, timestamps recorded server-side.

---

## 0) Executive Summary (What You Will Build)

You will build **BenzDesk**, a web application where:

- **Requesters (employees)** submit requests (invoice, reimbursement, vendor payment, etc.) and can only see their own requests.
- **Accounts Admins** see all requests and manage workflow (assign, update status, request info, close).
- **Director** sees all requests plus accountability metrics (open vs closed, who closed, time-to-first-response, SLA, per-admin workload).
- Every state change is tracked in an **append-only audit log** with **server timestamps** and **actor identity**.

Security is enforced **at the database level** using **Postgres Row Level Security (RLS)**.

---

## 1) Final Tech Stack (Best Reliable Options + Free Tier Friendly)

### 1.1 Hosting (Frontend)
- **Cloudflare Pages** (Free plan) for hosting the web UI.
  - Reliable, globally cached, easy Git deploys.
  - **Build limit:** 500 builds/month on Free plan.  
  - Suitable for this low-traffic internal app.

### 1.2 Minimal Server Endpoints
- **Cloudflare Pages Functions** (Free Workers quota) for:
  - Turnstile token verification (`/api/turnstile/verify`)
  - Optional provisioning endpoints (`/api/admin/invite`, `/api/admin/role`)
  - Any “server secret” usage (keeps secrets off the browser)
- Requests to Pages Functions count toward Workers Free plan quota:
  - Example: 50k Functions + 50k Workers = 100k daily usage.

### 1.3 Database + Auth + Storage (Backend)
- **Supabase**
  - **Database:** Postgres
  - **Auth:** Email OTP (passwordless) + optional password setup
  - **Storage:** Attachments (receipts, invoices)
  - **Authorization:** Postgres RLS + policies

### 1.4 Email Delivery for OTP (Reliable + Free Tier)
- **Resend (SMTP)** connected to Supabase Auth:
  - Free quotas (as of now): 100 transactional emails/day, 3,000/month.
  - Use your own domain for deliverability (SPF/DKIM/DMARC).

> Note: Supabase includes custom SMTP support in Free plan, but you still need an SMTP provider account.

### 1.5 Bot / Abuse Protection
- **Cloudflare Turnstile** on login/OTP request form.
  - Requires **server-side validation** because tokens can be forged.
  - Tokens expire quickly and are single-use.

### 1.6 Frontend Framework
- **Next.js** in **Static Export** mode (SPA-style) deployed to Pages.
  - Avoids SSR complexity on Cloudflare.
  - Very stable pattern: static hosting + secure backend enforced via RLS.
- **TypeScript** for reliability.
- **UI:** any stable component set (Tailwind optional). Keep dependencies minimal.

### 1.7 Observability
- **Sentry** (free tier is enough) for frontend error tracking (optional but recommended).
- Use Supabase logs for DB/auth debugging.

### 1.8 Versioning & “Legacy-Stable” Rules
To maximize long-term reliability:
- Pin major versions in `package.json` (no loose upgrades).
- Commit lockfile (`package-lock.json` or `pnpm-lock.yaml`) and use `npm ci` in CI.
- Avoid experimental Next.js features (server actions, partial prerendering, edge-only quirks).
- Keep server logic minimal and in SQL (triggers, constraints) + small, simple Cloudflare functions.

---

## 2) High-Level Architecture

```text
[Browser: Next.js Static UI on Cloudflare Pages]
          |
          | (supabase-js with anon key + user JWT)
          v
[Supabase Auth] ---- issues JWT session ----> [Supabase Postgres (RLS enforced)]
          |
          | (emails OTP via SMTP)
          v
[Resend SMTP Provider]

Optional server-secret endpoints:
[Cloudflare Pages Functions]
  - Turnstile validate (uses Turnstile secret)
  - Admin provisioning (uses Supabase Service Role key)
```

**Core rule:** The browser only uses Supabase **anon key**.  
**Never** expose Supabase **service role** key to the browser.

---

## 3) Functional Requirements (Must-Have)

### 3.1 Request Lifecycle
Statuses:
- `open`
- `in_progress`
- `waiting_on_requester`
- `closed`

Actions:
- Requester: create request, comment/add info, view status/history, upload attachments.
- Accounts Admin: assign, update status, add internal notes (optional), close/reopen.
- Director: view everything, dashboards, metrics, audit timeline.

### 3.2 Audit Trail
Every meaningful action must create an immutable event row:
- Request created
- Comment added
- Status changed
- Assignment changed
- Closed/Reopened
- Attachment uploaded/removed (if you allow removal)

Each event must include:
- `request_id`
- `created_at` (server time)
- `actor_id`
- event type + old/new values where applicable
- optional note

### 3.3 Strict Timestamps
- Never accept timestamps from clients.
- Use `DEFAULT now()` or triggers/functions for all timestamps.

### 3.4 Isolation
- Requesters can **only** see their own requests + related comments/events/attachments.
- Admins can see all.
- Director can see all + metrics views.

---

## 4) Non-Functional Requirements (Industry Grade)

### 4.1 Security
- Database-enforced authorization (RLS).
- Principle of least privilege.
- Domain-restricted access (only Benz emails).
- MFA required for Accounts Admin + Director.
- Bot mitigation on OTP request.
- Rate limiting on OTP requests.
- No direct delete of requests (use status changes).
- Append-only audit log; no updates/deletes allowed.

### 4.2 Reliability
- Idempotent endpoints where possible.
- Avoid background jobs unless necessary.
- Graceful handling of email delays and OTP expiry.
- Concurrency-safe updates (optimistic concurrency).

### 4.3 Maintainability
- SQL migrations under version control.
- Clear naming conventions.
- Minimal dependency surface.
- Comprehensive tests for RLS policies.

---

## 5) Database Schema (Authoritative Blueprint)

### 5.1 Enums
- `app_role`: `requester`, `accounts_admin`, `director`
- `request_status`: `open`, `in_progress`, `waiting_on_requester`, `closed`
- `request_event_type`: `created`, `comment`, `status_changed`, `assigned`, `closed`, `reopened`, `attachment_added`, `attachment_removed`

### 5.2 Tables

#### `user_roles`
Stores application roles (separate from Supabase auth).

Columns:
- `user_id uuid PK` (references auth.users.id)
- `role app_role NOT NULL DEFAULT 'requester'`
- `created_at timestamptz DEFAULT now()`
- `created_by uuid NULL` (who assigned role; director)
- `is_active boolean DEFAULT true` (for offboarding)

#### `requests`
Current ticket state.

Columns:
- `id uuid PK default gen_random_uuid()`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `created_by uuid NOT NULL`
- `title text NOT NULL`
- `description text NOT NULL`
- `category text NOT NULL`
- `priority int NOT NULL DEFAULT 3 CHECK (priority between 1 and 5)`
- `status request_status NOT NULL DEFAULT 'open'`
- `assigned_to uuid NULL`
- `closed_at timestamptz NULL`
- `closed_by uuid NULL`
- `updated_at timestamptz NOT NULL DEFAULT now()`
- `updated_by uuid NULL`
- `last_activity_at timestamptz NOT NULL DEFAULT now()`
- `last_activity_by uuid NULL`
- `first_admin_response_at timestamptz NULL`  (for SLA)
- `first_admin_response_by uuid NULL`

Indexes:
- `(created_by, created_at desc)`
- `(status, created_at desc)`
- `(assigned_to, status)`
- `(last_activity_at desc)`

#### `request_comments`
User-visible conversation.

Columns:
- `id bigint identity PK`
- `request_id uuid NOT NULL`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `author_id uuid NOT NULL`
- `body text NOT NULL`
- `is_internal boolean NOT NULL DEFAULT false`  
  - **Requesters cannot create internal comments.**
  - Admins can (optional). Director can read internal comments (optional).

Indexes:
- `(request_id, created_at)`

#### `request_events` (Append-only audit log)
Columns:
- `id bigint identity PK`
- `request_id uuid NOT NULL`
- `created_at timestamptz NOT NULL DEFAULT now()`
- `actor_id uuid NOT NULL`
- `event_type request_event_type NOT NULL`
- `old_data jsonb NOT NULL DEFAULT '{}'`
- `new_data jsonb NOT NULL DEFAULT '{}'`
- `note text NULL`

Indexes:
- `(request_id, created_at)`

#### `request_attachments`
Tracks file metadata (files stored in Supabase Storage).

Columns:
- `id bigint identity PK`
- `request_id uuid NOT NULL`
- `uploaded_at timestamptz NOT NULL DEFAULT now()`
- `uploaded_by uuid NOT NULL`
- `bucket text NOT NULL`
- `path text NOT NULL`  (e.g. `requests/<request_id>/<uuid>-<filename>`)
- `original_filename text NOT NULL`
- `mime_type text NOT NULL`
- `size_bytes bigint NOT NULL`

Indexes:
- `(request_id, uploaded_at)`

---

## 6) RLS Policies (This Is the Security Backbone)

### 6.1 Helper Function: `has_role(role)`
Create a stable helper function in `public` schema:
- Returns true if current `auth.uid()` has given role and is_active=true.

### 6.2 Rules by Table

#### `user_roles`
- Requester can `SELECT` only their own role row.
- Only director can `INSERT/UPDATE` roles.
- No one can delete role rows (set `is_active=false` to offboard).

#### `requests`
- Requester can:
  - `SELECT` rows where `created_by = auth.uid()`
  - `INSERT` only with `created_by = auth.uid()`
  - **NOT UPDATE** (requester changes happen through comments/attachments)
- Accounts Admin can:
  - `SELECT` all
  - `UPDATE` status/assignment fields
- Director can:
  - `SELECT` all
  - usually **no UPDATE** (director oversight only)

#### `request_comments`
- Anyone who can read the request can read comments (with internal filtering).
- Requester can insert comments only if:
  - request belongs to them
  - `is_internal=false`
  - `author_id=auth.uid()`
- Accounts Admin can insert internal comments too.

#### `request_events`
- Read allowed if you can read the request.
- **No client inserts.** Only DB triggers insert events (security definer).

#### `request_attachments`
- Read allowed if you can read the request.
- Insert allowed if you can read the request.
- Delete: optional; if allowed, must log `attachment_removed`.

---

## 7) Triggers & Audit Logging (Server Truth)

### 7.1 Trigger: On request insert
- Insert `request_events` row with type `created`.
- Set `last_activity_*` fields.
- Ensure `created_by` is `auth.uid()` (enforced by RLS + check constraint).

### 7.2 Trigger: On request update (admin only)
Detect changes:
- if `status` changed → log `status_changed`
- if `assigned_to` changed → log `assigned`
- if moved to closed → also set `closed_at`, `closed_by`, log `closed`
- if reopened → clear `closed_at`, `closed_by`, log `reopened`
- Update `updated_at`, `updated_by`, `last_activity_at`, `last_activity_by`.

**First admin response tracking:**
- On the first admin-originated update/comment for a request:
  - set `first_admin_response_at`, `first_admin_response_by`
  - never change after set

### 7.3 Trigger: On comment insert
- Log `comment` event
- Update `last_activity_at/by`
- If comment author is accounts_admin and first_admin_response is null: set it.

### 7.4 Trigger: On attachment insert/remove
- Log `attachment_added` or `attachment_removed`
- Update `last_activity_*`

### 7.5 Audit Log Integrity
- No update/delete privileges on `request_events`.
- If you must correct something, add a new `request_events` row describing correction.

---

## 8) Authentication Design (Email OTP + Optional Password)

### 8.1 OTP vs Magic Link (Supabase behavior)
Supabase’s `signInWithOtp`:
- is used for passwordless sign-in
- for email, it typically sends a magic link by default unless your email template includes the token
- can auto-create users unless disabled

**Must do:**
- Set `shouldCreateUser: false` on OTP sign-in (prevents signup-by-OTP).
- This forces a provisioning step (director/admin invites users).

### 8.2 User Provisioning (No Public Signup)
Two acceptable approaches:

**Approach A (Recommended): Invite users**
- Director provisions users (email list).
- Users receive email to login / set password.

**Approach B: Allow domain signups but block with hook**
- Use Supabase “Before User Created Hook” to allow only `@benz...` domain.
- Still set `shouldCreateUser:false` in UI for tighter control.

### 8.3 Password Setup (Optional)
After first OTP login:
- force “Set Password” screen
- call Supabase update user password
- thereafter user can login with password, or you can keep OTP-only.

**Recommended:** keep OTP-only for simplicity, but allow password as fallback.

### 8.4 MFA (Required for Admin & Director)
- Require TOTP-based MFA for:
  - 3 accounts admins
  - director
- Block admin features unless MFA is enabled (application-level gate + role policy).

---

## 9) OTP + Turnstile Flow (No Loopholes)

### 9.1 Why Turnstile must be server-validated
Tokens can be forged; client-side checks are not enough. Tokens expire quickly and are single-use.

### 9.2 Implementation
- Client renders Turnstile widget.
- On “Send OTP”:
  1) collect Turnstile token
  2) POST token to `/api/turnstile/verify` (Pages Function)
  3) only if server says OK → call `supabase.auth.signInWithOtp(...)`

### 9.3 Email Enumeration Prevention
Even if OTP sending fails:
- UI response must be the same message:
  - “If your account exists, an OTP has been sent.”
- Log internal errors for admins (not user-visible).

### 9.4 Rate Limiting Strategy
Implement both:
- Supabase Auth OTP controls (time between requests, expiration settings)
- Cloudflare rate-limits:
  - per-IP and per-email on `/api/turnstile/verify` and OTP endpoints
  - lock out after too many failures

---

## 10) Frontend Application Design (Stable + Simple)

### 10.1 Routes (Recommended)
- `/login`
- `/set-password` (optional)
- `/app` (shell)
  - `/app/my-requests`
  - `/app/request/[id]`
- `/admin` (accounts admins)
  - `/admin/queue`
  - `/admin/request/[id]`
  - `/admin/reports`
- `/director`
  - `/director/dashboard`
  - `/director/request/[id]`
  - `/director/audit/[id]`
  - `/director/admin-performance`

### 10.2 UI Components
- Request form (title, description, category, priority, attachments)
- Request list (filters by status, category, date)
- Request detail:
  - timeline (events)
  - comments
  - attachments
  - status/assignment controls (admin-only)
- Director dashboards:
  - Open vs closed counts
  - SLA breaches
  - per-admin backlog
  - average time to first response, average time to close
  - stale requests (no activity in X days)

### 10.3 Data Access Pattern
- Use Supabase client directly from browser:
  - `requests`, `request_comments`, `request_events`
- Security is guaranteed by RLS policies.
- Never write “security conditions” in UI alone.

### 10.4 Concurrency Handling (Avoid overwrites)
Implement optimistic concurrency on `requests`:
- Add `row_version int NOT NULL DEFAULT 1`
- On admin update:
  - `update ... set ..., row_version = row_version + 1 where id = $id and row_version = $expected`
  - if 0 rows returned → “This request was updated by someone else. Refresh.”

---

## 11) Attachments (Supabase Storage + Policies)

### 11.1 Storage Layout
Bucket: `benzdesk`
Path format:
- `requests/<request_id>/<uuid>-<original_filename>`

### 11.2 Restrictions
- Allow only approved mime types (pdf, jpg, png).
- Enforce size limits (free projects max global limit ≤ 50MB).

### 11.3 Access Controls
- RLS policies on `storage.objects` (Supabase Storage) must ensure:
  - request owner can read their attachments
  - admins/director can read all attachments
  - requester can only upload to their own request folder

### 11.4 Secure Download
- Prefer signed URLs (short-lived) if you want additional control.
- Otherwise ensure RLS + bucket policy are correct.

---

## 12) Director Oversight Metrics (SQL Views)

Create read-only views:
- `v_requests_overview` (counts by status)
- `v_admin_backlog` (open requests assigned to each admin)
- `v_sla_first_response` (time-to-first-response)
- `v_sla_time_to_close` (time-to-close)
- `v_stale_requests` (no activity in > N hours/days)
- `v_admin_throughput` (closed per admin per week)

These views must be readable by director, optionally by admins.

---

## 13) Admin Provisioning (Director-Only)

### 13.1 Why a server endpoint is needed
Creating users / assigning roles may require privileged credentials (service role key) which must not be exposed to browser.

### 13.2 Director-only endpoints (Cloudflare Pages Functions)
Endpoints:
- `POST /api/admin/invite-user`
- `POST /api/admin/set-role`
- `POST /api/admin/deactivate-user`

Rules:
- Verify caller’s Supabase JWT (Authorization header).
- Look up caller role in `user_roles`.
- Only proceed if caller role is `director`.
- Use Supabase service role key stored as Cloudflare secret.

---

## 14) Deployment Plan (Step-by-Step)

### 14.1 Supabase Setup
1) Create Supabase project.
2) Apply SQL migrations for:
   - enums, tables, indexes
   - RLS policies
   - triggers/functions
3) Configure Auth:
   - Email provider enabled
   - Email template modified to include OTP token
   - Set OTP expiration (recommended 10 minutes)
4) Configure Custom SMTP:
   - Add Resend SMTP settings
   - Configure SPF/DKIM/DMARC in DNS
5) Create director user and manually insert role row for director.

### 14.2 Cloudflare Setup
1) Create Cloudflare Pages project from GitHub.
2) Configure build:
   - `npm ci`
   - `npm run build`
   - ensure Next.js static export output directory is used
3) Add env vars:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
4) Add Pages Functions:
   - `/api/turnstile/verify`
   - `/api/admin/*` (optional)
5) Setup Turnstile site + secret keys.
6) Add custom domain, enforce HTTPS.

### 14.3 Resend Setup
1) Create Resend project.
2) Add and verify sending domain.
3) Generate SMTP credentials.
4) Put credentials into Supabase Custom SMTP settings.

---

## 15) Testing Plan (Do Not Skip)

### 15.1 Security Tests (Most important)
- Attempt to query other users’ requests from browser (must return 0).
- Attempt to update requests as requester (must fail).
- Attempt to insert internal comments as requester (must fail).
- Attempt to read attachments by guessing path (must fail).
- Attempt to modify audit log (must fail).

### 15.2 RLS Regression Tests
- Maintain a SQL test suite that runs:
  - as requester role
  - as accounts_admin role
  - as director role

### 15.3 OTP Edge Cases
- OTP expired → correct message
- OTP already used → correct message
- Resend OTP too soon → rate-limit message
- Email delayed → allow resend after cooldown
- User not provisioned → show generic message (no enumeration)

### 15.4 Concurrency Tests
- Two admins update same request simultaneously:
  - one succeeds
  - the other gets conflict and must refresh

---

## 16) Operational & Maintenance

### 16.1 Backups
- Free tier may not include automatic backups. For industry-grade:
  - schedule periodic manual exports (pg_dump) if needed
  - store encrypted backups in company-controlled storage

### 16.2 Offboarding
- Set `user_roles.is_active=false`
- Optionally delete user from Supabase Auth
- Ensure RLS checks `is_active=true` so offboarded users cannot access.

### 16.3 Secret Rotation
- Rotate:
  - Resend SMTP password
  - Supabase service role key (if ever exposed)
  - Turnstile secret key
- Store secrets only in:
  - Supabase dashboard (SMTP)
  - Cloudflare secrets (service role, turnstile secret)

### 16.4 Audit Review
- Director should be able to export:
  - request list + event timelines
  - admin performance report

---

## 17) Implementation Checklist (For the AI Builder)

### Must-Do Security
- [ ] Enable RLS on ALL app tables and storage objects policies.
- [ ] Use `shouldCreateUser:false` for OTP sign-in.
- [ ] Disable public signup or enforce domain allowlist via auth hook.
- [ ] Never expose Supabase service role key to the browser.
- [ ] Turnstile token server-side validation.
- [ ] Rate limit OTP requests and verify attempts.
- [ ] Append-only audit events (no update/delete).

### Must-Do Reliability
- [ ] Server timestamps only (`now()` defaults + triggers).
- [ ] Optimistic concurrency on request updates.
- [ ] Idempotent admin actions where possible.

### Must-Do Product Features
- [ ] Request creation + list + detail.
- [ ] Admin queue with filters.
- [ ] Director dashboards + drill-down.
- [ ] Attachments with strict access rules.
- [ ] Complete event timeline.

---

## 18) Appendix: Example Files & Structure

### Repository structure
```text
/benzdesk
  /apps/web
    /pages (or /app if you insist; keep stable)
    /components
    /lib/supabaseClient.ts
    /styles
  /infra
    /supabase
      /migrations
        001_init.sql
        002_rls.sql
        003_triggers.sql
  /functions
    /api/turnstile/verify.ts
    /api/admin/invite-user.ts
```

### Environment variables
```bash
# Cloudflare Pages
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...

# Cloudflare secrets (server-side only)
SUPABASE_SERVICE_ROLE_KEY=...
TURNSTILE_SECRET_KEY=...
TURNSTILE_SITE_KEY=... # can be public if needed
```

---

## 19) Notes on Free Tier Constraints (Be Aware)
- Email sending is constrained by SMTP provider quotas.
- Supabase free projects can pause after inactivity; ensure app is used or upgrade if needed.
- Attachment size capped by configured project limits.

---

## 20) “No Compromises” Final Rule
If something conflicts between “free” and “industry-grade reliability”, **security and correctness win**:
- Keep it secure on free tier now.
- Upgrade email/hosting plans later if the business depends on it.

