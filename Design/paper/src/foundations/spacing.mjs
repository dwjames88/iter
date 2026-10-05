// F03 Spacing, radii, sizes, strokes, layout widths. Values and descriptions are read from Design/tokens.json at
// build time; geometry is drawn with the dimension tokens themselves (d('space/md') ...), so a changed value resizes
// the specimen.
import { col, row, text, el, svgEl, raw } from '../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../tools/lib/tokens.mjs';
import { icon } from '../../tools/lib/icons.mjs';
import { confidenceMark } from '../../tools/lib/lightindex.mjs';
import { artboardHeader, page } from '../../tools/lib/specimens.mjs';
import { dimensions } from './tokdata.mjs';

const hair = () => `${d('stroke/hairline')} solid ${canvas('specimen/border')}`;
const names = (prefix) => Object.keys(dimensions).filter((n) => n.startsWith(prefix));
const val = (n) => `${dimensions[n].value} ${dimensions[n].unit}`;

// A generic item: sample slot, token name, value, job.
function item(n, sample, { slot = 200 } = {}) {
  return row({ name: `Token / ${n}`.slice(0, 50), align: 'center', gap: d('space/lg'), pad: [d('space/xs'), 0] },
    row({ name: 'Sample', align: 'center', w: slot, noshrink: true, style: { minHeight: 28 } }, sample),
    text(n, { name: 'Token Name', font: font('bodyEmphasis'), color: canvas('label/title'), w: 190, noshrink: true }),
    text(val(n), { name: 'Value', font: font('time'), color: canvas('label/title'), w: 64, noshrink: true }),
    text(dimensions[n].desc, { name: 'Job', font: font('callout'), color: canvas('label/body'), wrap: true, grow: true }));
}
const group = (title, ...rows) => col({ name: `Group / ${title}`.slice(0, 50), gap: d('space/xs') },
  text(title, { name: 'Group Title', font: font('title/section'), color: canvas('label/title'), style: { paddingBottom: 4, borderBottom: hair() } }), rows);

const box = (name, w, h, o = {}) => el('div', { name, style: { width: w, height: h, flexShrink: 0, background: o.bg ?? c('background/control'), border: `${d('stroke/thin')} solid ${o.stroke ?? c('text/tertiary')}`, borderRadius: o.radius, display: 'flex' } });

const spaceItem = (n) => item(n, el('div', { name: `Space ${n}`.slice(0, 50), style: { width: d(n), height: 16, background: c('text/secondary'), flexShrink: 0 } }));
const radiusItem = (n) => item(n, el('div', { name: `Radius ${n}`.slice(0, 50), style: { width: 64, height: 64, background: c('background/control'), border: `${d('stroke/thin')} solid ${c('text/tertiary')}`, borderRadius: d(n), flexShrink: 0 } }), { slot: 96 });

function sizeSample(n) {
  if (/^size\/badge\//.test(n) && n !== 'size/badge/minWidth') return box(`Badge ${n}`.slice(0, 50), d('size/badge/minWidth'), d(n), { radius: d('radius/badge') });
  if (n === 'size/badge/minWidth') return box('Badge min width', d(n), d('size/badge/height'), { radius: d('radius/badge') });
  if (/^size\/mapPin/.test(n)) return el('div', { name: `Pin ${n}`.slice(0, 50), style: { width: d(n), height: d(n), borderRadius: '999px', background: c('map/pin'), flexShrink: 0 } });
  if (/^size\/lightRing/.test(n)) return el('div', { name: `Ring ${n}`.slice(0, 50), style: { width: d(n), height: d(n), borderRadius: '999px', border: `${d('stroke/thick')} solid ${c('text/secondary')}`, flexShrink: 0 } });
  if (/^size\/icon\//.test(n)) return icon('binoculars', { size: dimensions[n].value, color: 'text/primary' });
  if (n === 'size/confidenceMark') return confidenceMark('high');
  if (/^size\/control\/height/.test(n)) return box(`Control ${n}`.slice(0, 50), 96, d(n), { radius: '999px' });
  if (n === 'size/hitTarget') return box('Hit target', d(n), d(n), { radius: d('radius/control') });
  return box(`Size ${n}`.slice(0, 50), d(n), d(n));
}
const chartItem = (n) => item(n, box(`Chart ${n}`.slice(0, 50), n === 'chart/arcMarker' ? d(n) : n === 'chart/windowMinWidth' ? d(n) : 140, n === 'chart/windowMinWidth' ? 24 : d(n), { radius: n === 'chart/arcMarker' ? '999px' : d('radius/badge'), bg: n === 'chart/arcMarker' ? c('map/sun') : c('sky/day'), stroke: c('separator/default') }), { slot: 160 });

function strokeSample(n) {
  if (n === 'stroke/dashLength' || n === 'stroke/dashGap') {
    return svgEl(`Dash ${n}`.slice(0, 50), { width: 120, height: 6 }, raw(`<line x1="0" y1="3" x2="120" y2="3" fill="none" style="stroke:${c('status/noForecast')};stroke-width:${d('stroke/regular')};stroke-dasharray:${d('stroke/dashLength')} ${d('stroke/dashGap')}"/>`));
  }
  if (n === 'stroke/focusRingWidth' || n === 'stroke/focusRingOffset') {
    return el('div', { name: 'Focus Ring Sample', style: { display: 'flex', padding: d('stroke/focusRingOffset'), border: `${d('stroke/focusRingWidth')} solid ${c('focus/ring')}`, borderRadius: '999px', flexShrink: 0 } },
      el('div', { name: 'Control', style: { width: 72, height: d('size/control/height'), borderRadius: '999px', background: c('background/control'), border: `${d('stroke/thin')} solid ${c('text/tertiary')}` } }));
  }
  const col2 = n === 'stroke/routeInactive' ? c('route/inactive') : /route/.test(n) ? c('route/active') : c('text/primary');
  const casing = n === 'stroke/routeCasing' ? c('background/window') : null;
  return el('div', { name: `Line ${n}`.slice(0, 50), style: { width: 120, height: d(n), background: casing ? c('text/secondary') : col2, flexShrink: 0 } });
}

function layoutItem(n) {
  return col({ name: `Token / ${n}`.slice(0, 50), gap: d('space/xs'), pad: [d('space/xs'), 0] },
    row({ name: 'Caption', align: 'center', gap: d('space/lg') },
      text(n, { name: 'Token Name', font: font('bodyEmphasis'), color: canvas('label/title'), w: 190, noshrink: true }),
      text(val(n), { name: 'Value', font: font('time'), color: canvas('label/title'), w: 64, noshrink: true }),
      text(dimensions[n].desc, { name: 'Job', font: font('callout'), color: canvas('label/body') })),
    el('div', { name: `Width ${n}`.slice(0, 50), style: { width: d(n), height: 14, background: c('text/secondary'), borderRadius: d('radius/badge'), flexShrink: 0 } }));
}

function board() {
  const sizes = names('size/');
  return page([
    artboardHeader({ title: 'Spacing, radii and sizes', type: 'IterSpace · IterRadius · IterSize · IterStroke', file: 'Packages/IterKit/Sources/IterDesign/IterMetrics.swift · Design/tokens.json', job: 'A 4 pt base with one half step, four corner radii, fixed component sizes, five stroke weights and the window layout widths. Every shape below is drawn with the token itself.' }),
    row({ name: 'Columns', gap: 48, align: 'flex-start' },
      col({ name: 'Left Column', gap: d('space/xl'), w: 720, noshrink: true },
        group('Spacing', names('space/').map(spaceItem)),
        group('Radii', names('radius/').map(radiusItem)),
        group('Strokes', names('stroke/').map((n) => item(n, strokeSample(n), { slot: 130 }))),
        group('Chart heights', names('chart/').map(chartItem))),
      col({ name: 'Right Column', gap: d('space/xl'), w: 792, noshrink: true },
        group('Sizes', sizes.map((n) => item(n, sizeSample(n), { slot: 110 }))))),
    group('Layout widths (drawn to scale)', names('layout/').map(layoutItem)),
  ], { gap: 28, pad: 40 });
}

export const artboards = [
  { id: 'F03-spacing-radii', name: 'F03 Spacing & radii', section: 'foundations', width: 1640, height: 2408, themes: ['light'], covers: [], render: board },
];
