# Agent Prompt — Build TravelMap (iOS) from Zero

You are starting a new iOS app called **TravelMap** from an empty folder. Read this whole prompt before writing any code. Your job for this session is to get a real, running V1 committed to git — not a mockup, not a partial scaffold that doesn't build.

## What the app is
A minimalist app to log which countries (and eventually regions) a user has visited, with a colored world map as the main view, live percentage stats, and a lightweight social layer to see friends' maps. Full product spec is below — build V1 only in this session (see "Scope for this session").

## Tech stack (non-negotiable)
- **Swift 5.10+ / SwiftUI**, iOS 17 minimum deployment target
- **MapKit** for the map (`MKPolygon` / `MKPolygonRenderer` overlays for country fills) — do not substitute a third-party map SDK
- **Supabase** as backend: Postgres (data), Storage (photos), Auth. Use the official `supabase-swift` package via Swift Package Manager
- **MVVM** architecture: `Views/`, `ViewModels/`, `Models/`, `Services/`
- No CocoaPods. SPM only.

## Step 1 — Git, before anything else
1. `git init` in the project root.
2. Add a `.gitignore` appropriate for Xcode/Swift (exclude `xcuserdata/`, `.build/`, `DerivedData/`, `*.xcworkspace` user state, `.env`).
3. Make an initial commit with just the `.gitignore` and a `README.md` stub.
4. Commit again after each meaningful step below (Xcode project created, schema added, each screen working) — small, real commits with clear messages, not one giant commit at the end.
5. Do not commit any Supabase keys. Put them in a `.env`/`Config.xcconfig` that's git-ignored, and add a `Config.xcconfig.example` template that IS committed.

## Step 2 — Project scaffold
1. Create the Xcode project (App target, SwiftUI lifecycle), bundle id `com.<placeholder>.travelmap` — use a placeholder, note in the README that it needs to be changed before real device deployment.
2. Add the `supabase-swift` package dependency via SPM.
3. Set up the folder structure:
   ```
   TravelMap/
     Models/
     ViewModels/
     Views/
       Map/
       AddVisit/
       Stats/
       Profile/
     Services/
       SupabaseClient.swift
     Resources/
       MapData/        <- bundled GeoJSON
   ```

## Step 3 — Supabase schema
Write and commit a `supabase/schema.sql` implementing this data model (regions/friends tables included now even though the UI for them isn't built until V2/V3 — don't redesign the schema later):

```sql
-- users handled by Supabase Auth; extend with a profile table
create table profiles (
  id uuid primary key references auth.users(id),
  display_name text not null,
  friend_code text unique not null,
  avatar_url text
);

create table visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) not null,
  country_code text not null,        -- ISO 3166-1 alpha-2
  visited_at date,
  note text,
  photo_urls text[],                 -- up to 4
  created_at timestamptz default now()
);

create table region_visits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id) not null,
  country_code text not null,
  region_code text not null,
  visited_at date,
  note text,
  photo_urls text[],
  created_at timestamptz default now()
);

create table friendships (
  user_id uuid references profiles(id) not null,
  friend_id uuid references profiles(id) not null,
  status text not null check (status in ('pending','accepted')),
  primary key (user_id, friend_id)
);

create table comments (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references profiles(id) not null,
  target_user_id uuid references profiles(id) not null,
  target_type text not null check (target_type in ('country','region')),
  target_code text not null,
  text text not null,
  created_at timestamptz default now()
);
```
Add Row Level Security policies: users can read/write their own `visits`/`region_visits`/`profile`; `visits`/`region_visits` are readable by accepted friends too; `friendships` readable/writable only by the two parties involved.

## Step 4 — Map data
1. Source Natural Earth admin-0 (countries) GeoJSON, simplify it (reduce vertex count — mobile doesn't need survey-grade borders), and bundle it in `Resources/MapData/countries.geojson`.
2. Also fetch admin-1 (regions) and bundle it as `regions.geojson`, even though it's not wired into the UI until V2 — get the asset pipeline right once.
3. Write a small parser/loader service that reads the bundled GeoJSON into `MKPolygon` overlays keyed by ISO country code, so the world map can look up "is this country visited" and pick a fill color.

## Step 5 — Build V1 screens (this session's actual deliverable)
Implement exactly these, end to end, wired to Supabase:
1. **Auth**: simple email/password sign-in via Supabase Auth (magic link is fine too — pick one, don't build both).
2. **World Map (home)**: full map, visited countries filled with the accent color, continent filter chips, live overall % badge.
3. **Add Visit**: search/select a country, optional date, 4-photo picker (upload to Supabase Storage), save → country fills in immediately.
4. **Stats**: overall %, per-continent bar breakdown.
5. **Profile (stub is fine)**: shows the user's friend code, sign-out button.
Tab bar: Map / Stats / Profile. No regions UI, no friends UI, no comments yet — those are out of scope for this session (schema exists, UI doesn't).

## Definition of done — verify before you stop
- [ ] Project builds with **zero errors and zero warnings** in Xcode
- [ ] App runs in the iOS Simulator
- [ ] You can sign in, add a visit for a real country with a photo, and watch it fill in on the map in the same run
- [ ] The % badge updates correctly after adding a visit
- [ ] `supabase/schema.sql` is committed and matches what the app actually uses
- [ ] `.env`/keys are NOT in git history; `Config.xcconfig.example` is
- [ ] Git log shows incremental commits, not one dump
- [ ] README.md explains: how to set up Supabase (env vars needed), how to run the app, and current scope (V1 only — regions and social are schema-ready but not built)

If something can't be verified in the simulator (e.g. real Supabase project not yet provisioned), say so explicitly in your final summary rather than claiming it works — don't report success on anything you haven't actually run.

## Explicitly out of scope for this session
- Region-level map/UI (V2)
- Friends/QR/comments UI (V3)
- App icon, launch screen polish, App Store metadata
- Real Apple Developer account / device deployment (simulator only is fine)
