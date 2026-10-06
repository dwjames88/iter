// timeline-b.mjs - Option B's LightTimeline: a copy of src/timeline-h.mjs extended for the full-width panel (shared file untouched).
// Differences: no left gutter (plot edge to edge, 0/50/100% labels sit inside the plot above their gridlines, with 12 pt of headroom above 100%),
// taller band/plot, 11 pt chart text, "past" hatch where there is no forecast, a "Now" notch, right-to-left bracket-label tiers (no leader ever
// crosses a label), two-line bracket labels in the zoomed view (name + score, time range), minor 30 min ticks, hairline edge on the band.
//
// timelineB(p) -> {html, layout}   p: width 328, bandHeight 88, plotHeight 112, headroom 12, tiers 3, domain {lo,hi}, tickEvery 3 (h), minorEvery 0 (min),
//   hourLabel (m)=>str, marker, selected kind, windows, hours, nowMin, forecastFrom (min), double (two-line labels), labelSize 11
import { text, el, svgEl, raw, row, col } from '../../../../paper/tools/lib/h.mjs';
import { c, dv, d, font, op, currentTheme } from '../../../../paper/tools/lib/tokens.mjs';
import { windowsToday, HOURS, SUN, MARKER_MIN, NOW_MIN, skyGradient, fmt } from '../data.mjs';
import { tintToken } from '../timeline-h.mjs';

const f2 = (n) => Math.round(n * 100) / 100;
const abs = (o) => ({ position: 'absolute', ...o });
const tw = (str, size, bold) => { let w = 0; for (const ch of String(str)) w += /[il.,:°·|'!–]/.test(ch) ? 0.27 : ch === ' ' ? 0.28 : /[A-Z0-9]/.test(ch) ? 0.62 : /[mwMW]/.test(ch) ? 0.82 : 0.52; return w * size * (bold ? 1.05 : 1); };

const PILL = 36;
function lab(str, { x, y, anchor = 'start', style = 'caption', color = 'text/secondary', name, size = 11, bold = false, bg = false }) {
  const h = 14, W = Math.ceil(tw(str, size, bold)) + (bg ? 3 : 8);
  const left = anchor === 'start' ? x : anchor === 'middle' ? x - W / 2 : x - W;
  return text(str, { name: name || `Label / ${str}`.slice(0, 50), font: font(style, { size, lineHeight: h, weight: bold ? 'semibold' : undefined }), color, w: W,
    align: anchor === 'middle' ? 'center' : anchor === 'end' ? 'right' : 'left', style: abs({ left: f2(left), top: f2(y), height: h, ...(bg ? { background: c('background/content') } : {}) }) });
}

export function timelineB(p0 = {}) {
  const p = { width: 328, bandHeight: 88, plotHeight: 112, headroom: 12, tiers: 3, domain: { lo: 0, hi: 1440 }, tickEvery: 3, minorEvery: 0, hourLabel: (m) => String((m / 60) % 24).padStart(2, '0'),
    marker: MARKER_MIN, selected: 'goldenEvening', windows: windowsToday, hours: HOURS, nowMin: NOW_MIN, forecastFrom: 11 * 60, double: false, ...p0 };
  const lg = 16, xs = 4, xxs = 2, sm = 8, thin = 1, reg = 1.5, thick = 2, hair = 0.5;
  const { lo, hi } = p.domain;
  const L = {}; L.tiersH = p.tiers * lg; L.bracketY = L.tiersH + xxs; L.skyTop = L.bracketY + xs + xxs; L.skyBottom = L.skyTop + p.bandHeight;
  L.axisBottom = L.skyBottom + 18; L.plotTop = L.axisBottom + sm; L.plotBottom = L.plotTop + p.plotHeight; L.total = L.plotBottom + xxs;
  L.left = 0; L.right = p.width; L.plotW = p.width; L.x = (m) => ((m - lo) / (hi - lo)) * p.width;
  const x = L.x, left = 0, right = p.width;
  const stroke = (tok, w, extra = '') => `style="stroke:${c(tok)};stroke-width:${w}${extra}" fill="none"`;
  const fillS = (tok, extra = '') => `style="fill:${c(tok)}${extra}"`;
  const parts = [], labels = [];
  const extent = (w) => { let x0 = Math.max(left, x(w.startMin)), x1 = Math.min(right, x(w.endMin)); if (x1 < x0) return [x0, x0];
    if (x1 - x0 < dv('chart/windowMinWidth')) { const mid = (x0 + x1) / 2; x0 = Math.max(left, mid - 2); x1 = Math.min(right, x0 + 4); } return [x0, x1]; };

  const sky = el('div', { name: 'Sky Band', style: abs({ left, top: L.skyTop, width: p.width, height: p.bandHeight, borderRadius: 8, background: skyGradient(p.domain, 'to right', SUN) }) });
  const edge = el('div', { name: 'Sky Band Edge', style: abs({ left, top: L.skyTop, width: p.width, height: p.bandHeight, borderRadius: 8, boxShadow: `inset 0 0 0 0.5px color-mix(in srgb, ${c('text/secondary')} 45%, transparent)` }) });

  // axis
  const hrStep = p.tickEvery * 60;
  for (let m = Math.ceil(lo / 30) * 30; m <= hi; m += 30) {
    const major = m % hrStep === 0, minor = p.minorEvery && m % p.minorEvery === 0 && !major;
    if (!major && !minor) continue;
    const tx = f2(x(m));
    parts.push(`<path d="M${tx} ${L.skyBottom}V${L.skyBottom + (major ? xs : 2)}" ${stroke('text/secondary', thin)}/>`);
    const lw = tw(p.hourLabel(m), 10) / 2 + 4;
    const covered = p.marker != null && Math.abs(tx - x(p.marker)) < PILL / 2 + lw + 1;
    if (major && !covered) labels.push(lab(p.hourLabel(m), { x: tx, y: L.skyBottom + xs, anchor: 'middle', style: 'timeSmall', name: `Hour ${p.hourLabel(m)}`, bg: p.windows.some((w) => w.kind === p.selected && Math.abs(tx - x(w.startMin)) < 14) }));
  }

  // plot
  const pt = L.plotTop, pb = L.plotBottom, y100 = pt + p.headroom, ph = pb - y100;
  const y = (f) => pb - Math.min(1, Math.max(0, f)) * ph;
  const defs = `<defs><pattern id="past" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="6" height="6" style="fill:${c('background/content')}"/><path d="M0 0V6" style="stroke:${c('text/tertiary')};stroke-width:1;stroke-opacity:0.5"/></pattern></defs>`;
  const fx = Math.max(left, x(p.forecastFrom));
  if (fx > left + 1) parts.push(`<rect x="0" y="${pt}" width="${f2(fx)}" height="${p.plotHeight}" style="fill:url(#past)"/>`,
    `<path d="M${f2(fx)} ${pt}V${pb}" ${stroke('text/tertiary', hair, ';stroke-dasharray:2 2')}/>`);
  for (const w of p.windows) {
    const [x0, x1] = extent(w); if (x1 <= x0) continue;
    parts.push(`<rect x="${f2(x0)}" y="${pt}" width="${f2(x1 - x0)}" height="${p.plotHeight}" ${fillS(tintToken(w.kind), `;fill-opacity:${currentTheme() === 'dark' ? 0.16 : 0.11}`)}/>`);
    if (w.kind === p.selected) parts.push(`<rect x="${f2(x0)}" y="${pt}" width="${f2(x1 - x0)}" height="${p.plotHeight}" ${fillS('selection/fill')}/>`);
  }
  for (const f of [0, 0.5, 1]) {
    parts.push(`<path d="M0 ${f2(y(f))}H${right}" ${stroke('separator/default', hair)}/>`);
    labels.push(lab(`${Math.round(f * 100)}%`, { x: 4, y: y(f) - 14, style: 'timeSmall', name: `Axis ${Math.round(f * 100)}%` }));
  }
  let pts = p.hours.map((h) => [x(h.min + 30), y(h.cloud)]);
  const first = p.hours[0];
  if (first && x(first.min) >= left && x(first.min) < pts[0][0]) pts = [[x(first.min), y(first.cloud)], ...pts];
  pts = pts.filter(([px]) => px >= left - 0.01 && px <= right + 0.01);
  if (pts.length > 1) {
    const top = pts.map(([px, py], i) => `${i ? 'L' : 'M'}${f2(px)} ${f2(py)}`).join('');
    const area = `M${f2(pts[0][0])} ${pb}${pts.map(([px, py]) => `L${f2(px)} ${f2(py)}`).join('')}L${f2(pts[pts.length - 1][0])} ${pb}Z`;
    parts.push(`<path d="${area}" ${fillS('cloud/mid', `;fill-opacity:${op('cloud-fill')}`)}/>`, `<path d="${top}" ${stroke('cloud/mid', reg, ';stroke-linejoin:round')}/>`);
  }
  for (const h of p.hours) { if (h.rain < 0.1) continue; const inset = (x(h.min + 60) - x(h.min)) * 0.2;
    parts.push(`<rect x="${f2(x(h.min) + inset)}" y="${f2(y(h.rain))}" width="${f2(Math.max(1, x(h.min + 60) - x(h.min) - 2 * inset))}" height="${f2(pb - y(h.rain))}" rx="1" ${fillS('sky/blueHour')}/>`); }

  // Now notch: triangle in the label row, hairline down the band and plot
  if (p.nowMin >= lo && p.nowMin <= hi) {
    const nx = f2(x(p.nowMin));
    parts.push(`<path d="M${nx} ${L.skyTop}V${pb}" ${stroke('text/secondary', hair, ';stroke-dasharray:2 2')}/>`,
      `<path d="M${f2(nx - 4)} ${L.skyTop - 6}H${f2(+nx + 4)}L${nx} ${L.skyTop - 1}Z" style="fill:${c('text/secondary')}"/>`);
    labels.push(lab(`Now ${fmt(p.nowMin)}`, { x: +nx + 6, y: L.skyTop - 20, anchor: 'start', style: 'captionStrong', color: 'text/secondary', name: 'Now Label', bold: true }));
  }

  // selected outline
  for (const w of p.windows.filter((w) => w.kind === p.selected)) {
    const [x0, x1] = extent(w); if (x1 <= x0) continue;
    const r = `x="${f2(x0 - thin)}" y="${f2(L.skyTop - thin)}" width="${f2(x1 - x0 + 2 * thin)}" height="${f2(pb - L.skyTop + 2 * thin)}" rx="4"`;
    parts.push(`<rect ${r} ${stroke('background/content', thick + 2 * thin)}/>`, `<rect ${r} ${stroke('accent/primary', thick)}/>`);
  }

  // brackets + labels. Right to left; each label takes the lowest tier whose placed labels it clears; the leader goes straight down at the bracket's x.
  const items = p.windows.map((w) => ({ w, e: extent(w) })).filter((i) => i.e[1] > i.e[0]).sort((a, b) => b.e[0] - a.e[0]);
  const placed = Array.from({ length: p.tiers }, () => []);
  for (const { w, e: [x0, x1] } of items) {
    const sel = w.kind === p.selected;
    parts.push(`<path d="M${f2(x0)} ${L.bracketY + xs}V${L.bracketY}H${f2(x1)}V${L.bracketY + xs}" ${stroke(sel ? 'accent/primary' : 'text/secondary', sel ? thick : reg)}/>`);
    const l1 = w.scored ? `${w.short} ${w.score}` : w.short;
    const wd = tw(l1, 11, sel) + 2;
    const lx = Math.max(-4, Math.min(x0, right - wd));
    let tier = 0; while (tier < p.tiers - 1 && placed[tier].some(([a, b]) => lx < b + (p.double ? 16 : 4) && lx + wd > a - (p.double ? 16 : 4))) tier++;
    placed[tier].push([lx, lx + wd]);
    const ty = L.tiersH - (tier + 1) * lg;
    labels.push(lab(l1, { x: lx, y: ty, style: sel ? 'captionStrong' : 'caption', color: w.scored ? 'text/primary' : 'text/secondary', name: `Bracket Label / ${w.short}`, bold: sel }));
    if (tier > 0) parts.push(`<path d="M${f2(x0)} ${ty + 14}V${L.bracketY}" ${stroke(sel ? 'accent/primary' : 'separator/default', sel ? thin : hair)}/>`);
  }

  // marker (scrubbing: solid)
  if (p.marker != null && p.marker >= lo && p.marker <= hi) {
    const mx = f2(x(p.marker));
    parts.push(`<path d="M${mx} ${L.skyTop}V${pb}" ${stroke('background/content', 4)}/>`, `<path d="M${mx} ${L.skyTop}V${pb}" ${stroke('text/primary', reg)}/>`,
      `<circle cx="${mx}" cy="${L.skyBottom}" r="4.5" style="fill:${c('text/primary')};stroke:${c('background/content')};stroke-width:1.5"/>`);
  }
  if (p.marker != null && p.marker >= lo && p.marker <= hi) {
    const mx = x(p.marker);
    labels.push(el('div', { name: 'Marker Time Pill', style: abs({ left: f2(mx - PILL / 2), top: L.skyBottom + xs + 0.5, width: PILL, height: 14, borderRadius: 7, background: c('text/primary'), display: 'flex', alignItems: 'center', justifyContent: 'center' }) },
      text(fmt(p.marker), { name: 'Marker Time', font: font('timeSmall', { size: 10, lineHeight: 14, weight: 'semibold' }), color: 'background/window' })));
  }
  const html = el('div', { name: 'Canvas / Light Timeline', style: { position: 'relative', width: p.width, height: L.total, flexShrink: 0 } },
    sky, edge, svgEl('Timeline Graphics', { width: p.width, height: L.total, style: abs({ left: 0, top: 0 }) }, raw(defs + parts.join('\n'))), labels);
  return { html, layout: L };
}

export function readoutB(p = {}) {
  return row({ name: 'Readout', align: 'center', gap: 6, noshrink: true, style: { height: 20 } },
    text(p.values ?? '18:26 · 25% cloud · 0% rain', { name: 'Readout Values', font: font('bodyEmphasis'), color: 'text/primary' }),
    text('·', { name: 'Dot', font: font('body'), color: 'text/secondary' }),
    text(p.window ?? 'Sunset', { name: 'Window Under Marker', font: font('subheadline'), color: 'text/secondary' }));
}
const sw = (tok, label) => row({ name: `Legend / ${label}`, align: 'center', gap: 4 },
  el('div', { name: 'Swatch', style: { width: 12, height: 12, borderRadius: 2, background: c(tok), border: `0.5px solid ${c('separator/default')}`, flexShrink: 0 } }),
  text(label, { name: 'Label', font: font('caption', { size: 11 }), color: 'text/secondary' }));
export const legendB = (narrow = false) => row({ name: 'Legend', align: 'center', gap: 12, noshrink: true, style: { height: 16 } }, sw('cloud/mid', 'Cloud cover'), sw('sky/blueHour', 'Chance of rain'),
  el('div', { name: 'Spacer', style: { flex: '1 1 0' } }), narrow ? null : text('Drag to read any time', { name: 'Hint', font: font('caption', { size: 11 }), color: 'text/tertiary' }));
