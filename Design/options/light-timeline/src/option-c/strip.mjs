// option-c/strip.mjs - Option C: the Light strip that docks across the top of the map pane.
// Nothing shared is edited; the sky/plot drawing logic is COPIED from ../timeline-h.mjs and extended (full-width band, hourly labels,
// bracket labels as event units, labels inside the plot, scrub flag, "Now" notch).
//
// lightStrip({ mapW, top=12, height=256, plotH=64, marker, selected, zoom, windows }) -> Html  (absolute, pane-relative)
// lightStripCollapsed({ mapW, top=12 }) -> Html  (44 pt bar)
// stripGeometry(mapW, opts) -> numbers used by the artboard (strip bottom edge etc.)
import { el, row, col, text, svgEl, raw } from '../../../../paper/tools/lib/h.mjs';
import { c, d, dv, canvas, font, op, currentTheme } from '../../../../paper/tools/lib/tokens.mjs';
import { icon } from '../../../../paper/tools/lib/icons.mjs';
import { windowsToday, HOURS, SUN, MARKER_MIN, NOW_MIN, skyGradient, windowUnder, fmt, SPOT } from '../data.mjs';
import { eventUnit, windowSymbol, scoreChip } from '../shell.mjs';
import { tintToken } from '../timeline-h.mjs';

const f2 = (n) => Math.round(n * 100) / 100;
const abs = (o) => ({ position: 'absolute', ...o });
const PAD = 12;               // strip inset from the pane edge, and inner padding
const HOUR_FONT = 11;

/** Absolutely placed single-line label. anchor: start|middle|end of x. */
function lab(str, { x, y, anchor = 'start', style = 'timeSmall', size = HOUR_FONT, color = 'text/secondary', name, w = 40, h = 14, weight }) {
  const left = anchor === 'start' ? x : anchor === 'middle' ? x - w / 2 : x - w;
  return text(str, { name: name || `Label / ${str}`.slice(0, 50), font: font(style, { size, lineHeight: h, ...(weight ? { weight } : {}) }), color, w,
    align: anchor === 'middle' ? 'center' : anchor === 'end' ? 'right' : 'left', style: abs({ left: f2(left), top: f2(y), height: h }) });
}

/** Compact segmented control (12 pt labels) - same coral selected segment as the app's, narrower than shell.segmented. */
function compactSegmented(items, selectedIndex, { height = 24, padX = 10 } = {}) {
  return row({ name: 'Segmented Control', pad: 2, radius: 8, noshrink: true, style: { height: height + 4, background: canvas('control/segmented-track'), alignItems: 'stretch' } },
    items.map((label, i) => {
      const sel = i === selectedIndex;
      return row({ name: `Segment / ${label}`.slice(0, 50), align: 'center', justify: 'center', radius: 6, noshrink: true,
        style: { padding: `0 ${padX}px`, background: sel ? c('accent/primary') : undefined } },
      text(label, { name: 'Label', font: font('body', { size: 12, lineHeight: 16 }), color: sel ? 'accent/onAccent' : 'text/primary' }));
    }));
}

function chevronButton(sym, name) {
  return row({ name, align: 'center', justify: 'center', noshrink: true, radius: 14,
    style: { width: 28, height: 28, background: c('background/control'), border: `0.5px solid ${c('separator/default')}` } }, icon(sym, { size: 13, color: 'text/secondary', weight: 'semibold' }));
}

const panelStyle = () => ({
  borderRadius: d('radius/panel'), background: `color-mix(in srgb, ${c('background/window')} 96%, transparent)`,
  border: `0.5px solid ${c('separator/default')}`, boxShadow: canvas('shadow/material'),
});

/** A bracket-tier event unit: symbol 16 + compact chip + start time (scored), or symbol + time only (passed / no score). */
function tierUnit(w, { selected = false, withTime = true } = {}) {
  const passed = !w.scored;
  const tf = font('timeSmall', { size: 11, lineHeight: 16, ...(selected ? { weight: 'semibold' } : {}) });
  return row({ name: `Unit / ${w.short}`, align: 'center', gap: 4, noshrink: true, style: { height: 18 } },
    windowSymbol(w.kind, { size: 16, color: passed ? 'text/secondary' : selected ? 'accent/text' : 'text/primary' }),
    passed ? null : scoreChip({ score: w.score, size: 'compact' }),
    withTime ? text(w.start, { name: 'Start Time', font: tf, color: passed ? 'text/secondary' : 'text/primary' }) : null);
}

/**
 * Placement of each window's unit: [tier 'A'|'B', side 'left'|'right' of its bracket, anchor 'start'|'end' of the window].
 * A = lower tier (next to the bracket), B = upper tier (shares the row with the scrub flag).
 */
const PLACE = {
  blueMorning: ['A', 'right', 'start'],   // text ends at the window's start
  goldenMorning: ['A', 'left', 'start'],  // text begins at the window's start
  goldenEvening: ['A', 'right', 'start'],
  blueEvening: ['A', 'left', 'start'],
  night: ['B', 'right', 'end'],           // upper tier, right-aligned to the window's end, hairline leader down
};

export function stripGeometry(mapW, { top = 12, height = 264, plotH = 72 } = {}) {
  const W = mapW - 2 * PAD - 2 * PAD;
  const headerTop = 8, headerH = 40;
  const tierB = headerTop + headerH, tierA = tierB + 20;             // 18 pt tiers, 2 pt gap
  const bracketY = tierA + 20, skyTop = bracketY + 8, bandH = 64, skyBottom = skyTop + bandH;
  const plotTop = skyBottom + 20, plotBottom = plotTop + plotH;
  const total = height ?? plotBottom + 12;
  return { W, stripW: mapW - 2 * PAD, top, height: total, bottom: top + total, headerTop, headerH, tierB, tierA, bracketY, skyTop, skyBottom, plotTop, plotBottom, bandH };
}

export function lightStrip({ mapW = 680, top = 12, height = 264, plotH = 72, marker = MARKER_MIN, selected = 'goldenEvening', windows = windowsToday, tight = false, cloudPct = 25 } = {}) {
  const G = stripGeometry(mapW, { top, height, plotH });
  const { W, stripW } = G;
  const x = (min) => (min / 1440) * W;
  const thin = dv('stroke/thin'), reg = dv('stroke/regular'), thick = dv('stroke/thick'), hair = dv('stroke/hairline');
  const parts = [], labels = [], units = [];
  const bandR = 8;
  const mw = dv('chart/windowMinWidth');
  const extent = (w) => { let x0 = x(w.startMin), x1 = x(w.endMin); if (x1 - x0 < mw) { const m = (x0 + x1) / 2; x0 = m - mw / 2; x1 = m + mw / 2; } return [x0, x1]; };

  // sky band: full width, hairline edge so the night ends stay distinct from the panel in both appearances
  const sky = el('div', { name: 'Sky Band', style: abs({ left: 0, top: G.skyTop, width: W, height: G.bandH, borderRadius: bandR, background: skyGradient({ lo: 0, hi: 1440 }, 'to right', SUN) }) });
  const skyEdge = el('div', { name: 'Sky Band Edge', style: abs({ left: 0, top: G.skyTop, width: W, height: G.bandH, borderRadius: bandR, border: `0.5px solid color-mix(in srgb, ${c('text/primary')} 16%, transparent)` }) });

  // hour axis: hourly ticks; labels every hour (every 2 h when tight). Labels under the scrub pill and the Now notch are dropped.
  const mx = f2(x(marker)), nx = f2(x(NOW_MIN));
  for (let hr = 0; hr < 24; hr++) {
    const tx = x(hr * 60);
    const long = hr % 6 === 0;
    parts.push(`<path d="M${f2(tx)} ${G.skyBottom}V${G.skyBottom + (long ? 5 : 3)}" style="stroke:${c('text/secondary')};stroke-width:${thin}" fill="none"/>`);
    if (tight && hr % 2) continue;
    if (Math.abs(tx - mx) < 26 || Math.abs(tx - nx) < 18) continue;
    labels.push(lab(String(hr).padStart(2, '0'), { x: hr === 0 ? 0 : tx, y: G.skyBottom + 6, anchor: hr === 0 ? 'start' : 'middle', w: 18, name: `Hour ${hr}` }));
  }
  parts.push(`<path d="M${f2(W)} ${G.skyBottom}V${G.skyBottom + 3}" style="stroke:${c('text/secondary')};stroke-width:${thin}" fill="none"/>`);

  // weather plot
  const pt = G.plotTop, pb = G.plotBottom, ph = pb - pt;
  const HEAD = 14;                                   // headroom above the 100% line for its label
  const y = (f) => pb - Math.min(1, Math.max(0, f)) * (ph - HEAD);
  const tintOpFor = (w) => (currentTheme() === 'dark' ? 0.16 : 0.11) * (w.kind === 'night' ? 0.3 : 1);
  for (const w of windows) {
    const [x0, x1] = extent(w);
    parts.push(`<rect x="${f2(x0)}" y="${pt}" width="${f2(x1 - x0)}" height="${ph}" style="fill:${c(tintToken(w.kind))};fill-opacity:${tintOpFor(w)}"/>`);
    if (w.kind === selected) parts.push(`<rect x="${f2(x0)}" y="${pt}" width="${f2(x1 - x0)}" height="${ph}" style="fill:${c('selection/fill')};fill-opacity:0.7"/>`);
  }
  for (const f of [0, 0.5, 1]) {
    parts.push(`<path d="M0 ${f2(y(f))}H${W}" style="stroke:${c('separator/default')};stroke-width:${hair}" fill="none"/>`);
    labels.push(lab(`${Math.round(f * 100)}%`, { x: 4, y: y(f) - 14, w: 30, name: `Axis ${Math.round(f * 100)}%` }));
  }
  const pts = HOURS.map((h) => [x(h.min + 30), y(h.cloud)]);
  const top1 = pts.map(([px, py], i) => `${i ? 'L' : 'M'}${f2(px)} ${f2(py)}`).join('');
  parts.push(`<path d="M${f2(pts[0][0])} ${pb}${pts.map(([px, py]) => `L${f2(px)} ${f2(py)}`).join('')}L${f2(pts[pts.length - 1][0])} ${pb}Z" style="fill:${c('cloud/mid')};fill-opacity:${op('cloud-fill')}"/>`,
    `<path d="${top1}" style="stroke:${c('cloud/mid')};stroke-width:${reg};stroke-linejoin:round" fill="none"/>`);
  for (const h of HOURS) {
    if (h.rain < 0.1) continue;
    const inset = (x(h.min + 60) - x(h.min)) * 0.2;
    parts.push(`<rect x="${f2(x(h.min) + inset)}" y="${f2(y(h.rain))}" width="${f2(x(h.min + 60) - x(h.min) - 2 * inset)}" height="${f2(pb - y(h.rain))}" rx="${thin}" style="fill:${c('sky/blueHour')}"/>`);
  }

  // selected window outline: band piece and plot piece, the axis row between them stays clear
  for (const w of windows.filter((v) => v.kind === selected)) {
    const [x0, x1] = extent(w);
    for (const [ya, yb] of [[G.skyTop, G.skyBottom], [pt, pb]]) {
      const r = `x="${f2(x0 - thin)}" y="${f2(ya - thin)}" width="${f2(x1 - x0 + 2 * thin)}" height="${f2(yb - ya + 2 * thin)}" rx="${bandR / 2}"`;
      parts.push(`<rect ${r} style="stroke:${c('background/window')};stroke-width:${thick + 2 * thin}" fill="none"/>`, `<rect ${r} style="stroke:${c('accent/primary')};stroke-width:${thick}" fill="none"/>`);
    }
  }

  // brackets (4 pt drop) and event-unit labels on two tiers
  const tierYA = G.tierA, tierYB = G.tierB;
  for (const w of windows) {
    const [x0, x1] = extent(w);
    const sel = w.kind === selected;
    const bx0 = x0 + 0.75, bx1 = x1 - 0.75;
    parts.push(`<path d="M${f2(bx0)} ${G.bracketY + 5}V${G.bracketY}H${f2(bx1)}V${G.bracketY + 5}" style="stroke:${c(sel ? 'accent/primary' : 'text/secondary')};stroke-width:${sel ? thick : reg};stroke-linejoin:round" fill="none"/>`);
    const [tier, side, anchor] = PLACE[w.kind];
    const edge = anchor === 'start' ? bx0 : bx1;
    const ty = tier === 'A' ? tierYA : tierYB;
    const pos = side === 'right' ? { right: f2(W - (edge + 1)) } : { left: f2(edge - 1) };
    units.push(el('div', { name: `Unit Anchor / ${w.short}`, style: abs({ ...pos, top: ty, height: 18, display: 'flex', alignItems: 'center' }) }, tierUnit(w, { selected: sel })));
    if (tier === 'B') parts.push(`<path d="M${f2(edge)} ${ty + 18}V${G.bracketY}" style="stroke:${c('text/tertiary')};stroke-width:${hair * 2}" fill="none"/>`);
  }

  // "Now": a coral notch under the band and coral text on the axis row
  parts.push(`<path d="M${nx - 3.5} ${G.skyBottom + 6}H${nx + 3.5}L${nx} ${G.skyBottom + 1}Z" style="fill:${c('accent/primary')}" stroke-linejoin="round"/>`);
  labels.push(lab('Now', { x: nx, y: G.skyBottom + 6, anchor: 'middle', w: 26, style: 'captionStrong', size: 10, color: 'accent/text', name: 'Now Label' }));

  // marker: solid while scrubbing, halo, knob on the band's bottom edge, time pill in the axis row
  parts.push(`<path d="M${mx} ${G.skyTop}V${pb}" style="stroke:${c('background/window')};stroke-width:${thin * 3}" fill="none"/>`,
    `<path d="M${mx} ${G.skyTop}V${pb}" style="stroke:${c('text/primary')};stroke-width:${reg}" fill="none"/>`,
    `<circle cx="${mx}" cy="${G.skyBottom}" r="${dv('space/xs')}" style="fill:${c('text/primary')};stroke:${c('background/window')};stroke-width:${thin}"/>`);
  const flag = row({ name: 'Scrub Flag', align: 'center', justify: 'center', style: abs({ left: f2(mx - 20), top: G.skyBottom + 5, width: 40, height: 16, borderRadius: 8, background: c('text/primary') }) },
    text(fmt(marker), { name: 'Scrub Time', font: font('timeSmall', { size: 11, lineHeight: 14, weight: 'semibold' }), color: 'background/window' }));

  labels.push(lab('Forecast starts 11:00', { x: x(11 * 60) / 2 - 55, y: (pt + (ph - HEAD) / 2 + HEAD) - 7, anchor: 'start', w: 110, style: 'caption', size: 10, color: 'text/tertiary', name: 'Forecast Note' }));
  // plot legend, folded into the plot's top-right
  const lg = (tok, label) => row({ name: `Legend / ${label}`, align: 'center', gap: 4, noshrink: true },
    el('div', { name: 'Swatch', style: { width: 10, height: 10, borderRadius: 2, background: c(tok), border: `0.5px solid ${c('separator/default')}`, flexShrink: 0 } }),
    text(label, { name: 'Label', font: font('caption', { size: 10, lineHeight: 13 }), color: 'text/secondary' }));
  const legend = row({ name: 'Plot Legend', align: 'center', gap: 10, style: abs({ right: 6, top: pt + 5, height: 14 }) }, lg('cloud/mid', 'Cloud'), lg('sky/blueHour', 'Rain'));

  // header: spot (name over event unit) | readout | segmented + collapse
  const win = windowUnder(marker, windows);
  const hh = HOURS.find((h) => marker >= h.min && marker < h.min + 60);
  const readout = `${fmt(marker)} · ${cloudPct ?? (hh ? Math.round(hh.cloud * 100) : 0)}% cloud · ${hh ? Math.round(hh.rain * 100) : 0}% rain`;
  const header = row({ name: 'Strip Header', align: 'center', gap: tight ? 12 : 16, style: abs({ left: 0, top: G.headerTop, width: W, height: G.headerH }) },
    col({ name: 'Spot', justify: 'center', noshrink: true, style: { height: G.headerH } },
      text(SPOT.name, { name: 'Spot Name', font: font('headline'), color: 'text/primary' }),
      eventUnit({ symbol: SPOT.next.kind, score: SPOT.next.score, time: SPOT.next.time, size: 'row' })),
    col({ name: 'Readout', grow: true, justify: 'center', gap: 2, style: { minWidth: 0 } },
      text(readout, { name: 'Readout Values', font: font('bodyEmphasis', { size: tight ? 12 : 13, lineHeight: 18 }), color: 'text/primary' }),
      text(win ? `${win.short === 'Sunset' ? 'Sunset' : win.short} · ${win.start}–${win.end}` : 'Between windows', { name: 'Window Under Marker', font: font('subheadline', { size: 12, lineHeight: 16 }), color: 'text/secondary' })),
    row({ name: 'Controls', align: 'center', gap: 8, noshrink: true }, compactSegmented(['Full day', 'Sunrise ±2 h', 'Sunset ±2 h'], 0, { padX: tight ? 8 : 10 }), chevronButton('chevron.up', 'Collapse Strip')));

  const canvasEl = el('div', { name: 'Canvas / Light Strip', style: abs({ left: PAD, top: 0, width: W, height: G.height }) },
    sky, svgEl('Strip Graphics', { width: W, height: G.height, style: abs({ left: 0, top: 0 }) }, raw(parts.join('\n'))), skyEdge, labels, units, flag, legend, header);
  return el('div', { name: 'Light Strip', style: { ...panelStyle(), ...abs({ left: PAD, top, width: stripW, height: G.height }), overflow: 'hidden', zIndex: 5 } }, canvasEl);
}

/** 44 pt collapsed bar: spot name + event unit at left, a 12 pt sky ribbon with the scored units only, a coral Now notch, expand chevron. */
export function lightStripCollapsed({ mapW = 680, top = 12, marker = MARKER_MIN, selected = 'goldenEvening', windows = windowsToday } = {}) {
  const stripW = mapW - 2 * PAD, H = 44;
  const LEFT = 116;                                   // spot block width
  const innerW = stripW - 2 * PAD;
  const W = innerW - LEFT - 12 - 36;                  // ribbon width (36 pt slot for the chevron)
  const x = (min) => (min / 1440) * W;
  const ribbonTop = 24, parts = [], units = [];
  const mw = dv('chart/windowMinWidth');
  const sky = el('div', { name: 'Sky Ribbon', style: abs({ left: 0, top: ribbonTop, width: W, height: 12, borderRadius: 6, background: skyGradient({ lo: 0, hi: 1440 }, 'to right', SUN) }) });
  const edge = el('div', { name: 'Sky Ribbon Edge', style: abs({ left: 0, top: ribbonTop, width: W, height: 12, borderRadius: 6, border: `0.5px solid color-mix(in srgb, ${c('text/primary')} 16%, transparent)` }) });
  const UW = 56;                                      // scored unit: symbol 16 + chip + gaps
  let cursor = -Infinity;
  for (const w of windows.filter((v) => v.scored)) {
    let x0 = x(w.startMin), x1 = x(w.endMin); if (x1 - x0 < mw) { const m = (x0 + x1) / 2; x0 = m - mw / 2; x1 = m + mw / 2; }
    const sel = w.kind === selected;
    if (sel) parts.push(`<rect x="${f2(x0 - 1)}" y="${ribbonTop - 1}" width="${f2(x1 - x0 + 2)}" height="14" rx="3" style="stroke:${c('background/window')};stroke-width:4" fill="none"/>`,
      `<rect x="${f2(x0 - 1)}" y="${ribbonTop - 1}" width="${f2(x1 - x0 + 2)}" height="14" rx="3" style="stroke:${c('accent/primary')};stroke-width:2" fill="none"/>`);
    const [, side, anchor] = PLACE[w.kind];
    const ex = anchor === 'start' ? x0 : x1;
    let left = side === 'right' ? ex - UW : ex - 1;
    left = Math.max(left, cursor + 8); cursor = left + UW;
    const cu = row({ name: `Unit / ${w.short}`, align: 'center', gap: 4, noshrink: true, style: { height: 18 } },
      windowSymbol(w.kind, { size: 16, color: sel ? 'accent/text' : 'text/primary' }), scoreChip({ score: w.score, size: 'compact' }));
    units.push(el('div', { name: `Unit Anchor / ${w.short}`, style: abs({ left: f2(left), top: 4, height: 18, display: 'flex', alignItems: 'center' }) }, cu));
  }
  const mx = f2(x(marker));
  parts.push(`<path d="M${mx} ${ribbonTop - 2}V${ribbonTop + 14}" style="stroke:${c('background/window')};stroke-width:3" fill="none"/>`,
    `<path d="M${mx} ${ribbonTop - 2}V${ribbonTop + 14}" style="stroke:${c('text/primary')};stroke-width:1.5" fill="none"/>`);
  const nx = f2(x(NOW_MIN));
  parts.push(`<path d="M${nx - 3.5} ${ribbonTop + 18}H${nx + 3.5}L${nx} ${ribbonTop + 13}Z" style="fill:${c('accent/primary')}" stroke-linejoin="round"/>`);
  const spot = col({ name: 'Spot', justify: 'center', style: abs({ left: 0, top: 0, width: LEFT, height: H }) },
    text(SPOT.name, { name: 'Spot Name', font: font('headline', { size: 13, lineHeight: 16 }), color: 'text/primary' }),
    eventUnit({ symbol: SPOT.next.kind, score: SPOT.next.score, time: SPOT.next.time, size: 'row' }));
  const inner = el('div', { name: 'Collapsed Canvas', style: abs({ left: PAD, top: 0, width: innerW, height: H }) },
    spot,
    el('div', { name: 'Ribbon Group', style: abs({ left: LEFT + 12, top: 0, width: W, height: H }) }, sky, svgEl('Ribbon Graphics', { width: W, height: H, style: abs({ left: 0, top: 0 }) }, raw(parts.join('\n'))), edge, units),
    el('div', { name: 'Expand Slot', style: abs({ right: 0, top: 8, width: 28, height: 28, display: 'flex' }) }, chevronButton('chevron.down', 'Expand Strip')));
  return el('div', { name: 'Light Strip / Collapsed', style: { ...panelStyle(), ...abs({ left: PAD, top, width: stripW, height: H }), overflow: 'hidden', zIndex: 5 } }, inner);
}
