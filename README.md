# BenzDesk - Internal Accounts Request Platform

A secure, auditable, role-based accounts request management system for internal use.

## Tech Stack

- **Frontend**: Next.js 14 (Static Export) + TypeScript + Tailwind CSS
- **Backend**: Supabase (PostgreSQL + Auth + Storage)
- **Hosting**: Cloudflare Pages
- **Serverless**: Cloudflare Pages Functions
- **Bot Protection**: Cloudflare Turnstile

## Quick Start

### Prerequisites

1. Node.js 18+ installed
2. Supabase project created
3. Cloudflare account (for Turnstile and deployment)

### Setup

1. **Clone and install dependencies**:
   ```bash
   npm install
   ```

2. **Configure environment**:
   ```bash
   cp .env.example .env.local
   # Edit .env.local with your Supabase and Turnstile keys
   ```

3. **Run database migrations**:
   - Go to your Supabase dashboard → SQL Editor
   - Run migrations in order:
     - `infra/supabase/migrations/001_init.sql`
     - `infra/supabase/migrations/002_rls.sql`
     - `infra/supabase/migrations/003_triggers.sql`
     - `infra/supabase/migrations/004_views.sql`

4. **Bootstrap the Director user**:
   - Create a user in Supabase Auth
   - Insert into `user_roles`: `INSERT INTO user_roles (user_id, role) VALUES ('user-uuid', 'director');`

5. **Start development server**:
   ```bash
   npm run dev
   ```

### Deployment

```bash
# Build static export
npm run build

# Deploy to Cloudflare Pages
npx wrangler pages deploy out
```

## Project Structure

```
benzdesk/
├── apps/web/                 # Next.js frontend
│   ├── app/                  # App Router pages
│   │   ├── login/           # Authentication
│   │   ├── app/             # Requester routes
│   │   ├── admin/           # Admin routes
│   │   └── director/        # Director routes
│   ├── components/          # React components
│   │   ├── ui/              # Design system
│   │   ├── layout/          # Layout components
│   │   └── requests/        # Request-specific components
│   ├── lib/                 # Utilities & context
│   ├── styles/              # Global CSS
│   └── types/               # TypeScript definitions
├── functions/               # Cloudflare Pages Functions
│   └── api/                 # API endpoints
├── infra/                   # Infrastructure
│   └── supabase/            # Database migrations
└── package.json
```

## User Roles

| Role | Access |
|------|--------|
| **Requester** | Create requests, view own requests, add comments |
| **Accounts Admin** | View all requests, update status, manage queue |
| **Director** | Full access, dashboards, user management, metrics |

## Security Features

- Row Level Security (RLS) on all tables
- Append-only audit log
- Optimistic concurrency control
- Server-side Turnstile verification
- No public signup (invite-only)
- Service role key never exposed to browser

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `NEXT_PUBLIC_SUPABASE_URL` | Yes | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Yes | Supabase anonymous key |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes | For Cloudflare Functions only |
| `TURNSTILE_SECRET_KEY` | Yes | Cloudflare Turnstile secret |
| `NEXT_PUBLIC_TURNSTILE_SITE_KEY` | Yes | Cloudflare Turnstile site key |

## License

Internal use only - Benz Packaging
