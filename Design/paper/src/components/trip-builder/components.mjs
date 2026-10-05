// Trip builder component artboards (D2): one per component, light and dark blocks, built from parts.mjs.
import { col, row, text, el, raw } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { menu, popover, note } from '../../../tools/lib/chrome.mjs';
import { stepper } from '../../../tools/lib/controls.mjs';
import { artboardHeader, themeBlocks, section, cell, page } from '../../../tools/lib/specimens.mjs';
import { stopNumberBadge, connectorRow, stopRow, dayHeader, suggestionBanner, addStopRow, tripPlanList, tripHeader, tripRouteMap, dayPickerPill,
  addStopBody, canyonCountry, conflictTrip, CANYON_STOPS, item, OVERNIGHT, FITS } from './parts.mjs';

const F = 'Trips/TripBuilderView.swift';
const FL = 'Trips/TripPlanList.swift';
const FS = 'Trips/StopRow.swift';
const frame = (header, notes, body, { direction = 'row' } = {}) => page([
  artboardHeader(header),
  col({ name: 'Content', gap: 24, align: 'flex-start' },
    notes.length ? row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' }, notes) : null,
    themeBlocks(body, { direction })),
], { gap: 24 });
const listGround = (name, w, ...kids) => col({ name, w, style: { background: c('background/content'), padding: `${d('space/sm')} ${d('space/lg')}`, borderRadius: d('radius/control') } }, kids);

const canyon = canyonCountry();
const conflict = conflictTrip();

const badgeBoard = () => frame({ title: 'StopNumberBadge', type: 'StopNumberBadge', file: FS, job: "The stop's number, matching its map pin: a 22 pt circle on the system quaternary fill, number in captionStrong." },
  [note({ title: 'Quaternary fill', body: 'SwiftUI .quaternary is about 10 to 15% of the label colour; drawn as 12% of text/primary. Hidden from VoiceOver (the row label carries the number).' })],
  () => [section('Numbers', row({ name: 'Badges', gap: 24 }, [1, 2, 3, 6, 10].map((n) => cell(`badge ${n}`, stopNumberBadge(n)))))]);

const connectorBoard = () => frame({ title: 'ConnectorRow', type: 'ConnectorRowView', file: FS, job: 'The drive between two stops and whether it fits; across a day boundary, an explicit overnight break.' },
  [note({ title: 'Rail colour', body: 'Coral (route/active) when the drive fits; violet (status/warning) with a triangle and "Drive doesn\'t fit: N short" when it does not. Never red.' }),
    note({ title: 'Loading', body: 'The drive text is absent until MapKit answers; only the rail shows (toolbar spinner).' })],
  () => [
    section('Same day', col({ name: 'Rows', gap: d('space/md') },
      cell('fits', listGround('List 440', 440, connectorRow({ drive: '3 hr, 8 min · 136 mi' })), { caption: 'Fits' }),
      cell('estimated', listGround('List 440', 440, connectorRow({ drive: '3 hr, 8 min · 136 mi', estimated: true })), { caption: 'Estimated (tooltip "Drive time estimated")' }),
      cell('does not fit', listGround('List 440', 440, connectorRow({ drive: '57 min · 41 mi', shortBy: "Drive doesn't fit: 12 hr, 57 min short" })), { caption: 'Does not fit' }),
      cell('loading', listGround('List 440', 440, connectorRow({ drive: null })), { caption: 'Loading' }))),
    section('Overnight (first stop of a later day)', col({ name: 'Overnight Rows', gap: d('space/md') },
      cell('overnight', listGround('List 440', 440, connectorRow({ overnight: true, drive: '2 hr, 19 min · 101 mi' })), { caption: 'Fits' }),
      cell('overnight long', listGround('List 440', 440, connectorRow({ overnight: true, drive: '2 hr, 56 min · 128 mi', estimated: true })), { caption: 'Estimated' }))),
  ], { direction: 'row' });

const dayBoard = () => frame({ title: 'DayHeader', type: 'DayHeader', file: FL, job: 'Which day, its light frame and its load. A whole-header drop target.' },
  [note({ title: 'Not upper-cased', body: 'The List section header is .textCase(nil): drawn as typed. Totals use monospaced digits.' })],
  () => [section('States', col({ name: 'Rows', gap: d('space/md') },
    cell('with stops', listGround('List 440', 440, dayHeader(canyon.days[1])), { caption: 'Two stops, driving' }),
    cell('one stop', listGround('List 440', 440, dayHeader(canyon.days[0])), { caption: 'One stop, no driving total under a minute' }),
    cell('no stops', listGround('List 440', 440, dayHeader({ title: 'Day 3 · Fri, Oct 9, 2026', frame: 'Sunrise 07:22 · Sunset 18:49', totals: 'No stops yet' })), { caption: 'No stops yet' }),
    cell('drop target', listGround('List 440', 440, dayHeader({ ...canyon.days[1], dropTarget: true })), { caption: 'Drop target: 2 pt accent capsule at the top' })))]);

const bannerBoard = () => frame({ title: 'SuggestionBanner', type: 'SuggestionBanner', file: FL, job: 'Offer, never apply, a light-first order for one day. Apply reorders; Dismiss hides it.' },
  [note({ title: 'Plural', body: '"fixes 1 conflict" / "fixes 2 conflicts" (automatic grammar agreement).' })],
  () => [section('Banner', col({ name: 'Rows', gap: d('space/md') },
    cell('two', listGround('List 480', 480, suggestionBanner({ conflicts: 2 })), { caption: 'Two conflicts' }),
    cell('one', listGround('List 480', 480, suggestionBanner({ conflicts: 1 })), { caption: 'One conflict' })))]);

const stopRowBoard = () => {
  const s = (st, extra = {}) => ({ ...st.stop, ...extra });
  const cn = conflict.days[0].items[1].stop;
  return frame({ title: 'StopRow', type: 'StopRowView', file: FS, job: 'One stop: when to leave and be set up first, then the session, the light, and the note.' },
    [note({ title: 'Schedule leads', body: 'Headline (bodyEmphasis): "Leave · park · set up by"; no "park" when walk-in is unknown; "Set up by" for the first stop of a trip. The leave time is in the previous stop\'s time zone.' }),
      note({ title: 'Window missing', body: 'No badge (the row has no session window); a violet line "No Sunrise window on this day at this place"; the menu reads "Sunrise · no window this day".' })],
    () => [
      section('Scored · default', cell('default', listGround('List 560', 560, stopRow(canyon.days[1].items[0].stop)))),
      section('Scored · first stop of a trip (no drive)', cell('first', listGround('List 560', 560, stopRow(canyon.days[0].items[0].stop)))),
      section('Selected (system list selection)', cell('selected', listGround('List 560', 560, stopRow({ ...canyon.days[1].items[0].stop, selected: true })))),
      section('Out of order (violet line)', cell('out of order', listGround('List 560', 560, stopRow(cn)))),
      section('No forecast (ring, "Weather off")', cell('no forecast', listGround('List 560', 560, stopRow(canyonCountry({ forecast: false }).days[1].items[0].stop)))),
      section('Window missing', cell('missing', listGround('List 560', 560, stopRow({ ...canyon.days[1].items[0].stop, badge: null, issues: ['No Sunrise window on this day at this place'], session: 'Sunrise · no window this day' })))),
      section('Narrow (960 window, left column 418)', cell('narrow', listGround('List 386', 386, stopRow(canyon.days[0].items[0].stop)), { caption: '"25 min walk-in" truncates and "20 min set-up" wraps, as in the 960 snapshot.' })),
    ], { direction: 'column' });
};

const planBoard = () => frame({ title: 'TripPlanList', type: 'TripPlanList', file: FL, job: 'The plan as day sections of stops and connectors, with drag and drop; an inset list on the list ground.' },
  [note({ title: 'Non-selectable rows', body: 'Banners, connectors, Add Stop, the caption and the attribution are not selectable. Only stop rows select.' }),
    note({ title: 'Drop indicator', body: 'A 2 pt (stroke/thick) capsule in accent/primary at the top of the target row, day header or Add Stop row. Shown on the Day 2 header and its Add Stop row.' })],
  () => [
    row({ name: 'Variants', gap: 24, align: 'flex-start' },
      cell('scored', col({ name: 'Plan 520', w: 520, h: 760, style: { overflow: 'hidden', borderRadius: d('radius/control') } }, tripPlanList({ days: canyon.days.slice(0, 2).map((x, i) => ({ ...x, dropTarget: i === 1 })), attribution: true, sample: true })), { caption: 'Scored, with the Sample data attribution row' }),
      cell('no forecast', col({ name: 'Plan 520', w: 520, h: 760, style: { overflow: 'hidden', borderRadius: d('radius/control') } }, tripPlanList({ caption: canyonCountry({ forecast: false }).caption, days: canyonCountry({ forecast: false }).days.slice(0, 2) })), { caption: 'No forecast: global caption, no attribution' })),
    cell('add stop', listGround('List 520', 520, addStopRow(), addStopRow({ dropTarget: true })), { caption: 'Add Stop row, normal and drop target' }),
  ], { direction: 'column' });

const headerBoard = () => frame({ title: 'TripHeader', type: 'TripHeader', file: F, job: "The trip's name (edit in place), dates and totals." },
  [note({ title: 'Editing', body: 'The name is a plain text field ("Click to rename"); Return or leaving the field commits; an empty name reverts. The snapshot shows the name selected (focus artefact).' }),
    note({ title: 'Totals', body: 'Driving total hidden under one minute; "(estimated)" suffix when any drive is a straight-line estimate.' })],
  () => [
    cell('default', col({ name: 'Frame 520', w: 520, style: { background: c('background/window') } }, tripHeader({ name: canyon.name, dates: canyon.dates, counts: canyon.counts, driving: canyon.driving })), { caption: 'Default' }),
    cell('estimated', col({ name: 'Frame 520', w: 520 }, tripHeader({ name: canyon.name, dates: canyon.dates, counts: canyon.counts, driving: '376 mi · 8 hr, 39 min driving (estimated)' })), { caption: 'Estimated' }),
    cell('no driving', col({ name: 'Frame 520', w: 520 }, tripHeader({ name: 'Day Out', dates: 'Wed 7 Oct', counts: '1 days · 1 stops' })), { caption: 'No driving total' }),
  ], { direction: 'column' });

const mapBoard = () => {
  const mapOf = (trip, selected) => tripRouteMap({ width: 520, height: 420, pins: trip.pins, legs: trip.legs, activeDay: trip.activeDay, selected, days: trip.dayTabs });
  const day2 = { ...canyon, activeDay: 1 };
  return frame({ title: 'TripRouteMap', type: 'TripRouteMap', file: 'Trips/TripRouteMap.swift', job: 'The route sanity check: numbered pins, the active day in the route colour, other days quieter.' },
    [note({ title: 'Live map vs stand-in', body: 'Only the selected stop is 36 pt; other active-day pins are 28 pt in accent/emphasis; pins of other days are 28 pt map/pinInactive. The snapshot stand-in draws every active-day pin large.' }),
      note({ title: 'Deviation: pin token', body: 'TripRouteMap.swift fills the pins of the active day with accent/emphasis; the snapshot stand-in draws map/pin. The source is drawn.' }),
      note({ title: 'Placeholder', body: 'The map is a placeholder; Apple\'s cartography, compass and scale are not drawn (zoom stepper shown).' })],
    () => [
      row({ name: 'Maps', gap: 24, align: 'flex-start' },
        cell('day 1', mapOf(canyon), { caption: 'Day 1 active, nothing selected' }),
        cell('day 2 selected', mapOf(day2, 3), { caption: 'Day 2 active, stop 3 selected (36 pt, 2 pt border)' })),
      row({ name: 'Maps 2', gap: 24, align: 'flex-start' },
        cell('conflict', mapOf(conflict), { caption: 'Conflict fixture: Day 1 route in route/active over a casing' }),
        cell('picker', col({ name: 'Picker Specimens', gap: d('space/md') }, dayPickerPill([1, 2, 3, 4], 0), dayPickerPill([1, 2, 3, 4], 2), dayPickerPill([1, 2], 1)), { caption: 'Day picker: regularMaterial pill; a menu beyond five days; hidden with one day' })),
    ], { direction: 'column' });
};

const addStopBoard = () => frame({ title: 'AddStopPopover', type: 'AddStopPopover', file: 'Trips/AddStopPopover.swift', job: 'Add stops to a day, nearest first, each with its score for that day. The popover stays open so several stops can be added.' },
  [note({ title: 'Added', body: 'A tick (checkmark.circle.fill, text/secondary) replaces plus.circle; the row stays. A spot already on that day shows the tick.' }),
    note({ title: 'Empty search', body: 'The system search-empty view (ContentUnavailableView.search).' })],
  () => [row({ name: 'Popovers', gap: 24, align: 'flex-start' },
    cell('default', popover({ width: 480, height: 504, arrow: 'top', arrowOffset: 30, name: 'AddStopPopover', body: addStopBody({}) }), { caption: 'Day 1 · nearest to Horseshoe Bend' }),
    cell('search', popover({ width: 480, height: 504, arrow: null, name: 'AddStopPopover / Search', body: addStopBody({ query: 'arch', anchor: 'Horseshoe Bend', rows: [
      { name: 'Delicate Arch', detail: 'Arches National Park, UT · 261 mi', win: { window: 'goldenEvening', score: 73, confidence: 'medium' } },
      { name: 'Mesa Arch', saved: true, detail: 'Canyonlands National Park, UT · 241 mi', win: { window: 'goldenMorning', score: 64, confidence: 'medium' }, added: true }] }) }), { caption: 'Filtered by "arch"; Mesa Arch just added' }))],
  { direction: 'column' });

const menusBoard = () => frame({ title: 'Trip builder menus', type: 'Menus and popovers', file: `${F}, ${FS}`, job: 'The set-up time popover, the session menu, the trip actions menu and the stop context menu. System-drawn; not in any snapshot.' },
  [note({ title: 'Session menu', body: 'One item per window of that day: "Sunrise · 07:21–07:56 · 74" (the score), or "· Weather off" when there is no forecast. The current choice is ticked.' }),
    note({ title: 'Move to Day', body: 'Only on multi-day trips; the stop\'s own day is disabled.' })],
  () => [row({ name: 'Menus', gap: 32, align: 'flex-start' },
    cell('setup', popover({ width: 300, height: 56, arrow: 'top', arrowOffset: 40, name: 'Set-up time popover', body: row({ name: 'Stepper Row', align: 'center', justify: 'space-between', gap: d('space/md'), pad: d('space/md') },
      text('Set up 20 min before the window', { name: 'Label', font: font('body') + ';font-variant-numeric:tabular-nums', color: 'text/primary' }), stepper()) }), { caption: 'Set-up time popover: stepper 0 to 120 in steps of 5' }),
    cell('session', menu([{ label: 'Morning blue hour · 06:46–07:16 · 58', checked: false }, { label: 'Sunrise · 07:21–07:56 · 74', checked: true }, { label: 'Sunset · 18:18–18:53 · 69' }, { label: 'Evening blue hour · 18:53–19:19 · 71' }], { name: 'Session menu' }), { caption: 'Session menu' }),
    cell('actions', menu([{ label: 'Change Dates…', shortcut: '⇧⌘D' }, { label: 'Export…', shortcut: '⇧⌘E' }, 'Duplicate', '-', { label: 'Delete Trip', destructive: true }], { name: 'Trip actions menu', width: 240 }), { caption: 'Trip actions menu' }),
    cell('context', menu(['Open Spot Page', 'Open in Maps', '-', 'Move Up', 'Move Down', { label: 'Move to Day', submenu: true }, '-', { label: 'Remove from Trip', destructive: true }], { name: 'Stop context menu', width: 220 }), { caption: 'Stop context menu' })),
  ], { direction: 'column' });

const COMP = (id, name, w, h, cov, render, extra = {}) => ({ id, name, section: 'components', width: w, height: h, themes: ['light'], covers: cov, render, ...extra });
export const artboards = [
  COMP('C-stop-number-badge', 'StopNumberBadge', 880, 408, ['Component/StopNumberBadge'], badgeBoard),
  COMP('C-connector-row', 'ConnectorRow', 1200, 832, ['Component/ConnectorRow'], connectorBoard),
  COMP('C-day-header', 'DayHeader', 1200, 696, ['Component/DayHeader'], dayBoard),
  COMP('C-suggestion-banner', 'SuggestionBanner', 1200, 544, ['Component/SuggestionBanner'], bannerBoard),
  COMP('C-stop-row', 'StopRow', 1400, 3032, ['Component/StopRow'], stopRowBoard),
  COMP('C-trip-plan-list', 'TripPlanList', 1200, 2264, ['Component/TripPlanList'], planBoard),
  COMP('C-trip-header', 'TripHeader', 1200, 1136, ['Component/TripHeader'], headerBoard),
  COMP('C-trip-route-map', 'TripRouteMap', 1200, 2272, ['Component/TripRouteMap'], mapBoard, { notes: ['Deviation: active pin token is accent/emphasis in source'] }),
  COMP('C-add-stop-popover', 'AddStopPopover', 1200, 1496, ['Component/AddStopPopover', 'Menus/AddStopPopover'], addStopBoard),
  COMP('C-trip-builder-menus', 'Trip builder menus', 1264, 880, ['Menus/Set-up time popover', 'Menus/Session menu', 'Menus/Trip actions menu', 'Menus/Stop context menu'], menusBoard),
];
