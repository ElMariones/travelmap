#!/usr/bin/env node
// Rebuilds TravelMap/Resources/MapData/{countries,regions}.geojson from Natural Earth.
//
//   node scripts/build-mapdata.mjs
//
// Requires network access and mapshaper (`npm install -g mapshaper`). The output is
// committed, so this only needs re-running when the Natural Earth data itself changes.

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';

const NE = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson';
const ADMIN0_URL = `${NE}/ne_50m_admin_0_countries.geojson`;
const ADMIN1_URL = `${NE}/ne_10m_admin_1_states_provinces.geojson`;

// Vertex budget: enough detail to read a border on a phone, small enough to bundle.
const COUNTRY_SIMPLIFY = '20%';
const REGION_SIMPLIFY = '5%';

const outDir = path.join(import.meta.dirname, '..', 'TravelMap', 'Resources', 'MapData');
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'travelmap-mapdata-'));

// Natural Earth files CONTINENT "Seven seas (open ocean)" for a handful of island
// territories; REGION_UN puts each of them in a real continent bucket.
const REGION_UN_FALLBACK = { Americas: 'South America', Africa: 'Africa', Asia: 'Asia', Europe: 'Europe', Oceania: 'Oceania' };
const CONTINENTS = new Set(['Africa', 'Asia', 'Europe', 'North America', 'South America', 'Oceania']);

async function download(url, dest) {
  process.stdout.write(`downloading ${path.basename(url)} ... `);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} for ${url}`);
  fs.writeFileSync(dest, Buffer.from(await res.arrayBuffer()));
  console.log(`${(fs.statSync(dest).size / 1e6).toFixed(1)} MB`);
}

function mapshaper(input, simplify, dissolveBy, copyFields, output) {
  execFileSync('mapshaper', [
    input,
    '-simplify', 'visvalingam', 'weighted', `percentage=${simplify}`, 'keep-shapes',
    '-dissolve', dissolveBy, `copy-fields=${copyFields}`,
    '-o', output, 'force',
  ], { stdio: ['ignore', 'ignore', 'inherit'] });
}

function normalizeCountries(srcPath, destPath) {
  const src = JSON.parse(fs.readFileSync(srcPath, 'utf8'));
  const kept = [];
  const dropped = [];

  for (const f of src.features) {
    const p = f.properties;
    // ISO_A2 is "-99" for a few entries (Norway, France, Kosovo) that ISO_A2_EH fills in.
    const code = p.ISO_A2_EH !== '-99' ? p.ISO_A2_EH : p.ISO_A2;
    if (!/^[A-Z]{2}$/.test(code)) { dropped.push(`${p.NAME} (no ISO alpha-2)`); continue; }
    if (code === 'AQ') { dropped.push(`${p.NAME} (not a destination country)`); continue; }

    let continent = p.CONTINENT;
    if (!CONTINENTS.has(continent)) continent = REGION_UN_FALLBACK[p.REGION_UN];
    if (!CONTINENTS.has(continent)) { dropped.push(`${p.NAME} (continent "${p.CONTINENT}")`); continue; }

    kept.push({
      type: 'Feature',
      properties: { code, name: p.NAME_EN || p.NAME_LONG || p.NAME, continent },
      geometry: f.geometry,
    });
  }

  fs.writeFileSync(destPath, JSON.stringify({ type: 'FeatureCollection', features: kept }));
  console.log(`countries: kept ${kept.length} features, dropped ${dropped.length} (${dropped.join('; ')})`);
  return new Set(kept.map((f) => f.properties.code));
}

function normalizeRegions(srcPath, destPath, validCountries) {
  const src = JSON.parse(fs.readFileSync(srcPath, 'utf8'));
  const kept = [];
  let dropped = 0;
  let synthetic = 0;

  for (const f of src.features) {
    const p = f.properties;
    const country = p.iso_a2;
    if (!validCountries.has(country)) { dropped++; continue; }

    // iso_3166_2 is authoritative where Natural Earth has it; the rest fall back to
    // NE's own stable adm1_code so every region still gets a unique key.
    let code = p.iso_3166_2;
    if (!new RegExp(`^${country}-[A-Z0-9]+$`).test(code)) {
      code = `${country}-NE${p.adm1_code}`;
      synthetic++;
    }

    kept.push({
      type: 'Feature',
      properties: { code, country, name: p.name_en || p.name || code },
      geometry: f.geometry,
    });
  }

  fs.writeFileSync(destPath, JSON.stringify({ type: 'FeatureCollection', features: kept }));
  console.log(`regions: kept ${kept.length} features, dropped ${dropped}, ${synthetic} used a fallback code`);
}

const admin0 = path.join(tmp, 'admin0.geojson');
const admin1 = path.join(tmp, 'admin1.geojson');
await download(ADMIN0_URL, admin0);
await download(ADMIN1_URL, admin1);

const countriesNormalized = path.join(tmp, 'countries-normalized.geojson');
const regionsNormalized = path.join(tmp, 'regions-normalized.geojson');
const countryCodes = normalizeCountries(admin0, countriesNormalized);
normalizeRegions(admin1, regionsNormalized, countryCodes);

fs.mkdirSync(outDir, { recursive: true });
mapshaper(countriesNormalized, COUNTRY_SIMPLIFY, 'code', 'name,continent', path.join(outDir, 'countries.geojson'));
mapshaper(regionsNormalized, REGION_SIMPLIFY, 'code', 'country,name', path.join(outDir, 'regions.geojson'));
fs.rmSync(tmp, { recursive: true, force: true });

for (const name of ['countries.geojson', 'regions.geojson']) {
  const p = path.join(outDir, name);
  console.log(`wrote ${p} (${(fs.statSync(p).size / 1024).toFixed(0)} KB, ${JSON.parse(fs.readFileSync(p, 'utf8')).features.length} features)`);
}
