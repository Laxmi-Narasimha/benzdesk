# Map Provider Migration Guide

This document explains how to switch the BenzMobiTraq distance + map system
between providers. The code retains both paths intentionally — when you scale
past Google's free tier or want to escape Google ToS constraints, you can
swap providers without rewriting application logic.

**Current provider (default):** Google Maps + Google Roads API.

---

## 1. Why two providers exist

| | Google Maps + Roads API | Self-hosted OSRM/Valhalla + Leaflet/OSM |
|---|---|---|
| Snap quality (India) | Excellent | Good in metros; weaker in Tier 2/3 |
| Setup | Hours (API key) | Days–weeks (server + OSM import + cron) |
| Cost at small scale (20 employees) | ₹0 (under free tier) | ~₹2,000/month server + your time |
| Cost at 500+ employees | $400+/month | Same server, basically flat |
| ToS friction | Cannot show snapped geometry on non-Google maps; geometry caching ≤ 30 days | None |
| Map data freshness | Continuous | Re-import OSM monthly |
| Failure modes | API outage, quota | Server down, OSM stale |

We are currently at ~20 employees + ~600 km/day combined fleet ≈ 18,000 km/month.
At ~30m downsampling we make ~7,000 Roads API requests/month — well under the
35,000/month free tier.

**Recommended migration point:** ≥500 active employees OR Google API monthly
bill > 2× the cost of a small OSRM EC2 instance + ops time. Until then, keep
Google.

---

## 2. The provider abstractions

### 2.1 Server-side map matching (the math)

Defined in `infra/supabase/functions/finalize-trip/_shared/map_matcher.ts`.

```ts
export interface MapMatcherProvider {
    readonly name: string;
    matchSegment(points: TimedPoint[]): Promise<MatchResult>;
}
```

The factory picks an implementation based on env:

```ts
function makeMapMatcherProvider(): MapMatcherProvider {
    const provider = Deno.env.get('MAP_MATCHER_PROVIDER') ?? 'google_roads';
    switch (provider) {
        case 'google_roads': return new GoogleRoadsProvider(...);
        // case 'osrm':       return new OsrmProvider(...);   // ← add when needed
        // case 'valhalla':   return new ValhallaProvider(...);
    }
}
```

### 2.2 Admin map display (the UI)

Defined in `app/director/mobitraq/timeline/page.tsx`. Switches between
`MapComponent.tsx` (Leaflet/OSM, kept intact) and `MapComponentGoogle.tsx`:

```tsx
const _mapProvider = (process.env.NEXT_PUBLIC_MAP_PROVIDER ?? 'google').toLowerCase();
const MapComponent = dynamic(() =>
    _mapProvider === 'osm'
        ? import('./MapComponent')          // Leaflet/OSM
        : import('./MapComponentGoogle'),   // Google Maps
    { ssr: false, ... }
);
```

---

## 3. How to migrate Google → OSRM/Valhalla

Do these in order. Each step is reversible by flipping the env var back.

### Step 1 — Stand up OSRM (or Valhalla)

OSRM:
1. Provision a small VM (4 vCPU / 8 GB RAM handles all of India OSM).
2. Download India OSM extract from Geofabrik:
   `https://download.geofabrik.de/asia/india-latest.osm.pbf`
3. Build OSRM:
   ```bash
   docker run -t -v "$PWD:/data" ghcr.io/project-osrm/osrm-backend \
     osrm-extract -p /opt/car.lua /data/india-latest.osm.pbf
   docker run -t -v "$PWD:/data" ghcr.io/project-osrm/osrm-backend \
     osrm-partition /data/india-latest.osrm
   docker run -t -v "$PWD:/data" ghcr.io/project-osrm/osrm-backend \
     osrm-customize /data/india-latest.osrm
   docker run -d -p 5000:5000 -v "$PWD:/data" \
     ghcr.io/project-osrm/osrm-backend osrm-routed --algorithm mld /data/india-latest.osrm
   ```
4. Test:
   `curl 'http://your-osrm:5000/match/v1/driving/77.5946,12.9716;77.5950,12.9720'`
5. Set up a monthly cron to refresh OSM data.

Valhalla: similar; use `trace_route` endpoint and `tile-extract` for India.

### Step 2 — Add the OSRM provider implementation

In `infra/supabase/functions/finalize-trip/_shared/map_matcher.ts`, add an
`OsrmProvider` class implementing `MapMatcherProvider`:

```ts
export class OsrmProvider implements MapMatcherProvider {
    readonly name = 'osrm';
    constructor(private readonly baseUrl: string) {}

    async matchSegment(points: TimedPoint[]): Promise<MatchResult> {
        // OSRM's /match endpoint accepts up to 100 points by default; chunking
        // is similar to the Google flow. POST body shape:
        //   POST /match/v1/driving/{lng1,lat1;lng2,lat2;...}?radiuses=...&geometries=geojson
        // Sum geodesic distance over `matchings[].geometry.coordinates`.
        // No 30-day cache restriction (OSM data).
        ...
        return { distanceKm, snappedPolyline, snappedPoints, notes, provider: 'osrm' };
    }
}
```

Add it to the factory switch.

### Step 3 — Flip the server env var

In Supabase project settings:

```
MAP_MATCHER_PROVIDER=osrm
OSRM_BASE_URL=http://your-osrm:5000
```

Redeploy the `finalize-trip` Edge Function. All NEW trip finalizations now
use OSRM. Historical sessions retain their Google-derived `final_km` (we
never re-snap unless an admin clicks "Verify").

### Step 4 — Flip the admin map env var

In your Next.js deployment env:

```
NEXT_PUBLIC_MAP_PROVIDER=osm
```

The legacy `MapComponent.tsx` (Leaflet/OSM) is loaded. OSRM-snapped polylines
have no ToS restriction, so we can either:

- **Option A**: continue to render only raw GPS breadcrumbs on Leaflet (simpler,
  matches today's behavior).
- **Option B**: extend `MapComponent.tsx` to also draw the OSRM-snapped polyline
  in green. Decode the `snapped_polyline` column (which now holds OSRM output,
  same encoded-polyline format as Google's) and add a `<Polyline>` for it.

We recommend Option B once you migrate — there's no ToS reason to hide the
snapped route, and it's useful for admins to see.

### Step 5 — Drop the Google API key

Once OSRM has been running healthy for a billing cycle and you've verified
finalizations on real trips, you can remove `GOOGLE_MAPS_SERVER_KEY` and
`NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY` from env. Update Google Cloud Console
to revoke or restrict the keys.

---

## 4. How to migrate OSRM → Google (the reverse)

If you ever need to revert (e.g. OSRM data quality degrades, India OSM
coverage gap discovered):

```
# Supabase env
MAP_MATCHER_PROVIDER=google_roads
GOOGLE_MAPS_SERVER_KEY=<server key with Roads API enabled>

# Next.js env
NEXT_PUBLIC_MAP_PROVIDER=google
NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY=<browser key restricted to your domains>
```

Redeploy. Done.

---

## 5. ToS reminders (Google path)

These constraints apply only while `MAP_MATCHER_PROVIDER=google_roads`.

1. **No mixing**: Roads-API-derived geometry must not be rendered on Leaflet/OSM.
   The `MapComponentGoogle.tsx` component is the only place we render
   `snapped_polyline`. The legacy `MapComponent.tsx` accepts the prop but
   silently ignores it.
2. **30-day cache limit**: `shift_sessions.snapped_polyline` and
   `polyline_expires_at` are nulled by `purge_expired_snapped_polylines()` —
   either via `pg_cron` (set up in migration 074) or by the `finalize-trip`
   Edge Function on each tick. `final_km` (a number derived from Roads output)
   is kept indefinitely as a business record.
3. **Place IDs**: free to cache indefinitely if we ever store them.
4. **Asset tracking**: re-confirm with Google / reseller every 12 months that
   our employee-tracking use case remains within standard Roads API terms.

---

## 6. Quick reference — provider state by env

| Env | Server effect | Admin UI effect |
|---|---|---|
| `MAP_MATCHER_PROVIDER=google_roads` | Roads API for finalization | (independent) |
| `MAP_MATCHER_PROVIDER=osrm` | OSRM for finalization | (independent) |
| `NEXT_PUBLIC_MAP_PROVIDER=google` | (independent) | Google Maps + snapped polyline |
| `NEXT_PUBLIC_MAP_PROVIDER=osm` | (independent) | Leaflet + raw GPS only |

You can run them mixed (e.g. OSRM server-side + Google Maps admin UI) but
the cleanest combos are:
- **Free tier**: Google server + Google admin
- **Scale / sovereignty**: OSRM server + Leaflet admin

---

## 7. Files touched if you ever rip out Google entirely

- `infra/supabase/functions/finalize-trip/_shared/map_matcher.ts` — remove
  `GoogleRoadsProvider`, keep factory switch.
- `app/director/mobitraq/timeline/MapComponentGoogle.tsx` — delete file,
  remove dispatcher branch in `page.tsx`.
- `package.json` — remove Google Maps JS deps if any.
- Supabase env — drop `GOOGLE_MAPS_SERVER_KEY`.
- Next.js env — drop `NEXT_PUBLIC_GOOGLE_MAPS_BROWSER_KEY`.

But until you actually do this, **keep both paths intact**. Optionality is
cheap; rebuilding a path you deleted is expensive.
