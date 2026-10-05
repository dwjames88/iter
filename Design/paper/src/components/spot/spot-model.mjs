// spot-model.mjs - view model and strings for the spot page (D4). Pure data, no HTML.
// Strings are from App/Sources/Spot/SpotText.swift and App/Sources/Text/LightText.swift. Numbers come from spot-raw.mjs,
// which is the real engine's output for the snapshot fixtures (see that file's header).
import { RAW } from './spot-raw.mjs';

export const artboards = [];

const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const parseDay = (s) => s.split('-').map(Number);
const dow = (y, m, d) => new Date(Date.UTC(y, m - 1, d)).getUTCDay();
export const dayLong = (y, m, d) => `${WD[dow(y, m, d)]}, ${MON[m - 1]} ${d}, ${y}`;
const dayNum = (y, m, d) => Math.round(Date.UTC(y, m - 1, d) / 86400000);
const hmMin = (s) => { const [h, mm] = s.split(':').map(Number); return h * 60 + mm; };
export const minToHM = (min) => { const m = Math.floor(min + 1e-6); return `${String(Math.floor(m / 60) % 24).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`; };
const pct = (f) => `${Math.round(f * 100)}%`;

export const INTENTS = [['sunrise', 'Sunrise'], ['sunset', 'Sunset'], ['blueHour', 'Blue hour'], ['night', 'Night']];
export const INTENT_NAME = Object.fromEntries(INTENTS);
export const WINDOW_NAME = { blueMorning: 'Morning blue hour', goldenMorning: 'Sunrise', goldenEvening: 'Sunset', blueEvening: 'Evening blue hour', night: 'Night' };
export const WINDOW_SHORT = { blueMorning: 'Blue AM', goldenMorning: 'Sunrise', goldenEvening: 'Sunset', blueEvening: 'Blue PM', night: 'Night' };
export const NO_FORECAST_SHORT = { weatherServiceNotEnabled: 'Weather off', serviceFailed: 'Offline', beyondHorizon: 'Too far ahead', inThePast: 'Passed', notLoaded: 'Loading' };
export const NO_FORECAST_LONG = {
  weatherServiceNotEnabled: "Weather isn't enabled for this build of Iter, so only sun and moon times are shown.",
  serviceFailed: "Couldn't reach Apple Weather. Sun and moon times are still exact.",
  beyondHorizon: 'Too far ahead for a forecast. Planned on sun angle and season until about ten days out.',
  inThePast: 'This window has passed.',
  notLoaded: 'Forecast not loaded yet.',
};
export const CATEGORY = {
  landscape: ['Landscape', 'mountain.2'], astro: ['Astro', 'sparkles'], architecture: ['Architecture', 'building.columns'], street: ['Street', 'figure.walk'],
  coast: ['Coast', 'water.waves'], wildlife: ['Wildlife', 'pawprint'], desert: ['Desert', 'sun.dust'], waterfall: ['Waterfall', 'drop'], forest: ['Forest', 'tree'], urban: ['Urban', 'building.2'],
};
const ORIGIN = { curated: 'Curated', user: 'Added by you', appleMaps: 'Apple Maps', scout: 'Scout' };
const BEST_LIGHT = { sunrise: 'sunrise', sunset: 'sunset', blueHour: 'blue hour', night: 'night sky', midday: 'midday', overcast: 'overcast' };
const MOON_NAME = { new: 'New moon', waxingCrescent: 'Waxing crescent', firstQuarter: 'First quarter', waxingGibbous: 'Waxing gibbous', full: 'Full moon', waningGibbous: 'Waning gibbous', lastQuarter: 'Last quarter', waningCrescent: 'Waning crescent' };
export const MOON_SYMBOL = { new: 'moonphase.new.moon', waxingCrescent: 'moonphase.waxing.crescent', firstQuarter: 'moonphase.first.quarter', waxingGibbous: 'moonphase.waxing.gibbous', full: 'moonphase.full.moon', waningGibbous: 'moonphase.waning.gibbous', lastQuarter: 'moonphase.last.quarter', waningCrescent: 'moonphase.waning.crescent' };
const COMPASS = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE', 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
export const compassPoint = (az) => COMPASS[Math.round((((az % 360) + 360) % 360) / 22.5) % 16];
export const degrees = (az) => `${Math.round(az)}° ${compassPoint(az)}`;
export const facingNote = (az) => `Classic view faces ${degrees(az)}`;
const ZONE_NOTE = { sample: 'Mountain Time · 1\u00a0h ahead of you', noforecast: 'Mountain Time · 1\u00a0h ahead of you', failed: 'Mountain Time · 1\u00a0h ahead of you', user: 'Mountain Time · 1\u00a0h ahead of you', polar: 'Central European Time · 9\u00a0h ahead of you' };

export const FACTOR_TITLE = { lowCloud: 'Low cloud', midHighCloud: 'Mid and high cloud', totalCloud: 'Cloud cover', clearSky: 'Clear sky', precipitation: 'Rain', visibility: 'Visibility', moonlight: 'Moonlight', darkSky: 'Dark sky', wind: 'Wind', sunAlignment: 'Sun direction' };
export function factorValue(c) {
  switch (c.factor) {
    case 'visibility': return `${Math.round(c.value / 1609.344)} mi`;
    case 'wind': return `${Math.round(c.value * 0.621371)} mph`;
    case 'sunAlignment': return `${Math.round(c.value)}°`;
    default: return pct(c.value);
  }
}
export function sentence(c, kind) {
  const { factor: f, effect: e } = c;
  if (f === 'lowCloud') return e === 'hurts' ? 'Low cloud can block the sun at the horizon.' : 'Little low cloud: the horizon should be open.';
  if (f === 'midHighCloud') return e === 'helps' ? 'Mid and high cloud catches colour.' : e === 'hurts' ? 'A thick upper deck mutes the colour.' : 'Some upper cloud, little effect.';
  if (f === 'totalCloud') return e === 'helps' ? 'Cloud cover suits this window.' : e === 'hurts' ? 'Heavy cloud cover.' : 'Cloud layers unavailable; judged on total cover.';
  if (f === 'clearSky') return kind === 'night' ? 'Clear sky for stars.' : 'Bare sky: clean light, flat colour.';
  if (f === 'precipitation') return e === 'hurts' ? 'Rain is likely.' : 'Little chance of rain.';
  if (f === 'visibility') return e === 'hurts' ? 'Haze or fog cuts visibility.' : 'Good visibility.';
  if (f === 'moonlight') return 'A bright moon is up and washes out stars.';
  if (f === 'darkSky') return 'Moon down or thin: a dark sky.';
  if (f === 'wind') return e === 'hurts' ? 'Strong wind: tripods and reflections suffer.' : 'Light wind.';
  return e === 'helps' ? 'The sun lines up with the classic view.' : 'The sun is off-axis from the classic view.';
}
export const signed = (p) => (p === 0 ? '0' : p > 0 ? `+${p}` : `−${Math.abs(p)}`);
export const CONFIDENCE_NAME = { high: 'High confidence', medium: 'Medium confidence', low: 'Low confidence' };
export const CONFIDENCE_EXPLAINED = { high: 'The forecast is close, so the score is firm.', medium: 'A few days out: expect the score to move a little.', low: 'Far out or missing inputs: treat the score as a guide.' };
export function leadNote(h) {
  const r = Math.round(h);
  if (r < 1) return 'Forecast is for right now.';
  if (r < 48) return `Forecast is about ${r} hours ahead of this window.`;
  return `Forecast is about ${Math.round(h / 24)} days ahead of this window.`;
}
export const rangeText = (w) => (w.range && w.range[0] !== w.range[1] ? `${w.range[0]}–${w.range[1]}` : null);

const fahrenheit = (c) => `${Math.round(c * 9 / 5 + 32)}°`;

// Interpolate a sampled path [[min, alt, az], ...] at a minute of the day.
function at(path, min) {
  for (let i = 1; i < path.length; i++) {
    if (path[i][0] >= min) {
      const [m0, a0, z0] = path[i - 1], [m1, a1, z1] = path[i];
      const t = m1 === m0 ? 0 : (min - m0) / (m1 - m0);
      return [a0 + (a1 - a0) * t, z0 + (z1 - z0) * t];
    }
  }
  return [path[path.length - 1][1], path[path.length - 1][2]];
}

/**
 * view model. key: 'sample'|'noforecast'|'failed'|'polar'|'user'.
 * opts: { focus:'full'|'sunrise'|'sunset', expanded:[kind], loading:bool, markerMin:number, selected:kind, explanation:{state,...} }
 */
export function vm(key, opts = {}) {
  const r = RAW[key];
  if (!r) throw new Error(`vm: unknown state ${key}`);
  const loading = !!opts.loading;
  const [ty, tm, td] = parseDay(r.today);
  const [dy, dm, dd] = parseDay(r.day);
  const rel = (y, m, d) => { const n = dayNum(y, m, d) - dayNum(ty, tm, td); return n === 0 ? 'Today' : n === 1 ? 'Tomorrow' : n === -1 ? 'Yesterday' : dayLong(y, m, d); };
  const asNoForecast = (w) => (loading && !w.scored && w.reason !== 'inThePast' ? { ...w, reason: 'notLoaded' } : w);
  const windows = r.windows.map(asNoForecast);
  const hasWeather = r.hours.length > 0;
  const selected = opts.selected ?? r.selected;
  const unavailableReason = loading ? null : (key === 'noforecast' ? 'weatherServiceNotEnabled' : key === 'failed' ? 'serviceFailed' : null);
  const best = r.best ? { ...r.best, window: r.best.window } : null;
  const sunMin = r.sun.sunrise ? hmMin(r.sun.sunrise) : null, setMin = r.sun.sunset ? hmMin(r.sun.sunset) : null;
  const focus = opts.focus || 'full';
  let lo = 0, hi = 1440;
  if (focus === 'sunrise' && sunMin != null) { lo = Math.max(0, sunMin - 120); hi = Math.min(1440, sunMin + 120); }
  if (focus === 'sunset' && setMin != null) { lo = Math.max(0, setMin - 120); hi = Math.min(1440, setMin + 120); }
  const selWin = windows.find((w) => w.kind === selected);
  const headline = windows.find((w) => w.kind === r.intent || (r.intent === 'sunrise' && w.kind === 'goldenMorning') || (r.intent === 'sunset' && w.kind === 'goldenEvening') || (r.intent === 'night' && w.kind === 'night'));
  let markerMin = opts.markerMin ?? r.markerMin;
  if (opts.markerMin === undefined && !selWin && headline) markerMin = (headline.startMin + headline.endMin) / 2;
  const sunAt = at(r.sunPath, markerMin), moonAt = at(r.moonPath, markerMin);
  const markerWindow = windows.find((w) => markerMin >= w.startMin && markerMin <= w.endMin);
  const hourAt = r.hours.find((h) => markerMin >= h.min && markerMin < h.min + 60);
  const wasLoadedHours = hasWeather ? r.hours : [];
  const foci = ['full'].concat(r.sun.sunrise ? ['sunrise'] : [], r.sun.sunset ? ['sunset'] : []);
  const outlook = r.outlook.map((o) => {
    const h = o.headline ? asNoForecast(o.headline) : null;
    return { y: o.y, m: o.m, d: o.d, wd: WD[dow(o.y, o.m, o.d)], dn: String(o.d), headline: h, isBest: !!best && best.day === `${o.y}-${o.m}-${o.d}`, selected: r.day === `${o.y}-${o.m}-${o.d}` };
  });
  return {
    key, raw: r, loading, focus, foci,
    spot: {
      name: r.spot.name, locality: r.spot.locality, origin: ORIGIN[r.spot.origin], isUser: r.spot.origin === 'user',
      category: CATEGORY[r.spot.category][0], categorySymbol: CATEGORY[r.spot.category][1],
      facing: r.spot.facing, blurb: r.spot.blurb, notes: r.spot.notes, walk: r.spot.walk, elevM: r.spot.elev,
      bestLight: r.spot.bestLight.map((b) => BEST_LIGHT[b]), zoneNote: ZONE_NOTE[key], saved: key === 'sample' || key === 'noforecast' || key === 'failed',
    },
    intent: r.intent, intentLabel: INTENT_NAME[r.intent],
    day: { y: dy, m: dm, d: dd, long: dayLong(dy, dm, dd), rel: rel(dy, dm, dd), isToday: r.day === r.today },
    selected, best, outlook, windows,
    sun: r.sun, nextSunrise: r.nextSunrise, nextSunset: r.nextSunset, todayKind: r.todayKind,
    moon: { ...r.moon, label: MOON_NAME[r.moon.name], symbol: MOON_SYMBOL[r.moon.name] },
    updated: r.fetchedAt ? `Updated ${r.fetchedAt}` : null,
    sample: key !== 'noforecast' && key !== 'failed',
    unavailableReason, hasWeather: hasWeather && !loading, hasLayers: hasWeather,
    domain: { lo, hi }, tiers: focus === 'full' ? 3 : 2, tickEvery: focus === 'full' ? 3 : 1,
    sunPath: r.sunPath, moonPath: r.moonPath, hours: wasLoadedHours.map((h) => ({ ...h, temp: fahrenheit(h.tempC), windMph: Math.round(h.wind * 0.621371) })),
    marker: {
      min: markerMin, hm: minToHM(markerMin), sunAlt: sunAt[0], sunAz: sunAt[1], moonAlt: moonAt[0], moonAz: moonAt[1],
      cloud: hourAt ? hourAt.cover : null, rain: hourAt ? hourAt.rain : null, windowName: markerWindow ? WINDOW_NAME[markerWindow.kind] : null,
    },
    hmMin, rel,
    explanation: opts.explanation || null, expanded: opts.expanded || [],
  };
}

export const outlookCaption = (o) => {
  if (!o.headline) return 'No window';
  return o.headline.scored ? (rangeText(o.headline) ?? ' ') : NO_FORECAST_SHORT[o.headline.reason];
};
export const outlookFade = (o) => (o.headline && o.headline.scored ? (o.headline.confidence === 'low' ? 'low' : o.headline.confidence === 'medium' ? 'medium' : null) : null);

export function sunAtLine(m) {
  const { sunAlt, sunAz, hm } = m.marker;
  if (sunAlt >= 0) return `At ${hm} the sun is ${Math.round(sunAlt)}° above the horizon, toward ${degrees(sunAz)}.`;
  return `At ${hm} the sun is below the horizon.`;
}
export function frameNote(m) {
  const f = m.spot.facing;
  if (f == null || m.marker.sunAlt < 0) return null;
  let diff = Math.abs(m.marker.sunAz - f) % 360;
  if (diff > 180) diff = 360 - diff;
  return diff <= 35 ? 'The sun is in your frame.' : diff <= 100 ? 'The sun is off to one side.' : 'The sun is behind you.';
}
export function moonLine(m) {
  const mo = m.moon;
  const parts = [mo.label, `${pct(mo.illum)} lit`];
  if (mo.alwaysUp) parts.push('up all day'); else if (mo.alwaysDown) parts.push('below the horizon all day');
  else { if (mo.rise) parts.push(`rises ${mo.rise}`); if (mo.set) parts.push(`sets ${mo.set}`); }
  return parts.join(' · ');
}
export function elevationText(m) {
  const ft = Math.round(m.spot.elevM * 3.28084);
  return `${ft.toLocaleString('en-US')} ft elevation`;
}
export const percentText = pct;
export const BEST_AT = (m) => (m.spot.bestLight.length ? `Best at ${m.spot.bestLight.join(' and ')}` : null);
