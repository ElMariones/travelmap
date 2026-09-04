#!/usr/bin/env node
// Builds Shared/WidgetMapData/worldmap.json — the tiny world the widget draws.
//
//   node scripts/build-widgetmap.mjs
//
// Reads the already-bundled countries.geojson, so it needs no network and no mapshaper.
// The output is committed; re-run it only after build-mapdata.mjs changes the source.
//
// Why a second, smaller copy of the same world: the widget can't use MapKit, runs in a
// 40 MB process, and draws the map at about 150 points across. countries.geojson is
// 490 KB of detail sized for a full-screen pinch-zoomable map, and every byte of it would
// have to be parsed on a background refresh to draw shapes a few pixels wide.

import fs from 'node:fs';
import path from 'node:path';

const SRC = path.join(import.meta.dirname, '..', 'TravelMap', 'Resources', 'MapData', 'countries.geojson');
const OUT_DIR = path.join(import.meta.dirname, '..', 'Shared', 'WidgetMapData');
const OUT = path.join(OUT_DIR, 'worldmap.json');

// Equirectangular, cropped to where the land is. Dropping Antarctica and the empty north
// buys about 25% more height for everything anyone has actually been to.
const MIN_LON = -180, MAX_LON = 180;
const MIN_LAT = -56, MAX_LAT = 83;

// x runs across a 0…10000 grid; at widget size that is far below a pixel, and integers
// make the file about a third the size of the same numbers as floats.
//
// y is scaled by the *same* factor as x rather than being stretched to fill its own 0…10000
// range. That keeps the stored coordinates already proportional, so the drawing code can
// scale both axes by one number and never has to know the projection's aspect ratio —
// which is exactly the sort of constant that gets applied in one place and forgotten in
// another, leaving every country subtly the wrong shape.
const GRID = 10000;
const HEIGHT = Math.round(GRID * ((MAX_LAT - MIN_LAT) / (MAX_LON - MIN_LON)));

// Simplification tolerance in grid units. 14/10000 of the map width is roughly a fifth of
// a pixel on a large widget.
const TOLERANCE = 14;

// A ring smaller than this in grid units squared can't render as more than a speck. Every
// country keeps its largest ring regardless, so nothing vanishes from the map entirely.
const MIN_RING_AREA = 90;

const CONTINENT_KEYS = {
  Africa: 'AF', Asia: 'AS', Europe: 'EU',
  'North America': 'NA', 'South America': 'SA', Oceania: 'OC',
};

function project([lon, lat]) {
  const scale = GRID / (MAX_LON - MIN_LON);
  const x = (lon - MIN_LON) * scale;
  // Latitude runs the other way from screen y.
  const y = (MAX_LAT - lat) * scale;
  return [Math.round(x), Math.round(y)];
}

/** Perpendicular distance from p to the segment ab. */
function distanceToSegment(p, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1];
  if (dx === 0 && dy === 0) return Math.hypot(p[0] - a[0], p[1] - a[1]);
  const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
}

/** Ramer–Douglas–Peucker, iterative so a long coastline can't blow the stack. */
function simplify(points, tolerance) {
  if (points.length < 3) return points;
  const keep = new Uint8Array(points.length);
  keep[0] = keep[points.length - 1] = 1;
  const stack = [[0, points.length - 1]];

  while (stack.length) {
    const [first, last] = stack.pop();
    let index = -1, furthest = tolerance;
    for (let i = first + 1; i < last; i++) {
      const d = distanceToSegment(points[i], points[first], points[last]);
      if (d > furthest) { furthest = d; index = i; }
    }
    if (index !== -1) {
      keep[index] = 1;
      stack.push([first, index], [index, last]);
    }
  }
  return points.filter((_, i) => keep[i]);
}

/** Shoelace area, unsigned. */
function area(points) {
  let sum = 0;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    sum += points[j][0] * points[i][1] - points[i][0] * points[j][1];
  }
  return Math.abs(sum) / 2;
}

/** Mean of a set of already-projected points. */
function centroid(points) {
  const sum = points.reduce((acc, p) => [acc[0] + p[0], acc[1] + p[1]], [0, 0]);
  return [Math.round(sum[0] / points.length), Math.round(sum[1] / points.length)];
}

/** A small diamond, so a country too small to draw is still somewhere on the map. */
function marker([x, y], radius = 22) {
  return [[x, y - radius], [x + radius, y], [x, y + radius], [x - radius, y]];
}

/** Drops consecutive duplicates left behind by rounding onto the grid. */
function dedupe(points) {
  const out = [];
  for (const p of points) {
    const last = out[out.length - 1];
    if (!last || last[0] !== p[0] || last[1] !== p[1]) out.push(p);
  }
  return out;
}

const source = JSON.parse(fs.readFileSync(SRC, 'utf8'));
const countries = [];
let totalPoints = 0;

for (const feature of source.features) {
  const { code, continent } = feature.properties;
  const polygons = feature.geometry.type === 'Polygon'
    ? [feature.geometry.coordinates]
    : feature.geometry.coordinates;

  // Outer rings only. A widget-sized country has no room for a hole in it, and keeping
  // them would mean an even-odd fill and roughly double the points.
  const rings = [];
  for (const polygon of polygons) {
    const ring = simplify(dedupe(polygon[0].map(project)), TOLERANCE);
    if (ring.length >= 3) rings.push(ring);
  }

  // Forty micro-states — Singapore, Malta, Monaco, most of the Pacific — simplify away to
  // nothing at this scale. Dropping them would mean a user who has been to Singapore and
  // nowhere else looks at a completely empty map. They get a marker instead: not their
  // real outline, but present, in the right place, and visibly theirs.
  if (rings.length === 0) {
    const projected = polygons.flatMap((polygon) => polygon[0].map(project));
    rings.push(marker(centroid(projected)));
  }

  rings.sort((a, b) => area(b) - area(a));
  const kept = rings.filter((ring, index) => index === 0 || area(ring) >= MIN_RING_AREA);

  totalPoints += kept.reduce((sum, ring) => sum + ring.length, 0);
  countries.push({
    c: code,
    k: CONTINENT_KEYS[continent] ?? '',
    // Flattened to [x, y, x, y, …]: half the JSON brackets of nested pairs, and it decodes
    // straight into a flat Swift array.
    r: kept.map((ring) => ring.flat()),
  });
}

countries.sort((a, b) => a.c.localeCompare(b.c));

fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(OUT, JSON.stringify({
  version: 1,
  grid: GRID,
  height: HEIGHT,
  bounds: { minLon: MIN_LON, maxLon: MAX_LON, minLat: MIN_LAT, maxLat: MAX_LAT },
  countries,
}));

const kb = (fs.statSync(OUT).size / 1024).toFixed(0);
console.log(`wrote ${OUT} (${kb} KB, ${countries.length} countries, ${totalPoints} points)`);
