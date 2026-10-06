// column.mjs - Option A: "Light through the day" as a full-height column (time runs top -> bottom) between the sidebar and the list.
// lightColumn({width=208, height, mode:'day'|'set', empty=false, scrubbing=true, marker=MARKER_MIN, scrim:'none'|'band'|'both', spot, compact}) -> Html
//   height = the body height under the toolbar (820-52 = 768, 652-52 = 600). Anatomy: header 32 | range control 44 | readout 40 | timeline (rest) | footer 29.
import { el, row, col, text, svgEl, raw } from '../../../../paper/tools/lib/h.mjs';
import { c, dv, font, op, canvas, currentTheme } from '../../../../paper/tools/lib/tokens.mjs';
import { windowsToday, HOURS, SUN, MARKER_MIN, NOW_MIN, skyGradient, windowUnder, fmt, toMin, SPOT } from '../data.mjs';
import { segmented, windowSymbol, scoreChip } from '../shell.mjs';
import { tintToken } from '../timeline-h.mjs';

const f2 = (n) => Math.round(n * 100) / 100;
const abs = (o) => ({ position: 'absolute', ...o });
const stroke = (tok, w, extra = '') => `style="stroke:${c(tok)};stroke-width:${w}${extra}" fill="none"`;
const fillS = (tok, extra = '') => `style="fill:${c(tok)}${extra}"`;
const TN = { fontVariantNumeric: 'tabular-nums' };

export const HEADER_H = 32, CONTROLS_H = 44, READOUT_H = 40, FOOTER_H = 29;
const PAD_T = 22, PAD_B = 10, UNIT_H = 22, GAP = 26;

/** Event unit exactly as the list rows draw it (symbol 20, gap 8, chip 36x22, time 12), optionally bold for the selected window. */
export function unit(w, { bold = false } = {}) {
  const u = row({ name: `EventUnit / ${w.short}`, align: 'center', gap: 3, noshrink: true, style: { height: UNIT_H } },
    windowSymbol(w.kind, { size: 16, color: bold ? 'text/primary' : 'text/secondary' }),
    w.scored ? scoreChip({ score: w.score, size: 'compact' }) : null,
    text(w.start, { name: 'Start Time', font: font('timeSmall', { size: 10, lineHeight: 14, weight: bold ? 'semibold' : undefined }), color: bold ? 'text/primary' : 'text/secondary', style: TN }));
  return bold ? row({ name: 'Selected Capsule', align: 'center', noshrink: true, style: { height: 24, padding: '0 3px', borderRadius: 999, background: c('selection/fill'), boxShadow: `inset 0 0 0 1px ${c('accent/primary')}` } }, u) : u;
}
const sunUnit = (kind, time, short) => row({ name: `SunTime / ${short}`, align: 'center', gap: 8, noshrink: true, style: { height: UNIT_H } },
  windowSymbol(kind, { size: 20 }), text(time, { name: 'Time', font: font('timeSmall', { size: 12, lineHeight: 16 }), color: 'text/secondary', style: TN }));

/** Spread unit centres so none are closer than GAP: cluster, centre each cluster on the mean of its anchors. */
function spread(anchors, lo, hi) {
  const order = anchors.map((a, i) => ({ a, i })).sort((p, q) => p.a - q.a);
  let groups = order.map((o) => ({ items: [o], top: o.a }));
  const settle = (g) => { g.top = g.items.reduce((s, o, k) => s + (o.a - k * GAP), 0) / g.items.length; };
  for (let changed = true; changed;) {
    changed = false;
    for (let k = 0; k < groups.length - 1; k++) {
      if (groups[k].top + groups[k].items.length * GAP > groups[k + 1].top + 0.001) {
        groups[k].items.push(...groups[k + 1].items); groups.splice(k + 1, 1); settle(groups[k]); changed = true; break;
      }
    }
  }
  const out = [];
  for (const g of groups) {
    const top = Math.min(Math.max(g.top, lo), hi - (g.items.length - 1) * GAP);
    g.items.forEach((o, k) => { out[o.i] = top + k * GAP; });
  }
  return out;
}

export function lightColumn({ width = 208, height = 768, mode = 'day', empty = false, scrubbing = true, marker = MARKER_MIN, readoutValues = null, scrim = 'none', windows = windowsToday, hours = HOURS, sun = SUN, now = NOW_MIN } = {}) {
  const compact = width < 200;
  const dom = mode === 'set' ? { lo: sun.sunset - 120 + 0, hi: sun.sunset + 120 } : { lo: 0, hi: 1440 };
  if (mode === 'set') { dom.lo = toMin('16:43'); dom.hi = toMin('20:43'); }
  const canvasH = height - HEADER_H - CONTROLS_H - READOUT_H - FOOTER_H;
  const H = canvasH - PAD_T - PAD_B;
  const y = (m) => PAD_T + ((m - dom.lo) / (dom.hi - dom.lo)) * H;
  // horizontal geometry
  const G = compact ? { inset: 12, bar: 32, band: 18, gapBar: 4 } : { inset: 12, bar: 48, band: 24, gapBar: 4 };
  const barX = G.inset + 28, barR = barX + G.bar, bandX = barR + G.gapBar, bandR = bandX + G.band;
  const bx = bandR + 4, ux = bandR + 8;
  const thin = dv('stroke/thin'), reg = dv('stroke/regular'), thick = dv('stroke/thick'), hair = dv('stroke/hairline');
  const parts = [], items = [];
  const radius = dv('radius/badge');

  // sky bar + band track
  const sky = el('div', { name: 'Sky Bar', style: abs({ left: barX, top: PAD_T, width: G.bar, height: H, borderRadius: radius, background: skyGradient(dom, 'to bottom', sun) }) });
  const skyEdge = el('div', { name: 'Sky Bar Edge', style: abs({ left: barX, top: PAD_T, width: G.bar, height: H, borderRadius: radius, boxShadow: currentTheme() === 'dark' ? `inset 0 0 0 1px ${c('text/quaternary')}` : `inset 0 0 0 0.5px ${c('separator/default')}`, pointerEvents: 'none' }) });
  if (!empty) parts.push(`<rect x="${bandX}" y="${PAD_T}" width="${G.band}" height="${H}" rx="3" ${fillS('background/control', ';fill-opacity:0.5')}/>`);
  const ext = (w) => { let a = y(Math.max(dom.lo, w.startMin)), b = y(Math.min(dom.hi, w.endMin)); if (b - a < 4) { const m = (a + b) / 2; a = m - 2; b = m + 2; } return [a, b]; };
  const vis = windows.filter((w) => w.endMin > dom.lo && w.startMin < dom.hi);
  const markerOn = !empty && marker != null && marker >= dom.lo && marker <= dom.hi;
  const my = markerOn ? y(marker) : null;

  // hour axis
  const labels = [];
  const step = mode === 'set' ? 60 : 180;
  for (let m = Math.ceil(dom.lo / 30) * 30; m <= dom.hi + 0.01; m += 30) {
    if (mode !== 'set' && m % 60 !== 0) continue;
    const major = m % step === 0 && (mode === 'set' ? m % 60 === 0 : true);
    const hourly = m % 60 === 0;
    if (!major && mode !== 'set') continue;
    const ty = f2(y(m));
    if (my != null && Math.abs(ty - my) < 12) continue;
    parts.push(`<path d="M${barX - (major ? 4 : 2)} ${ty}H${barX}" ${major ? stroke('text/secondary', thin) : stroke('text/tertiary', thin)}/>`);
    if (major && hourly && !(my != null && Math.abs(ty - my) < 12)) {
      labels.push(text(String(Math.floor(m / 60) % 24).padStart(2, '0'), { name: `Hour ${Math.floor(m / 60) % 24}`, font: font('timeSmall'), color: 'text/secondary', w: 14, align: 'right', style: { ...abs({ left: barX - 6 - 14, top: f2(y(m) - 6.5), height: 13 }), ...TN } }));
    }
  }

  if (!empty) {
    // window tints in the band; selected fill
    for (const w of vis) {
      const [a, b] = ext(w);
      parts.push(`<rect x="${bandX}" y="${f2(a)}" width="${G.band}" height="${f2(b - a)}" ${fillS(tintToken(w.kind), `;fill-opacity:${currentTheme() === 'dark' ? 0.16 : 0.10}`)}/>`);
      if (w.selected) parts.push(`<rect x="${bandX}" y="${f2(a)}" width="${G.band}" height="${f2(b - a)}" ${fillS('selection/fill')}/>`);
    }
    // 50 % guide + cloud area (grows rightwards) + rain bars
    parts.push(`<path d="M${f2(bandX + G.band / 2)} ${PAD_T}V${PAD_T + H}" ${stroke('text/tertiary', hair)}/>`);
    const pts = [];
    for (let i = 0; i < hours.length; i++) pts.push([hours[i].min + 30, hours[i].cloud]);
    const clipped = [];
    for (let i = 0; i < pts.length; i++) {
      const [m, v] = pts[i];
      if (i > 0) { const [pm, pv] = pts[i - 1]; for (const e of [dom.lo, dom.hi]) if ((pm < e && m > e)) clipped.push([e, pv + ((v - pv) * (e - pm)) / (m - pm)]); }
      if (m >= dom.lo && m <= dom.hi) clipped.push([m, v]);
    }
    clipped.sort((p, q) => p[0] - q[0]);
    const X = (f) => f2(bandX + Math.min(1, Math.max(0, f)) * G.band);
    if (clipped.length > 1) {
      const ln = clipped.map(([m, v], i) => `${i ? 'L' : 'M'}${X(v)} ${f2(y(m))}`).join('');
      parts.push(`<path d="M${bandX} ${f2(y(clipped[0][0]))}${clipped.map(([m, v]) => `L${X(v)} ${f2(y(m))}`).join('')}L${bandX} ${f2(y(clipped[clipped.length - 1][0]))}Z" ${fillS('cloud/mid', `;fill-opacity:0.7`)}/>`,
        `<path d="${ln}" ${stroke('text/secondary', reg, ';stroke-linejoin:round')}/>`);
    }
    for (const h of hours) if (h.rain >= 0.1) {
      const ins = (y(h.min + 60) - y(h.min)) * 0.2;
      parts.push(`<rect x="${bandX}" y="${f2(y(h.min) + ins)}" width="${f2(h.rain * G.band)}" height="${f2(y(h.min + 60) - y(h.min) - 2 * ins)}" rx="${thin}" ${fillS('sky/blueHour')}/>`);
    }
    parts.push(`<rect x="${bandX + 0.25}" y="${PAD_T + 0.25}" width="${G.band - 0.5}" height="${H - 0.5}" rx="3" ${stroke('separator/default', hair)}/>`);
  }

  if (!empty) items.push(text('0–100%', { name: 'Band Scale', font: font('timeSmall'), color: 'text/tertiary', w: 40, align: 'center', style: abs({ left: f2(bandX + G.band / 2 - 20), top: PAD_T - 16, height: 13 }) }));
  // past scrim + now
  const nowOn = now >= dom.lo && now <= dom.hi;
  if (nowOn && scrim !== 'none') {
    const ny = y(now);
    const sx = scrim === 'both' ? barX : bandX;
    parts.push(`<rect x="${sx}" y="${PAD_T}" width="${bandR - sx}" height="${f2(ny - PAD_T)}" rx="${scrim === 'both' ? 0 : 0}" ${fillS('background/content', ';fill-opacity:0.5')}/>`);
  }
  // selected outline
  const selected = empty ? null : vis.find((w) => w.selected);
  if (selected) {
    const [a, b] = ext(selected);
    const r = `x="${barX - 1}" y="${f2(a - 1)}" width="${bandR - barX + 2}" height="${f2(b - a + 2)}" rx="3"`;
    parts.push(`<rect ${r} ${stroke('background/content', thick + 2 * thin)}/>`, `<rect ${r} ${stroke('accent/primary', thick)}/>`);
  }
  // now line
  if (nowOn) {
    const ny = f2(y(now));
    parts.push(`<path d="M${barX} ${ny}H${bandR}" ${stroke('accent/primary', reg)}/>`, `<circle cx="${barX}" cy="${ny}" r="2.5" ${fillS('accent/primary')}/>`);
    items.push(text('Now', { name: 'Now Label', font: font('captionStrong'), color: 'accent/text', style: abs({ left: bandR + 6, top: f2(ny - 6.5), height: 13 }) }));
  }

  // windows: brackets, leaders, units
  if (!empty) {
    const anchors = vis.map((w) => { const [a, b] = ext(w); return b - a < UNIT_H ? (a + b) / 2 : a + UNIT_H / 2; });
    const centres = spread(anchors, PAD_T + UNIT_H / 2, PAD_T + H - UNIT_H / 2);
    vis.forEach((w, i) => {
      const [a, b] = ext(w); const cy = centres[i]; const sel = !!w.selected;
      const openEnd = w.endMin > dom.hi;
      const a1 = a + 0.75, b1 = b - 0.75;
      parts.push(`<path d="M${bx - 3} ${f2(a1)}H${bx}V${f2(b1)}${openEnd ? '' : `H${bx - 3}`}" ${stroke(sel ? 'accent/primary' : 'text/secondary', sel ? thick : reg)}/>`);
      const sy = Math.min(Math.max(cy, a1), b1);
      if (Math.abs(sy - cy) > 1) parts.push(`<path d="M${bx} ${f2(sy)}H${bx + 2}V${f2(cy)}H${ux - 1}" ${stroke('text/tertiary', thin)}/>`);
      else parts.push(`<path d="M${bx} ${f2(cy)}H${ux - 1}" ${stroke('text/tertiary', thin)}/>`);
      items.push(el('div', { name: `Unit Anchor / ${w.short}`, style: abs({ left: sel ? ux - 2 : ux, top: f2(cy - 12), height: 24, display: 'flex', alignItems: 'center' }) }, unit(w, { bold: sel })));
    });
  } else {
    // empty: sunrise / sunset times only
    for (const [kind, min, short] of [['sunrise', sun.sunrise, 'Sunrise'], ['sunset', sun.sunset, 'Sunset']]) {
      const sy = f2(y(min));
      parts.push(`<path d="M${barR - 4} ${sy}H${barR + 12}" ${stroke('text/secondary', reg)}/>`);
      items.push(el('div', { name: `Sun Time Anchor / ${short}`, style: abs({ left: barR + 14, top: f2(sy - UNIT_H / 2), height: UNIT_H, display: 'flex', alignItems: 'center' }) }, sunUnit(kind, fmt(min), short)));
    }
  }

  // marker
  if (markerOn) {
    const m = f2(my);
    parts.push(`<path d="M${barX} ${m}H${bandR}" ${stroke('background/content', 3)}/>`);
    parts.push(`<path d="M${barX} ${m}H${bandR}" ${stroke('text/primary', scrubbing ? reg : thin, scrubbing ? '' : `;stroke-dasharray:${dv('stroke/dashLength')} ${dv('stroke/dashGap')}`)}/>`);
    parts.push(`<circle cx="${barR}" cy="${m}" r="4" style="fill:${c('text/primary')};stroke:${c('background/content')};stroke-width:1"/>`);
    items.push(row({ name: 'Time Pill', align: 'center', justify: 'center', style: abs({ left: barX - 2 - (compact ? 32 : 34), top: f2(my - 8), width: compact ? 32 : 34, height: 16, borderRadius: 8,
      background: scrubbing ? c('text/primary') : c('background/content'), border: scrubbing ? undefined : `0.5px solid ${c('text/tertiary')}`, boxShadow: scrubbing ? `0 0 0 1px ${c('background/content')}` : undefined }) },
    text(fmt(marker), { name: 'Pill Time', font: font('timeSmall', { weight: 'semibold' }), color: scrubbing ? 'background/content' : 'text/primary', style: TN })));
  }

  const timeline = el('div', { name: 'Timeline Canvas', style: { position: 'relative', width, height: canvasH, flexShrink: 0, overflow: 'hidden' } },
    sky, svgEl('Timeline Graphics', { width, height: canvasH, style: abs({ left: 0, top: 0 }) }, raw(parts.join('\n'))), skyEdge, labels, items);

  // header
  const header = row({ name: 'Column Header', align: 'center', justify: 'space-between', gap: 8, noshrink: true, style: { height: HEADER_H, padding: '0 12px', borderBottom: `0.5px solid ${c('separator/default')}` } },
    empty ? text('Select a place to see its light', { name: 'Empty Caption', font: font('subheadline'), color: 'text/secondary', style: { overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 } })
      : [text(SPOT.name, { name: 'Spot Name', font: font('subheadline', { weight: 'semibold' }), color: 'text/primary', style: { overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 } }),
        text('Today', { name: 'Day', font: font('subheadline'), color: 'text/secondary', noshrink: true })]);
  // range control
  const controls = row({ name: 'Range Control', align: 'center', noshrink: true, style: { height: CONTROLS_H, padding: '0 8px' } }, segmented(['Day', 'Rise', 'Set'], mode === 'set' ? 2 : 0, { width: width - 16 }));
  // readout: fixed two lines
  const w = windowUnder(marker, windows);
  const hr = hours.find((h) => marker >= h.min && marker < h.min + 60);
  const sel0 = windows.find((x) => x.selected);
  let l1, l2;
  if (empty) { l1 = 'Monterey area'; l2 = `Sunrise ${fmt(sun.sunrise)} · Sunset ${fmt(sun.sunset)}`; }
  else if (scrubbing) { l1 = `${fmt(marker)}${w ? ` · ${w.name ?? w.short}` : ''}`; l2 = readoutValues ?? (hr ? `${Math.round(hr.cloud * 100)}% cloud · ${Math.round(hr.rain * 100)}% rain` : 'No forecast'); }
  else { l1 = `${sel0.start}–${sel0.end} · ${sel0.short}`; l2 = '30% cloud · 0% rain'; }
  const readout = col({ name: 'Readout', justify: 'flex-start', noshrink: true, style: { height: READOUT_H, padding: '4px 12px 0', overflow: 'hidden' } },
    text(l1, { name: 'Readout Line 1', font: font('bodyEmphasis'), color: 'text/primary', style: { ...TN, overflow: 'hidden', textOverflow: 'ellipsis', height: 18 } }),
    text(l2, { name: 'Readout Line 2', font: font('subheadline'), color: 'text/secondary', style: { ...TN, overflow: 'hidden', textOverflow: 'ellipsis', height: 16 } }));
  // footer
  const sw = (tok, label, o) => row({ name: `Legend / ${label}`, align: 'center', gap: 4, noshrink: true },
    el('div', { name: 'Swatch', style: { width: 8, height: 8, borderRadius: 2, background: c(tok), opacity: o, border: `0.5px solid ${c('separator/default')}`, flexShrink: 0 } }),
    text(label, { name: 'Label', font: font('caption', { size: 11 }), color: 'text/secondary' }));
  const footer = row({ name: 'Footer', align: 'center', justify: 'space-between', noshrink: true, style: { height: FOOTER_H, padding: '0 12px', borderTop: `0.5px solid ${c('separator/default')}`, background: c('background/content') } },
    empty ? text('Sun times only', { name: 'Caption', font: font('caption', { size: 11 }), color: 'text/secondary' })
      : [row({ name: 'Legend', align: 'center', gap: 10 }, sw('cloud/mid', 'Cloud', 0.5), sw('sky/blueHour', 'Rain', 1)),
        text(compact ? 'As of 11:50' : 'Updated 11:50', { name: 'Updated', font: font('caption', { size: 11 }), color: 'text/secondary', style: TN })]);
  return col({ name: 'Light Column', w: width, h: height, noshrink: true, style: { background: c('background/content') } }, header, controls, readout, timeline, footer);
}
