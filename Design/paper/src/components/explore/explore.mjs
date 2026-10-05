// Explore components (D3): ExploreListPanel, ExploreRow, ExploreMapPane, ExplorePinView, ExplorePlaceCard, AddSpotBanner,
// AddToTripMenu, MapStandIn. Source: App/Sources/Explore/*.swift, App/Sources/Components/AddToTripMenu.swift.
// The Explore screens (src/screens/explore/explore.mjs) are built from the SAME exported functions as these specimens.
import { col, row, text, el, svgEl, raw, spacer } from '../../../tools/lib/h.mjs';
import { c, d, dv, canvas, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { button, divider, spinner, contentUnavailable } from '../../../tools/lib/controls.mjs';
import { menu, mapPlaceholder, note } from '../../../tools/lib/chrome.mjs';
import { lightBadge, sampleDataLabel, weatherAttribution, provenanceTag, WINDOWS, bandFor, NO_FORECAST } from '../../../tools/lib/lightindex.mjs';
import { artboardHeader, themeBlocks, section, gridRow, cell, colHeaders, page } from '../../../tools/lib/specimens.mjs';

const abs = (o) => ({ position: 'absolute', ...o });

// ---- data (curated spots, sample weather: Tue 6 Oct 2026, 10:00 Denver; from the Explore snapshots) ---------------------------
export const DAY = 'Tue, Oct 6, 2026';
export const LIST_W = 360; // IterSize.listIdeal (the snapshots show the 520 listMax; the app opens at the ideal width)

// A scored row: kind = LightWindow kind. conf = confidence (sample weather is medium).
const S = (name, locality, kind, score, time, conf = 'medium') => ({ name, locality, kind, score, time, conf });
const N = (name, locality, kind, time, reason = 'weatherServiceNotEnabled') => ({ name, locality, kind, time, reason });

// Default state: sorted by best light, the rows that fit a 1280 x 820 window (11 of the 45).
export const ROWS_DEFAULT = [
  S('Ancient Bristlecone Pine Forest', 'White Mountains, CA', 'night', 86, '19:54'),
  S('Mobius Arch, Alabama Hills', 'Lone Pine, CA', 'night', 86, '19:54'),
  S('Palouse Falls', 'Palouse Falls State Park, WA', 'goldenEvening', 79, '17:42'),
  S('Keyhole Arch, Pfeiffer Beach', 'Big Sur, CA', 'goldenEvening', 75, '18:09'),
  S('Bombay Beach', 'Salton Sea, CA', 'goldenEvening', 74, '17:47'),
  S('Hopi Point', 'Grand Canyon National Park, AZ', 'goldenEvening', 73, '17:30'),
  S('McWay Falls', 'Julia Pfeiffer Burns State Park, CA', 'goldenEvening', 73, '18:08'),
  S('Point Reyes Lighthouse', 'Point Reyes National Seashore, CA', 'goldenEvening', 73, '18:12'),
  S('The Watchman from Canyon Junction', 'Zion National Park, UT', 'goldenEvening', 73, '18:32'),
  S('The Wave', 'Coyote Buttes North, AZ', 'goldenEvening', 73, '17:29'),
  S('Glacier Point', 'Yosemite National Park, CA', 'goldenEvening', 58, '17:58'),
];
// No forecast: every score is unknown, so the sort falls back to name.
export const ROWS_NOFORECAST = [
  N('Ancient Bristlecone Pine Forest', 'White Mountains, CA', 'night', '19:54'),
  N('Badwater Basin', 'Death Valley National Park, CA', 'goldenMorning', '06:46'),
  N('Bixby Bridge', 'Big Sur, CA', 'goldenEvening', '18:09'),
  N('Bodie Ghost Town', 'Bodie State Historic Park, CA', 'goldenEvening', '17:55'),
  N('Bombay Beach', 'Salton Sea, CA', 'goldenEvening', '17:47'),
  N('Bonneville Salt Flats', 'Wendover, UT', 'goldenEvening', '18:32'),
  N('Canyon Overlook', 'Zion National Park, UT', 'goldenMorning', '07:31'),
  N('Convict Lake', 'Mammoth Lakes, CA', 'goldenMorning', '06:55'),
  N('Crater Lake from Watchman Overlook', 'Crater Lake National Park, OR', 'goldenMorning', '07:11'),
  N('Dead Horse Point', 'Dead Horse Point State Park, UT', 'goldenMorning', '07:19'),
  N('Delicate Arch', 'Arches National Park, UT', 'goldenEvening', '18:17'),
];

// Map pin positions as fractions of the map pane, measured from the snapshot stand-in (which projects the 45 spots' real
// coordinates). [x, y] in the 2000 px wide snapshot view; converted below.
const fx = (X) => (X - 813) / 1187, fy = (Y) => (Y - 81) / 1200;
const P = (X, Y, extra = {}) => ({ fx: fx(X), fy: fy(Y), ...extra });
export const MESA = P(1857, 830, { id: 'Mesa Arch' });
const CHIPS = [
  P(1309, 208, { kind: 'goldenEvening', score: 79 }), P(1314, 872, { kind: 'night', score: 86 }), P(1318, 928, { kind: 'night', score: 86 }),
  P(1074, 954, { kind: 'goldenEvening', score: 75 }), P(1708, 966, { kind: 'goldenEvening', score: 73 }), P(1473, 1160, { kind: 'goldenEvening', score: 74 }),
];
const DOTS = [
  ...[[932, 264], [1053, 286], [1593, 631], [1257, 813], [1213, 849], [1329, 973], [1365, 999], [1473, 1049], [1551, 936], [1575, 940], [1759, 909], [1881, 775]].map(([x, y]) => P(x, y, { score: 30 })),
  ...[[1029, 840], [1802, 787]].map(([x, y]) => P(x, y, { score: 50 })),
  ...[[994, 828], [1221, 847], [1717, 900]].map(([x, y]) => P(x, y, { score: 66 })),
];
const RINGS = [[1078, 201], [1078, 308], [1049, 474], [1185, 760], [1256, 832], [1267, 857], [1283, 885], [1382, 928], [1401, 941], [1404, 955], [1655, 885], [1706, 855], [1749, 908], [1793, 798], [1841, 901], [1648, 955], [1866, 795], [1068, 944], [1083, 960], [1312, 872], [1315, 928]].map(([x, y]) => P(x, y));
export const PINS = { chips: CHIPS, dots: DOTS, rings: RINGS };

// ---- ExploreRow -------------------------------------------------------------------------------------------------------------------
const RIGHT_W = 112; // fixed slot so badges align across rows (the built row is right-aligned and sized to content)
export function exploreRow({ name, locality, kind, score, conf = 'medium', time, reason, yours = false, noWindow = false, selected = false, width }) {
  const light = noWindow
    ? text('No such light today', { name: 'No Window Today', font: font('caption'), color: 'text/secondary' })
    : col({ name: 'Light', gap: d('space/xxs'), align: 'flex-start' },
      typeof score === 'number'
        ? lightBadge({ style: 'regular', window: kind, score, band: bandFor(score), confidence: conf })
        : lightBadge({ style: 'regular', window: kind, reason: reason || 'weatherServiceNotEnabled' }),
      time ? text(time, { name: 'Start Time', font: font('type/timeSmall'), color: 'text/secondary' }) : null);
  return row({ name: `ExploreRow / ${name}`.slice(0, 50), align: 'center', gap: d('space/md'), w: width, noshrink: !!width,
    style: { padding: `8px ${selected ? d('space/sm') : '0'}`, background: selected ? canvas('selection/tint') : undefined, borderRadius: selected ? d('radius/control') : undefined } },
  col({ name: 'Spot', gap: d('space/xxs'), grow: true },
    text(name, { name: 'Name', font: font('bodyEmphasis'), color: 'text/primary', style: { overflow: 'hidden', textOverflow: 'ellipsis' } }),
    row({ name: 'Locality Line', align: 'center', gap: d('space/xs'), style: { minWidth: 0 } },
      text(locality, { name: 'Locality', font: font('caption'), color: 'text/secondary', style: { overflow: 'hidden', textOverflow: 'ellipsis', minWidth: 0 } }),
      yours ? provenanceTag('Added by you') : null)),
  el('div', { name: 'Light Slot', style: { width: RIGHT_W, flexShrink: 0, display: 'flex', justifyContent: 'flex-start' } }, light));
}

// ---- ExploreListPanel -------------------------------------------------------------------------------------------------------------
// opts: count, intent ("Each spot's best" | 'Sunset' ...), loading, sample, notice (NO_FORECAST key), search ({state:'offer'|'searching'|'failed', query}),
// sections: [{title, rows:[exploreRow opts]}] | empty: 'filters' | 'places' ; footerSample, width, height
function summaryLine({ count, intent, loading, day = DAY }) {
  return row({ name: 'Summary', align: 'center', gap: d('space/xs') },
    text(`${count} ${count === 1 ? 'place' : 'places'}`, { name: 'Count', font: font('subheadline'), color: 'text/secondary' }),
    text('·', { name: 'Separator 1', font: font('subheadline'), color: 'text/tertiary' }),
    text(day, { name: 'Day', font: font('subheadline'), color: 'text/secondary' }),
    text('·', { name: 'Separator 2', font: font('subheadline'), color: 'text/tertiary' }),
    text(intent, { name: 'Intent', font: font('subheadline'), color: 'text/secondary' }),
    spacer(), loading ? spinner(14) : null);
}
function searchStatus(s) {
  if (!s) return null;
  if (s.state === 'searching') {
    return row({ name: 'Search Status / Searching', align: 'center', gap: d('space/sm') }, spinner(14),
      text('Searching Apple Maps…', { name: 'Message', font: font('caption'), color: 'text/secondary' }), spacer(),
      button('Cancel', { size: 'small' }));
  }
  if (s.state === 'failed') {
    return row({ name: 'Search Status / Failed', align: 'flex-start', gap: d('space/sm') },
      row({ name: 'Failure Label', align: 'flex-start', gap: d('space/xs'), grow: true },
        el('div', { name: 'Icon Slot', style: { display: 'flex', alignItems: 'center', height: 14, flexShrink: 0 } }, icon('exclamationmark.triangle', { size: 12, color: 'status/warning' })),
        text(`Couldn't search Apple Maps for “${s.query}”.`, { name: 'Message', font: font('caption'), color: 'status/warning', wrap: true, grow: true })),
      button('Retry', { size: 'small' }));
  }
  return row({ name: 'Search Status / Offer', align: 'center', gap: d('space/xs') }, icon('magnifyingglass', { size: 11, color: 'accent/text' }),
    text(`Search Apple Maps for “${s.query}”`, { name: 'Link', font: font('caption'), color: 'accent/text' }));
}
export function exploreHeader({ count, day, intent = "Each spot's best", loading = false, sample = false, notice, search }) {
  return col({ name: 'Header', gap: d('space/sm'), style: { padding: `${d('space/sm')} ${d('space/md')}`, flexShrink: 0 } },
    summaryLine({ count, intent, loading, day }),
    sample ? sampleDataLabel({ style: 'inline' }) : null,
    notice ? row({ name: 'Forecast Notice', align: 'flex-start', gap: d('space/xs') },
      el('div', { name: 'Icon Slot', style: { display: 'flex', alignItems: 'center', height: 14, flexShrink: 0 } }, icon('cloud.slash', { size: 12, color: 'text/secondary' })),
      text(NO_FORECAST[notice].long, { name: 'Notice', font: font('caption'), color: 'text/secondary', wrap: true, grow: true })) : null,
    searchStatus(search));
}
export function listSectionBlock({ title, rows, count }) {
  return col({ name: `List Section / ${title}`.slice(0, 50), style: { flexShrink: 0 } },
    row({ name: 'Section Header', align: 'center', justify: 'space-between', style: { padding: '10px 16px 4px' } },
      text(title, { name: 'Title', font: font('captionStrong'), color: 'text/secondary' }),
      text(String(count ?? rows.length), { name: 'Count', font: font('captionStrong'), color: 'text/secondary' })),
    col({ name: 'Rows', style: { padding: '0 16px' } },
      rows.flatMap((r, i) => [i ? divider({ name: 'Row Separator' }) : null, exploreRow(r)])));
}
export function exploreEmpty(kind, { query = '', narrowed = false } = {}) {
  const places = kind === 'places';
  return col({ name: 'Empty State', grow: true, align: 'center', justify: 'center', style: { minHeight: 0 } },
    contentUnavailable({
      symbol: places ? 'mappin.slash' : 'line.3.horizontal.decrease.circle',
      title: places ? 'No places found' : 'No Matching Spots',
      description: places ? `Nothing on Apple Maps matches “${query}” around the map.` : 'Nothing fits the current search and filters.',
      buttons: !places || narrowed ? [button('Clear Filters')] : [],
    }));
}
export function exploreListPanel({ width = LIST_W, height, header, sections = [], empty, emptyOpts, footer = 'sample' } = {}) {
  const body = empty
    ? exploreEmpty(empty, emptyOpts)
    : col({ name: 'List', grow: true, clip: true, style: { minHeight: 0 } }, sections.map(listSectionBlock));
  return col({ name: 'ExploreListPanel', w: width, h: height, noshrink: true, bg: c('background/content'), style: { minHeight: 0 } },
    exploreHeader(header), divider({ name: 'Header Divider' }), body, divider({ name: 'Footer Divider' }),
    row({ name: 'Footer', align: 'center', style: { padding: `${d('space/sm')} ${d('space/md')}`, minHeight: 33, flexShrink: 0 } },
      footer === 'sample' ? weatherAttribution({ sample: true }) : footer === 'weather' ? weatherAttribution() : null));
}

// ---- ExplorePinView ---------------------------------------------------------------------------------------------------------------
const BAND_OF = (s) => bandFor(s);
export function pinDot({ score } = {}) {
  const base = { width: d('space/md'), height: d('space/md'), borderRadius: '999px', flexShrink: 0 };
  if (typeof score === 'number') return el('div', { name: 'ExplorePin / dot', style: { ...base, background: c(`light/ramp/${BAND_OF(score)}`), border: `${d('stroke/hairline')} solid ${c('separator/default')}` } });
  return el('div', { name: 'ExplorePin / dot (no forecast)', style: { ...base, background: c('background/content'), border: `${d('stroke/regular')} solid ${c('status/noForecast')}` } });
}
export function pinChip({ kind, score } = {}) {
  if (typeof score !== 'number' && !kind) return pinDot({});
  return row({ name: 'ExplorePin / chip', align: 'center', noshrink: true,
    style: { padding: `${d('space/xxs')} ${d('space/xs')}`, borderRadius: '999px', background: c('background/content'), border: `${d('stroke/hairline')} solid ${c('separator/default')}` } },
  lightBadge(typeof score === 'number' ? { style: 'compact', window: kind, score, band: BAND_OF(score) } : { style: 'compact', window: kind, reason: 'weatherServiceNotEnabled' }));
}
export function pinSelected({ kind, score, time, name } = {}) {
  const inner = kind
    ? row({ name: 'Pin Content', align: 'center', gap: d('space/xs') },
      lightBadge(typeof score === 'number' ? { style: 'compact', window: kind, score, band: BAND_OF(score) } : { style: 'compact', window: kind, reason: 'weatherServiceNotEnabled' }),
      time ? text(time, { name: 'Start Time', font: font('type/timeSmall'), color: 'text/primary' }) : null)
    : text(name, { name: 'Spot Name', font: font('captionStrong'), color: 'text/primary' });
  return col({ name: 'ExplorePin / selected', align: 'center', gap: d('space/xxs'), noshrink: true },
    row({ name: 'Selected Capsule', align: 'center', style: { padding: `${d('space/xs')} ${d('space/sm')}`, borderRadius: '999px', background: c('background/content'), border: `${d('stroke/thick')} solid ${c('map/pin')}` } }, inner),
    icon('arrowtriangle.down.fill', { size: 11, color: 'map/pin' }));
}
// A pin placed on the map pane: a 0 x 0 anchor at (x, y) that centres its content on the point (or sits on it, for the selected pin).
export function pinAt(x, y, child, { bottom = false, name = 'Pin Anchor' } = {}) {
  return el('div', { name, style: abs({ left: Math.round(x), top: Math.round(y), width: 0, height: 0, display: 'flex', justifyContent: 'center', alignItems: bottom ? 'flex-end' : 'center' }) }, child);
}

// All pins for a state. mode: 'default' (chips, scored dots, rings) | 'noforecast' (every pin a ring) | 'none'.
export function exploreMapPins({ width, height, mode = 'default', selected, draft }) {
  const at = (p) => [p.fx * width, p.fy * height];
  const out = [];
  if (mode === 'noforecast') {
    [...RINGS, ...CHIPS, ...DOTS].forEach((p) => out.push(pinAt(...at(p), pinDot({}))));
  } else if (mode === 'default') {
    RINGS.forEach((p) => out.push(pinAt(...at(p), pinDot({}))));
    DOTS.forEach((p) => out.push(pinAt(...at(p), pinDot({ score: p.score }))));
    CHIPS.forEach((p) => out.push(pinAt(...at(p), pinChip(p))));
  }
  if (selected) out.push(pinAt(...at(selected.pos || MESA), pinSelected(selected), { bottom: true, name: 'Pin Anchor / Selected' }));
  if (draft) out.push(pinAt(draft.x, draft.y, icon('mappin.circle.fill', { size: 28, color: 'accent/primary' }), { bottom: true, name: 'Pin Anchor / New spot' }));
  return out;
}

// ---- AddSpotBanner / ExplorePlaceCard ---------------------------------------------------------------------------------------------
const matFill = () => canvas('material/regular');
export function addSpotBanner() {
  return row({ name: 'AddSpotBanner', align: 'center', gap: d('space/sm'), noshrink: true,
    style: { padding: `${d('space/sm')} ${d('space/md')}`, borderRadius: '999px', background: matFill(), border: `${d('stroke/thin')} solid ${c('accent/primary')}` } },
  icon('mappin.and.ellipse', { size: 15, color: 'accent/primary' }),
  text('Click the map to drop a pin for your spot', { name: 'Hint', font: font('subheadline'), color: 'text/primary' }),
  button('Cancel'));
}
export function addToTripButton() {
  return row({ name: 'AddToTripMenu / button', align: 'center', gap: d('space/xs'), noshrink: true,
    style: { height: d('size/control/height'), padding: `0 ${d('space/md')}`, borderRadius: '999px', background: canvas('control/button'), border: `1px solid ${canvas('control/button-stroke')}`, boxShadow: canvas('shadow/button') } },
  icon('plus.circle', { size: 14, color: 'text/primary' }),
  text('Add to Trip', { name: 'Label', font: font('body'), color: 'text/primary' }),
  icon('chevron.down', { size: 9, color: 'text/secondary', weight: 'bold' }));
}
// kind: 'passed' (the snapshot case) | 'scored' | 'none' (no such light today) ; own: your own spot (no Save button)
export function explorePlaceCard({ name = 'Mesa Arch', locality = 'Canyonlands National Park, UT', origin = 'Curated', kind = 'passed', saved = true, own = false, width = LIST_W } = {}) {
  let light;
  if (kind === 'none') {
    light = text('No such light today', { name: 'No Window Today', font: font('subheadline'), color: 'text/secondary' });
  } else {
    const scored = kind === 'scored';
    light = col({ name: 'Light Block', gap: d('space/xs') },
      row({ name: 'Light Row', align: 'center', gap: d('space/md') },
        scored ? lightBadge({ style: 'regular', window: 'goldenEvening', score: 73, band: 'good', confidence: 'medium', sample: true })
          : lightBadge({ style: 'regular', window: 'goldenMorning', reason: 'inThePast' }),
        spacer(),
        col({ name: 'Times', align: 'flex-end' },
          text(scored ? '17:30' : '07:20', { name: 'Start Time', font: font('type/time'), color: 'text/primary' }),
          text(scored ? '17:30–18:05' : '07:20–07:55', { name: 'Time Range', font: font('caption'), color: 'text/secondary' }))),
      scored ? null : text(NO_FORECAST.inThePast.long, { name: 'Reason', font: font('caption'), color: 'text/secondary', wrap: true }));
  }
  return col({ name: `ExplorePlaceCard / ${name}`.slice(0, 50), w: width, gap: d('space/md'), pad: d('space/md'), noshrink: true,
    style: { background: matFill(), borderRadius: d('radius/panel'), border: `${d('stroke/hairline')} solid ${c('separator/default')}` } },
  row({ name: 'Identity', align: 'flex-start', gap: d('space/sm') },
    col({ name: 'Name and Locality', gap: d('space/xxs'), grow: true },
      text(name, { name: 'Name', font: font('headline'), color: 'text/primary' }),
      row({ name: 'Locality Line', align: 'center', gap: d('space/xs') },
        text(locality, { name: 'Locality', font: font('subheadline'), color: 'text/secondary' }), provenanceTag(origin))),
    icon('xmark.circle.fill', { size: 16, color: 'text/tertiary' })),
  light,
  row({ name: 'Actions', align: 'center', gap: d('space/sm') },
    button('Open', { kind: 'prominent', width: 64 }),
    own ? null : button(saved ? 'Saved' : 'Save', { icon: saved ? 'bookmark.fill' : 'bookmark' }),
    addToTripButton()));
}

// ---- ExploreMapPane ---------------------------------------------------------------------------------------------------------------
function mapControls() {
  const cap = (nm, ...kids) => col({ name: nm, align: 'center', justify: 'center', noshrink: true, style: { width: 28, borderRadius: 10, background: canvas('chrome/control'), border: `1px solid ${canvas('chrome/control-stroke')}`, boxShadow: canvas('shadow/control') } }, kids);
  return col({ name: 'Map Controls (swap)', gap: d('space/sm'), align: 'center', style: abs({ top: d('space/md'), right: d('space/md') }) },
    cap('Zoom Stepper', el('div', { name: 'Zoom In', style: { height: 28, display: 'flex', alignItems: 'center' } }, icon('plus', { size: 12, color: 'text/primary', weight: 'semibold' })),
      el('div', { name: 'Stepper Divider', style: { width: 16, height: 1, background: c('separator/default') } }),
      el('div', { name: 'Zoom Out', style: { height: 28, display: 'flex', alignItems: 'center' } }, icon('minus', { size: 12, color: 'text/primary', weight: 'semibold' }))),
    cap('Compass', el('div', { name: 'Compass Glyph', style: { height: 28, display: 'flex', alignItems: 'center' } }, icon('location.north.fill', { size: 13, color: 'status/danger' }))));
}
// state: { pins mode, selected pin, card opts | null, banner, draft }
export function exploreMapPane({ width, height, mode = 'default', selected, card, banner = false, draft, label, pins } = {}) {
  const kids = [
    ...(pins || exploreMapPins({ width, height, mode, selected, draft })),
    mapControls(),
    banner ? el('div', { name: 'Banner Position', style: abs({ top: d('space/md'), left: 0, right: 0, display: 'flex', justifyContent: 'center' }) }, addSpotBanner()) : null,
    card ? el('div', { name: 'Place Card Position', style: abs({ bottom: d('space/md'), left: 0, right: 0, display: 'flex', justifyContent: 'center' }) }, explorePlaceCard(card)) : null,
  ];
  return mapPlaceholder({ width, height, label, children: kids });
}

// ---- menus (AddToTripMenu, spot/pin context menu, filters, sort) --------------------------------------------------------------
export const TRIP_DAYS = [
  ['Day 1', 'Wed, Oct 7, 2026', 'Sunrise · 71'], ['Day 2', 'Thu, Oct 8, 2026', 'Sunrise · 64'],
  ['Day 3', 'Fri, Oct 9, 2026', 'Sunrise · 58'], ['Day 4', 'Sat, Oct 10, 2026', 'Sunrise · No forecast'],
];
export const addToTripMenu = (o = {}) => menu([
  { label: 'Canyon Country', submenu: true, highlight: o.highlightTrip },
  '-',
  { label: 'New Trip with This Spot' },
], { name: 'Menu / Add to Trip', ...o });
export const tripDaysMenu = (o = {}) => menu(TRIP_DAYS.map(([a, b, cc], i) => ({ label: `${a} · ${b} · ${cc}`, highlight: i === 0 && o.highlight })), { name: 'Submenu / Canyon Country days', ...o });
export const spotContextMenu = (o = {}) => menu([
  { label: 'Open', icon: 'arrow.right.circle' },
  { label: o.saved ? 'Unsave' : 'Save', icon: o.saved ? 'bookmark.slash' : 'bookmark' },
  { label: 'Add to Trip', icon: 'plus.circle', submenu: true, highlight: o.highlightAdd },
  '-',
  { label: 'Open in Maps', icon: 'map' },
  { label: 'Copy Coordinates', icon: 'doc.on.doc' },
], { name: 'Menu / Spot context', ...o });
export const CATEGORIES = ['Landscape', 'Desert', 'Coast', 'Waterfall', 'Astro', 'Architecture', 'Street', 'Wildlife', 'Macro', 'Aerial'];
export const filtersMenu = (o = {}) => menu([
  { label: 'Category', submenu: true, highlight: o.highlight === 'Category' },
  { label: 'Known For', submenu: true, highlight: o.highlight === 'Known For' },
  { label: 'Source', submenu: true, highlight: o.highlight === 'Source' },
  '-',
  { label: 'Clear Filters', disabled: !o.active },
], { name: 'Menu / Filters', ...o });
export const categorySubmenu = (o = {}) => menu(CATEGORIES.map((l, i) => ({ label: l, checked: o.checked === i })), { name: 'Submenu / Category', ...o });
export const knownForSubmenu = (o = {}) => menu(['Sunrise', 'Sunset', 'Blue hour', 'Night sky', 'Midday', 'Overcast'].map((l) => ({ label: l })), { name: 'Submenu / Known For', ...o });
export const sourceSubmenu = (o = {}) => menu(['Curated', 'Your Spots', 'Apple Maps'].map((l, i) => ({ label: l, checked: o.checked === i })), { name: 'Submenu / Source', ...o });
export const sortMenu = (o = {}) => menu([
  { header: 'Sort' },
  ...['Best Light', 'Name', 'Distance from Map Centre', 'Popularity'].map((l, i) => ({ label: l, checked: i === 0 })),
], { name: 'Menu / Sort', ...o });
export const lightMenu = (o = {}) => menu([
  { label: "Each spot's best", checked: true }, '-',
  { label: 'Sunrise', icon: 'sunrise' }, { label: 'Sunset', icon: 'sunset' }, { label: 'Blue hour', icon: 'moon.haze' }, { label: 'Night', icon: 'moon.stars' },
], { name: 'Menu / Light', ...o });

// ==== component artboards ================================================================================================================

// ExploreRow
const rowBoard = () => {
  const W = 480;
  const body = () => [
    section('Light states',
      gridRow('Scored', [cell('row scored', exploreRow({ ...ROWS_DEFAULT[0], width: W }), { width: W })], { labelWidth: 120 }),
      gridRow('Scored, good', [cell('row good', exploreRow({ ...ROWS_DEFAULT[5], width: W }), { width: W })], { labelWidth: 120 }),
      gridRow('Low confidence', [cell('row low confidence', exploreRow({ ...ROWS_DEFAULT[6], conf: 'low', width: W }), { width: W })], { labelWidth: 120 }),
      gridRow('No forecast', [cell('row no forecast', exploreRow({ ...ROWS_NOFORECAST[1], width: W }), { width: W })], { labelWidth: 120 }),
      gridRow('No such light today', [cell('row no window', exploreRow({ name: 'Haystack Rock', locality: 'Cannon Beach, OR', noWindow: true, width: W }), { width: W })], { labelWidth: 120 }),
      gridRow('Your own spot', [cell('row yours', exploreRow({ name: 'Backyard Ridge', locality: 'Boulder, CO', kind: 'goldenEvening', score: 66, time: '17:48', yours: true, width: W }), { width: W })], { labelWidth: 120 }),
      gridRow('Selected', [cell('row selected', exploreRow({ ...ROWS_DEFAULT[2], selected: true, width: W }), { width: W })], { labelWidth: 120 })),
  ];
  return page([
    artboardHeader({ title: 'ExploreRow', type: 'ExploreRowView', file: 'Explore/ExploreListPanel.swift', job: 'One spot and its light on the chosen day: name over locality at left; badge and window start time at right.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Anatomy', body: 'Gap space/md, vertical padding space/xs inside the system List row (about 10 px each side as drawn). Name type/bodyEmphasis; locality type/caption; time type/timeSmall with monospaced digits. The badge column is a fixed 112 px slot here so columns align; the app sizes it to content and right-aligns it.' }),
        note({ title: 'Provenance', body: 'Only "Added by you" rows carry a ProvenanceTag; Curated and Apple Maps rows do not (SCREENS.md says Apple Maps rows are tagged: the source does not).' }),
        note({ title: 'Hover', body: 'The row has no hover style; hovering gives the map pin a chip.' })),
      themeBlocks(body, { width: 780 })),
  ], { gap: 24 });
};

// ExplorePinView
const pinBoard = () => {
  const body = () => [
    section('Dot',
      row({ name: 'Dots', gap: 32, align: 'center' },
        ['poor', 'fair', 'good', 'great', 'epic'].map((b, i) => cell(`dot ${b}`, pinDot({ score: [22, 48, 66, 81, 94][i] }), { caption: b })),
        cell('dot no forecast', pinDot({}), { caption: 'no forecast' }))),
    section('Chip',
      row({ name: 'Chips', gap: 32, align: 'center', wrap: true },
        cell('chip night', pinChip({ kind: 'night', score: 86 })), cell('chip sunset', pinChip({ kind: 'goldenEvening', score: 73 })),
        cell('chip sunrise', pinChip({ kind: 'goldenMorning', score: 64 })), cell('chip no forecast', pinChip({ kind: 'goldenMorning' }), { caption: 'no forecast: ring + short name' }))),
    section('Selected',
      row({ name: 'Selected Pins', gap: 40, align: 'flex-end', wrap: true },
        cell('selected scored', pinSelected({ kind: 'goldenEvening', score: 73, time: '17:30' })),
        cell('selected no forecast', pinSelected({ kind: 'goldenMorning', time: '07:20' }), { caption: 'Mesa Arch, window passed' }),
        cell('selected no window', pinSelected({ name: 'Haystack Rock' }), { caption: 'no window: spot name' }))),
  ];
  return page([
    artboardHeader({ title: 'ExplorePinView', type: 'ExplorePinView', file: 'Explore/ExplorePinView.swift', job: 'Map hierarchy: one selected pin, the best six scored spots (and a hovered one) as chips, everything else a dot.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Selected pin colour', body: 'COMPONENTS.md says the selected border and arrow are accent/primary. The source draws both in IterColor.mapPin (map/pin). Source followed.' }),
        note({ title: 'Anchor', body: 'The selected pin anchors at the bottom tip of its arrow; dots and chips anchor at their centre. Draw order: selected, then chips, then dots (selected on top).' })),
      themeBlocks(body, { width: 640 })),
  ], { gap: 24 });
};

// ExplorePlaceCard
const cardBoard = () => {
  const body = () => [
    row({ name: 'Cards', gap: 32, align: 'flex-start', wrap: true },
      cell('card passed', explorePlaceCard({ kind: 'passed' }), { caption: 'No forecast / window passed (the snapshots); saved', width: LIST_W }),
      cell('card scored', explorePlaceCard({ name: 'Hopi Point', locality: 'Grand Canyon National Park, AZ', kind: 'scored', saved: false }), { caption: 'Scored, window ahead; not saved', width: LIST_W })),
    row({ name: 'Cards 2', gap: 32, align: 'flex-start', wrap: true },
      cell('card no window', explorePlaceCard({ name: 'Haystack Rock', locality: 'Cannon Beach, OR', kind: 'none', saved: false }), { caption: 'No window that day', width: LIST_W }),
      cell('card own spot', explorePlaceCard({ name: 'Backyard Ridge', locality: 'Boulder, CO', origin: 'Added by you', kind: 'scored', own: true }), { caption: 'Your own spot: no Save button', width: LIST_W })),
  ];
  return page([
    artboardHeader({ title: 'ExplorePlaceCard', type: 'ExplorePlaceCard', file: 'Explore/ExplorePlaceCard.swift', job: "The selected spot's identity, its light that day, and one primary action." }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Save symbol (doc error)', body: 'COMPONENTS.md and SCREENS.md say star / star.fill ("Saved (filled star)"). The source uses bookmark / bookmark.fill, as everywhere else. Source followed.' }),
        note({ title: 'Material', body: 'The card is regularMaterial in the app (canvas material/regular here); the snapshots draw it flat background/content. The built card is max 360 wide, centred at the bottom of the map with space/md margin.' }),
        note({ title: 'Sample data', body: 'The scored card shows the Sample data label inline in the badge (showsSource defaults on); the passed-window card has none.' })),
      themeBlocks(body, { width: 840 })),
  ], { gap: 24 });
};

// AddSpotBanner
const bannerBoard = () => {
  const body = () => [section('Banner', cell('banner', addSpotBanner(), { caption: 'Capsule, 1 pt accent outline; Cancel responds to Esc' }))];
  return page([
    artboardHeader({ title: 'AddSpotBanner', type: 'AddSpotBanner', file: 'Explore/ExploreMapPane.swift', job: 'Tells the user what a click will do in Add Spot mode.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Material', body: 'regularMaterial in the app (canvas material/regular here), flat background/content in snapshots. Docked at the top of the map with space/md margin; the place card hides in this mode.' })),
      themeBlocks(body, { width: 520 })),
  ], { gap: 24 });
};

// AddToTripMenu
const addTripBoard = () => {
  const body = () => [
    row({ name: 'Menu Row', gap: 40, align: 'flex-start' },
      cell('button', addToTripButton(), { caption: 'Button style (place card, bordered)' }),
      col({ name: 'Menu Open', gap: d('space/sm'), align: 'flex-start' },
        row({ name: 'Open Menus', gap: 6, align: 'flex-start' },
          addToTripMenu({ highlightTrip: true }),
          tripDaysMenu({}))),
    ),
    section('Menu row in context menus', cell('menu row', menu([{ label: 'Add to Trip', icon: 'plus.circle', submenu: true, highlight: true }]), { caption: 'Spot and pin context menu, Saved context menu' })),
  ];
  return page([
    artboardHeader({ title: 'AddToTripMenu', type: 'AddToTripMenu', file: 'Components/AddToTripMenu.swift', job: 'Add a spot to a trip day, where the choice of day is a light decision.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Day label', body: 'Source: "Day 2 · Thu, Oct 8, 2026 · Sunrise · 64" (TimeText.day and LightText.headline "Sunset · 64"). COMPONENTS.md shows "Day 2 · Wed 7 Oct · Sunset 64"; neither the date nor the middle dot in the headline matches the source. Scores shown are illustrative.' }),
        note({ title: 'New Trip with This Spot', body: 'Creates a one-day trip "Trip to <spot>" starting tomorrow, adds the stop and opens the trip.' })),
      themeBlocks(body, { width: 760 })),
  ], { gap: 24 });
};

// MapStandIn
const standInBoard = () => {
  const W = 560, H = 400;
  const standIn = () => el('div', { name: 'MapStandIn (snapshot)', style: { width: W, height: H, position: 'relative', display: 'flex', overflow: 'hidden', background: c('background/control'), flexShrink: 0 } },
    ...exploreMapPins({ width: W, height: H, mode: 'default', selected: { kind: 'goldenMorning', time: '07:20' } }),
    text('Map (snapshot stand-in)', { name: 'Stand-in Label', font: font('caption'), color: 'text/tertiary', style: abs({ top: d('space/sm'), left: d('space/sm') }) }));
  const body = () => [
    row({ name: 'Pair', gap: 32, align: 'flex-start' },
      cell('stand-in', standIn(), { caption: 'MapStandIn / ExploreMapStandIn (snapshots only): flat background/control, label top-left', width: W }),
      cell('placeholder', mapPlaceholder({ width: W, height: H, children: exploreMapPins({ width: W, height: H, mode: 'default', selected: { kind: 'goldenMorning', time: '07:20' } }) }), { caption: 'Map placeholder (swap) used on the Explore artboards: roads and contours ground, swap for a real map', width: W })),
  ];
  return page([
    artboardHeader({ title: 'MapStandIn', type: 'MapStandIn, ExploreMapStandIn', file: 'Components/MapStandIn.swift, Explore/ExploreMapPane.swift', job: 'Snapshots only: a labelled stand-in for a live map. Not part of the product design.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Stand-in versus placeholder', body: 'The stand-in is what the snapshot tests draw: a flat ground that projects the 45 spots at their real coordinates, with the same pin views. These artboards use a quiet map placeholder (named "Map placeholder (swap)") with the pins drawn on top at the stand-in positions; swap it for a real map image.', width: 360 }),
        note({ title: 'Real map', body: 'The product map is MapKit: standard, flat, no points of interest, with zoom stepper, compass and scale. Design it from ExploreMapPane, not from the stand-in.', width: 360 })),
      themeBlocks(body, { width: 1240, direction: 'column' })),
  ], { gap: 24 });
};

// ExploreMapPane
const paneBoard = () => {
  const W = 560, H = 440;
  const body = () => [
    row({ name: 'Panes', gap: 32, align: 'flex-start', wrap: true },
      cell('pane default', exploreMapPane({ width: W, height: H }), { caption: 'Default: chips for the best six, dots, rings for no score', width: W }),
      cell('pane selected', exploreMapPane({ width: W, height: H, selected: { kind: 'goldenMorning', time: '07:20' }, card: { kind: 'passed' } }), { caption: 'A selection: selected pin and place card', width: W }),
      cell('pane add spot', exploreMapPane({ width: W, height: H, banner: true }), { caption: 'Add Spot mode: banner, crosshair cursor, pins not clickable, card hidden', width: W }),
      cell('pane draft', exploreMapPane({ width: W, height: H, banner: false, draft: { x: 300, y: 220 } }), { caption: 'Draft pin placed: "New spot" (mappin.circle.fill, accent); the Spot editor sheet opens', width: W })),
  ];
  return page([
    artboardHeader({ title: 'ExploreMapPane', type: 'ExploreMapPane', file: 'Explore/ExploreMapPane.swift', job: 'The map with pin hierarchy, shared selection, the place card and Add Spot mode.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Placeholder', body: 'The ground is a placeholder to swap for the real map. Pins are drawn at the stand-in positions. Controls (zoom stepper, compass) are indicative; MapKit draws them.' })),
      themeBlocks(body, { width: 1240, direction: 'column' })),
  ], { gap: 24 });
};

// ExploreListPanel
const panelBoard = () => {
  const H = 640;
  const sample = { count: 45, sample: true, loading: false };
  const body = () => [
    row({ name: 'Panels', gap: 24, align: 'flex-start', wrap: true },
      cell('panel list', exploreListPanel({ height: H, header: sample, sections: [{ title: 'Spots', count: 45, rows: ROWS_DEFAULT.slice(0, 7) }] }), { caption: 'List, sample data', width: LIST_W }),
      cell('panel loading search', exploreListPanel({ height: H, header: { count: 45, sample: true, loading: true, search: { state: 'searching', query: 'antelope' } }, sections: [{ title: 'Spots', count: 45, rows: ROWS_DEFAULT.slice(0, 7) }] }), { caption: 'Loading forecasts (spinner) and searching Apple Maps', width: LIST_W }),
      cell('panel failed', exploreListPanel({ height: H, header: { count: 45, sample: true, search: { state: 'failed', query: 'antelope' } }, sections: [{ title: 'Spots', count: 45, rows: ROWS_DEFAULT.slice(0, 7) }] }), { caption: 'Search failed: warning line with Retry', width: LIST_W }),
      cell('panel offer', exploreListPanel({ height: H, header: { count: 45, sample: true, search: { state: 'offer', query: 'antelope' } }, sections: [{ title: 'Spots', count: 45, rows: ROWS_DEFAULT.slice(0, 7) }] }), { caption: 'Query typed, not yet searched: link row', width: LIST_W })),
    row({ name: 'Panels 2', gap: 24, align: 'flex-start', wrap: true },
      cell('panel notice', exploreListPanel({ height: H, footer: null, header: { count: 45, notice: 'weatherServiceNotEnabled' }, sections: [{ title: 'Spots', count: 45, rows: ROWS_NOFORECAST.slice(0, 7) }] }), { caption: 'No forecast: reason with cloud.slash, empty footer', width: LIST_W }),
      cell('panel empty filters', exploreListPanel({ height: H, header: { count: 0, sample: true }, empty: 'filters' }), { caption: 'Empty: No Matching Spots', width: LIST_W }),
      cell('panel empty places', exploreListPanel({ height: H, header: { count: 0, sample: true }, empty: 'places', emptyOpts: { query: 'antelope' } }), { caption: 'Empty: No places found (real search)', width: LIST_W })),
  ];
  return page([
    artboardHeader({ title: 'ExploreListPanel', type: 'ExploreListPanel', file: 'Explore/ExploreListPanel.swift', job: 'The reading surface of Explore: summary, notices, search status, the list, attribution.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Width', body: 'The column is 300 min, 360 ideal, 520 max (HSplitView); drawn at the ideal 360. The snapshots show it at 520.' }),
        note({ title: 'cloud.slash', body: 'The cloud.slash symbol is missing from the local SF Symbol set, so the notice icon is the neutral stand-in glyph.' })),
      themeBlocks(body, { width: 1640, direction: 'column' })),
  ], { gap: 24 });
};

export const artboards = [
  { id: 'C-explore-row', name: 'ExploreRow', section: 'components', width: 1720, height: 944, themes: ['light'], covers: ['Component/ExploreRow'], notes: [], render: rowBoard },
  { id: 'C-explore-pin', name: 'ExplorePinView', section: 'components', width: 1400, height: 624, themes: ['light'], covers: ['Component/ExplorePinView'], notes: ['COMPONENTS.md says the selected pin is accent/primary; source uses map/pin'], render: pinBoard },
  { id: 'C-explore-place-card', name: 'ExplorePlaceCard', section: 'components', width: 1800, height: 752, themes: ['light'], covers: ['Component/ExplorePlaceCard'], notes: ['Save symbol: bookmark, not star'], render: cardBoard },
  { id: 'C-add-spot-banner', name: 'AddSpotBanner', section: 'components', width: 1200, height: 464, themes: ['light'], covers: ['Component/AddSpotBanner'], render: bannerBoard },
  { id: 'C-add-to-trip-menu', name: 'AddToTripMenu', section: 'components', width: 1680, height: 640, themes: ['light'], covers: ['Component/AddToTripMenu', 'Menus/AddToTripMenu'], notes: ['Day label strings differ from COMPONENTS.md'], render: addTripBoard },
  { id: 'C-map-stand-in', name: 'MapStandIn', section: 'components', width: 1304, height: 1312, themes: ['light'], covers: ['Component/MapStandIn'], render: standInBoard },
  { id: 'C-explore-map-pane', name: 'ExploreMapPane', section: 'components', width: 1304, height: 2368, themes: ['light'], covers: ['Component/ExploreMapPane'], render: paneBoard },
  { id: 'C-explore-list-panel', name: 'ExploreListPanel', section: 'components', width: 1704, height: 3128, themes: ['light'], covers: ['Component/ExploreListPanel'], render: panelBoard },
];
