# TravelMap — App Design

## Concept
Log a place you've been in under 10 seconds, see your world fill in color. Everything else (regions, stats, social) supports that core loop — nothing should slow it down.

## Design Principles
- One accent color for "visited," neutral gray for everything else. No color soup.
- Logging a visit is the fastest action in the app — never buried more than 2 taps deep.
- Map is always the hero. Stats and social are secondary tabs, not competing for attention.
- Region-level detail is opt-in depth, not a requirement — someone who only logs countries should never feel the app is unfinished.

## Navigation (Tab Bar)
1. **Map** (home) — world/continent/country map, always visible
2. **Visits** — chronological trip history and editing
3. **Stats** — % visited, breakdowns
4. **Friends** — social layer
5. **Profile** — your data and settings

A floating **+** button (visible from Map and Country views) starts the add-visit flow from anywhere.

## Screens & Flows

### 1. World Map (Home)
- Full-screen world map, visited countries filled with accent color, unvisited in neutral gray.
- Top bar: continent filter chips (All / Europe / Asia / Africa / N.America / S.America / Oceania) — tapping one zooms + filters the % shown.
- Overall % visited shown as a small badge, updates live with the continent filter.
- Tap a country → Country Detail.

### 2. Add Visit
- Search or tap-to-select country (autocomplete + map tap both work).
- Required title, plus an optional year or month/year (never a false exact day).
- Toggle: "I've been to this whole country" vs "add specific region."
- Photo picker: exactly 4 slots, square crop, optional (can save with 0 photos and add later).
- Save → country fills in immediately on the map, no confirmation screen needed.
- Existing visits can be edited later, including title, partial date, note, and photo set.

### 3. Visit Timeline
- All visits in reverse chronological order by when the trip happened, not when it was logged.
- Undated visits appear last.
- Tap a visit to see its title, country, date, note, and photos, then edit or delete it.

### 4. Country Detail / Region Map
- Shows the country's internal map (states/provinces/regions), regions colored the same way countries are on the world map.
- Same continent-style filter concept doesn't apply here — instead shows: country name, date range if entered, the 4 country-level photos, and % of regions visited (if using region mode for that country).
- Tap a region → same 4-photo add flow, scoped to that region.
- Countries with no meaningful subdivision (e.g., small island nations) skip region mode entirely and just show the photos/notes screen.

### 5. Stats
- Big number: % of world visited (by country).
- Per-continent breakdown: simple horizontal bars, % + country count (e.g., "Europe — 62% · 28/45").
- Optional secondary stat once region data exists: "% of [country] explored," shown only for countries where regions have been logged.

### 6. Friends & Social
- Add friend via a personal short code or QR (scan or share sheet).
- Friends list → tap a friend → see their world map (read-only), their stats, and drill into their countries/regions to see their 4 photos.
- Comments: lightweight, per-country or per-region, threaded flat (no replies-to-replies) — keep it a guestbook, not a feed.
- No public feed/discovery — this stays friend-code-based and private by design, which also keeps v1 simple.

### 7. Profile
- Your own map/stats shortcut, your code/QR for others to add you, account/export, privacy toggle (who can see your map — friends only vs link-shareable read-only view).

## Data Model
```
User
 ├─ id, display_name, friend_code, avatar

Visit (country-level)
 ├─ id, user_id, country_code, title, visited_at (optional), date_precision, created_at
 ├─ photos[4] (storage URLs)
 └─ note (optional short text)

RegionVisit
 ├─ id, user_id, country_code, region_code, visited_at (optional)
 ├─ photos[4]
 └─ note (optional)

Friendship
 ├─ user_id, friend_id, status (pending/accepted)

Comment
 ├─ id, author_id, target_user_id, target_type (country/region), target_code, text, created_at
```
Percentages are always derived, never stored: `visited_count / total_count` per continent and globally, computed client-side from the country/region reference table.

## Map Data Strategy
- **Countries:** Natural Earth (public domain) admin-0 GeoJSON — clean, small, standard reference for "which countries exist" and their borders.
- **Regions:** Natural Earth admin-1 GeoJSON covers most countries' states/provinces at a usable simplification level for mobile. A handful of small countries have no admin-1 subdivision — those fall back to country-only mode automatically (no manual list-maintenance needed).
- Pre-process both into simplified, bundled GeoJSON (topojson to cut file size) rather than fetching live — keeps the map instant and offline-capable, which matters more here than always-fresh borders.

## Tech Stack Recommendation
Given your Next.js/TypeScript/Supabase background and the new Mac:

- **App:** SwiftUI + MapKit overlays (`MKPolygon`/`MKPolygonRenderer` for the fill-in effect). Native is worth it here specifically because you're rendering hundreds of custom-colored map polygons at 60fps — that's a place where React Native/Expo's map libraries get noticeably janky, and this app lives or dies on the map feeling instant.
- **Backend:** Supabase — Postgres for visits/friendships/comments, Storage for the photos, Auth for accounts, Realtime not needed for v1. You already know this stack, so backend velocity stays high while you're learning SwiftUI.
- **Friend code/QR:** generate a short code server-side, QR is just that code encoded — no extra infra.

If you'd rather stay in TypeScript end-to-end and accept some map performance trade-offs, Expo + `react-native-maps` (or Mapbox GL Native via Expo) is the fallback — same Supabase backend either way.

## MVP Phasing
- **V1:** World map, continent filter, country-level add-visit with 4 photos, overall + per-continent %. No regions, no social. Ship this first — it's the whole core loop.
- **V2:** Region mode — country detail map, region add-visit, per-country % explored.
- **V3:** Friends — code/QR add, read-only friend maps, comments.
