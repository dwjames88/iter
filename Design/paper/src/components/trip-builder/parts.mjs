// Trip builder components (D2): TripHeader, TripPlanList, DayHeader, StopRow, StopNumberBadge, ConnectorRow,
// SuggestionBanner, TripRouteMap, AddStopPopover, plus the small menus. Source of truth: App/Sources/Trips/*.swift.
// Everything here is exported so the screens (src/screens/trip-builder) and the specimens use the same functions.
import { col, row, text, el, svgEl, raw, spacer } from '../../../tools/lib/h.mjs';
import { c, d, dv, canvas, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { button, divider, segmented, textField } from '../../../tools/lib/controls.mjs';
import { mapPlaceholder } from '../../../tools/lib/chrome.mjs';
import { lightBadge, weatherAttribution, warningLine } from '../../../tools/lib/lightindex.mjs';

const TNUM = ';font-variant-numeric:tabular-nums';
const mix = (token, pct) => `color-mix(in srgb, ${c(token)} ${pct}%, transparent)`;
const abs = (o) => ({ position: 'absolute', ...o });

// ---- StopNumberBadge ---------------------------------------------------------------------------------------
// 22 pt circle, system quaternary fill (about 12% of the label colour), number in captionStrong, monospaced digits.
export function stopNumberBadge(n) {
  return row({ name: `StopNumberBadge / ${n}`, align: 'center', justify: 'center', noshrink: true, w: d('size/badge/height'), h: d('size/badge/height'),
    style: { borderRadius: '999px', background: mix('text/primary', 12) } },
  text(String(n), { name: 'Number', font: font('captionStrong') + TNUM, color: 'text/primary' }));
}

// ---- ConnectorRow ------------------------------------------------------------------------------------------
// o: {drive:'57 min · 41 mi' | null (loading), overnight, estimated, shortBy:"Drive doesn't fit: ..." string}
function rail(fits) {
  return row({ name: 'Rail', align: 'center', justify: 'center', noshrink: true, w: d('size/badge/height') },
    el('div', { name: 'Rail Bar', style: { width: d('stroke/thick'), height: d('size/icon/medium'), borderRadius: d('stroke/thin'), background: c(fits ? 'route/active' : 'status/warning'), flexShrink: 0 } }));
}
function driveText(o) {
  if (!o.drive) return null;
  const f = font('caption') + TNUM;
  return row({ name: 'Drive', align: 'center', gap: d('space/xs'), noshrink: true },
    icon('car.fill', { size: 12, color: 'text/secondary' }),
    text(o.drive, { name: 'Drive Time and Distance', font: f, color: 'text/secondary' }),
    o.estimated ? [text('·', { name: 'Dot', font: f, color: 'text/secondary' }), text('estimated', { name: 'Estimated', font: font('caption'), color: 'text/secondary' })] : null,
    o.shortBy ? [text('·', { name: 'Dot', font: f, color: 'text/secondary' }), icon('exclamationmark.triangle.fill', { size: 11, color: 'status/warning' }),
      text(o.shortBy, { name: 'Does Not Fit', font: font('caption'), color: 'status/warning' })] : null);
}
export function connectorRow(o = {}) {
  const nm = o.overnight ? 'Overnight' : o.shortBy ? "Doesn't Fit" : o.drive ? 'Fits' : 'Loading';
  return row({ name: `ConnectorRow / ${nm}`, align: 'center', gap: d('space/md'), style: { padding: `${d('space/xs')} 0` } },
    rail(!o.shortBy),
    o.overnight
      ? [row({ name: 'Overnight Label', align: 'center', gap: d('space/xs'), noshrink: true },
        icon('moon.stars', { size: 12, color: 'text/secondary' }),
        text('Overnight', { name: 'Overnight', font: font('captionStrong'), color: 'text/secondary' })),
      el('div', { name: 'Hairline', style: { flex: '1 1 0', minWidth: 0, height: d('stroke/hairline'), background: c('separator/default') } }),
      driveText(o)]
      : [driveText(o), spacer()]);
}

// ---- StopRow -----------------------------------------------------------------------------------------------
// o: {number, name, locality, badge:{window,score|reason,confidence}, schedule, session, walkIn, setUp, issues:[], selected}
function sessionMenu(label) {
  return row({ name: 'Session Menu', align: 'center', gap: d('space/sm'), noshrink: true,
    style: { height: 22, padding: `0 ${d('space/sm')} 0 ${d('space/md')}`, borderRadius: '999px', background: canvas('control/button'), border: `1px solid ${canvas('control/button-stroke')}`, boxShadow: canvas('shadow/button') } },
  text(label, { name: 'Session', font: font('caption') + TNUM, color: 'text/secondary' }),
  icon('chevron.up.chevron.down', { size: 9, color: 'text/secondary', weight: 'semibold' }));
}
const shrinkEllipsis = 'flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis';
export function stopRow(o) {
  const f = font('caption') + TNUM;
  const inner = row({ name: `StopRow / ${o.name}`.slice(0, 50), align: 'flex-start', gap: d('space/md'), style: { padding: `${d('space/sm')} 0`, borderRadius: d('radius/control') } },
    stopNumberBadge(o.number),
    col({ name: 'Stop Content', grow: true, gap: d('space/xs') },
      row({ name: 'Title Line', align: 'flex-start', gap: d('space/sm') },
        col({ name: 'Name and Locality', grow: true },
          text(o.name, { name: 'Spot Name', font: font('headline'), color: 'text/primary', wrap: true }),
          o.locality ? text(o.locality, { name: 'Locality', font: font('caption'), color: 'text/secondary', style: 'overflow:hidden;text-overflow:ellipsis' }) : null),
        o.badge ? lightBadge({ style: 'regular', ...o.badge }) : null),
      o.schedule ? text(o.schedule, { name: 'Schedule', font: font('bodyEmphasis') + TNUM, color: 'text/primary', wrap: true }) : null,
      row({ name: 'Session Line', align: 'center', gap: d('space/sm') },
        sessionMenu(o.session),
        text(o.walkIn, { name: 'Walk-in', font: f, color: 'text/secondary', style: shrinkEllipsis }),
        text('·', { name: 'Dot', font: f, color: 'text/secondary', noshrink: true }),
        text(o.setUp ?? '20 min set-up', { name: 'Set-up', font: f, color: 'text/secondary', wrap: true, style: 'flex:0 1 auto;min-width:0' })),
      (o.issues || []).map((t) => warningLine(t)),
      text('Add a note', { name: 'Note Placeholder', font: font('callout'), color: 'text/tertiary' })));
  return o.selected ? el('div', { name: 'Selected Row', style: { display: 'flex', flexDirection: 'column', background: canvas('selection/tint'), borderRadius: d('radius/control'), padding: `0 ${d('space/sm')}` } }, inner) : inner;
}

// ---- DayHeader / SuggestionBanner / Add Stop ---------------------------------------------------------------
export function dayHeader({ title, frame, totals, dropTarget = false }) {
  const f = font('caption') + TNUM;
  return col({ name: `DayHeader / ${title.split(' · ')[0]}`.slice(0, 50), style: { padding: `${d('space/xs')} 0`, position: 'relative' } },
    dropTarget ? dropIndicator() : null,
    row({ name: 'Header Row', align: 'baseline', gap: d('space/md') },
      col({ name: 'Day and Frame', gap: d('space/xxs'), noshrink: true },
        text(title, { name: 'Day Title', font: font('headline'), color: 'text/primary' }),
        frame ? row({ name: 'Light Frame', align: 'center', gap: d('space/xs') },
          icon('sun.horizon', { size: 12, color: 'text/secondary' }),
          text(frame, { name: 'Sunrise and Sunset', font: f, color: 'text/secondary' })) : null),
      spacer(),
      text(totals, { name: 'Totals', font: f, color: 'text/secondary' })));
}
export function dropIndicator() {
  return el('div', { name: 'Drop Indicator', style: abs({ top: 0, left: 0, right: 0, height: d('stroke/thick'), borderRadius: '999px', background: c('accent/primary') }) });
}
export function suggestionBanner({ conflicts = 2 } = {}) {
  return col({ name: 'SuggestionBanner Slot', style: { padding: `${d('space/xs')} 0` } },
    row({ name: 'SuggestionBanner', align: 'center', gap: d('space/sm'), pad: d('space/sm'), bg: 'background/control', radius: d('radius/control'),
      style: { border: `${d('stroke/hairline')} solid ${c('separator/default')}` } },
    icon('arrow.up.arrow.down', { size: 14, color: 'text/secondary' }),
    col({ name: 'Message', noshrink: true },
      text(`Reorder by light: fixes ${conflicts} conflict${conflicts === 1 ? '' : 's'}`, { name: 'Title', font: font('subheadline'), color: 'text/primary' }),
      text('Puts the stops in the order their light arrives.', { name: 'Detail', font: font('caption'), color: 'text/secondary' })),
    spacer(),
    button('Dismiss', { kind: 'borderless', size: 'small' }),
    button('Apply', { kind: 'bordered', size: 'small' })));
}
export function addStopRow({ dropTarget = false } = {}) {
  return row({ name: 'Add Stop Row', align: 'center', gap: d('space/sm'), style: { padding: `${d('space/sm')} 0`, position: 'relative' } },
    dropTarget ? dropIndicator() : null,
    icon('plus', { size: 14, color: 'accent/primary' }),
    text('Add Stop', { name: 'Add Stop', font: font('body'), color: 'accent/primary' }));
}

// ---- TripPlanList ------------------------------------------------------------------------------------------
// o: {caption, days:[{title, frame, totals, banner:{conflicts}, items:[{connector?, stop}], dropTarget}], attribution:bool, sample, width, grow}
export function tripPlanList(o) {
  // o.cut = {day, items, connector}: the list is clipped by its scroll view; rows are cut on a row boundary so nothing is half drawn.
  // Days after cut.day are left out; in cut.day only the first `items` stops show, then (connector) the next stop's connector alone.
  const cut = o.cut;
  const shown = cut ? o.days.slice(0, cut.day + 1) : o.days;
  const days = shown.map((day, di) => {
    const isCut = cut && di === cut.day && cut.items !== undefined;
    const items = isCut ? day.items.slice(0, cut.items) : day.items;
    const stub = isCut && cut.connector ? day.items[cut.items]?.connector : null;
    return col({ name: `Day Section / ${day.title.split(' · ')[0]}`, style: { flexShrink: 0 } },
      dayHeader(day),
      day.banner ? suggestionBanner(day.banner) : null,
      items.map((it) => [it.connector ? connectorRow(it.connector) : null, stopRow(it.stop)]),
      stub ? connectorRow(stub) : null,
      isCut ? null : (day.noAddStop ? null : addStopRow()));
  });
  return col({ name: 'TripPlanList', grow: true, w: o.width, gap: d('space/xl'), style: { background: c('background/content'), padding: `${d('space/sm')} ${d('space/lg')} ${d('space/lg')}`, overflow: 'hidden', minHeight: 0 } },
    o.caption ? text(o.caption, { name: 'No Forecast Caption', font: font('caption'), color: 'text/secondary', wrap: true, style: { padding: `${d('space/xs')} 0` } }) : null,
    days,
    o.attribution && !cut ? row({ name: 'Attribution Row', style: { padding: `${d('space/xs')} 0` } }, weatherAttribution({ sample: !!o.sample })) : null);
}

// ---- TripHeader --------------------------------------------------------------------------------------------
export function tripHeader({ name, dates, counts, driving, width }) {
  const f = font('subheadline');
  const dot = () => text('·', { name: 'Dot', font: f, color: 'text/secondary' });
  return col({ name: 'TripHeader', gap: d('space/xs'), w: width, style: { padding: d('space/lg'), background: c('background/window'), flexShrink: 0 } },
    text(name, { name: 'Trip Name', font: font('title/spot'), color: 'text/primary' }),
    row({ name: 'Dates and Totals', align: 'center', gap: d('space/sm') },
      row({ name: 'Date Button', align: 'center', gap: d('space/xs'), noshrink: true },
        icon('calendar', { size: 14, color: 'text/secondary' }), text(dates, { name: 'Date Range', font: f, color: 'text/secondary' })),
      dot(), text(counts, { name: 'Days and Stops', font: f, color: 'text/secondary' }),
      driving ? [dot(), text(driving, { name: 'Driving Total', font: f + TNUM, color: 'text/secondary', style: 'flex:0 1 auto;min-width:0;overflow:hidden;text-overflow:ellipsis' })] : null));
}

// ---- TripRouteMap ------------------------------------------------------------------------------------------
// o: {width, height, pins:[{n, name, x, y (0..1 of the pane), day}], legs:[{from:n, to:n, day}], activeDay, selected (n), days:[1,2,3,4], grow}
function leg(a, b, W, H) {
  const [x1, y1, x2, y2] = [a.x * W, a.y * H, b.x * W, b.y * H];
  const mx = (x1 + x2) / 2, my = (y1 + y2) / 2, dx = x2 - x1, dy = y2 - y1;
  const k = 0.1, cx = mx - dy * k, cy = my + dx * k;
  return `M${x1.toFixed(1)} ${y1.toFixed(1)} Q${cx.toFixed(1)} ${cy.toFixed(1)} ${x2.toFixed(1)} ${y2.toFixed(1)}`;
}
export function dayPickerPill(days, activeIndex) {
  return row({ name: 'Day Picker', align: 'center', pad: d('space/xs'), noshrink: true,
    style: { background: canvas('material/regular'), borderRadius: d('radius/control'), border: `1px solid ${canvas('material/stroke')}`, boxShadow: canvas('shadow/material') } },
  segmented(days.map((n) => `Day ${n}`), activeIndex));
}
export function tripRouteMap(o) {
  const { width = 520, height = 768, pins, legs = [], activeDay = 0, selected, days = [] } = o;
  const by = Object.fromEntries(pins.map((p) => [p.n, p]));
  const casing = [], active = [], inactive = [];
  for (const l of legs) {
    const dpath = leg(by[l.from], by[l.to], width, height);
    if (l.day === activeDay) {
      casing.push(`<path d="${dpath}" style="stroke:${c('background/window')}" stroke-width="${dv('stroke/routeCasing')}"/>`);
      active.push(`<path d="${dpath}" style="stroke:${c('route/active')}" stroke-width="${dv('stroke/route')}"/>`);
    } else inactive.push(`<path d="${dpath}" style="stroke:${c('route/inactive')}" stroke-width="${dv('stroke/routeInactive')}"/>`);
  }
  const routes = svgEl('Routes', { width, height, style: abs({ top: 0, left: 0 }) },
    raw(`<g fill="none" stroke-linecap="round" stroke-linejoin="round">${inactive.join('')}${casing.join('')}${active.join('')}</g>`));
  const pinEls = pins.map((p) => {
    const sel = p.n === selected, inDay = p.day === activeDay;
    const sz = sel ? dv('size/mapPinSelected') : dv('size/mapPin');
    return row({ name: `Pin / ${p.n} · ${p.name}`.slice(0, 50), align: 'center', justify: 'center', w: sz, h: sz,
      style: abs({ left: Math.round(p.x * width - sz / 2), top: Math.round(p.y * height - sz / 2), borderRadius: '999px',
        background: c(inDay ? 'accent/emphasis' : 'map/pinInactive'), border: `${sel ? d('stroke/thick') : d('stroke/thin')} solid ${c('background/window')}` }) },
    text(String(p.n), { name: 'Number', font: font('captionStrong') + TNUM, color: inDay ? 'accent/onAccent' : 'background/window' }));
  });
  const zoom = col({ name: 'Zoom Stepper', align: 'center', noshrink: true,
    style: abs({ top: dv('space/md'), right: dv('space/md'), width: 28, background: canvas('material/regular'), borderRadius: d('radius/control'), border: `1px solid ${canvas('material/stroke')}`, boxShadow: canvas('shadow/material'), padding: '2px 0' }) },
  row({ name: 'Zoom In', align: 'center', justify: 'center', h: 26 }, icon('plus', { size: 12, color: 'text/primary', weight: 'semibold' })),
  divider({ name: 'Stepper Divider' }),
  row({ name: 'Zoom Out', align: 'center', justify: 'center', h: 26 }, icon('minus', { size: 12, color: 'text/primary', weight: 'semibold' })));
  const picker = days.length > 1 ? el('div', { name: 'Day Picker Position', style: abs({ top: dv('space/md'), left: dv('space/md'), display: 'flex' }) }, dayPickerPill(days, activeDay)) : null;
  return mapPlaceholder({ width, height, grow: !!o.grow, label: 'Map placeholder: swap for a map image', children: [routes, pinEls, picker, zoom] });
}

// ---- AddStopPopover ----------------------------------------------------------------------------------------
export const ADD_STOP_ROWS = [
  { name: 'Horseshoe Bend', saved: true, detail: 'Page, AZ · 0 ft', win: { window: 'goldenEvening', score: 7, confidence: 'medium' }, added: true },
  { name: 'Upper Antelope Canyon', saved: true, detail: 'Page, AZ · 3 mi', win: { window: 'goldenMorning', score: 58, confidence: 'medium' } },
  { name: 'The Wave', detail: 'Coyote Buttes North, AZ · 38 mi', win: { window: 'goldenMorning', score: 61, confidence: 'medium' } },
  { name: 'Hopi Point', detail: 'Grand Canyon National Park, AZ · 124 mi', win: { window: 'goldenEvening', score: 66, confidence: 'low' } },
  { name: 'Monument Valley', saved: true, detail: 'Navajo Nation, AZ/UT · 133 mi', win: { window: 'goldenMorning', score: 74, confidence: 'medium' } },
  { name: 'Factory Butte', detail: 'Hanksville, UT · 231 mi', win: { window: 'goldenEvening', score: 52, confidence: 'low' } },
  { name: 'Delicate Arch', detail: 'Arches National Park, UT · 261 mi', win: { window: 'goldenEvening', score: 73, confidence: 'medium' } },
];
function addStopRowItem(r) {
  return row({ name: `AddStopRow / ${r.name}`.slice(0, 50), align: 'center', gap: d('space/sm'), style: { padding: `${d('space/sm')} ${d('space/md')}`, flexShrink: 0 } },
    col({ name: 'Name and Detail', grow: true },
      row({ name: 'Name Line', align: 'center', gap: d('space/xs') },
        text(r.name, { name: 'Spot Name', font: font('body'), color: 'text/primary' }),
        r.saved ? icon('bookmark.fill', { size: 11, color: 'text/secondary' }) : null),
      text(r.detail, { name: 'Detail', font: font('caption'), color: 'text/secondary' })),
    lightBadge({ style: 'compact', ...r.win }),
    row({ name: 'Add Slot', align: 'center', justify: 'center', noshrink: true, w: 20 },
      icon(r.added ? 'checkmark.circle.fill' : 'plus.circle', { size: 16, color: r.added ? 'text/secondary' : 'accent/primary' })));
}
export function addStopBody({ anchor = 'Horseshoe Bend', query = '', rows = ADD_STOP_ROWS } = {}) {
  const field = row({ name: 'Search Field', align: 'center', gap: d('space/xs'), noshrink: true,
    style: { height: d('size/control/height'), padding: `0 ${d('space/sm')}`, borderRadius: d('radius/control'), background: c('background/control'), border: `${d('stroke/hairline')} solid ${c('separator/default')}` } },
  icon('magnifyingglass', { size: 13, color: 'text/secondary' }),
  text(query || 'Search spots', { name: query ? 'Query' : 'Placeholder', font: font('body'), color: query ? 'text/primary' : 'text/tertiary', grow: true }),
  query ? icon('xmark.circle.fill', { size: 13, color: 'text/secondary' }) : null);
  return col({ name: 'AddStopPopover Content', grow: true, style: { minHeight: 0 } },
    col({ name: 'Header', gap: d('space/xs'), pad: d('space/md'), noshrink: true },
      field, text(`Nearest to ${anchor} first`, { name: 'Order Caption', font: font('caption'), color: 'text/secondary' })),
    divider(),
    col({ name: 'Candidates', grow: true, style: { overflow: 'hidden', minHeight: 0 } }, rows.map(addStopRowItem)));
}

export const artboards = []; // helper module: artboards are in components.mjs and the screens

// ---- Fixtures (Canyon Country seed and the conflict fixture) -----------------------------------------------
const WIN = { sunrise: 'goldenMorning', sunset: 'goldenEvening', blue: 'blueEvening' };
// s: stop description. forecast=false -> hollow ring and "Weather off" in the session menu.
function mk(s, forecast) {
  const label = s.kind === 'blue' ? 'Evening blue hour' : s.kind === 'sunrise' ? 'Sunrise' : 'Sunset';
  const base = `${label} · ${s.range}`;
  return {
    number: s.n, name: s.name, locality: s.loc, schedule: s.sched, walkIn: s.walk, issues: s.issues,
    session: forecast ? `${base} · ${s.score}` : `${base} · Weather off`,
    badge: forecast ? { window: WIN[s.kind], score: s.score, confidence: s.conf || 'high' } : { window: WIN[s.kind], reason: 'weatherServiceNotEnabled' },
  };
}
export const item = (s, forecast, connector) => ({ connector, stop: mk(s, forecast) });
export const OVERNIGHT = (drive) => ({ overnight: true, drive });
export const FITS = (drive) => ({ drive });
export const SHORT = (drive, m) => ({ drive, shortBy: `Drive doesn't fit: ${m} short` });

export const CANYON_STOPS = {
  hb: { n: 1, name: 'Horseshoe Bend', loc: 'Page, AZ', kind: 'sunset', range: '17:25–18:00', score: 7, conf: 'medium', sched: 'Set up by 17:05', walk: '25 min walk-in' },
  mv: { n: 2, name: 'Monument Valley', loc: 'Navajo Nation, AZ/UT', kind: 'sunrise', range: '07:21–07:56', score: 74, sched: 'Leave 03:42 · set up by 07:01', walk: 'walk-in unknown' },
  dh: { n: 3, name: 'Dead Horse Point', loc: 'Dead Horse Point State Park, UT', kind: 'sunset', range: '18:15–18:50', score: 5, conf: 'medium', sched: 'Leave 14:45 · park 17:53 · set up by 17:55', walk: '2 min walk-in' },
  // Days 3 and 4 are not in the supplied snapshots (the list is cut off at 820 pt): times and scores below are illustrative.
  ma: { n: 4, name: 'Mesa Arch', loc: 'Canyonlands National Park, UT', kind: 'sunrise', range: '07:22–07:57', score: 64, sched: 'Leave 06:36 · park 06:52 · set up by 07:02', walk: '10 min walk-in' },
  da: { n: 5, name: 'Delicate Arch', loc: 'Arches National Park, UT', kind: 'sunset', range: '18:15–18:49', score: 81, sched: 'Leave 16:08 · park 17:05 · set up by 17:55', walk: '50 min walk-in' },
  gv: { n: 6, name: 'Goblin Valley', loc: 'Goblin Valley State Park, UT', kind: 'sunset', range: '18:13–18:47', score: 58, conf: 'medium', sched: 'Leave 15:54 · set up by 17:53', walk: 'walk-in unknown' },
};
const S = CANYON_STOPS;

export function canyonCountry({ forecast = true } = {}) {
  const f = forecast;
  return {
    name: 'Canyon Country', dates: 'Wed 7 – Sat, Oct 10', counts: '4 days · 6 stops', driving: '376 mi · 8 hr, 39 min driving',
    caption: f ? null : "Weather isn't enabled for this build of Iter, so only sun and moon times are shown.",
    attribution: f, sample: f, dayTabs: [1, 2, 3, 4], activeDay: 0,
    cutAt: f ? { 1280: { day: 2, items: 0, connector: true }, 960: { day: 1, items: 1, connector: true } } : { 1280: { day: 1 }, 960: { day: 1, items: 1, connector: true } },
    days: [
      { title: 'Day 1 · Wed, Oct 7, 2026', frame: 'Sunrise 06:26 · Sunset 18:00', totals: '1 stop', items: [item(S.hb, f)] },
      { title: 'Day 2 · Thu, Oct 8, 2026', frame: 'Sunrise 07:21 · Sunset 18:53', totals: '2 stops · 5 hr, 27 min driving',
        items: [item(S.mv, f, OVERNIGHT('2 hr, 19 min · 101 mi')), item(S.dh, f, FITS('3 hr, 8 min · 136 mi'))] },
      { title: 'Day 3 · Fri, Oct 9, 2026', frame: 'Sunrise 07:22 · Sunset 18:49', totals: '2 stops · 1 hr, 13 min driving',
        items: [item(S.ma, f, OVERNIGHT('16 min · 12 mi')), item(S.da, f, FITS('57 min · 41 mi'))] },
      { title: 'Day 4 · Sat, Oct 10, 2026', frame: 'Sunrise 07:23 · Sunset 18:47', totals: '1 stop · 1 hr, 59 min driving',
        items: [item(S.gv, f, OVERNIGHT('1 hr, 59 min · 86 mi'))] },
    ],
    // Pin positions from the snapshot stand-in (fraction of the map pane). Legs: into stop `to`, belonging to that stop's day.
    pins: [
      { n: 1, name: 'Horseshoe Bend', x: 0.143, y: 0.857, day: 0 }, { n: 2, name: 'Monument Valley', x: 0.639, y: 0.82, day: 1 },
      { n: 3, name: 'Dead Horse Point', x: 0.771, y: 0.286, day: 1 }, { n: 4, name: 'Mesa Arch', x: 0.726, y: 0.315, day: 2 },
      { n: 5, name: 'Delicate Arch', x: 0.857, y: 0.187, day: 2 }, { n: 6, name: 'Goblin Valley', x: 0.428, y: 0.249, day: 3 },
    ],
    legs: [{ from: 1, to: 2, day: 1 }, { from: 2, to: 3, day: 1 }, { from: 3, to: 4, day: 2 }, { from: 4, to: 5, day: 2 }, { from: 5, to: 6, day: 3 }],
  };
}

export function conflictTrip() {
  const f = true;
  const st = {
    da: { n: 1, name: 'Delicate Arch', loc: 'Arches National Park, UT', kind: 'sunset', range: '18:15–18:51', score: 73, sched: 'Set up by 17:55', walk: '50 min walk-in' },
    ma: { n: 2, name: 'Mesa Arch', loc: 'Canyonlands National Park, UT', kind: 'sunrise', range: '07:20–07:56', score: 68, sched: 'Leave 05:54 · park 06:50 · set up by 07:00', walk: '10 min walk-in',
      issues: ["Out of order: this Sunrise is earlier than the previous stop's Sunset"] },
    mv: { n: 3, name: 'Monument Valley', loc: 'Navajo Nation, AZ/UT', kind: 'sunset', range: '18:18–18:53', score: 74, sched: 'Leave 15:02 · set up by 17:58', walk: 'walk-in unknown' },
    hb: { n: 4, name: 'Horseshoe Bend', loc: 'Page, AZ', kind: 'blue', range: '17:58–18:24', score: 76, sched: 'Leave 15:54 · park 17:13 · set up by 17:38', walk: '25 min walk-in' },
  };
  return {
    name: 'Arches and Monument Valley', dates: 'Wed 7 – Thu, Oct 8', counts: '2 days · 4 stops', driving: '270 mi · 6 hr, 12 min driving',
    attribution: true, sample: true, dayTabs: [1, 2], activeDay: 0,
    cutAt: { 1280: { day: 1, items: 1, connector: true }, 960: { day: 1, items: 0, connector: true } },
    days: [
      { title: 'Day 1 · Wed, Oct 7, 2026', frame: 'Sunrise 07:19 · Sunset 18:51', totals: '2 stops · 57 min driving', banner: { conflicts: 2 },
        items: [item(st.da, f), item(st.ma, f, SHORT('57 min · 41 mi', '12 hr, 57 min'))] },
      { title: 'Day 2 · Thu, Oct 8, 2026', frame: 'Sunrise 07:21 · Sunset 18:53', totals: '2 stops · 5 hr, 15 min driving',
        items: [item(st.mv, f, OVERNIGHT('2 hr, 56 min · 128 mi')), item(st.hb, f, SHORT('2 hr, 19 min · 101 mi', '2 hr, 58 min'))] },
    ],
    pins: [
      { n: 1, name: 'Delicate Arch', x: 0.857, y: 0.187, day: 0 }, { n: 2, name: 'Mesa Arch', x: 0.726, y: 0.315, day: 0 },
      { n: 3, name: 'Monument Valley', x: 0.639, y: 0.82, day: 1 }, { n: 4, name: 'Horseshoe Bend', x: 0.143, y: 0.857, day: 1 },
    ],
    legs: [{ from: 1, to: 2, day: 0 }, { from: 2, to: 3, day: 1 }, { from: 3, to: 4, day: 1 }],
  };
}
