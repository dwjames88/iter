// panel-b.mjs - Option B: the places-list column becomes the Light panel for the selected spot. Also the list state with a hover affordance
// and the slimmed place card. Copies of shell.mjs pieces (listRow, defaultList) are extended here with a hover chevron; shell.mjs is untouched.
import { el, row, col, text, spacer } from '../../../../paper/tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../../paper/tools/lib/tokens.mjs';
import { icon } from '../../../../paper/tools/lib/icons.mjs';
import { confidenceMark, provenanceTag, scoreChip, BANDS, bandFor } from '../../../../paper/tools/lib/lightindex.mjs';
import { eventUnit, windowSymbol, segmented, sectionHeader, placeCard } from '../shell.mjs';
import { LIST_ROWS, SPOT, windowsToday, windowsTomorrow, WINDOW_KINDS, toMin } from '../data.mjs';
import { timelineB, readoutB, legendB } from './timeline-b.mjs';

const abs = (o) => ({ position: 'absolute', ...o });
const hair = () => `0.5px solid ${c('separator/default')}`;
const sectionTitle = (t, extra = null) => row({ name: `Section Title / ${t}`.slice(0, 50), align: 'center', justify: 'space-between', noshrink: true, style: { height: 20 } },
  text(t, { name: 'Title', font: font('title/section', { size: 15, lineHeight: 20 }), color: 'text/primary' }), extra);

// ---- column header: back + stepper ---------------------------------------------------------------------------------------------
export function panelHeader({ index = 3, total = 16 } = {}) {
  const step = (sym) => row({ name: `Step / ${sym}`, align: 'center', justify: 'center', noshrink: true, style: { width: 22, height: 24, borderRadius: 6 } }, icon(sym, { size: 11, color: 'text/secondary', weight: 'semibold' }));
  return row({ name: 'Panel Header', align: 'center', justify: 'space-between', noshrink: true, attrs: { title: 'Back to places (Esc)' },
    style: { height: 32, padding: '0 10px 0 8px', borderBottom: hair() } },
  row({ name: 'Back Control', align: 'center', gap: 2, style: { height: 24, padding: '0 6px 0 2px', borderRadius: 6 } },
    icon('chevron.left', { size: 13, color: 'accent/text', weight: 'semibold' }), text('Places', { name: 'Back Label', font: font('body'), color: 'accent/text' })),
  row({ name: 'Place Stepper', align: 'center', gap: 4 },
    text(`${index} of ${total}`, { name: 'Position', font: font('body'), color: 'text/secondary' }),
    row({ name: 'Previous / Next', align: 'center', gap: 0 }, step('chevron.up'), step('chevron.down'))));
}

// ---- spot block ----------------------------------------------------------------------------------------------------------------
export function spotBlock() {
  return col({ name: 'Spot Block', gap: 2, noshrink: true },
    row({ name: 'Title Row', align: 'center', justify: 'space-between', style: { height: 22 } },
      text(SPOT.name, { name: 'Name', font: font('title/section', { size: 17, lineHeight: 22 }), color: 'text/primary' }),
      eventUnit({ symbol: SPOT.next.kind, score: SPOT.next.score, time: SPOT.next.time, size: 'card' })),
    row({ name: 'Locality Line', align: 'center', gap: 6, style: { height: 16 } },
      text(`${SPOT.locality} · ${SPOT.distance}`, { name: 'Locality', font: font('subheadline'), color: 'text/secondary' }), provenanceTag(SPOT.origin)));
}

// ---- window rows ---------------------------------------------------------------------------------------------------------------
const CONF = { goldenEvening: 'medium', blueEvening: 'medium', night: 'high' };
function windowRow(w, { selected, last, expandable = true }) {
  const word = BANDS[bandFor(w.score)].name;
  return row({ name: `WindowRow / ${w.short}`, align: 'center', noshrink: true, style: { height: 32, padding: '0 12px 0 10px', position: 'relative', borderBottom: last ? 'none' : hair() } },
    selected ? el('div', { name: 'Selection', style: abs({ left: 3, right: 3, top: 3, bottom: last ? 3 : 2.5, borderRadius: 8, background: c('selection/fill'), border: `1.5px solid ${c('accent/primary')}` }) }) : null,
    row({ name: 'Row Body', align: 'center', grow: true, style: { position: 'relative', minWidth: 0 } },
      row({ name: 'Chevron Slot', align: 'center', w: 18, noshrink: true }, expandable ? icon('chevron.right', { size: 10, color: 'text/secondary', weight: 'semibold' }) : null),
      row({ name: 'Event Unit', align: 'center', gap: 8, noshrink: true }, windowSymbol(w.kind, { size: 20 }), scoreChip({ score: w.score, size: 'regular' }),
        text(`${w.start}–${w.end}`, { name: 'Time Range', font: font('time'), color: 'text/primary', noshrink: true })),
      spacer(),
      row({ name: 'Quality', align: 'center', gap: 5, noshrink: true }, text(word, { name: 'Band Word', font: font('caption', { size: 11 }), color: 'text/secondary' }), confidenceMark(CONF[w.kind] || 'high'))));
}
export function todayRows({ selectedKind = 'goldenEvening' } = {}) {
  const ws = windowsToday.filter((w) => w.scored);
  return col({ name: 'Today Rows', gap: 6, noshrink: true },
    sectionTitle('Today', text('Tue, Oct 6', { name: 'Day', font: font('subheadline'), color: 'text/secondary' })),
    col({ name: 'Window Rows Card', clip: true, style: { background: c('background/control'), borderRadius: d('radius/card'), border: hair() } },
      ws.map((w, i) => windowRow(w, { selected: w.kind === selectedKind, last: i === ws.length - 1 }))));
}
const NAME = { blueMorning: 'Blue AM', goldenMorning: 'Sunrise', goldenEvening: 'Sunset', blueEvening: 'Blue PM', night: 'Night' };
export function comingUp() {
  return col({ name: 'Coming Up', gap: 6, noshrink: true },
    sectionTitle('Coming up'),
    col({ name: 'Coming Up Rows', clip: true, style: { background: c('background/control'), borderRadius: d('radius/card'), border: hair() } },
      row({ name: 'Day Header', align: 'center', noshrink: true, style: { height: 22, padding: '0 14px', borderBottom: hair() } },
        text('Tomorrow · Wed', { name: 'Day Label', font: font('captionStrong', { size: 11 }), color: 'text/secondary' })),
      windowsTomorrow.map((w, i) => row({ name: `ComingUpRow / ${w.short}`, align: 'center', gap: 8, noshrink: true, style: { height: 28, padding: '0 12px 0 14px', borderBottom: i === windowsTomorrow.length - 1 ? 'none' : hair() } },
        windowSymbol(w.kind, { size: 16 }), scoreChip({ score: w.score, size: 'compact' }),
        text(w.start, { name: 'Start Time', font: font('timeSmall', { size: 12, lineHeight: 16 }), color: 'text/primary' }),
        spacer(), text(NAME[w.kind], { name: 'Window Name', font: font('subheadline'), color: 'text/secondary' })))));
}

// ---- the panel -----------------------------------------------------------------------------------------------------------------
/** opts: width (column width), zoom 0|2, band, plot, gapBelow */
export function lightPanel({ width = 360, zoom = 0, band = 88, plot = 112, index = 3 } = {}) {
  const inner = width - 32;
  const zoomed = zoom === 2;
  const tl = timelineB(zoomed ? { width: inner, bandHeight: band, plotHeight: plot, tiers: 2, double: true, domain: { lo: toMin('16:43'), hi: toMin('20:43') }, tickEvery: 1, minorEvery: 30,
    hourLabel: (m) => `${String(Math.round(m / 60)).padStart(2, '0')}:00`, nowMin: null }
    : { width: inner, bandHeight: band, plotHeight: plot });
  return col({ name: 'Light Panel', grow: true, style: { minHeight: 0, background: c('background/content'), overflow: 'hidden' } },
    panelHeader({ index }),
    col({ name: 'Scroll Viewport', gap: 0, grow: true, style: { minHeight: 0, overflow: 'hidden', padding: '8px 16px 0' } },
      spotBlock(),
      el('div', { name: 'Gap 14', style: { height: 8, flexShrink: 0 } }),
      sectionTitle('Light through the day'),
      el('div', { name: 'Gap 8', style: { height: 8, flexShrink: 0 } }),
      segmented(['Full day', 'Sunrise ±2 h', 'Sunset ±2 h'], zoom, { width: inner }),
      el('div', { name: 'Gap 8b', style: { height: 8, flexShrink: 0 } }),
      readoutB(),
      el('div', { name: 'Gap 2', style: { height: 0, flexShrink: 0 } }),
      tl.html,
      el('div', { name: 'Gap 6', style: { height: 2, flexShrink: 0 } }),
      legendB(width < 350),
      el('div', { name: 'Gap 16', style: { height: 8, flexShrink: 0 } }),
      todayRows(),
      el('div', { name: 'Gap 16b', style: { height: 8, flexShrink: 0 } }),
      comingUp(),
      el('div', { name: 'Bottom Pad', style: { height: 16, flexShrink: 0 } })),
    footer('OpenWeather · updated 11:50'));
}
const footer = (t) => row({ name: 'Footer', align: 'center', noshrink: true, style: { height: 29, padding: '0 12px', borderTop: hair(), background: c('background/content') } },
  text(t, { name: 'Attribution', font: font('caption', { size: 11 }), color: 'text/secondary' }));

// ---- the list state (hover affordance) ----------------------------------------------------------------------------------------
function listRowB({ name, locality, mi, score, time, kind, hover, last }) {
  return row({ name: `ListRow / ${name}`.slice(0, 50), noshrink: true, style: { height: 47, padding: '0 10px', position: 'relative' } },
    row({ name: 'Row Body', align: 'center', gap: 8, grow: true, style: { padding: hover ? '0 8px 0 6px' : '0 6px', borderRadius: 10, position: 'relative', background: hover ? canvas('chrome/control-active') : undefined } },
      col({ name: 'Text', grow: true, justify: 'center', style: { minWidth: 0 } },
        text(name, { name: 'Name', font: font('headline'), color: 'text/primary', style: { overflow: 'hidden', textOverflow: 'ellipsis' } }),
        row({ name: 'Locality Line', align: 'center', style: { minWidth: 0 } },
          text(locality, { name: 'Locality', font: font('subheadline'), color: 'text/secondary', style: { overflow: 'hidden', textOverflow: 'ellipsis', flex: '0 1 auto', minWidth: 0 } }),
          text(` · ${mi} mi`, { name: 'Distance', font: font('subheadline'), color: 'text/secondary', noshrink: true, style: { whiteSpace: 'pre' } }))),
      eventUnit({ symbol: kind, score, time, size: 'row' }),
      hover ? row({ name: 'Hover Affordance / chevron.right', align: 'center', justify: 'center', w: 12, noshrink: true }, icon('chevron.right', { size: 11, color: 'text/secondary', weight: 'bold' })) : null,
      hover || last ? null : el('div', { name: 'Separator', style: abs({ left: 6, right: 6, bottom: 0, height: 0.5, background: c('separator/default') }) })));
}
export function listB({ hoverName = 'Bixby Bridge' } = {}) {
  return col({ name: 'List Panel', grow: true, style: { minHeight: 0, background: c('background/content'), overflow: 'hidden' } },
    row({ name: 'List Header', align: 'center', justify: 'space-between', noshrink: true, style: { height: 32, padding: '0 14px 0 12px', borderBottom: hair() } },
      text('45 places', { name: 'Count', font: font('body'), color: 'text/secondary' }), icon('line.3.horizontal.decrease.circle', { size: 17, color: 'accent/primary' })),
    sectionHeader({ title: 'Near You · Within 300 mi', count: 16 }),
    col({ name: 'Rows', grow: true, style: { minHeight: 0, overflow: 'hidden' } }, LIST_ROWS.map((r, i) => listRowB({ ...r, hover: r.name === hoverName, last: i === LIST_ROWS.length - 1 }))),
    footer('OpenWeather'));
}

// ---- slimmed place card: header + image strip + the start of "Good to know" ----------------------------------------------------
function fact(sym, label) {
  return row({ name: `Fact / ${label}`, align: 'center', gap: 8, style: { height: 24 } }, icon(sym, { size: 14, color: 'text/secondary' }), text(label, { name: 'Fact', font: font('callout'), color: 'text/primary' }));
}
export function slimCard({ width = 360, height = 372 } = {}) {
  return placeCard({ width, height, sections: [col({ name: 'Good to know', gap: 8 }, sectionTitle('Good to know'),
    col({ name: 'Facts Card', gap: 0, pad: 12, style: { background: c('background/control'), borderRadius: d('radius/card'), border: hair() } },
      fact('location.north.line', SPOT.facing), fact('figure.walk', SPOT.walkIn), fact('sun.max', SPOT.best)))] });
}
