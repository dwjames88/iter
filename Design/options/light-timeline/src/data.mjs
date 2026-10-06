// data.mjs - the real data (Bixby Bridge, Tue Oct 6 2026, OpenWeather, updated 11:50, now 11:50) and sky helpers.
// Exports: toMin, fmt, frac, WINDOW_KINDS, SPOT, SUN, windowsToday, windowsTomorrow, HOURS, NOW_MIN, MARKER_MIN, LIST_ROWS,
//          sunAltitude(min, sun?), skyColor(alt), skyStops({lo,hi}, dir, sun?), skyGradient({lo,hi}, dir, sun?), windowUnder(min, windows)
import { c } from '../../../paper/tools/lib/tokens.mjs';
import { bandFor } from '../../../paper/tools/lib/lightindex.mjs';

/** 'HH:MM' -> minutes since midnight. */
export const toMin = (s) => { const [h, m] = s.split(':').map(Number); return h * 60 + m; };
/** minutes -> 'HH:MM' (24 -> '24:00' is shown as '00:00'). */
export const fmt = (m) => `${String(Math.floor(m / 60) % 24).padStart(2, '0')}:${String(Math.round(m % 60)).padStart(2, '0')}`;
/** minute -> 0..1 within a domain {lo,hi} (minutes). Default domain is the full day. */
export const frac = (min, dom = { lo: 0, hi: 1440 }) => (min - dom.lo) / (dom.hi - dom.lo);

export const WINDOW_KINDS = {
  blueMorning: { short: 'Blue AM', name: 'Morning blue hour', symbol: 'sun.horizon' },
  goldenMorning: { short: 'Sunrise', name: 'Sunrise', symbol: 'sunrise' },
  goldenEvening: { short: 'Sunset', name: 'Sunset', symbol: 'sunset' },
  blueEvening: { short: 'Blue PM', name: 'Evening blue hour', symbol: 'moon.haze' },
  night: { short: 'Night', name: 'Night', symbol: 'moon.stars' },
};
const W = (kind, a, b, score) => ({ kind, short: WINDOW_KINDS[kind].short, startMin: toMin(a), endMin: toMin(b), start: a, end: b,
  scored: typeof score === 'number', score, band: typeof score === 'number' ? bandFor(score) : null });

export const SPOT = { name: 'Bixby Bridge', locality: 'Big Sur, CA', origin: 'Curated', distance: '101 mi', facing: 'Faces 170° S', walkIn: '5 min walk-in', best: 'Best at sunset',
  source: 'OpenWeather', updated: '11:50', day: 'Tue, Oct 6, 2026', next: { kind: 'goldenEvening', score: 76, time: '18:09' } };
export const SUN = { sunrise: toMin('07:08'), sunset: toMin('18:43') };
export const NOW_MIN = toMin('11:50');
export const MARKER_MIN = toMin('18:26');

export const windowsToday = [
  W('blueMorning', '06:43', '07:08'), W('goldenMorning', '07:08', '07:43'),
  W('goldenEvening', '18:09', '18:43', 76), W('blueEvening', '18:43', '19:09', 78), W('night', '20:08', '23:08', 79),
];
export const windowsTomorrow = [
  W('blueMorning', '06:42', '07:07', 74), W('goldenMorning', '07:07', '07:42', 66),
  W('goldenEvening', '18:07', '18:42', 67), W('blueEvening', '18:42', '19:07', 75), W('night', '20:07', '23:07', 86),
];
/** Hourly cloud cover (fraction). OpenWeather: one series, no layers. Forecast starts 11:00. Chance of rain 0 all day. */
export const HOURS = [[11, 85], [12, 87], [13, 88], [14, 89], [15, 88], [16, 72], [17, 42], [18, 30], [19, 12], [20, 7], [21, 8], [22, 10], [23, 11]]
  .map(([h, p]) => ({ h, min: h * 60, cloud: p / 100, rain: 0 }));

/** The window under a minute (or null). */
export const windowUnder = (min, windows = windowsToday) => windows.find((w) => min >= w.startMin && min < w.endMin) || null;

/** The Explore list, in order. All rows use the sunset symbol. */
export const LIST_ROWS = [
  ['Golden Gate from Battery Spencer', 'Marin Headlands, CA', 6, 67, '18:10'], ['Point Reyes Lighthouse', 'Point Reyes National Seashore, CA', 36, 31, '18:12'],
  ['Bixby Bridge', 'Big Sur, CA', 101, 76, '18:09'], ['Keyhole Arch, Pfeiffer Beach', 'Big Sur, CA', 111, 70, '18:09'],
  ['McWay Falls', 'Julia Pfeiffer Burns State Park, CA', 119, 45, '18:08'], ['Emerald Bay', 'Lake Tahoe, CA', 150, 66, '17:59'],
  ['Tunnel View', 'Yosemite National Park, CA', 150, 66, '17:59'], ['Valley View', 'Yosemite National Park, CA', 151, 66, '17:58'],
  ['Glacier Point', 'Yosemite National Park, CA', 155, 66, '17:58'], ['South Tufa, Mono Lake', 'Lee Vining, CA', 185, 67, '17:56'],
  ['Bodie Ghost Town', 'Bodie State Historic Park, CA', 188, 66, '17:55'], ['Convict Lake', 'Mammoth Lakes, CA', 195, 67, '17:55'],
  ['Lake Sabrina', 'Bishop Creek, CA', 212, 68, '17:55'], ['Ancient Bristlecone Pine Forest', 'White Mountains, CA', 234, 66, '17:53'],
].map(([name, locality, mi, score, time]) => ({ name, locality, mi, score, time, kind: 'goldenEvening' }));

// ---- sky ----------------------------------------------------------------------------------------------------------------
/** Approximate sun altitude (degrees) at a minute of day. Piecewise linear through -18/-6/0/+6 landmarks, peak ~38 at solar noon. */
export function sunAltitude(min, sun = SUN) {
  const { sunrise: sr, sunset: ss } = sun;
  const noon = (sr + ss) / 2;
  const pts = [[sr - 75, -18], [sr - 25, -6], [sr, 0], [sr + 35, 6], [sr + 90, 14], [noon, 38], [ss - 90, 14], [ss - 35, 6], [ss, 0], [ss + 25, -6], [ss + 75, -18]];
  if (min <= pts[0][0]) return Math.max(-40, -18 - (pts[0][0] - min) * 0.2);
  if (min >= pts[pts.length - 1][0]) return Math.max(-40, -18 - (min - pts[pts.length - 1][0]) * 0.2);
  for (let i = 0; i < pts.length - 1; i++) {
    const [a, av] = pts[i], [b, bv] = pts[i + 1];
    if (min >= a && min <= b) return av + ((bv - av) * (min - a)) / (b - a);
  }
  return 0;
}
/** COMPONENTS.md LightTimeline s3: <-18 night; -18..-6 night->blueHour; -6..horizon blueHour; across horizon blueHour->golden; to +6 golden; +6..+14 golden->day; day. */
export function skyColor(alt) {
  const mix = (a, b, t) => (t <= 0.004 ? c(a) : t >= 0.996 ? c(b) : `color-mix(in srgb, ${c(b)} ${Math.round(t * 1000) / 10}%, ${c(a)})`);
  if (alt < -18) return mix('sky/night', 'sky/night', 0);
  if (alt < -6) return mix('sky/night', 'sky/blueHour', (alt + 18) / 12);
  if (alt < -0.8) return mix('sky/blueHour', 'sky/blueHour', 0);
  if (alt < 0.8) return mix('sky/blueHour', 'sky/golden', (alt + 0.8) / 1.6);
  if (alt < 6) return mix('sky/golden', 'sky/golden', 0);
  if (alt < 14) return mix('sky/golden', 'sky/day', (alt - 6) / 8);
  return mix('sky/day', 'sky/day', 0);
}
/** Gradient stops for a time domain: [{pos: 0..1, css}] (colours resolve with the current theme). */
export function skyStops(dom = { lo: 0, hi: 1440 }, sun = SUN, step = 2) {
  const out = [];
  for (let m = dom.lo; m <= dom.hi + 1e-6; m += step) out.push({ min: m, pos: frac(Math.min(m, dom.hi), dom), css: skyColor(sunAltitude(m, sun)) });
  if (out[out.length - 1].min < dom.hi) out.push({ min: dom.hi, pos: 1, css: skyColor(sunAltitude(dom.hi, sun)) });
  return out.filter((s, i, a) => i === 0 || i === a.length - 1 || !(a[i - 1].css === s.css && a[i + 1].css === s.css));
}
/** CSS gradient for a domain. dir: 'to right' (time left->right) | 'to bottom' (time top->bottom). */
export function skyGradient(dom = { lo: 0, hi: 1440 }, dir = 'to right', sun = SUN) {
  return `linear-gradient(${dir}, ${skyStops(dom, sun).map((s) => `${s.css} ${Math.round(s.pos * 10000) / 100}%`).join(', ')})`;
}
