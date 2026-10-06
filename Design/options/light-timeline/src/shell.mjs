// shell.mjs - the Explore window (macOS 26, Paper-form HTML, inline styles) plus reusable pieces. Measured from the real captures
// (2560 px = 1280 pt): sidebar 240, list column 360, toolbar 52, row 47, list header 32, section header 29, footer 29, card 360 wide.
//
// exploreWindow({width=1280, height=820, sidebar=(width>=1280), extraColumn:{width,html}|null, listWidth=360, list:Html|null,
//   map:Html|null, overlay:Html|Html[]|null, title='Explore', selectedStyle:'system'|'accent', mapCaption=''}) -> Html
//   At 960 the sidebar defaults OFF (the app collapses it below 240+761 pt; traffic lights + toggle move into the toolbar) and the list
//   defaults to 340 (layout/listColumnMin). `overlay` is absolutely positioned inside the map pane (pane-relative coordinates).
// defaultList({selected='Bixby Bridge', selectedStyle, width}) -> Html   the real list (header, section header, 14 rows, footer)
// defaultMap({width, height, selectedName='Bixby Bridge', children, mapCaption}) -> Html   neutral placeholder map with pins
// eventUnit({symbol='goldenEvening', score, time, size:'row'|'card'|'pin'|'large'}) -> Html   symbol + score chip + time, one unit
// scoreChip({score, size:'compact'|'regular'|'large'}) (re-export)   windowSymbol(name, {size=20, color}) -> Html
//   name: sunrise | sunset | blueAM | blueMorning | blueEvening | blue PM | night | window kinds (goldenEvening ...)
// segmented(items, selectedIndex, {width}) -> Html   coral selected segment (accent/primary, white text) as in the app
// listRow({name, locality, mi, score, time, kind, selected, selectedStyle, last}) -> Html   sectionHeader({title, count}) -> Html
// pinDot({score}) pinChip({score, kind}) pinSelected({score, time, kind}) -> Html   mapPin(x, y, child, {bottom}) absolutely anchors
// placeCard({name, locality, origin, event:{kind,score,time}, sections:[Html], scrollY=0, width=360, height=372, image=true}) -> Html
//   pinned header (name, locality + tag, event unit, close) then a body that scrolls: image strip (200) + sections (12 pt inset, 16 gap).
//   `height` default 372 = the real card in an 820 window (half the map); pass up to 560 (layout/placeCardMaxHeight) for tall mocks.
import { el, row, col, text, svgEl, raw, spacer } from '../../../paper/tools/lib/h.mjs';
import { c, d, dv, canvas, font, currentTheme } from '../../../paper/tools/lib/tokens.mjs';
import { icon } from '../../../paper/tools/lib/icons.mjs';
import { scoreChip as paperChip, provenanceTag, bandFor } from '../../../paper/tools/lib/lightindex.mjs';
import { trafficLights, mapPlaceholder, materialSurface } from '../../../paper/tools/lib/chrome.mjs';
import { LIST_ROWS } from './data.mjs';

const abs = (o) => ({ position: 'absolute', ...o });
export const scoreChip = paperChip;

// ---- symbols ------------------------------------------------------------------------------------------------------------------
const SYM = { sunrise: 'sunrise', goldenMorning: 'sunrise', sunset: 'sunset', goldenEvening: 'sunset', blueAM: 'sun.horizon', blueMorning: 'sun.horizon',
  'blue AM': 'sun.horizon', blueEvening: 'moon.haze', bluePM: 'moon.haze', 'blue PM': 'moon.haze', night: 'moon.stars' };
export function windowSymbol(name = 'sunset', { size = 20, color = 'text/secondary' } = {}) {
  const s = SYM[name]; if (!s) throw new Error(`windowSymbol: unknown "${name}" (${Object.keys(SYM).join(', ')})`);
  return icon(s, { size, color, name: `WindowSymbol / ${name}` });
}

// ---- event unit: symbol + chip + time as ONE tightly grouped piece (13-row-event-module.png) ---------------------------------------
const UNIT = { row: { sym: 20, gap: 8, chip: 'regular', tf: ['timeSmall', 12] }, card: { sym: 20, gap: 10, chip: 'regular', tf: ['timeSmall', 12] },
  pin: { sym: 14, gap: 4, chip: 'compact', tf: ['timeSmall', 11] }, large: { sym: 24, gap: 12, chip: 'regular', tf: ['time', 13] } };
export function eventUnit({ symbol = 'goldenEvening', score, time, size = 'row', timeColor = 'text/secondary' } = {}) {
  const u = UNIT[size]; if (!u) throw new Error(`eventUnit size "${size}"`);
  return row({ name: `EventUnit / ${size}`, align: 'center', gap: u.gap, noshrink: true },
    windowSymbol(symbol, { size: u.sym }),
    typeof score === 'number' ? scoreChip({ score, size: u.chip }) : null,
    time ? text(time, { name: 'Start Time', font: font(u.tf[0], { size: u.tf[1], lineHeight: 16 }), color: size === 'pin' ? 'text/primary' : timeColor }) : null);
}

// ---- segmented: coral selected segment (screenshot 10) -------------------------------------------------------------------------
export function segmented(items, selectedIndex = 0, { width, height = 24 } = {}) {
  return row({ name: 'Segmented Control', pad: 2, radius: 8, noshrink: true, w: width, style: { height: height + 4, background: canvas('control/segmented-track'), alignItems: 'stretch' } },
    items.map((label, i) => {
      const sel = i === selectedIndex;
      const sepNext = !sel && i < items.length - 1 && i + 1 !== selectedIndex;
      return row({ name: `Segment / ${label}`.slice(0, 50), align: 'center', justify: 'center', radius: 6, grow: !!width, w: width ? undefined : 90,
        style: { background: sel ? c('accent/primary') : undefined, position: 'relative', flexShrink: width ? 1 : 0 } },
      text(label, { name: 'Label', font: font('body'), color: sel ? 'accent/onAccent' : 'text/primary' }),
      sepNext ? el('div', { name: 'Divider', style: abs({ right: 0, top: 6, bottom: 6, width: 1, background: c('separator/default') }) }) : null);
    }));
}

// ---- list ---------------------------------------------------------------------------------------------------------------------
export function sectionHeader({ title, count }) {
  return row({ name: `Section Header / ${title}`.slice(0, 50), align: 'center', justify: 'space-between', noshrink: true,
    style: { height: 29, padding: '0 16px', background: canvas('control/segmented-track'), borderBottom: `0.5px solid ${c('separator/default')}` } },
  text(title, { name: 'Title', font: font('footnote', { weight: 'semibold', size: 11, lineHeight: 14 }), color: 'text/secondary' }),
  text(String(count), { name: 'Count', font: font('timeSmall', { weight: 'semibold', size: 11, lineHeight: 14 }), color: 'text/secondary' }));
}
export function listRow({ name, locality, mi, score, time, kind = 'goldenEvening', selected = false, selectedStyle = 'system', last = false }) {
  const fill = selected ? (selectedStyle === 'accent' ? { background: c('selection/fill'), border: `1.5px solid ${c('accent/primary')}` } : { background: canvas('chrome/control-active') }) : {};
  return row({ name: `ListRow / ${name}`.slice(0, 50), noshrink: true, style: { height: 47, padding: '0 10px', position: 'relative' } },
    row({ name: 'Row Body', align: 'center', gap: 8, grow: true, style: { padding: '0 6px', borderRadius: 10, position: 'relative', ...fill } },
      col({ name: 'Text', grow: true, justify: 'center', style: { minWidth: 0 } },
        text(name, { name: 'Name', font: font('headline'), color: 'text/primary', style: { overflow: 'hidden', textOverflow: 'ellipsis' } }),
        row({ name: 'Locality Line', align: 'center', style: { minWidth: 0 } },
          text(locality, { name: 'Locality', font: font('subheadline'), color: 'text/secondary', style: { overflow: 'hidden', textOverflow: 'ellipsis', flex: '0 1 auto', minWidth: 0 } }),
          text(` · ${mi} mi`, { name: 'Distance', font: font('subheadline'), color: 'text/secondary', noshrink: true, style: { whiteSpace: 'pre' } }))),
      eventUnit({ symbol: kind, score, time, size: 'row' }),
      selected || last ? null : el('div', { name: 'Separator', style: abs({ left: 6, right: 6, bottom: 0, height: 0.5, background: c('separator/default') }) })));
}
export function defaultList({ selected = 'Bixby Bridge', selectedStyle = 'system', rows = LIST_ROWS } = {}) {
  return col({ name: 'List Panel', grow: true, style: { minHeight: 0, background: c('background/content'), overflow: 'hidden' } },
    row({ name: 'List Header', align: 'center', justify: 'space-between', noshrink: true, style: { height: 32, padding: '0 14px 0 12px', borderBottom: `0.5px solid ${c('separator/default')}` } },
      text('45 places', { name: 'Count', font: font('body'), color: 'text/secondary' }),
      icon('line.3.horizontal.decrease.circle', { size: 17, color: 'accent/primary' })),
    sectionHeader({ title: 'Near You · Within 300 mi', count: 16 }),
    col({ name: 'Rows', grow: true, style: { minHeight: 0, overflow: 'hidden' } }, rows.map((r, i) => listRow({ ...r, selected: r.name === selected, selectedStyle, last: i === rows.length - 1 }))),
    row({ name: 'Footer', align: 'center', noshrink: true, style: { height: 29, padding: '0 12px', borderTop: `0.5px solid ${c('separator/default')}`, background: c('background/content') } },
      text('OpenWeather', { name: 'Attribution', font: font('caption', { size: 11 }), color: 'text/secondary' })));
}

// ---- pins ---------------------------------------------------------------------------------------------------------------------
export function pinDot({ score }) {
  return el('div', { name: 'ExplorePin / dot', style: { width: 12, height: 12, borderRadius: '999px', flexShrink: 0, background: c(`light/ramp/${bandFor(score)}`), border: `0.5px solid ${c('separator/default')}` } });
}
export function pinChip({ score, kind = 'goldenEvening' }) {
  return row({ name: 'ExplorePin / chip', align: 'center', gap: 4, noshrink: true,
    style: { padding: '2px 4px 2px 6px', borderRadius: '999px', background: c('background/content'), border: `0.5px solid ${c('separator/default')}`, boxShadow: canvas('shadow/button') } },
  eventUnit({ symbol: kind, score, size: 'pin' }));
}
export function pinSelected({ score, time, kind = 'goldenEvening' }) {
  return col({ name: 'ExplorePin / selected', align: 'center', gap: 1, noshrink: true },
    row({ name: 'Selected Capsule', align: 'center', style: { padding: '4px 8px', borderRadius: '999px', background: c('background/content'), border: `2px solid ${c('map/pin')}`, boxShadow: canvas('shadow/button') } },
      eventUnit({ symbol: kind, score, time, size: 'pin' })),
    svgEl('Pin Tip', { width: 11, height: 8 }, raw(`<path d="M0.5 0.5H10.5L5.5 7.5Z" style="fill:${c('map/pin')}" stroke-linejoin="round"/>`)));
}
/** Anchor a pin at pane pixel (x,y): centred on the point, or (bottom) sitting on it. */
export function mapPin(x, y, child, { bottom = false } = {}) {
  return el('div', { name: bottom ? 'Pin Anchor / Selected' : 'Pin Anchor', style: abs({ left: Math.round(x), top: Math.round(y), width: 0, height: 0, display: 'flex', justifyContent: 'center', alignItems: bottom ? 'flex-end' : 'center' }) }, child);
}
// fractions of the map pane (680 x 768 at 1280x820): [fx, fy, score, 'chip'|'dot']
const PINS = [[0.07, 0.10, 31, 'dot'], [0.17, 0.17, 67, 'chip'], [0.34, 0.60, 70, 'chip'], [0.30, 0.69, 45, 'dot'], [0.62, 0.11, 66, 'chip'], [0.54, 0.20, 66, 'dot'],
  [0.45, 0.30, 66, 'dot'], [0.80, 0.25, 67, 'chip'], [0.90, 0.13, 66, 'dot'], [0.72, 0.19, 66, 'dot'], [0.70, 0.36, 67, 'dot'], [0.12, 0.40, 62, 'dot'], [0.10, 0.70, 58, 'dot'],
  [0.27, 0.86, 71, 'dot'], [0.18, 0.92, 55, 'chip'], [0.40, 0.88, 66, 'dot']];
export function defaultMap({ width = 680, height = 768, selectedName = 'Bixby Bridge', children = [], mapCaption = '' } = {}) {
  const sel = LIST_ROWS.find((r) => r.name === selectedName);
  const pins = PINS.map(([fx, fy, score, kind]) => mapPin(fx * width, fy * height, kind === 'chip' ? pinChip({ score }) : pinDot({ score })));
  return mapPlaceholder({ grow: true, label: mapCaption, children: [pins, sel ? mapPin(0.2 * width, 0.5 * height, pinSelected({ score: sel.score, time: sel.time }), { bottom: true }) : null, children] });
}

// ---- place card ---------------------------------------------------------------------------------------------------------------
function imageStrip(w) {
  return el('div', { name: 'Image Strip (placeholder)', style: { width: w, height: 200, position: 'relative', flexShrink: 0, overflow: 'hidden',
    background: `linear-gradient(180deg, color-mix(in srgb, ${c('text/quaternary')} 70%, ${c('background/window')}) 0%, color-mix(in srgb, ${c('text/tertiary')} 55%, ${c('background/window')}) 100%)` } },
  el('div', { name: 'Horizon', style: abs({ left: 0, right: 0, top: 112, bottom: 0, background: `color-mix(in srgb, ${c('text/secondary')} 45%, ${c('background/window')})` }) }),
  row({ name: 'Look Around Capsule', align: 'center', style: abs({ left: 12, top: 12, height: 26, padding: '0 10px', borderRadius: '999px', background: 'rgba(52,60,78,0.82)' }) },
    text('Look Around', { name: 'Label', font: font('subheadline', { weight: 'semibold', size: 12 }), style: { color: '#FFFFFF' } })),
  row({ name: 'Page Dots', align: 'center', gap: 5, style: abs({ left: 0, right: 0, bottom: 10, justifyContent: 'center' }) },
    [1, 0.45].map((o, i) => el('div', { name: `Dot ${i + 1}`, style: { width: 6, height: 6, borderRadius: '999px', background: '#FFFFFF', opacity: o } }))));
}
export function placeCard({ name = 'Bixby Bridge', locality = 'Big Sur, CA', origin = 'Curated', event = { kind: 'goldenEvening', score: 76, time: '18:09' }, sections = [], scrollY = 0, width = 360, height = 372, image = true } = {}) {
  const bg = `color-mix(in srgb, ${c('background/window')} 95%, transparent)`;
  return col({ name: 'Place Card', w: width, h: height, noshrink: true, clip: true,
    style: { position: 'relative', borderRadius: d('radius/panel'), background: bg, border: `0.5px solid ${c('separator/default')}`, boxShadow: canvas('shadow/material') } },
  col({ name: 'Pinned Header', gap: 8, noshrink: true, style: { padding: '12px 12px 8px', position: 'relative', zIndex: 2, background: bg } },
    col({ name: 'Title Block', gap: 2 },
      text(name, { name: 'Name', font: font('headline'), color: 'text/primary' }),
      row({ name: 'Locality Line', align: 'center', gap: 6 }, text(locality, { name: 'Locality', font: font('subheadline'), color: 'text/secondary' }), provenanceTag(origin))),
    eventUnit({ symbol: event.kind, score: event.score, time: event.time, size: 'card' }),
    el('div', { name: 'Close', style: abs({ right: 12, top: 12, display: 'flex' }) }, icon('xmark.circle.fill', { size: 18, color: 'text/tertiary' }))),
  el('div', { name: 'Scroll Viewport', style: { flex: '1 1 0', minHeight: 0, position: 'relative', overflow: 'hidden' } },
    col({ name: 'Scroll Content', w: width, style: abs({ left: 0, top: -scrollY }) },
      image ? imageStrip(width) : null,
      col({ name: 'Sections', gap: 16, style: { padding: '12px' } }, sections))));
}

// ---- window -------------------------------------------------------------------------------------------------------------------
const glass = (name, kids, extra = {}) => row({ name, align: 'center', noshrink: true, style: { height: 34, ...materialSurface({ kind: 'glass', radius: 999 }), ...extra } }, kids);
const cell = (sym, w = 36) => row({ name: `Toolbar Item / ${sym}`, align: 'center', justify: 'center', noshrink: true, style: { width: w, height: 34 } }, icon(sym, { size: 17, color: 'text/primary' }));
const sideRow = (label, sym, sel) => row({ name: `Sidebar Row / ${label}`, align: 'center', gap: 2, noshrink: true,
  style: { height: 32, padding: '0 10px', borderRadius: 10, background: sel ? canvas('chrome/control-active') : undefined } },
row({ name: 'Icon Slot', align: 'center', justify: 'center', w: 24, noshrink: true }, icon(sym, { size: 17, color: 'accent/primary' })),
text(label, { name: 'Label', font: font('body', { size: 13 }), color: 'text/primary', style: { paddingLeft: 4 } }));
const sideHead = (label, top) => row({ name: `Section Header / ${label}`, align: 'center', noshrink: true, style: { height: 20 + top, paddingTop: top, paddingLeft: 4 } },
  text(label, { name: 'Label', font: font('footnote', { size: 11, weight: 'semibold', lineHeight: 14 }), color: 'text/tertiary' }));

export function exploreWindow({ width = 1280, height = 820, sidebar, extraColumn = null, listWidth, list, map, overlay = null, title = 'Explore', selectedStyle = 'system', mapCaption = '' } = {}) {
  const dark = currentTheme() === 'dark';
  const showSide = sidebar ?? width >= 1280;
  const lw = listWidth ?? (width >= 1280 ? 360 : 340);
  const SW = 240, TB = 52;
  const toolbarBg = dark ? c('background/systemWindow') : '#FFFFFF';
  const sideCol = showSide ? col({ name: 'Sidebar', w: SW, noshrink: true, style: { background: c('background/systemWindow'), height: '100%' } },
    row({ name: 'Sidebar Toolbar', align: 'center', gap: 8, noshrink: true, style: { height: TB, padding: '0 9px 0 19px' } }, trafficLights(), spacer(),
      glass('Toolbar Button / plus', cell('plus', 34), { width: 34 }), glass('Toolbar Button / sidebar', cell('sidebar.left', 34), { width: 34 })),
    col({ name: 'Sidebar List', grow: true, style: { padding: '0 10px', minHeight: 0 } },
      sideHead('Trips', 0), sideRow('All Trips', 'map', false), sideRow('Canyon Country', 'point.topleft.down.to.point.bottomright.curvepath', false),
      sideHead('Find', 12), sideRow('Explore', 'binoculars', true), sideRow('Saved', 'bookmark', false), sideRow('Scout', 'sparkle.magnifyingglass', false))) : null;
  const toolbar = row({ name: 'Toolbar', align: 'center', gap: 9, noshrink: true, style: { height: TB, padding: showSide ? '0 9px 0 20px' : '0 9px 0 19px', background: toolbarBg, position: 'relative', zIndex: 3 } },
    showSide ? null : [trafficLights(), glass('Toolbar Button / sidebar', cell('sidebar.left', 34), { width: 34 })],
    text(title, { name: 'Window Title', font: font('title/section', { size: 15, weight: 'semibold', lineHeight: 20 }), color: 'text/primary', style: { paddingLeft: showSide ? 0 : 6 } }),
    spacer(), glass('Toolbar Group', [cell('wind'), cell('mappin.and.ellipse')]),
    row({ name: 'Toolbar Search', align: 'center', gap: 8, noshrink: true, style: { width: showSide ? 324 : 240, height: 34, padding: '0 12px', ...materialSurface({ kind: 'glass', radius: 999 }) } },
      icon('magnifyingglass', { size: 14, color: 'text/secondary' }), text('Search', { name: 'Prompt', font: font('body'), color: 'text/secondary' })));
  const body = row({ name: 'Content', grow: true, style: { minHeight: 0 } },
    extraColumn ? col({ name: 'Extra Column', w: extraColumn.width, noshrink: true, style: { background: c('background/content'), borderRight: `0.5px solid ${c('separator/default')}`, overflow: 'hidden' } }, extraColumn.html) : null,
    col({ name: 'List Column', w: lw, noshrink: true, style: { borderRight: `0.5px solid ${c('separator/default')}`, minHeight: 0 } }, list ?? defaultList({ selectedStyle })),
    el('div', { name: 'Map Pane', style: { flex: '1 1 0', minWidth: 0, position: 'relative', display: 'flex' } },
      map ?? defaultMap({ width: width - (showSide ? SW : 0) - lw - (extraColumn ? extraColumn.width : 0), height: height - TB, mapCaption }),
      (Array.isArray(overlay) ? overlay : [overlay]).filter(Boolean)));
  return row({ name: 'Window', w: width, h: height, clip: true, noshrink: true,
    style: { position: 'relative', borderRadius: 26, background: c('background/window'), border: `1px solid ${canvas('window/outline')}` } },
  sideCol, col({ name: 'Detail', grow: true, style: { minHeight: 0, minWidth: 0 } }, toolbar, body));
}
