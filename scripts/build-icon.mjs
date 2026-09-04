#!/usr/bin/env node
// Regenerates the flat layer artwork inside TravelMap/Resources/AppIcon.icon.
//
//   node scripts/build-icon.mjs
//
// The icon is a Liquid Glass icon: this script writes only *flat* SVG shapes, and the
// system does the lighting. Nothing here paints a highlight, a shadow, a bevel, or a
// rounded corner — Icon Composer and the OS own all four, and baking them in double-
// exposes against the glass the system adds on top.
//
// Two things about the renderer, both learned by looking at the Home Screen rather than
// at the file:
//
//   1. It draws *fills* and ignores `stroke`. A stroked graticule compiles cleanly and
//      renders as a blank white disc.
//   2. Its elliptical-arc support is not trustworthy — an `A`/`a` arc came out as a pie
//      wedge. So every curve below is emitted as an explicit polygon: `M`, `L`, `Z` and
//      nothing else, which leaves no room for interpretation.
//
// Neither failure produces a warning, which is why the only real check on this file is
// building it into the simulator and looking at the result.

import fs from 'node:fs';
import path from 'node:path';

const OUT = path.join(import.meta.dirname, '..', 'TravelMap', 'Resources', 'AppIcon.icon');
const ASSETS = path.join(OUT, 'Assets');

const CANVAS = 1024;

// The globe. Large and low-left, leaving the upper right for the pin.
const GLOBE = { cx: 460, cy: 570, r: 320 };
// Bold enough to survive the 60px render; the HIG's "no thin lines" is about this.
const STROKE = 30;

// The pin. `drop` is how far below the circle's centre the tip sits.
const PIN = { cx: 735, cy: 300, r: 118, drop: 210, hole: 50 };

// Flat fills, no gradients. Colours are chosen so every element contrasts with whatever
// it actually touches — the graticule only ever sits on the globe, but the pin crosses
// both the globe and the background, so it has to work against both.
const WARM_WHITE = '#FFF4EA';
const GRATICULE = '#E4623C';
const PLUM = '#6B1E3F';

// Segments per full turn. At 1024px this is well under a pixel per step.
const SEGMENTS = 180;

// ── Geometry ──────────────────────────────────────────────────────────────────────────

const round = (n) => Math.round(n * 10) / 10;

/** Points along an ellipse, from `from` to `to` radians. */
function arcPoints(cx, cy, rx, ry, from = 0, to = Math.PI * 2, segments = SEGMENTS) {
  const count = Math.max(2, Math.ceil((segments * Math.abs(to - from)) / (Math.PI * 2)));
  return Array.from({ length: count + 1 }, (_, i) => {
    const angle = from + ((to - from) * i) / count;
    return [cx + rx * Math.cos(angle), cy + ry * Math.sin(angle)];
  });
}

function pathData(...rings) {
  return rings
    .map((ring) => `M ${ring.map(([x, y]) => `${round(x)} ${round(y)}`).join(' L ')} Z`)
    .join(' ');
}

/**
 * A closed ring between two concentric ellipses, as a single polygon.
 *
 * The outer edge runs forwards and the inner edge runs back, so the shape closes on
 * itself and fills correctly under either fill rule. Relying on `fill-rule="evenodd"`
 * across two subpaths would be one more thing for the renderer to disagree about.
 */
function ringPath(cx, cy, rx, ry, thickness) {
  const half = thickness / 2;
  const outer = arcPoints(cx, cy, rx + half, ry + half);
  const inner = arcPoints(cx, cy, rx - half, ry - half).reverse();
  return pathData([...outer, ...inner]);
}

/** A horizontal capsule — the outline a round-capped line would have had. */
function capsulePath(x1, x2, y, thickness) {
  const r = thickness / 2;
  return pathData([
    ...arcPoints(x2, y, r, r, -Math.PI / 2, Math.PI / 2, 48),
    ...arcPoints(x1, y, r, r, Math.PI / 2, (Math.PI * 3) / 2, 48),
  ]);
}

/** Half-width of a parallel at vertical offset `dy`, measured to its endpoint. */
function halfChord(dy) {
  // A round cap is a disc of radius STROKE/2 centred on the endpoint, so the endpoint has
  // to sit that far inside the coastline — not on it. Measuring to the chord instead
  // leaves a nub of stroke hanging off both edges of the globe: invisible at 1024px and
  // unmistakable at 60.
  const inner = GLOBE.r - STROKE / 2;
  return Math.sqrt(Math.max(0, inner ** 2 - dy ** 2));
}

function svg(body) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CANVAS} ${CANVAS}" width="${CANVAS}" height="${CANVAS}">
${body}
</svg>
`;
}

// ── Layer 1: the globe ────────────────────────────────────────────────────────────────
// One round shape, filled. Round and solid is what the glass material renders best; the
// previous version's open arc left the system nothing to light.

const globe = svg(
  `  <path fill="${WARM_WHITE}" d="${pathData(arcPoints(GLOBE.cx, GLOBE.cy, GLOBE.r, GLOBE.r))}"/>`
);

// ── Layer 2: the graticule ────────────────────────────────────────────────────────────
// A meridian ring and three parallels, each ending exactly at the coastline.

const meridianRing = ringPath(GLOBE.cx, GLOBE.cy, 142, GLOBE.r - STROKE / 2, STROKE);

const parallels = [-160, 0, 160].map((dy) =>
  capsulePath(GLOBE.cx - halfChord(dy), GLOBE.cx + halfChord(dy), GLOBE.cy + dy, STROKE)
);

// One path, with `fill` on the path itself. Both halves of that matter: a `fill` set on a
// wrapping `<g>` is not inherited by the children — the layer renders as nothing at all —
// and every other layer here is a single element, which is the shape the renderer is
// demonstrably happy with.
//
// The subpaths overlap where the parallels cross the meridian's interior. Under the
// non-zero rule the ring's hole is winding 0 and a parallel crossing it brings that to 1,
// so the parallels stay visible through the middle of the globe, which is what a globe
// looks like.
const graticule = svg(
  `  <path fill="${GRATICULE}" d="${[meridianRing, ...parallels].join(' ')}"/>`
);

// ── Layer 3: the pin ──────────────────────────────────────────────────────────────────
// A teardrop: the two straight edges are the tangents from the tip to the circle, so the
// join is smooth by construction rather than by eye.

const tangentAngle = Math.acos(PIN.r / PIN.drop);

// The head is traced from one tangent point, the long way over the top, to the other. The
// tip closes the shape. Angles run from +x, and +y is down, so the tip lies at π/2.
const head = arcPoints(
  PIN.cx,
  PIN.cy,
  PIN.r,
  PIN.r,
  Math.PI / 2 - tangentAngle,
  Math.PI / 2 + tangentAngle - Math.PI * 2
);

const pinBody = [[PIN.cx, PIN.cy + PIN.drop], ...head];
// The head is traced with *decreasing* angle, so the hole is traced with increasing angle
// to wind the opposite way. Opposite winding is what makes it a hole under the non-zero
// rule; reversing it to match the head instead fills it back in solid.
const pinHole = arcPoints(PIN.cx, PIN.cy, PIN.hole, PIN.hole);

const pin = svg(`  <path fill="${PLUM}" d="${pathData(pinBody, pinHole)}"/>`);

// ── The document ──────────────────────────────────────────────────────────────────────
// Three depth groups. Each gets its own shadow and specular treatment, which is the whole
// reason to separate them: the pin should read as sitting above the globe, and it only
// does that if the system can cast one onto the other.
//
// **Groups are ordered front to back**, not back to front — `groups[0]` is the topmost
// layer. Getting this backwards paints the opaque globe over everything else, and the
// symptom is not an error but an icon that is simply a white disc with the pin sliced off
// at the coastline.

const icon = {
  fill: {
    // Derived from the app's accent, so the icon and the app agree on what colour
    // TravelMap is. A colour field rather than a neutral one, so the light, dark and
    // tinted renders stay distinguishable from each other.
    'automatic-gradient': 'display-p3:0.976,0.435,0.290,1.000',
  },
  groups: [
    {
      layers: [{ 'image-name': '3-pin.svg', name: 'Pin' }],
      shadow: { kind: 'neutral', opacity: 0.5 },
      specular: true,
      translucency: { enabled: true, value: 0.5 },
    },
    {
      layers: [{ 'image-name': '2-graticule.svg', name: 'Graticule' }],
      // `neutral` and `none` are the only shadow kinds actool accepts. Anything else
      // fails the whole build with a nil-object exception out of the asset compiler that
      // names neither the file nor the key.
      shadow: { kind: 'neutral', opacity: 0.2 },
      // Specular off: these are narrow shapes, and the glass highlight makes narrow
      // shapes look inflated rather than lit.
      specular: false,
      translucency: { enabled: true, value: 0.25 },
    },
    {
      layers: [{ 'image-name': '1-globe.svg', name: 'Globe' }],
      shadow: { kind: 'neutral', opacity: 0.3 },
      specular: true,
      translucency: { enabled: true, value: 0.35 },
    },
  ],
  'supported-platforms': {
    circles: ['watchOS'],
    squares: 'shared',
  },
};

// ── Write ─────────────────────────────────────────────────────────────────────────────

fs.mkdirSync(ASSETS, { recursive: true });

// Filenames are prefixed 1…3 back to front, which is the order Icon Composer's importer
// expects — the opposite of the order `groups` is written in above.
const layers = { '1-globe.svg': globe, '2-graticule.svg': graticule, '3-pin.svg': pin };
for (const [name, contents] of Object.entries(layers)) {
  fs.writeFileSync(path.join(ASSETS, name), contents);
}

// Remove any previous generation's layers, so a renamed layer doesn't linger in the
// bundle and quietly get compiled in.
for (const stale of fs.readdirSync(ASSETS)) {
  if (!(stale in layers)) {
    fs.rmSync(path.join(ASSETS, stale));
    console.log(`removed stale layer ${stale}`);
  }
}

fs.writeFileSync(path.join(OUT, 'icon.json'), `${JSON.stringify(icon, null, 2)}\n`);
console.log(`wrote ${OUT} (${Object.keys(layers).length} layers)`);
