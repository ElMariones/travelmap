# TravelMap

Log the countries you've been to and watch your world fill in with colour.

iOS 17+ · SwiftUI · MapKit · Supabase

<!-- Scope: V1 only. See "What's built" below. -->

## What's built

**V1 — the core loop, working end to end:**

- **Auth** — email + password via Supabase Auth
- **World map** — every country drawn as a MapKit overlay, filled with the accent
  colour when visited and neutral gray when not, over a deliberately muted base map
- **Continent filter** — chips across the top fly the camera and re-scope the live
  percentage badge
- **Add a visit** — searchable country list, optional date and note, up to four photos
  uploaded to Supabase Storage; the country fills in on the map immediately
- **Country detail** — tap a country for your visits, notes, and photos, or to log it
- **Stats** — overall percentage plus a per-continent breakdown
- **Profile** — display name, friend code, sign out

**Not built yet.** The database schema covers all of it, so none of this needs a
schema change:

- **V2** — region mode: per-country region maps and region-level visits.
  `region_visits` exists and `regions.geojson` is already bundled and parsed by the
  same pipeline; there's no UI.
- **V3** — friends: add by code or QR, read-only friend maps, per-country comments.
  `friendships` and `comments` exist with RLS policies; there's no UI.

## Setup

### 1. Supabase

Create a project at [supabase.com](https://supabase.com), then:

1. Open **SQL Editor** and run the whole of [`supabase/schema.sql`](supabase/schema.sql).
   It creates the tables, the row-level-security policies, the `profiles` trigger, and
   the private `visit-photos` storage bucket.
2. Go to **Authentication → Providers → Email**. For local development you'll probably
   want **Confirm email** off, so a new account is signed in immediately. With it on,
   the app tells you to check your inbox and then sign in — both paths work.
3. Copy your project URL and anon key from **Project Settings → API**.

### 2. Credentials

```bash
cp Config.xcconfig.example Config.xcconfig
```

Fill in the two values. `Config.xcconfig` is git-ignored; the `.example` template is
what's committed, so keys never reach the repository.

The anon key is meant to ship inside a client — row-level security is what actually
protects the data. Don't put the `service_role` key here.

Launching without this step is safe: the app detects the placeholder values and shows a
setup screen instead of failing at the first network call.

### 3. Run

```bash
open TravelMap.xcodeproj
```

Pick an iPhone simulator and run. Requires Xcode 16+ and the iOS 17 SDK or newer;
`supabase-swift` resolves automatically through Swift Package Manager.

The project file is generated from [`project.yml`](project.yml) by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and committed, so you don't need
XcodeGen to build. If you change the target's structure, regenerate it:

```bash
xcodegen generate
```

**Before deploying to a device**, change the bundle identifier from the placeholder
`com.placeholder.travelmap` in `project.yml` (or in Xcode's target settings) and set
your development team.

## Architecture

```
TravelMap/
  Models/         Country, Continent, Visit, Profile
  ViewModels/     SessionStore (auth), VisitStore (visits + derived stats)
  Views/          Map/, AddVisit/, Stats/, Profile/, Auth/
  Services/       SupabaseClient, AuthService, VisitsService, GeoDataService
  Resources/      MapData/ (bundled GeoJSON), Assets.xcassets
supabase/
  schema.sql      Tables, RLS policies, triggers, storage bucket
scripts/
  build-mapdata.mjs   Regenerates the bundled GeoJSON from Natural Earth
```

A few decisions worth knowing about:

**Percentages are derived, never stored.** `VisitStore` computes them from the bundled
reference country set against the user's visits, so there's no counter to drift.

**The map is `MKMapView`, not SwiftUI's `Map`.** One `MKMultiPolygon` overlay per
country, and `MKMultiPolygonRenderer` lets a single country recolour in place when you
save a visit rather than rebuilding the other 235.

**Map taps are hit-tested against the polygons directly**, not against renderer state,
so a tap resolves the same way whether or not MapKit has drawn that country yet.

**Photos live in a private bucket.** `visits.photo_urls` holds Storage *object paths*,
not URLs; the app swaps them for short-lived signed URLs at display time. The column
name comes from the original data model and was kept as-is.

## Map data

Countries and regions both come from [Natural Earth](https://www.naturalearthdata.com)
(public domain) and are bundled rather than fetched, which keeps the map instant and
works offline.

| File | Source | Simplification | Size |
| --- | --- | --- | --- |
| `countries.geojson` | admin-0, 1:50m | 20%, dissolved by ISO alpha-2 | ~490 KB, 236 countries |
| `regions.geojson` | admin-1, 1:10m | 5%, dissolved by ISO 3166-2 | ~2.7 MB, 4,477 regions |

To rebuild them (needs network and `npm install -g mapshaper`):

```bash
node scripts/build-mapdata.mjs
```

The reference set of 236 countries is every Natural Earth admin-0 entry that has an ISO
3166-1 alpha-2 code, minus Antarctica. That includes dependencies with their own codes,
such as Greenland and Puerto Rico. Somaliland, Northern Cyprus, and the Siachen Glacier
have no ISO alpha-2 code and are left out.

## Known limitation: the world doesn't fit

MapKit hard-clamps a flat map's camera at about 38,500 km out. On a portrait iPhone
that works out to roughly 95 degrees of longitude, so the "All" view is MapKit's widest
possible framing rather than the literal whole globe — you pan or use the continent
chips to reach the rest. This is a MapKit constraint, not a tuning value: asking for a
wider camera returns the same clamped result, in both the flat and realistic elevation
styles.
