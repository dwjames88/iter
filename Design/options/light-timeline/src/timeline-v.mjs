// timeline-v.mjs - vertical skeleton of the light timeline: TIME runs top -> bottom. A clean, parameterised starting point; art-direct it.
//
// timelineV(p) -> { html, width, height, layout }
//   Columns, left to right: hour axis (axisWidth) | sky bar (barWidth) | gap | chart band (chartWidth: cloud as a horizontal area, 0..100% across)
//   | gap | window labels column (labelsWidth; 0 = none) with a vertical bracket per window.
//   layout = { y(min), x0Bar, x1Bar, x0Chart, x1Chart, xLabels, top, bottom, width, height }  (px, canvas coordinates)
// Params p (all optional):
//   height 560 (px for the time domain)   top 18 (space above for the % axis labels)   bottomPad 6
//   barWidth 40  chartWidth 160  axisWidth 26  gap 10  labelsWidth 96  domain {lo:0,hi:1440}  tickEvery 3 (hours)  bandRadius 6
//   marker minute (MARKER_MIN)  selected window kind ('goldenEvening'; null)  windows  hours  sun  showChart true  showLabels true
//   hourLabelEvery 3  (labels every N hours; ticks follow tickEvery)
import { el, text, svgEl, raw } from '../../../paper/tools/lib/h.mjs';
import { c, d, dv, font, op } from '../../../paper/tools/lib/tokens.mjs';
import { windowsToday, HOURS, SUN, MARKER_MIN, skyGradient } from './data.mjs';
import { tintToken, lab } from './timeline-h.mjs';

const f2 = (n) => Math.round(n * 100) / 100;
const abs = (o) => ({ position: 'absolute', ...o });
const stroke = (tok, w, extra = '') => `style="stroke:${c(tok)};stroke-width:${w}${extra}" fill="none"`;
const fillS = (tok, extra = '') => `style="fill:${c(tok)}${extra}"`;

export function timelineV(p0 = {}) {
  const p = { height: 560, top: 18, bottomPad: 6, barWidth: 40, chartWidth: 160, axisWidth: 26, gap: 10, labelsWidth: 96, domain: { lo: 0, hi: 1440 }, tickEvery: 3, bandRadius: dv('radius/badge'),
    marker: MARKER_MIN, selected: 'goldenEvening', windows: windowsToday, hours: HOURS, sun: SUN, showChart: true, showLabels: true, ...p0 };
  const { lo, hi } = p.domain;
  const x0Bar = p.axisWidth + 4, x1Bar = x0Bar + p.barWidth;
  const x0Chart = x1Bar + p.gap, x1Chart = x0Chart + (p.showChart ? p.chartWidth : 0);
  const xLabels = (p.showChart ? x1Chart : x1Bar) + p.gap;
  const width = xLabels + (p.showLabels ? p.labelsWidth : 0);
  const height = p.top + p.height + p.bottomPad;
  const y = (min) => p.top + ((min - lo) / (hi - lo)) * p.height;
  const thin = dv('stroke/thin'), reg = dv('stroke/regular'), thick = dv('stroke/thick'), hair = dv('stroke/hairline');
  const parts = [], labels = [];
  const ext = (w) => { let a = y(Math.max(lo, w.startMin)), b = y(Math.min(hi, w.endMin)); const mh = dv('chart/windowMinWidth'); if (b - a < mh) { a = (a + b) / 2 - mh / 2; b = a + mh; } return [a, b]; };

  const sky = el('div', { name: 'Sky Bar', style: abs({ left: x0Bar, top: p.top, width: p.barWidth, height: p.height, borderRadius: p.bandRadius, background: skyGradient(p.domain, 'to bottom', p.sun) }) });

  for (let hr = 0; hr <= 24; hr += p.tickEvery) {
    const mn = hr * 60; if (mn < lo || mn > hi) continue;
    parts.push(`<path d="M${x0Bar - 4} ${f2(y(mn))}H${x0Bar}" ${stroke('text/secondary', thin)}/>`);
    labels.push(lab(String(hr % 24).padStart(2, '0'), { x: x0Bar - 6, y: y(mn), anchor: 'end', vAnchor: 'middle', style: 'timeSmall', name: `Hour ${hr % 24}`, w: p.axisWidth }));
  }

  if (p.showChart) {
    const cw = x1Chart - x0Chart, X = (f) => x0Chart + Math.min(1, Math.max(0, f)) * cw;
    for (const w of p.windows) {
      const [a, b] = ext(w);
      parts.push(`<rect x="${x0Chart}" y="${f2(a)}" width="${cw}" height="${f2(b - a)}" ${fillS(tintToken(w.kind), `;fill-opacity:${op('window-tint')}`)}/>`);
      if (w.kind === p.selected) parts.push(`<rect x="${x0Chart}" y="${f2(a)}" width="${cw}" height="${f2(b - a)}" ${fillS('selection/fill')}/>`);
    }
    for (const f of [0, 0.5, 1]) {
      parts.push(`<path d="M${f2(X(f))} ${p.top}V${p.top + p.height}" ${stroke('separator/default', hair)}/>`);
      labels.push(lab(`${f * 100}%`, { x: X(f), y: 0, anchor: 'middle', style: 'timeSmall', name: `Axis ${f * 100}%` }));
    }
    const pts = p.hours.map((h) => [X(h.cloud), y(h.min + 30)]).filter(([, py]) => py >= p.top && py <= p.top + p.height);
    if (pts.length > 1) {
      const line = pts.map(([px, py], i) => `${i ? 'L' : 'M'}${f2(px)} ${f2(py)}`).join('');
      parts.push(`<path d="M${x0Chart} ${f2(pts[0][1])}${pts.map(([px, py]) => `L${f2(px)} ${f2(py)}`).join('')}L${x0Chart} ${f2(pts[pts.length - 1][1])}Z" ${fillS('cloud/mid', `;fill-opacity:${op('cloud-fill')}`)}/>`,
        `<path d="${line}" ${stroke('cloud/mid', reg, ';stroke-linejoin:round')}/>`);
    }
    for (const h of p.hours) if (h.rain >= 0.1) {
      const inset = (y(h.min + 60) - y(h.min)) * 0.2;
      parts.push(`<rect x="${x0Chart}" y="${f2(y(h.min) + inset)}" width="${f2(h.rain * cw)}" height="${f2(y(h.min + 60) - y(h.min) - 2 * inset)}" rx="${thin}" ${fillS('sky/blueHour')}/>`);
    }
  }

  const right = p.showChart ? x1Chart : x1Bar;
  for (const w of p.windows.filter((w) => w.kind === p.selected)) {
    const [a, b] = ext(w);
    const r = `x="${x0Bar - thin}" y="${f2(a - thin)}" width="${right - x0Bar + 2 * thin}" height="${f2(b - a + 2 * thin)}" rx="${p.bandRadius / 2}"`;
    parts.push(`<rect ${r} ${stroke('background/control', thick + 2 * thin)}/>`, `<rect ${r} ${stroke('accent/primary', thick)}/>`);
  }

  if (p.showLabels) {
    let last = -Infinity;
    for (const w of [...p.windows].sort((a, b) => a.startMin - b.startMin)) {
      const [a, b] = ext(w);
      const sel = w.kind === p.selected;
      const bx = xLabels - 2;
      parts.push(`<path d="M${bx - 4} ${f2(a)}H${bx}V${f2(b)}H${bx - 4}" ${stroke(sel ? 'accent/primary' : 'text/secondary', sel ? thick : reg)}/>`);
      const ty = Math.max(a - 6, last + 14);
      last = ty;
      labels.push(lab(w.scored ? `${w.short} ${w.score}` : w.short, { x: xLabels + 6, y: ty, style: sel ? 'captionStrong' : 'caption', color: w.scored ? 'text/primary' : 'text/secondary', name: `Window Label / ${w.short}`, w: p.labelsWidth - 6 }));
    }
  }

  if (p.marker != null && p.marker >= lo && p.marker <= hi) {
    const my = f2(y(p.marker));
    parts.push(`<path d="M${x0Bar} ${my}H${right}" ${stroke('background/control', thin * 3)}/>`,
      `<path d="M${x0Bar} ${my}H${right}" ${stroke('text/primary', thin, `;stroke-dasharray:${dv('stroke/dashLength')} ${dv('stroke/dashGap')}`)}/>`,
      `<circle cx="${x1Bar}" cy="${my}" r="${dv('space/xs')}" style="fill:${c('text/primary')};stroke:${c('background/control')};stroke-width:${thin}"/>`);
  }
  const html = el('div', { name: 'Canvas / Light Timeline (vertical)', style: { position: 'relative', width, height, flexShrink: 0 } },
    sky, svgEl('Timeline Graphics', { width, height, style: abs({ left: 0, top: 0 }) }, raw(parts.join('\n'))), labels);
  return { html, width, height, layout: { y, x0Bar, x1Bar, x0Chart, x1Chart, xLabels, top: p.top, bottom: p.top + p.height, width, height } };
}
