# TravelMap

Log the countries you've been to and watch your world fill in with colour.

An iOS app built around one idea: logging a place should take under ten seconds and never
be more than two taps away. The map is the hero — save a visit and the country fills in
straight away, with the percentage badge ticking up behind the sheet.

**iOS 26+ · SwiftUI · Liquid Glass · MapKit · Supabase**

## What it does

- **World map** — 236 countries as MapKit overlays, visited ones filled with the accent
  colour, everything else neutral gray
- **Continent filter** — chips fly the camera and re-scope the live percentage
- **Log a visit** — search a country, add an optional date, note and up to four photos
- **Stats** — how much of the world you've seen, broken down by continent
- **Sign in with Apple**, or email and password

Countries and borders come from [Natural Earth](https://www.naturalearthdata.com), bundled
and pre-simplified so the map is instant and works offline.

## Getting started

1. Create a [Supabase](https://supabase.com) project and run
   [`supabase/schema.sql`](supabase/schema.sql) in its SQL editor.
2. Copy the credentials template and fill in your project URL and **publishable** key:
   ```bash
   cp Config.xcconfig.example Config.xcconfig
   ```
3. Open `TravelMap.xcodeproj` and run. Requires Xcode 26+.

Launching without step 2 is safe — the app detects the placeholder values and shows a
setup screen instead of failing at the first network call.

Sign in with Apple additionally needs an Apple Developer team and Supabase's Apple
provider enabled; email and password work without either.

## Status

V1 is complete: countries, photos, stats. Regions and the social layer are in the database
schema but have no UI yet.

**Full technical documentation — architecture, every file, known constraints and the
roadmap — lives in [AGENTS.md](AGENTS.md).**

## Licence

Not yet licensed. Natural Earth data is public domain.
