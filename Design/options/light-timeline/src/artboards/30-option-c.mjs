// 30-option-c: Option C "Light strip across the top of the map". Bixby Bridge selected, scrubbing 18:26, Sunset window selected.
// The strip docks 12 pt from the map pane's top/left/right; the card stays bottom-trailing and shrinks to fit under it with a 12 pt gap.
import { el, col, row, text } from '../../../../paper/tools/lib/h.mjs';
import { c, d, font, canvas } from '../../../../paper/tools/lib/tokens.mjs';
import { icon } from '../../../../paper/tools/lib/icons.mjs';
import { mapPlaceholder } from '../../../../paper/tools/lib/chrome.mjs';
import { exploreWindow, placeCard, mapPin, pinChip, pinDot, pinSelected } from '../shell.mjs';
import { LIST_ROWS, SPOT } from '../data.mjs';
import { lightStrip, lightStripCollapsed } from '../option-c/strip.mjs';

// same fractions as shell.defaultMap, re-fitted into the part of the pane the strip leaves visible (the camera inset)
const PINS = [[0.07, 0.10, 31, 'dot'], [0.17, 0.17, 67, 'chip'], [0.34, 0.60, 70, 'chip'], [0.30, 0.69, 45, 'dot'], [0.62, 0.11, 66, 'chip'], [0.54, 0.20, 66, 'dot'],
  [0.45, 0.30, 66, 'dot'], [0.80, 0.25, 67, 'chip'], [0.90, 0.13, 66, 'dot'], [0.72, 0.19, 66, 'dot'], [0.70, 0.36, 67, 'dot'], [0.12, 0.40, 62, 'dot'], [0.10, 0.70, 58, 'dot'],
  [0.27, 0.86, 71, 'dot'], [0.18, 0.92, 55, 'chip'], [0.40, 0.88, 66, 'dot']];
function insetMap(w, h, visTop) {
  const sel = LIST_ROWS.find((r) => r.name === 'Bixby Bridge');
  const vh = h - visTop;
  const pins = PINS.map(([fx, fy, score, kind]) => mapPin(fx * w, visTop + fy * vh, kind === 'chip' ? pinChip({ score }) : pinDot({ score })));
  return mapPlaceholder({ grow: true, label: '', children: [pins, mapPin(0.2 * w, visTop + 0.5 * vh, pinSelected({ score: sel.score, time: sel.time }), { bottom: true })] });
}

// the slimmer card: header + image strip + the top of "Good to know" (no light sections)
function goodToKnow() {
  const rowOf = (sym, label, last) => row({ name: `Fact / ${label}`.slice(0, 50), align: 'center', gap: 10, style: { height: 36, padding: '0 12px', borderBottom: last ? undefined : `0.5px solid ${c('separator/default')}` } },
    icon(sym, { size: 17, color: 'accent/primary' }), text(label, { name: 'Label', font: font('body'), color: 'text/primary' }));
  return col({ name: 'Good to know', gap: 8 },
    text('Good to know', { name: 'Section Title', font: font('title/section', { size: 15, lineHeight: 20 }), color: 'text/primary' }),
    col({ name: 'Facts Card', style: { background: c('background/control'), borderRadius: d('radius/card'), border: `0.5px solid ${c('separator/default')}` } },
      rowOf('safari', SPOT.facing), rowOf('figure.walk', SPOT.walkIn), rowOf('sunset', SPOT.best, true)));
}

function board({ width, height, collapsed = false, cardW = 320 }) {
  const sidebar = width >= 1280;
  const lw = sidebar ? 360 : 340;
  const mapW = width - (sidebar ? 240 : 0) - lw, mapH = height - 52;
  const stripH = collapsed ? 44 : (width >= 1280 ? 264 : 256);
  const strip = collapsed ? lightStripCollapsed({ mapW }) : lightStrip({ mapW, height: stripH, plotH: width >= 1280 ? 72 : 64, tight: width < 1280 });
  const cardH = Math.min(480, mapH - 12 - stripH - 12 - 12);
  const card = placeCard({ width: cardW, height: cardH, scrollY: cardH < 380 ? 110 : 0, sections: [goodToKnow(), el('div', { name: 'More (stub)', style: { height: 160 } })] });
  return exploreWindow({ width, height, map: insetMap(mapW, mapH, 12 + stripH + 24),
    overlay: [strip, el('div', { name: 'Card Position', style: { position: 'absolute', right: 12, bottom: 12, display: 'flex' } }, card)] });
}

export const artboards = [
  { id: 'C-1280-light', width: 1280, height: 820, appearance: 'light', html: () => board({ width: 1280, height: 820 }) },
  { id: 'C-1280-dark', width: 1280, height: 820, appearance: 'dark', html: () => board({ width: 1280, height: 820 }) },
  { id: 'C-960-light', width: 960, height: 652, appearance: 'light', html: () => board({ width: 960, height: 652 }) },
  { id: 'C-960-dark', width: 960, height: 652, appearance: 'dark', html: () => board({ width: 960, height: 652 }) },
  { id: 'C-1280-collapsed-light', width: 1280, height: 820, appearance: 'light', html: () => board({ width: 1280, height: 820, collapsed: true }) },
];
