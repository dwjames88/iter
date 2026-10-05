// Screens: All Trips (empty, list, all sessions passed, import error), New Trip sheet (template, empty), Change Dates sheet.
// Source of truth: App/Sources/Trips/TripsHomeView.swift, NewTripSheet.swift, ChangeDatesSheet.swift, TripFlows.swift.
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, dv, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { button, popUpButton, datePicker, stepper } from '../../../tools/lib/controls.mjs';
import { macWindow, sidebar, toolbarButton, toolbarGroup, sheet, alert } from '../../../tools/lib/chrome.mjs';
import { warningLine } from '../../../tools/lib/lightindex.mjs';
import { op } from '../../../tools/lib/tokens.mjs';
import { tripCard, templateRow, TEMPLATES, groupedForm } from '../../components/trips-home/trips-home.mjs';

const NEXT_CANYON = { kind: 'next', symbol: 'sunset', text: 'Next: Horseshoe Bend · Sunset from 17:25, Wed' };
const TRIPS = [
  { name: 'Weekend on the coast', dates: 'Thu 3 – Sat, Dec 5', counts: '3 days · 0 stops', footer: { kind: 'none' } },
  { name: 'Yosemite', dates: 'Sat 14 – Sun, Nov 15', counts: '2 days · 3 stops', footer: { kind: 'next', symbol: 'sunset', text: 'Next: Tunnel View · Sunset from 16:09, Sat' } },
  { name: 'Canyon Country', dates: 'Wed 7 – Sat, Oct 10', counts: '4 days · 6 stops', footer: NEXT_CANYON },
];
const PASSED = [
  { name: 'Yosemite', dates: 'Sat 3 – Sun, Oct 4', counts: '2 days · 3 stops', footer: { kind: 'passed' } },
  { name: 'Canyon Country', dates: 'Wed 7 – Sat, Oct 10', counts: '4 days · 6 stops', footer: NEXT_CANYON },
];

// Adaptive grid, as LazyVGrid: columns 300..360, gap space/lg, margin space/xl.
function tripGrid(trips, windowWidth, sidebarWidth = 240) {
  const margin = dv('space/xl'), gap = dv('space/lg'), min = dv('layout/listMin'), ideal = dv('layout/listIdeal');
  const avail = windowWidth - 2 - sidebarWidth - 2 * margin;
  const cols = Math.max(1, Math.floor((avail + gap) / (min + gap)));
  const w = Math.min(ideal, (avail - (cols - 1) * gap) / cols);
  return col({ name: 'All Trips', grow: true, pad: d('space/xl'), style: { background: c('background/window'), minHeight: 0 } },
    row({ name: 'Trip Grid', gap: d('space/lg'), align: 'flex-start', wrap: true }, trips.map((t) => tripCard({ ...t, width: w }))));
}

function emptyTrips() {
  return col({ name: 'All Trips Empty', grow: true, align: 'center', style: { background: c('background/window'), minHeight: 0, padding: `${d('space/xxl')} ${d('space/xxl')}` } },
    col({ name: 'Empty State', align: 'center', gap: d('space/xl'), w: '100%' },
      col({ name: 'Headline Block', align: 'center', gap: d('space/sm') },
        text('Plan trips around the light', { name: 'Headline', font: font('title/spot'), color: 'text/primary', align: 'center' }),
        text('Pick your spots and days. Iter works out when to leave so you are set up before the light arrives.', { name: 'Explanation', font: font('callout'), color: 'text/secondary', align: 'center', wrap: true })),
      button('New Trip', { kind: 'prominent', size: 'large', width: 128 }),
      col({ name: 'Templates', gap: d('space/sm'), w: '100%', style: { maxWidth: 520 } },
        text('Or start from a template', { name: 'Templates Heading', font: font('captionStrong'), color: 'text/secondary' }),
        TEMPLATES.map((t) => templateRow({ ...t })))));
}

function home({ width = 1280, height = 820, trips, tripNames, empty, overlays = [] }) {
  return macWindow({
    width, height, title: 'All Trips',
    sidebar: sidebar({ selected: 'trips', trips: tripNames, sampleBanner: true }),
    toolbarTrailing: empty ? [] : [toolbarButton('plus')],
    detail: empty ? emptyTrips() : tripGrid(trips, width),
    overlays,
  });
}

// ---- sheets ----------------------------------------------------------------------------------------------------
const dim = (el_) => el_; // semantic marker: disabled controls use the disabled opacity
const daysRow = (n, disabled) => row({ name: 'Row / Days', align: 'center', justify: 'space-between', style: { minHeight: 36, padding: `${d('space/xs')} ${d('space/md')}`, opacity: disabled ? op('disabled') : undefined } },
  row({ name: 'Days Label And Value', align: 'center', gap: d('space/sm') },
    text('Days', { name: 'Label', font: font('body'), color: 'text/primary' }),
    text(String(n), { name: 'Value', font: font('body'), color: 'text/primary' })),
  stepper());
const caption = (t, extra) => text(t, { name: 'Caption', font: font('caption'), color: 'text/secondary', wrap: true, ...extra });

function newTripBody({ template }) {
  const rows = [
    { label: 'Name', control: text(template ? 'Canyon Country' : 'New Trip', { name: 'Name Placeholder', font: font('body'), color: 'text/tertiary', align: 'right' }) },
    { label: 'Starts', control: datePicker('10/7/2026') },
    { node: daysRow(template ? 4 : 3, !!template) },
    { label: 'Start from', control: popUpButton(template ? 'Canyon Country · 4 days, 6 stops' : 'Empty trip') },
  ];
  if (template) rows.push({ caption: 'The template sets the number of days. You can add, move and remove stops afterwards.' });
  return groupedForm({ rows, name: 'Form' });
}
function changeDatesBody({ moves }) {
  const rows = [
    { label: 'Starts', control: datePicker('10/7/2026') },
    { node: daysRow(moves ? 3 : 4, false) },
    { label: 'Ends', control: text(moves ? 'Fri, Oct 9' : 'Sat, Oct 10', { name: 'Value', font: font('body'), color: 'text/primary' }) },
  ];
  if (moves) rows.push({ node: row({ name: 'Warning Row', style: { padding: `${d('space/sm')} ${d('space/md')}` } },
    warningLine('1 stop will move to Day 3, the new last day. You can undo this.', { font: 'callout' })) });
  return groupedForm({ rows, name: 'Form' });
}
const sheetButtons = (primary) => [button('Cancel', { kind: 'bordered', size: 'regular' }), button(primary, { kind: 'prominent', size: 'regular' })];

const newTripSheet = (template) => sheet({ width: 680, title: 'New Trip', body: newTripBody({ template }), buttons: sheetButtons('Create'), top: 28 });
const changeDatesSheet = (moves) => sheet({ width: 680, title: 'Change Dates', body: changeDatesBody({ moves }), buttons: sheetButtons('Change Dates'), top: 28 });

// Change Dates sits over the trip builder (owned by the Trip builder artboards); the backdrop here is the window chrome only.
function tripBackdrop(overlays) {
  return macWindow({
    width: 1280, height: 820, title: undefined, hideTitle: true,
    sidebar: sidebar({ selected: 'Canyon Country', trips: ['Weekend on the coast', 'Yosemite', 'Canyon Country'], sampleBanner: true }),
    toolbarTrailing: [toolbarButton('square.and.arrow.up'), toolbarButton('ellipsis.circle')],
    detail: col({ name: 'Trip Builder (see Trip builder artboards)', grow: true, pad: d('space/lg'), gap: d('space/xs'), style: { background: c('background/window'), minHeight: 0 } },
      text('Canyon Country', { name: 'Trip Name', font: font('title/spot'), color: 'text/primary' }),
      text('Wed 7 – Sat, Oct 10 · 4 days · 6 stops', { name: 'Trip Summary', font: font('subheadline'), color: 'text/secondary' })),
    overlays,
  });
}

const tripNames = ['Weekend on the coast', 'Yosemite', 'Canyon Country'];
const snap = (id) => `snapshots/${id}-{theme}-1280x820.png`;
export const artboards = [
  { id: 'S-trips-empty', name: 'All Trips · Empty', section: 'screens', width: 1280, height: 820, snapshot: snap('trips-empty'),
    covers: ['All Trips/Empty'], render: () => home({ empty: true, tripNames: [] }) },
  { id: 'S-trips-list', name: 'All Trips · List', section: 'screens', width: 1280, height: 820, snapshot: snap('trips-list'),
    covers: ['All Trips/List'], notes: ['Three cards: no stops, two with a Next line. The snapshot draws no toolbar contents; the New Trip plus button is drawn from the source.'], render: () => home({ trips: TRIPS, tripNames }) },
  { id: 'S-trips-all-passed', name: 'All Trips · All sessions passed', section: 'screens', width: 1280, height: 820,
    covers: ['All Trips/Card, all sessions passed'], render: () => home({ trips: PASSED, tripNames: ['Yosemite', 'Canyon Country'] }) },
  { id: 'S-trips-import-error', name: 'All Trips · Import error', section: 'screens', width: 1280, height: 820,
    covers: ['All Trips/Import error'],
    notes: ['System alert drawn with the shared alert panel; the real alert is the system SwiftUI .alert (app icon, bold title, message, OK).'],
    render: () => home({ trips: TRIPS, tripNames, overlays: [alert({ title: "Couldn't Import Trip", message: "This file isn't an Iter trip, or it is damaged. Nothing was imported.", buttons: ['OK'], width: 280 })] }) },

  { id: 'S-new-trip-template', name: 'New Trip sheet · Template chosen', section: 'screens', width: 1280, height: 820, snapshot: snap('trip-new-sheet'),
    covers: ['New Trip sheet (and Change Dates sheet)/New Trip, template chosen'],
    notes: ['Sheet is 680 wide (listIdeal + inspectorIdeal) and sized to its content, as in the app. The snapshot draws a larger frame with empty space and a 12 pt panel; the source is followed (macOS 26 sheet radius).'],
    render: () => home({ trips: TRIPS, tripNames, overlays: [newTripSheet(true)] }) },
  { id: 'S-new-trip-empty', name: 'New Trip sheet · Empty trip', section: 'screens', width: 1280, height: 820,
    covers: ['New Trip sheet (and Change Dates sheet)/New Trip, empty'],
    render: () => home({ trips: TRIPS, tripNames, overlays: [newTripSheet(false)] }) },
  { id: 'S-change-dates', name: 'Change Dates · Stops would move', section: 'screens', width: 1280, height: 820,
    covers: ['New Trip sheet (and Change Dates sheet)/Change Dates, stops would move'],
    notes: ['Ends is formatted like the trip dates ("Fri, Oct 9", en_US), not "Fri 9 Oct" as SCREENS.md says. Drawn over the trip builder window chrome; see the Trip builder artboards for that screen.'],
    render: () => tripBackdrop([changeDatesSheet(true)]) },
];
