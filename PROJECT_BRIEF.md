# BenzDesk Project Brief
## Complete Handoff Document for AI Continuation

---

## 1. PROJECT OVERVIEW

**BenzDesk** is an internal accounts query/request portal for **Benz Packaging** (Indian manufacturing company). Employees submit requests to the accounts team (expenses, salary queries, purchase orders, etc.), and admins process them.

### Purpose
- Replace email/WhatsApp based query handling
- Provide audit trail for all requests
- Track SLAs and response times
- Give directors oversight on team performance

### Live URL
**https://benzdesk.pages.dev**

---

## 2. CREDENTIALS (CRITICAL)

### Supabase (Database & Auth)
- **Project URL**: `https://igrudnilqwmlgvmgneng.supabase.co`
- **Anon Key**: Check `.env.local` file in project root
- **Dashboard**: https://supabase.com/dashboard/project/igrudnilqwmlgvmgneng

### Cloudflare Pages (Hosting)
- **Project**: benzdesk
- **URL**: https://benzdesk.pages.dev
- **Deploy command**: `npm run pages:deploy`

### User Accounts in System

| Email | Password | Role | Notes |
|-------|----------|------|-------|
| chaitanya@benz-packaging.com | BenzDesk@2026! | director | Full access, metrics |
| dinesh@benz-packaging.com | BenzDesk2026! | accounts_admin | Process requests |
| hr.support@benz-packaging.com | BenzDesk2026! | accounts_admin | Process requests |
| laxmi@benz-packaging.com | BenzDesk2026! | requester | Employee - creates requests |

---

## 3. TECH STACK

| Layer | Technology | Version |
|-------|------------|---------|
| Frontend | Next.js (App Router) | 14.0.4 |
| Styling | Tailwind CSS | 3.3.6 |
| Language | TypeScript | 5.3.3 |
| Database | Supabase (PostgreSQL) | - |
| Auth | Supabase Auth | - |
| Storage | Supabase Storage | - |
| Hosting | Cloudflare Pages | Static Export |

### Key Dependencies
- `@supabase/supabase-js` - Database client
- `date-fns` - Date formatting
- `lucide-react` - Icons
- `clsx` - Conditional classnames

---

## 4. PROJECT STRUCTURE

```
c:\Users\user\benzdesk\
├── app/                        # Next.js App Router pages
│   ├── layout.tsx              # Root layout with providers
│   ├── page.tsx                # Home redirect
│   ├── login/page.tsx          # Login page
│   ├── app/                    # Requester portal
│   │   ├── page.tsx            # Dashboard
│   │   ├── request/            # Request detail
│   │   └── new/page.tsx        # Create request
│   ├── admin/                  # Admin portal
│   │   ├── page.tsx            # Admin queue
│   │   └── request/            # Request detail
│   └── director/               # Director portal
│       ├── page.tsx            # Metrics dashboard
│       └── request/            # Request detail
│
├── components/
│   ├── ui/                     # Reusable UI components
│   │   ├── Button.tsx
│   │   ├── Input.tsx
│   │   ├── Select.tsx
│   │   ├── Card.tsx
│   │   ├── Badge.tsx
│   │   ├── Modal.tsx
│   │   ├── Loading.tsx
│   │   ├── Toast.tsx
│   │   └── index.ts            # Barrel export
│   ├── requests/               # Request-specific components
│   │   ├── RequestForm.tsx     # Create request form
│   │   ├── RequestList.tsx     # List with filters
│   │   ├── RequestDetail.tsx   # Full request view
│   │   ├── RequestTimeline.tsx # Audit trail
│   │   ├── CommentThread.tsx   # Comments
│   │   ├── AttachmentList.tsx  # File uploads
│   │   └── index.ts
│   └── layout/
│       ├── Sidebar.tsx
│       └── Header.tsx
│
├── lib/
│   ├── supabaseClient.ts       # Supabase singleton client
│   └── AuthContext.tsx         # Auth provider & hooks
│
├── types/
│   └── index.ts                # All TypeScript types
│
├── styles/
│   └── globals.css             # Global styles, CSS variables
│
├── infra/supabase/migrations/  # SQL migrations
│   ├── 001_init.sql            # Tables, enums, indexes
│   ├── 002_rls.sql             # Row Level Security policies
│   ├── 003_triggers.sql        # Audit logging triggers
│   ├── 004_views.sql           # Director metric views
│   └── 005_add_deadline.sql    # Deadline column
│
├── functions/                  # Cloudflare Pages functions (not active)
│
├── .env.local                  # Environment variables (DO NOT COMMIT)
├── next.config.js              # Next.js config (static export)
├── tailwind.config.js          # Tailwind theme
├── tsconfig.json               # TypeScript config
└── package.json                # Dependencies & scripts
```

---

## 5. DATABASE SCHEMA

### Tables

**requests**
```sql
id              UUID PRIMARY KEY
created_at      TIMESTAMPTZ
created_by      UUID (FK auth.users)
title           TEXT
description     TEXT
category        TEXT (check constraint)
priority        INTEGER (1-5)
status          TEXT ('open', 'in_progress', 'waiting_on_requester', 'closed')
deadline        TIMESTAMPTZ NULL
assigned_to     UUID NULL
closed_at       TIMESTAMPTZ NULL
closed_by       UUID NULL
updated_at      TIMESTAMPTZ
row_version     INTEGER (optimistic concurrency)
first_admin_response_at TIMESTAMPTZ NULL
last_activity_at TIMESTAMPTZ
```

**request_comments**
```sql
id              SERIAL PRIMARY KEY
request_id      UUID (FK requests)
author_id       UUID (FK auth.users)
body            TEXT
is_internal     BOOLEAN (admin-only notes)
created_at      TIMESTAMPTZ
```

**request_events** (Immutable audit log)
```sql
id              SERIAL PRIMARY KEY
request_id      UUID
actor_id        UUID
event_type      TEXT
old_data        JSONB
new_data        JSONB
created_at      TIMESTAMPTZ
```

**request_attachments**
```sql
id              SERIAL PRIMARY KEY
request_id      UUID
uploaded_by     UUID
bucket          TEXT
path            TEXT
original_filename TEXT
mime_type       TEXT
size_bytes      INTEGER
uploaded_at     TIMESTAMPTZ
```

**user_roles**
```sql
user_id         UUID PRIMARY KEY
role            TEXT ('requester', 'accounts_admin', 'director')
is_active       BOOLEAN
created_at      TIMESTAMPTZ
```

### Current Categories (valid_category constraint)
- expense_reimbursement
- salary_payroll
- purchase_order
- delivery_challan
- invoice_query
- vendor_payment
- travel_allowance
- gst_tax_query
- bank_account_update
- advance_request
- petty_cash
- other

---

## 6. AUTHENTICATION FLOW

1. User enters email on login page
2. Can authenticate via:
   - **Password**: Direct login with password
   - **OTP**: Magic link sent to email
3. After auth, system fetches user role from `user_roles` table
4. Redirects to appropriate portal based on role:
   - `requester` → `/app`
   - `accounts_admin` → `/admin`
   - `director` → `/director`

### AuthContext (lib/AuthContext.tsx)
Provides:
- `user` - Current user with role
- `isAdmin`, `isDirector`, `canManageRequests` - Role checks
- `loginWithPassword()`, `sendOtp()`, `verifyOtpCode()`, `logout()`
- `ProtectedRoute` component for route guards

---

## 7. ROW LEVEL SECURITY (RLS)

All tables have RLS enabled. Key policies:

**requests**
- Requesters see only their own requests
- Admins/Directors see all requests
- Only request creator or admins can update

**request_comments**
- Internal comments (`is_internal=true`) hidden from requesters
- Admins can add internal notes

**request_events**
- Read-only for all (immutable audit log)
- Auto-populated by triggers

---

## 8. IMPORTANT DESIGN DECISIONS

### Static Export
- Using `output: 'export'` in next.config.js
- **Why**: Cloudflare Pages adapter had issues on Windows
- **Impact**: All dynamic routes use query params (`/request?id=123`) not path params

### URL Pattern
- OLD: `/app/request/[id]` (causes 404 on static host)
- NEW: `/app/request?id=123` (works with static export)
- RequestList links to `?id=` format
- RequestForm redirects to `?id=` format

### Monochrome Theme
- User specifically requested NO blue/colored accents
- Pure black (#000), white (#fff), grays only
- Status badges are the only colored elements (green/yellow/red)

---

## 9. BUILD & DEPLOY

### Local Development
```bash
cd c:\Users\user\benzdesk
npm install
npm run dev
# Opens at http://localhost:3000
```

### Build for Production
```bash
npm run build
# Creates /out directory with static export
```

### Deploy to Cloudflare
```bash
npm run pages:deploy
# Deploys /out to Cloudflare Pages
```

### Environment Variables
Required in `.env.local`:
```
NEXT_PUBLIC_SUPABASE_URL=https://igrudnilqwmlgvmgneng.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=<anon-key>
```

---

## 10. CURRENT STATE

### Working Features
- Login (password and OTP)
- Create request with categories, priority, deadline, attachments
- View request list with filters
- Request detail with timeline and comments
- Admin status updates
- File upload and download
- Overdue deadline highlighting

### Known Issues / Not Implemented
- Email notifications not set up
- Turnstile (Cloudflare captcha) not integrated
- Real-time updates (using page refresh currently)
- Director metrics dashboard may need more views

---

## 11. KEY FILES TO UNDERSTAND

| File | Purpose |
|------|---------|
| `types/index.ts` | All TypeScript types and constants |
| `lib/supabaseClient.ts` | Database client setup |
| `lib/AuthContext.tsx` | Authentication state management |
| `components/requests/RequestForm.tsx` | Main form for creating requests |
| `components/requests/RequestDetail.tsx` | Full request view with admin controls |
| `styles/globals.css` | All CSS variables and component styles |
| `infra/supabase/migrations/*.sql` | Database schema definitions |

---

## 12. COMMON TASKS

### Add New Category
1. Update `RequestCategory` type in `types/index.ts`
2. Update `REQUEST_CATEGORY_LABELS` in `types/index.ts`
3. Update `categoryGroups` in `components/requests/RequestForm.tsx`
4. Run SQL: `ALTER TABLE requests DROP CONSTRAINT valid_category; ALTER TABLE requests ADD CONSTRAINT valid_category CHECK (category IN (...));`

### Add New User
1. Go to Supabase Dashboard → Authentication → Users → Add User
2. Create with email and password (enable auto-confirm)
3. Run SQL to assign role: `INSERT INTO user_roles (user_id, role) VALUES ('<uuid>', 'requester');`

### Change UI Theme
- All colors in `styles/globals.css` CSS variables (`:root`)
- Tailwind theme in `tailwind.config.js`

---

## 13. SUPABASE SQL EDITOR ACCESS

URL: https://supabase.com/dashboard/project/igrudnilqwmlgvmgneng/sql/new

Useful queries:
```sql
-- See all users and roles
SELECT u.email, r.role FROM auth.users u LEFT JOIN user_roles r ON u.id = r.user_id;

-- See all requests
SELECT id, title, status, category, created_at FROM requests ORDER BY created_at DESC;

-- Check categories in use
SELECT DISTINCT category FROM requests;
```

---

## 14. PROJECT CONTACTS

- **Company**: Benz Packaging (Indian manufacturing)
- **Director**: chaitanya@benz-packaging.com
- **Use Case**: Internal accounts team query management

---

## END OF HANDOFF DOCUMENT

This document contains everything needed to continue development on BenzDesk. The codebase is at `c:\Users\user\benzdesk`. Always test locally before deploying.
