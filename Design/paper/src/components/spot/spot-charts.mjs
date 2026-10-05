// LightTimeline, SkyArc, HourlyStrip (App/Sources/Spot/LightTimelineView.swift, SkyArcView.swift, HourlyWeatherView.swift).
// The charts are real inline SVG (graphics) plus real text nodes positioned on the canvas (labels), computed here from the same
// numbers the Swift canvases use: left gutter 44, right inset space/lg, tiers of 16, sky band 56, axis 18, plot 80, arc plot 168.
import { col, row, text, el, svgEl, raw, spacer } from '../../../tools/lib/h.mjs';
import { c, d, dv, font, op } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { segmented } from '../../../tools/lib/controls.mjs';
import { weatherAttribution, sampleDataLabel } from '../../../tools/lib/lightindex.mjs';
import { spotCard } from './spot-lead.mjs';
import { WINDOW_SHORT, WINDOW_NAME, NO_FORECAST_LONG, facingNote, degrees, sunAtLine, frameNote, moonLine, percentText } from './spot-model.mjs';

export const artboards = [];

const f2 = (n) => Math.round(n * 100) / 100;
const abs = (o) => ({ position: 'absolute', ...o });
const FSIZE = { caption: 10, captionStrong: 10, timeSmall: 10, footnote: 10, subheadline: 11, callout: 12 };
const FLINE = { caption: 13, captionStrong: 13, timeSmall: 13 };
// Rough SF Pro advance widths (em) - only used to decide label tiers and edge clamps, as SwiftUI's measure() does.
function tw(str, size, bold = false) {
  let w = 0;
  for (const ch of String(str)) w += /[il.,:°·|'!]/.test(ch) ? 0.27 : ch === ' ' ? 0.28 : /[A-Z0-9]/.test(ch) ? 0.62 : /[mwMW]/.test(ch) ? 0.82 : 0.52;
  return w * size * (bold ? 1.04 : 1);
}
let uid = 0;

/** A text label placed on a chart canvas. anchor: start | middle | end (x); vAnchor: top | middle | bottom (y). */
function lab(str, { x, y, anchor = 'start', vAnchor = 'top', style: fs = 'caption', color = 'text/secondary', bold = false, name }) {
  const size = FSIZE[fs] ?? 10, h = FLINE[fs] ?? 13;
  const W = Math.ceil(tw(str, size, bold)) + 12;
  const left = anchor === 'start' ? x : anchor === 'middle' ? x - W / 2 : x - W;
  const top = vAnchor === 'top' ? y : vAnchor === 'middle' ? y - h / 2 : y - h;
  return text(str, { name: name || `Label / ${str}`.slice(0, 50), font: font(fs), color, w: W, align: anchor === 'middle' ? 'center' : anchor === 'end' ? 'right' : 'left', style: abs({ left: f2(left), top: f2(top), height: h }) });
}
const canvasFrame = (name, W, H, ...kids) => el('div', { name, style: { position: 'relative', width: W, height: H, flexShrink: 0 } }, ...kids);
const stroke = (colorToken, w, extra = '') => `style="stroke:${c(colorToken)};stroke-width:${w}${extra}" fill="none"`;
const fillS = (colorToken, extra = '') => `style="fill:${c(colorToken)}${extra}"`;
const OPA = (name) => `;fill-opacity:${op(name)}`;
const tint = (kind) => (kind === 'goldenMorning' || kind === 'goldenEvening' ? 'sky/golden' : kind === 'night' ? 'sky/night' : 'sky/blueHour');

// ---------------------------------------------------------------------------------------------------------------------
// LightTimeline
// ---------------------------------------------------------------------------------------------------------------------
function skyStyle(alt, theme) {
  // returns [a, b, t]: night -18, blue -6..-0.8, blue->golden across the horizon, golden to +6, golden->day 6..14, day.
  if (alt < -18) return ['sky/night', null, 0];
  if (alt < -6) return ['sky/night', 'sky/blueHour', (alt + 18) / 12];
  if (alt < -0.8) return ['sky/blueHour', null, 0];
  if (alt < 0.8) return ['sky/blueHour', 'sky/golden', (alt + 0.8) / 1.6];
  if (alt < 6) return ['sky/golden', null, 0];
  if (alt < 14) return ['sky/golden', 'sky/day', (alt - 6) / 8];
  return ['sky/day', null, 0];
}
const mixCss = ([a, b, t]) => (t <= 0.004 ? c(a) : t >= 0.996 ? c(b) : `color-mix(in srgb, ${c(b)} ${f2(t * 100)}%, ${c(a)})`);

export function timelineLayout(m) {
  const S = { xxs: dv('space/xxs'), xs: dv('space/xs'), sm: dv('space/sm') };
  const tiersH = m.tiers * dv('space/lg');
  const bracketY = tiersH + S.xxs;
  const skyTop = bracketY + S.xs + S.xxs;
  const skyBottom = skyTop + dv('chart/timelineHeight');
  const axisBottom = skyBottom + dv('chart/timelineAxisHeight');
  const plotTop = axisBottom + S.sm;
  const plotBottom = plotTop + (m.hasWeather ? dv('chart/hourlyTintHeight') * 2 : 0);
  return { tiersH, bracketY, skyTop, skyBottom, axisBottom, plotTop, plotBottom, total: m.hasWeather ? plotBottom + S.xxs : axisBottom };
}

export function timelineCanvas(m, { width = 868 } = {}) {
  const L = timelineLayout(m);
  const left = dv('size/control/heightLarge') + dv('space/sm'), right = width - dv('space/lg'), plotW = right - left;
  const { lo, hi } = m.domain, span = hi - lo;
  const x = (min) => left + ((min - lo) / span) * plotW;
  const S = { xxs: dv('space/xxs'), xs: dv('space/xs'), sm: dv('space/sm'), lg: dv('space/lg') };
  const thin = dv('stroke/thin'), regular = dv('stroke/regular'), thick = dv('stroke/thick'), hair = dv('stroke/hairline');
  const extent = (w) => {
    let x0 = Math.max(left, x(w.startMin)), x1 = Math.min(right, x(w.endMin));
    if (x1 < x0) return [x0, x0];
    const minW = dv('chart/windowMinWidth');
    if (x1 - x0 < minW) { const mid = (x0 + x1) / 2; x0 = Math.max(left, mid - minW / 2); x1 = Math.min(right, x0 + minW); }
    return [x0, x1];
  };
  const parts = []; // svg inner pieces
  const labels = [];

  // Sky band (a gradient frame: editable in Paper) coloured by sun altitude.
  const stops = m.sunPath.filter(([mn]) => mn >= lo - 60 && mn <= hi + 60).map(([mn, alt]) => ({ loc: Math.min(1, Math.max(0, (mn - lo) / span)), css: mixCss(skyStyle(alt)) }));
  const keep = stops.filter((s, i) => !(i > 0 && i < stops.length - 1 && stops[i - 1].css === s.css && stops[i + 1].css === s.css));
  const gradient = keep.length > 1 ? `linear-gradient(90deg, ${keep.map((s) => `${s.css} ${f2(s.loc * 100)}%`).join(', ')})` : c('sky/night');
  const sky = el('div', { name: 'Sky Band', style: abs({ left, top: L.skyTop, width: plotW, height: dv('chart/timelineHeight'), borderRadius: d('radius/badge'), background: gradient }) });

  // Axis ticks and hour labels (24 h, spot zone).
  for (let hr = 0; hr <= 24; hr += m.tickEvery) {
    const mn = hr * 60;
    if (mn < lo || mn > hi) continue;
    const tx = x(mn);
    parts.push(`<path d="M${f2(tx)} ${L.skyBottom}V${L.skyBottom + S.xs}" ${stroke('text/secondary', thin)}/>`);
    labels.push(lab(String(hr % 24).padStart(2, '0'), { x: tx, y: L.skyBottom + S.xs, anchor: 'middle', style: 'timeSmall', name: `Hour ${hr % 24}` }));
  }

  // Weather plot.
  if (m.hasWeather) {
    const ptop = L.plotTop, pbot = L.plotBottom, ph = pbot - ptop;
    const y = (f) => pbot - Math.min(1, Math.max(0, f)) * ph;
    for (const w of m.windows) {
      const [x0, x1] = extent(w);
      if (x1 <= x0) continue;
      parts.push(`<rect x="${f2(x0)}" y="${ptop}" width="${f2(x1 - x0)}" height="${ph}" ${fillS(tint(w.kind), OPA('window-tint'))}/>`);
      if (w.kind === m.selected) parts.push(`<rect x="${f2(x0)}" y="${ptop}" width="${f2(x1 - x0)}" height="${ph}" ${fillS('selection/fill')}/>`);
    }
    for (const f of [0, 0.5, 1]) {
      parts.push(`<path d="M${left} ${f2(y(f))}H${right}" ${stroke('separator/default', hair)}/>`);
      labels.push(lab(percentText(f), { x: left - S.xs, y: y(f), anchor: 'end', vAnchor: 'middle', style: 'timeSmall', name: `Axis ${percentText(f)}` }));
    }
    const hrs = m.hours.filter((h) => h.min + 60 >= lo - 60 && h.min <= hi + 60);
    const series = m.hasLayers ? [['cloud/high', 'high'], ['cloud/mid', 'mid'], ['cloud/low', 'low']] : [['cloud/mid', 'cover']];
    const clipPts = (pts) => { // clip a polyline to [left, right] by interpolation
      const out = [];
      for (let i = 0; i < pts.length; i++) {
        const [px, py] = pts[i];
        if (px >= left && px <= right) { out.push([px, py]); }
        if (i + 1 < pts.length) {
          const [qx, qy] = pts[i + 1];
          for (const edge of [left, right]) if ((px < edge && qx > edge) || (px > edge && qx < edge)) out.push([edge, py + ((qy - py) * (edge - px)) / (qx - px)]);
        }
      }
      return out.sort((a, b) => a[0] - b[0]);
    };
    if (hrs.length > 1) for (const [tok, k] of series) {
      const pts = clipPts(hrs.map((h) => [x(h.min + 30), y(h[k])]));
      if (pts.length < 2) continue;
      const top = pts.map(([px, py], i) => `${i ? 'L' : 'M'}${f2(px)} ${f2(py)}`).join('');
      const area = `M${f2(pts[0][0])} ${pbot}${pts.map(([px, py]) => `L${f2(px)} ${f2(py)}`).join('')}L${f2(pts[pts.length - 1][0])} ${pbot}Z`;
      parts.push(`<path d="${area}" ${fillS(tok, OPA('cloud-fill'))}/>`, `<path d="${top}" ${stroke(tok, regular, ';stroke-linejoin:round')}/>`);
    }
    for (const h of hrs) {
      if (h.rain < 0.1) continue;
      let x0 = x(h.min), x1 = x(h.min + 60);
      const inset = (x1 - x0) * 0.2;
      x0 += inset; x1 -= inset;
      x0 = Math.max(left, x0); x1 = Math.min(right, x1);
      if (x1 <= x0) continue;
      parts.push(`<rect x="${f2(x0)}" y="${f2(y(h.rain))}" width="${f2(Math.max(1, x1 - x0))}" height="${f2(pbot - y(h.rain))}" rx="${thin}" ${fillS('sky/blueHour')}/>`);
    }
  }

  // Selected window across the whole stack (accent outline with a window-colour halo).
  const bottom = m.hasWeather ? L.plotBottom : L.skyBottom;
  for (const w of m.windows.filter((w) => w.kind === m.selected)) {
    const [x0, x1] = extent(w);
    if (x1 <= x0) continue;
    const r = `x="${f2(x0 - thin)}" y="${f2(L.skyTop - thin)}" width="${f2(x1 - x0 + 2 * thin)}" height="${f2(bottom - L.skyTop + 2 * thin)}" rx="${dv('radius/badge') / 2}"`;
    parts.push(`<rect ${r} ${stroke('background/window', thick + 2 * thin)}/>`, `<rect ${r} ${stroke('accent/primary', thick)}/>`);
  }

  // Brackets with tiered labels.
  const tierEnds = Array(m.tiers).fill(-Infinity);
  for (const w of [...m.windows].sort((a, b) => a.startMin - b.startMin)) {
    const [x0, x1] = extent(w);
    if (x1 <= x0) continue;
    const sel = w.kind === m.selected;
    parts.push(`<path d="M${f2(x0)} ${L.bracketY + S.xs}V${L.bracketY}H${f2(x1)}V${L.bracketY + S.xs}" ${stroke(sel ? 'accent/primary' : 'text/secondary', sel ? thick : regular)}/>`);
    const str = w.scored ? `${WINDOW_SHORT[w.kind]} ${w.score}` : WINDOW_SHORT[w.kind];
    const tWidth = tw(str, 10, sel);
    let lx = x0;
    if (lx + tWidth > right) lx = right - tWidth;
    lx = Math.max(left - S.sm, lx);
    let tier = 0;
    while (tier < m.tiers - 1 && lx < tierEnds[tier] + S.xs) tier++;
    tierEnds[tier] = lx + tWidth;
    const ty = L.tiersH - (tier + 1) * dv('space/lg');
    labels.push(lab(str, { x: lx, y: ty, style: sel ? 'captionStrong' : 'caption', bold: sel, color: w.scored ? 'text/primary' : 'text/secondary', name: `Bracket Label / ${WINDOW_SHORT[w.kind]}` }));
    if (tier > 0) parts.push(`<path d="M${f2(x0)} ${ty + dv('space/lg') - thin}V${L.bracketY}" ${stroke('separator/default', hair)}/>`);
  }

  // Marker: dashed line at rest, with a knob on the sky band's bottom edge.
  if (m.marker.min >= lo && m.marker.min <= hi) {
    const mx = f2(x(m.marker.min));
    parts.push(`<path d="M${mx} ${L.skyTop}V${bottom}" ${stroke('background/window', thin + 2 * thin)}/>`,
      `<path d="M${mx} ${L.skyTop}V${bottom}" ${stroke('text/primary', thin, `;stroke-dasharray:${dv('stroke/dashLength')} ${dv('stroke/dashGap')}`)}/>`,
      `<circle cx="${mx}" cy="${L.skyBottom}" r="${S.xs}" style="fill:${c('text/primary')};stroke:${c('background/window')};stroke-width:${thin}"/>`);
  }

  return canvasFrame('Canvas / Light Timeline', width, L.total, sky,
    svgEl('Timeline Graphics', { width, height: L.total, style: abs({ left: 0, top: 0 }) }, raw(parts.join('\n'))), labels);
}

const swatch = (tok, label) => row({ name: `Legend / ${label}`, align: 'center', gap: d('space/xs') },
  el('div', { name: 'Swatch', style: { width: d('space/md'), height: d('space/md'), borderRadius: d('space/xxs'), background: c(tok), border: `${d('stroke/hairline')} solid ${c('separator/default')}`, flexShrink: 0 } }),
  text(label, { name: 'Label', font: font('caption'), color: 'text/secondary' }));

export function timelineLegend(m) {
  return row({ name: 'Legend', align: 'center', gap: d('space/md') },
    m.hasLayers ? [swatch('cloud/high', 'High cloud'), swatch('cloud/mid', 'Mid cloud'), swatch('cloud/low', 'Low cloud')] : swatch('cloud/mid', 'Cloud cover'),
    swatch('sky/blueHour', 'Chance of rain'));
}
/** The no-forecast note. SF Symbol cloud.slash does not exist on the build Mac, so SwiftUI draws the label with no glyph. */
export function timelineNoWeather(m) {
  const msg = m.loading ? 'Checking the forecast…' : NO_FORECAST_LONG[m.unavailableReason ?? 'notLoaded'];
  return row({ name: 'No Weather Note', align: 'center', gap: d('space/xs') },
    el('div', { name: 'Icon Slot (cloud.slash missing)', style: { width: 8, height: 14, flexShrink: 0 } }),
    text(msg, { name: 'Reason', font: font('subheadline'), color: 'text/secondary' }));
}
export function timelineReadout(m) {
  const mk = m.marker;
  const parts = [mk.hm];
  if (mk.cloud != null) parts.push(`${percentText(mk.cloud)} cloud`);
  if (mk.rain != null) parts.push(`${percentText(mk.rain)} rain`);
  return row({ name: 'Readout', align: 'center', gap: d('space/sm'), style: { minHeight: d('size/badge/height') } },
    text(parts.join(' · '), { name: 'Readout Values', font: font('bodyEmphasis'), color: 'text/primary', style: { fontVariantNumeric: 'tabular-nums' } }),
    mk.windowName ? [text('·', { name: 'Dot', font: font('body'), color: 'text/secondary' }), text(mk.windowName, { name: 'Window Under Marker', font: font('subheadline'), color: 'text/secondary' })] : null,
    spacer(), text('Hover or drag to read any time', { name: 'Hint', font: font('caption'), color: 'text/tertiary' }));
}
const ZOOM = [['full', 'Full day'], ['sunrise', 'Sunrise ±2 h'], ['sunset', 'Sunset ±2 h']];
export function lightTimeline(m, { width } = {}) {
  const inner = (width ?? 892) - 2 * dv('space/md');
  return col({ name: 'LightTimeline', gap: d('space/md'), w: width },
    row({ name: 'Title Row', align: 'baseline', justify: 'space-between' },
      text('Light through the day', { name: 'Section Title', font: font('title/section'), color: 'text/primary' }),
      m.foci.length > 1 ? segmented(ZOOM.filter(([k]) => m.foci.includes(k)).map(([, l]) => l), m.foci.indexOf(m.focus)) : null),
    spotCard(col({ name: 'Timeline Body', gap: d('space/sm') }, timelineReadout(m), timelineCanvas(m, { width: inner }), m.hasWeather ? timelineLegend(m) : timelineNoWeather(m)), { name: 'SpotCard / Timeline' }));
}

// ---------------------------------------------------------------------------------------------------------------------
// SkyArc
// ---------------------------------------------------------------------------------------------------------------------
export function arcCanvas(m, { width = 868 } = {}) {
  const S = { xxs: dv('space/xxs'), xs: dv('space/xs'), sm: dv('space/sm'), lg: dv('space/lg') };
  const thin = dv('stroke/thin'), thick = dv('stroke/thick'), hair = dv('stroke/hairline'), regular = dv('stroke/regular');
  const left = dv('size/control/heightLarge') + S.sm, right = width - S.lg;
  const top = S.lg + S.xs, ph = dv('chart/arcHeight'), bottom = top + ph;
  const H = top + ph + dv('chart/timelineAxisHeight') + S.lg;
  const plotW = right - left;
  const sun = m.sunPath, moon = m.moonPath;
  const highest = Math.max(...sun.map((p) => p[1]), ...moon.map((p) => p[1]), 0);
  const yMax = Math.min(90, Math.max(60, Math.ceil(highest / 10) * 10 + 10));
  const yMin = -20;
  const x = (az) => left + (az / 360) * plotW;
  const y = (alt) => bottom - ((alt - yMin) / (yMax - yMin)) * ph;
  const horizon = y(0);
  const parts = [], labels = [];
  parts.push(`<rect x="${left}" y="${top}" width="${f2(plotW)}" height="${f2(horizon - top)}" ${fillS('sky/day', OPA('window-tint'))}/>`,
    `<rect x="${left}" y="${f2(horizon)}" width="${f2(plotW)}" height="${f2(bottom - horizon)}" style="fill:${c('sky/night')};fill-opacity:calc(var(--opacity-window-tint) / 2)"/>`,
    `<rect x="${left}" y="${top}" width="${f2(plotW)}" height="${ph}" ${stroke('separator/default', hair)}/>`);
  for (let a = 30; a <= yMax; a += 30) {
    parts.push(`<path d="M${left} ${f2(y(a))}H${right}" ${stroke('separator/default', hair)}/>`);
    labels.push(lab(`${a}°`, { x: left - S.xs, y: y(a), anchor: 'end', vAnchor: 'middle', style: 'timeSmall', name: `Height ${a}` }));
  }
  labels.push(lab('0°', { x: left - S.xs, y: horizon, anchor: 'end', vAnchor: 'middle', style: 'timeSmall', name: 'Height 0' }));
  parts.push(`<path d="M${left} ${f2(horizon)}H${right}" ${stroke('text/secondary', thin)}/>`);
  labels.push(lab('Horizon', { x: left + S.xs, y: horizon - S.xxs, vAnchor: 'bottom', name: 'Horizon' }));
  for (const [az, nm] of [[0, 'N'], [90, 'E'], [180, 'S'], [270, 'W'], [360, 'N']]) {
    parts.push(`<path d="M${f2(x(az))} ${bottom}V${bottom + S.xs}" ${stroke('text/secondary', thin)}/>`);
    labels.push(lab(nm, { x: x(az), y: bottom + S.xs, anchor: 'middle', style: 'captionStrong', color: 'text/primary', bold: true, name: `Compass ${nm}` }));
  }
  for (const az of [45, 135, 225, 315]) parts.push(`<path d="M${f2(x(az))} ${bottom}V${bottom + S.xxs}" ${stroke('separator/default', thin)}/>`);
  labels.push(lab('Compass direction →', { x: left + plotW / 2, y: H, anchor: 'middle', vAnchor: 'bottom', name: 'Axis Title X' }));
  labels.push(lab('↑ Height above the horizon', { x: left + S.xs, y: top + S.xs, name: 'Axis Title Y' }));

  const facing = m.spot.facing;
  if (facing != null) {
    parts.push(`<path d="M${f2(x(facing))} ${top}V${bottom}" ${stroke('accent/primary', regular, `;stroke-dasharray:${dv('stroke/dashLength')} ${dv('stroke/dashGap')}`)}/>`);
    const t = facingNote(facing), w = tw(t, 10, true);
    const lx = Math.min(Math.max(left, x(facing) - w / 2), right - w);
    labels.push(lab(t, { x: lx, y: top - S.xxs, vAnchor: 'bottom', style: 'captionStrong', color: 'accent/text', bold: true, name: 'Classic View Label' }));
  }
  for (const [az, time, nm] of [[m.sun.sunriseAz, m.sun.sunrise, 'Sunrise'], [m.sun.sunsetAz, m.sun.sunset, 'Sunset']]) {
    if (az == null || !time) continue;
    const ex = x(az);
    parts.push(`<path d="M${f2(ex)} ${f2(horizon - S.xs)}V${f2(horizon + S.xs)}" ${stroke('text/primary', thick)}/>`);
    const l1 = `${nm} ${time}`, l2 = degrees(az);
    const w = Math.max(tw(l1, 10), tw(l2, 10));
    const lx = Math.min(Math.max(left, ex - w / 2), right - w);
    labels.push(lab(l1, { x: lx + w / 2, y: horizon + S.xs + S.xxs, anchor: 'middle', color: 'text/primary', name: `${nm} Time` }),
      lab(l2, { x: lx + w / 2, y: horizon + S.xs + S.xxs + S.lg - S.xs, anchor: 'middle', color: 'text/secondary', name: `${nm} Bearing` }));
  }
  // Paths: only above the horizon; segments that wrap through north are not joined.
  const pathD = (pts) => {
    let dd = '', pen = false;
    for (let i = 1; i < pts.length; i++) {
      const a = pts[i - 1], b = pts[i];
      if (a[1] < 0 || b[1] < 0 || Math.abs(a[2] - b[2]) >= 180) { pen = false; continue; }
      if (!pen) { dd += `M${f2(x(a[2]))} ${f2(y(a[1]))}`; pen = true; }
      dd += `L${f2(x(b[2]))} ${f2(y(b[1]))}`;
    }
    return dd;
  };
  const clipStyle = `;stroke-linecap:round;stroke-linejoin:round`;
  const md = pathD(moon), sd = pathD(sun);
  if (md) parts.push(`<path d="${md}" ${stroke('map/moon', thick, clipStyle)}/>`);
  if (sd) parts.push(`<path d="${sd}" ${stroke('text/primary', thick, clipStyle)}/>`);
  // Markers at the shared time.
  const r = dv('chart/arcMarker') / 2;
  const mk = m.marker;
  if (mk.moonAlt >= 0) parts.push(`<circle cx="${f2(x(mk.moonAz))}" cy="${f2(y(mk.moonAlt))}" r="${r}" style="fill:${c('map/moon')};stroke:${c('background/window')};stroke-width:${regular}"/>`);
  if (mk.sunAlt >= yMin) {
    if (mk.sunAlt >= 0) parts.push(`<circle cx="${f2(x(mk.sunAz))}" cy="${f2(y(mk.sunAlt))}" r="${r}" style="fill:${c('map/sun')};stroke:${c('background/window')};stroke-width:${regular}"/>`);
    else parts.push(`<circle cx="${f2(x(mk.sunAz))}" cy="${f2(y(mk.sunAlt))}" r="${r}" style="fill:${c('background/window')};stroke:${c('map/sun')};stroke-width:${thick}"/>`);
  }
  return canvasFrame('Canvas / Sky Arc', width, H, svgEl('Sky Arc Graphics', { width, height: H, style: abs({ left: 0, top: 0 }) }, raw(parts.join('\n'))), labels);
}
const dot = (tok, label) => row({ name: `Legend / ${label}`, align: 'center', gap: d('space/xs') },
  el('div', { name: 'Dot', style: { width: d('space/md'), height: d('space/md'), borderRadius: '999px', background: c(tok), flexShrink: 0 } }), text(label, { name: 'Label', font: font('caption'), color: 'text/secondary' }));
export function skyArc(m, { width } = {}) {
  const inner = (width ?? 892) - 2 * dv('space/md');
  const fn = frameNote(m);
  return col({ name: 'SkyArc', gap: d('space/md'), w: width },
    text('Sun and moon', { name: 'Section Title', font: font('title/section'), color: 'text/primary' }),
    spotCard(col({ name: 'Arc Body', gap: d('space/sm') },
      arcCanvas(m, { width: inner }),
      row({ name: 'Legend', align: 'center', gap: d('space/md') }, dot('map/sun', 'Sun'), dot('map/moon', 'Moon'),
        m.spot.facing != null ? row({ name: 'Legend / Classic view', align: 'center', gap: d('space/xs') }, el('div', { name: 'Bar', style: { width: d('stroke/thick'), height: d('space/md'), background: c('accent/primary'), flexShrink: 0 } }), text('Classic view', { name: 'Label', font: font('caption'), color: 'text/secondary' })) : null),
      text(sunAtLine(m), { name: 'Sun Line', font: font('callout'), color: 'text/primary', wrap: true }),
      fn ? text(fn, { name: 'Frame Note', font: font('callout'), color: 'text/secondary', wrap: true }) : null,
      row({ name: 'Moon Row', align: 'center', gap: d('space/sm') }, icon(m.moon.symbol, { size: dv('size/icon/large'), color: 'text/primary' }), text(moonLine(m), { name: 'Moon Line', font: font('callout'), color: 'text/secondary' }))), { name: 'SpotCard / Sky Arc' }));
}

// ---------------------------------------------------------------------------------------------------------------------
// HourlyStrip
// ---------------------------------------------------------------------------------------------------------------------
export function hourlyCanvas(m, { width = 868 } = {}) {
  const left = dv('size/control/heightLarge') + dv('space/sm'), plotW = width - left - dv('space/lg');
  const { lo, hi } = m.domain, span = hi - lo;
  const rowH = dv('size/icon/large') + dv('space/xxs'), H = rowH * 5;
  const x = (min) => left + ((min - lo) / span) * plotW;
  const colW = (plotW * 60) / span;
  const kids = [];
  for (const w of m.windows) {
    const x0 = Math.max(left, x(w.startMin)), x1 = Math.min(left + plotW, x(w.endMin));
    if (x1 <= x0) continue;
    const sel = w.kind === m.selected;
    kids.push(el('div', { name: `Window Tint / ${WINDOW_SHORT[w.kind]}`, style: abs({ left: f2(x0), top: 0, width: f2(x1 - x0), height: H, background: c(tint(w.kind)), opacity: op('window-tint') }) }));
    if (sel) kids.push(el('div', { name: 'Selected Window Tint', style: abs({ left: f2(x0), top: 0, width: f2(x1 - x0), height: H, background: c('selection/fill') }) }));
  }
  kids.push(col({ name: 'Row Labels', style: abs({ left: 0, top: rowH, width: left - dv('space/xs'), alignItems: 'flex-end' }) },
    ['Temp', 'Cloud', 'Rain', 'Wind'].map((t) => el('div', { name: `Row Label / ${t}`, style: { height: rowH, display: 'flex', alignItems: 'center' } }, text(t, { name: 'Label', font: font('caption'), color: 'text/secondary' })))));
  const hours = m.hours.filter((h) => (h.min >= lo && h.min <= hi) || (h.min + 59.98 >= lo && h.min + 59.98 <= hi));
  for (const h of hours) {
    const isMarker = m.marker.min >= h.min && m.marker.min < h.min + 60;
    const cellEl = (t, nm, color = 'text/primary') => el('div', { name: `Cell / ${nm}`, style: { height: rowH, display: 'flex', alignItems: 'center', justifyContent: 'center' } }, text(t, { name: nm, font: font('timeSmall'), color }));
    const cl = Math.max(0, x(h.min)), cr = Math.min(width, x(h.min) + colW);
    if (cr <= cl) continue;
    if (isMarker) kids.push(el('div', { name: 'Marker Hour Tint', style: abs({ left: f2(cl), top: 0, width: f2(cr - cl), height: H, background: c('text/primary'), opacity: 'calc(var(--opacity-selection-tint) / 2)' }) }));
    kids.push(col({ name: `Hour ${String(Math.floor(h.min / 60)).padStart(2, '0')}`, align: 'stretch',
      style: abs({ left: f2(cl), top: 0, width: f2(cr - cl), height: H }) },
    el('div', { name: 'Symbol', style: { height: rowH, display: 'flex', alignItems: 'center', justifyContent: 'center' } }, icon(h.symbol, { size: 13, color: 'text/secondary' })),
    cellEl(h.temp, 'Temp'), cellEl(String(Math.round(h.cover * 100)), 'Cloud'), cellEl(h.rain >= 0.2 ? String(Math.round(h.rain * 100)) : '', 'Rain', 'accent/text'), cellEl(String(h.windMph), 'Wind')));
  }
  return el('div', { name: 'Canvas / Hourly Strip', style: { position: 'relative', width, height: H, overflow: 'hidden', flexShrink: 0 } }, kids);
}
export function hourlyStrip(m, { width } = {}) {
  if (!m.hasWeather) return null;
  const inner = (width ?? 892) - 2 * dv('space/md');
  return col({ name: 'HourlyStrip', gap: d('space/md'), w: width },
    row({ name: 'Title Row', align: 'baseline', justify: 'space-between' },
      text('Hour by hour', { name: 'Section Title', font: font('title/section'), color: 'text/primary' }),
      text(m.updated, { name: 'Updated', font: font('footnote'), color: 'text/secondary' })),
    spotCard(col({ name: 'Hourly Body', gap: d('space/sm') }, hourlyCanvas(m, { width: inner }),
      row({ name: 'Footer', align: 'baseline', justify: 'space-between' }, weatherAttribution({ sample: m.sample }), text('Wind in mph', { name: 'Wind Unit', font: font('caption'), color: 'text/secondary' }))), { name: 'SpotCard / Hourly' }));
}
