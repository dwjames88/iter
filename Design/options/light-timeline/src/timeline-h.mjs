// timeline-h.mjs - the horizontal "Light through the day" timeline, redrawn from the real app (screenshot 10) and
// COMPONENTS.md LightTimeline. Everything is parameterised so Options B and C can grow it.
//
// timelineLayoutH(p)  -> {tiersH, bracketY, skyTop, skyBottom, axisBottom, plotTop, plotBottom, total, left, right, plotW, x(min)}
// timelineCanvasH(p)  -> Html canvas (position:relative, width p.width, height layout.total). Same coordinates as the layout,
//                        so a caller can wrap it and add absolutely positioned overlays using layout.x(min).
// timelineReadoutH(p) -> readout row;  timelineLegendH(p) -> legend row
// lightTimelineModule(p) -> title + zoom segmented + card(readout, canvas, legend): the whole module as in the card.
// Params p (all optional):
//   width 336 (canvas width)  gutter 44 (left, for % labels)  rightInset 16  tiers 3  bandHeight 56  axisHeight 18  plotHeight 80 (0 = no plot)
//   domain {lo:0,hi:1440} (minutes)  tickEvery 3 (hours)  marker minute (MARKER_MIN)  selected window kind ('goldenEvening'; null = none)
//   windows (windowsToday)  hours (HOURS)  sun (SUN)  bandRadius 6  showBrackets true  showLegend true  zoom 0|1|2 (segmented index)
//   readoutValues (string override, e.g. '18:26 · 25% cloud · 0% rain')  gapAfterBand 0 (extra px between the axis and the plot)
import { col, row, text, el, svgEl, raw, spacer } from '../../../paper/tools/lib/h.mjs';
import { c, d, dv, font, op } from '../../../paper/tools/lib/tokens.mjs';
import { windowsToday, HOURS, SUN, MARKER_MIN, skyGradient, windowUnder, fmt, frac } from './data.mjs';
import { segmented } from './shell.mjs';

const f2 = (n) => Math.round(n * 100) / 100;
const abs = (o) => ({ position: 'absolute', ...o });
const SZ = { caption: 10, captionStrong: 10, timeSmall: 10 };
const tw = (str, size, bold) => { let w = 0; for (const ch of String(str)) w += /[il.,:°·|'!]/.test(ch) ? 0.27 : ch === ' ' ? 0.28 : /[A-Z0-9]/.test(ch) ? 0.62 : /[mwMW]/.test(ch) ? 0.82 : 0.52; return w * size * (bold ? 1.04 : 1); };
export const tintToken = (kind) => (kind === 'goldenMorning' || kind === 'goldenEvening' ? 'sky/golden' : kind === 'night' ? 'sky/night' : 'sky/blueHour');
const stroke = (tok, w, extra = '') => `style="stroke:${c(tok)};stroke-width:${w}${extra}" fill="none"`;
const fillS = (tok, extra = '') => `style="fill:${c(tok)}${extra}"`;

/** A text label on a canvas. anchor start|middle|end; vAnchor top|middle|bottom. */
export function lab(str, { x, y, anchor = 'start', vAnchor = 'top', style = 'caption', color = 'text/secondary', name, w }) {
  const size = SZ[style] ?? 10, h = 13;
  const W = w ?? Math.ceil(tw(str, size, style === 'captionStrong')) + 12;
  const left = anchor === 'start' ? x : anchor === 'middle' ? x - W / 2 : x - W;
  const top = vAnchor === 'top' ? y : vAnchor === 'middle' ? y - h / 2 : y - h;
  return text(str, { name: name || `Label / ${str}`.slice(0, 50), font: font(style), color, w: W, align: anchor === 'middle' ? 'center' : anchor === 'end' ? 'right' : 'left', style: abs({ left: f2(left), top: f2(top), height: h }) });
}

const norm = (p = {}) => ({ width: 336, gutter: 44, rightInset: 16, tiers: 3, bandHeight: dv('chart/timelineHeight'), axisHeight: dv('chart/timelineAxisHeight'), plotHeight: 80,
  domain: { lo: 0, hi: 1440 }, tickEvery: 3, marker: MARKER_MIN, selected: 'goldenEvening', windows: windowsToday, hours: HOURS, sun: SUN, bandRadius: dv('radius/badge'),
  showBrackets: true, showLegend: true, gapAfterBand: 0, zoom: 0, ...p });

export function timelineLayoutH(p0) {
  const p = norm(p0);
  const xs = dv('space/xs'), xxs = dv('space/xxs'), sm = dv('space/sm'), lg = dv('space/lg');
  const tiersH = p.showBrackets ? p.tiers * lg : 0;
  const bracketY = tiersH + xxs;
  const skyTop = p.showBrackets ? bracketY + xs + xxs : 0;
  const skyBottom = skyTop + p.bandHeight;
  const axisBottom = skyBottom + p.axisHeight;
  const plotTop = axisBottom + sm + p.gapAfterBand;
  const plotBottom = plotTop + p.plotHeight;
  const left = p.gutter, right = p.width - p.rightInset, plotW = right - left;
  const { lo, hi } = p.domain;
  return { tiersH, bracketY, skyTop, skyBottom, axisBottom, plotTop, plotBottom, total: p.plotHeight ? plotBottom + xxs : axisBottom, left, right, plotW, x: (min) => left + ((min - lo) / (hi - lo)) * plotW };
}

export function timelineCanvasH(p0) {
  const p = norm(p0);
  const L = timelineLayoutH(p);
  const { left, right, plotW, x } = L;
  const { lo, hi } = p.domain;
  const xs = dv('space/xs'), xxs = dv('space/xxs'), lg = dv('space/lg'), thin = dv('stroke/thin'), reg = dv('stroke/regular'), thick = dv('stroke/thick'), hair = dv('stroke/hairline');
  const parts = [], labels = [];
  const extent = (w) => {
    let x0 = Math.max(left, x(w.startMin)), x1 = Math.min(right, x(w.endMin));
    if (x1 < x0) return [x0, x0];
    const mw = dv('chart/windowMinWidth');
    if (x1 - x0 < mw) { const mid = (x0 + x1) / 2; x0 = Math.max(left, mid - mw / 2); x1 = Math.min(right, x0 + mw); }
    return [x0, x1];
  };
  const sky = el('div', { name: 'Sky Band', style: abs({ left, top: L.skyTop, width: plotW, height: p.bandHeight, borderRadius: p.bandRadius, background: skyGradient(p.domain, 'to right', p.sun) }) });

  for (let hr = 0; hr <= 24; hr += p.tickEvery) {
    const mn = hr * 60; if (mn < lo || mn > hi) continue;
    const tx = x(mn);
    parts.push(`<path d="M${f2(tx)} ${L.skyBottom}V${L.skyBottom + xs}" ${stroke('text/secondary', thin)}/>`);
    labels.push(lab(String(hr % 24).padStart(2, '0'), { x: tx, y: L.skyBottom + xs, anchor: 'middle', style: 'timeSmall', name: `Hour ${hr % 24}` }));
  }

  if (p.plotHeight) {
    const pt = L.plotTop, pb = L.plotBottom, ph = pb - pt;
    const y = (f) => pb - Math.min(1, Math.max(0, f)) * ph;
    for (const w of p.windows) {
      const [x0, x1] = extent(w); if (x1 <= x0) continue;
      parts.push(`<rect x="${f2(x0)}" y="${pt}" width="${f2(x1 - x0)}" height="${ph}" ${fillS(tintToken(w.kind), `;fill-opacity:${op('window-tint')}`)}/>`);
      if (w.kind === p.selected) parts.push(`<rect x="${f2(x0)}" y="${pt}" width="${f2(x1 - x0)}" height="${ph}" ${fillS('selection/fill')}/>`);
    }
    for (const f of [0, 0.5, 1]) {
      parts.push(`<path d="M${left} ${f2(y(f))}H${right}" ${stroke('separator/default', hair)}/>`);
      labels.push(lab(`${Math.round(f * 100)}%`, { x: left - xs, y: y(f), anchor: 'end', vAnchor: 'middle', style: 'timeSmall', name: `Axis ${Math.round(f * 100)}%` }));
    }
    const pts = p.hours.map((h) => [x(h.min + 30), y(h.cloud)]).filter(([px]) => px >= left - 0.01 && px <= right + 0.01);
    if (pts.length > 1) {
      const top = pts.map(([px, py], i) => `${i ? 'L' : 'M'}${f2(px)} ${f2(py)}`).join('');
      const area = `M${f2(pts[0][0])} ${pb}${pts.map(([px, py]) => `L${f2(px)} ${f2(py)}`).join('')}L${f2(pts[pts.length - 1][0])} ${pb}Z`;
      parts.push(`<path d="${area}" ${fillS('cloud/mid', `;fill-opacity:${op('cloud-fill')}`)}/>`, `<path d="${top}" ${stroke('cloud/mid', reg, ';stroke-linejoin:round')}/>`);
    }
    for (const h of p.hours) {
      if (h.rain < 0.1) continue;
      const inset = (x(h.min + 60) - x(h.min)) * 0.2;
      const x0 = x(h.min) + inset, x1 = x(h.min + 60) - inset;
      parts.push(`<rect x="${f2(x0)}" y="${f2(y(h.rain))}" width="${f2(Math.max(1, x1 - x0))}" height="${f2(pb - y(h.rain))}" rx="${thin}" ${fillS('sky/blueHour')}/>`);
    }
  }

  const bottom = p.plotHeight ? L.plotBottom : L.skyBottom;
  for (const w of p.windows.filter((w) => w.kind === p.selected)) {
    const [x0, x1] = extent(w); if (x1 <= x0) continue;
    const r = `x="${f2(x0 - thin)}" y="${f2(L.skyTop - thin)}" width="${f2(x1 - x0 + 2 * thin)}" height="${f2(bottom - L.skyTop + 2 * thin)}" rx="${p.bandRadius / 2}"`;
    parts.push(`<rect ${r} ${stroke('background/control', thick + 2 * thin)}/>`, `<rect ${r} ${stroke('accent/primary', thick)}/>`);
  }

  if (p.showBrackets) {
    const ends = Array(p.tiers).fill(-Infinity);
    for (const w of [...p.windows].sort((a, b) => a.startMin - b.startMin)) {
      const [x0, x1] = extent(w); if (x1 <= x0) continue;
      const sel = w.kind === p.selected;
      parts.push(`<path d="M${f2(x0)} ${L.bracketY + xs}V${L.bracketY}H${f2(x1)}V${L.bracketY + xs}" ${stroke(sel ? 'accent/primary' : 'text/secondary', sel ? thick : reg)}/>`);
      const str = w.scored ? `${w.short} ${w.score}` : w.short;
      const wd = tw(str, 10, sel);
      let lx = Math.max(left - dv('space/sm'), Math.min(x0, right - wd));
      let tier = 0;
      while (tier < p.tiers - 1 && lx < ends[tier] + xs) tier++;
      ends[tier] = lx + wd;
      const ty = L.tiersH - (tier + 1) * lg;
      labels.push(lab(str, { x: lx, y: ty, style: sel ? 'captionStrong' : 'caption', color: w.scored ? 'text/primary' : 'text/secondary', name: `Bracket Label / ${w.short}` }));
      if (tier > 0) parts.push(`<path d="M${f2(x0)} ${ty + lg - thin}V${L.bracketY}" ${stroke('separator/default', hair)}/>`);
    }
  }

  if (p.marker != null && p.marker >= lo && p.marker <= hi) {
    const mx = f2(x(p.marker));
    parts.push(`<path d="M${mx} ${L.skyTop}V${bottom}" ${stroke('background/control', thin * 3)}/>`,
      `<path d="M${mx} ${L.skyTop}V${bottom}" ${stroke('text/primary', thin, `;stroke-dasharray:${dv('stroke/dashLength')} ${dv('stroke/dashGap')}`)}/>`,
      `<circle cx="${mx}" cy="${L.skyBottom}" r="${xs}" style="fill:${c('text/primary')};stroke:${c('background/control')};stroke-width:${thin}"/>`);
  }
  return el('div', { name: 'Canvas / Light Timeline', style: { position: 'relative', width: p.width, height: L.total, flexShrink: 0 } },
    sky, svgEl('Timeline Graphics', { width: p.width, height: L.total, style: abs({ left: 0, top: 0 }) }, raw(parts.join('\n'))), labels);
}

export function timelineReadoutH(p0) {
  const p = norm(p0);
  const w = windowUnder(p.marker, p.windows);
  const h = p.hours.find((x) => p.marker >= x.min && p.marker < x.min + 60);
  const vals = p.readoutValues ?? [fmt(p.marker), h ? `${Math.round(h.cloud * 100)}% cloud` : null, h ? `${Math.round(h.rain * 100)}% rain` : null].filter(Boolean).join(' · ');
  return row({ name: 'Readout', align: 'center', gap: d('space/sm'), style: { minHeight: d('size/badge/height') } },
    text(vals, { name: 'Readout Values', font: font('bodyEmphasis'), color: 'text/primary', wrap: true, style: { maxWidth: 124 } }),
    w ? [text('·', { name: 'Dot', font: font('body'), color: 'text/secondary' }), text(w.short, { name: 'Window Under Marker', font: font('subheadline'), color: 'text/secondary' })] : null,
    spacer(), text('Hover or drag to read any time', { name: 'Hint', font: font('caption'), color: 'text/tertiary', wrap: true, style: { width: 104 } }));
}
const sw = (tok, label) => row({ name: `Legend / ${label}`, align: 'center', gap: d('space/xs') },
  el('div', { name: 'Swatch', style: { width: 12, height: 12, borderRadius: 2, background: c(tok), border: `0.5px solid ${c('separator/default')}`, flexShrink: 0 } }),
  text(label, { name: 'Label', font: font('caption'), color: 'text/secondary' }));
export const timelineLegendH = () => row({ name: 'Legend', align: 'center', gap: d('space/md') }, sw('cloud/mid', 'Cloud cover'), sw('sky/blueHour', 'Chance of rain'));

/** The whole module: "Light through the day" title, zoom segmented, card with readout + canvas + legend. p.width = module width (card width); canvas is width - 24. */
export function lightTimelineModule(p0 = {}) {
  const width = p0.width ?? 336;
  const p = norm({ ...p0, width: width - 24 });
  return col({ name: 'LightTimeline', gap: d('space/md'), w: width, noshrink: true },
    text('Light through the day', { name: 'Section Title', font: font('title/section', { size: 15, lineHeight: 20 }), color: 'text/primary' }),
    segmented(['Full day', 'Sunrise ±2 h', 'Sunset ±2 h'], p.zoom, { width }),
    col({ name: 'SpotCard / Timeline', gap: d('space/sm'), pad: d('space/md'), style: { background: c('background/control'), borderRadius: d('radius/card'), border: `0.5px solid ${c('separator/default')}`, alignSelf: 'stretch' } },
      timelineReadoutH(p), timelineCanvasH(p), p.showLegend ? timelineLegendH() : null));
}
