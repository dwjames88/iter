// Trips home components: TripCard, TemplateRow, TripContextMenu (App/Sources/Trips/TripsHomeView.swift, Shell/SidebarView.swift).
// Exported for the All Trips screens, the shell and the context-menu artboard. Also exports groupedForm, the grouped Form
// look shared by the New Trip / Change Dates sheets and the Settings panes.
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { divider } from '../../../tools/lib/controls.mjs';
import { menu, note, sheetPanel } from '../../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, section, cell, page } from '../../../tools/lib/specimens.mjs';

const cardSurface = () => ({ background: c('background/control'), borderRadius: d('radius/card'), border: `${d('stroke/hairline')} solid ${c('separator/default')}` });

// ---- TripCard ------------------------------------------------------------------------------------------------
// footer: {kind:'next', symbol:'sunset', text:'Next: ...'} | {kind:'none'} | {kind:'passed'}
const FOOTERS = {
  none: { symbol: 'plus.circle', color: 'accent/primary', text: 'No stops yet. Open the trip to add the first.', textColor: 'text/secondary' },
  passed: { symbol: 'checkmark.circle', color: 'text/secondary', text: 'All sessions have passed', textColor: 'text/secondary' },
};
export function tripCard({ name, dates, counts, footer, width }) {
  const f = footer.kind === 'next' ? { symbol: footer.symbol || 'sunset', color: 'text/secondary', text: footer.text, textColor: 'text/primary', lines: 2 } : FOOTERS[footer.kind];
  return col({ name: `TripCard / ${name}`.slice(0, 50), gap: d('space/sm'), pad: d('space/md'), w: width, noshrink: true, style: cardSurface() },
    text(name, { name: 'Trip Name', font: font('title/spot'), color: 'text/primary', wrap: true }),
    col({ name: 'Dates and Counts', gap: d('space/xxs') },
      text(dates, { name: 'Date Range', font: font('subheadline'), color: 'text/primary' }),
      text(counts, { name: 'Days and Stops', font: font('subheadline'), color: 'text/secondary' })),
    divider(),
    row({ name: 'Footer', align: 'center', gap: d('space/sm') },
      icon(f.symbol, { size: 16, color: f.color }),
      text(f.text, { name: 'Footer Text', font: font('subheadline'), color: f.textColor, wrap: true, grow: true })));
}

// ---- TemplateRow ---------------------------------------------------------------------------------------------
export function templateRow({ name, counts, spots, width }) {
  return row({ name: `TemplateRow / ${name}`, align: 'center', gap: d('space/md'), pad: d('space/md'), w: width, style: cardSurface() },
    col({ name: 'Template Text', gap: d('space/xxs'), grow: true, style: { minWidth: 0 } },
      text(name, { name: 'Template Name', font: font('headline'), color: 'text/primary' }),
      text(counts, { name: 'Days and Stops', font: font('subheadline'), color: 'text/secondary' }),
      text(spots, { name: 'Spot Names', font: font('caption'), color: 'text/secondary' })),
    icon('chevron.right', { size: 12, color: 'text/secondary', weight: 'semibold' }));
}
export const TEMPLATES = [
  { name: 'Canyon Country', counts: '4 days · 6 stops', spots: 'Horseshoe Bend, Monument Valley, Dead Horse Point…' },
  { name: 'Eastern Sierra', counts: '3 days · 6 stops', spots: 'Fossil Falls, Alabama Hills, Lake Sabrina…' },
  { name: 'Yosemite', counts: '2 days · 3 stops', spots: 'Tunnel View, Valley View, Glacier Point' },
];

// ---- TripContextMenu -----------------------------------------------------------------------------------------
export const tripContextItems = (highlight) => [
  { label: 'Open', highlight: highlight === 'Open' }, 'Duplicate', 'Share…', '-', { label: 'Delete Trip', destructive: true }];
export function tripContextMenu(opts = {}) {
  const { highlight, x, y, width = 200, name = 'TripContextMenu' } = opts;
  return menu(tripContextItems(highlight), { width, x, y, name });
}

// ---- grouped Form (system look) -------------------------------------------------------------------------------
// rows: {label, control, labelNode?} | {node} | {caption}. Returns one grouped section (header above, footer below).
export function groupedForm({ header, rows, footer, width, name }) {
  const body = col({ name: 'Group', bg: canvas('control/group'), radius: 12, clip: true }, rows.flatMap((r, i) => {
    const content = r.node ? r.node
      : r.caption ? text(r.caption, { name: 'Caption', font: font('caption'), color: 'text/secondary', wrap: true, style: { padding: `${d('space/sm')} ${d('space/md')}` } })
        : row({ name: `Row / ${r.label}`.slice(0, 50), align: 'center', justify: 'space-between', gap: d('space/lg'), style: { minHeight: 36, padding: `${d('space/xs')} ${d('space/md')}` } },
          r.labelNode || text(r.label, { name: 'Label', font: font('body'), color: 'text/primary' }), r.control || null);
    return [i ? el('div', { name: 'Row Divider Inset', style: { display: 'flex', flexDirection: 'column', padding: `0 ${d('space/md')}` } }, divider({ name: 'Row Divider' })) : null, content];
  }));
  return col({ name: name || (header ? `Form Section / ${header}` : 'Form Section').slice(0, 50), gap: d('space/sm'), w: width },
    header ? text(header, { name: 'Section Header', font: font('headline'), color: 'text/primary', style: { padding: `0 ${d('space/md')}` } }) : null,
    body,
    footer ? text(footer, { name: 'Section Footer', font: font('caption'), color: 'text/secondary', wrap: true, style: { padding: `0 ${d('space/md')}` } }) : null);
}

// ---- component artboards -------------------------------------------------------------------------------------
const cardBoard = () => page([
  artboardHeader({ title: 'TripCard', type: 'TripCard (private)', file: 'Trips/TripsHomeView.swift', job: 'One trip on All Trips, with its next session. The whole card is a button; right-click gives the TripContextMenu.' }),
  col({ name: 'Content', gap: 24, align: 'flex-start' },
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Anatomy', body: 'Padding space/md, gap space/sm, radius/card, fill background/control, hairline separator/default border. Name type/title/spot (serif) up to two lines.' }),
      note({ title: 'No hover style', body: 'The app draws no custom hover state, pressed state or focus ring beyond the system button.' }),
      note({ title: 'Width', body: 'The card fills its grid column: 300 to 360 pt (layout/listMin to listIdeal). Specimens are 360.' })),
    themeBlocks(() => [
      section('Footer states', col({ name: 'Cards', gap: d('space/lg') },
        cell('next session', tripCard({ name: 'Canyon Country', dates: 'Wed 7 – Sat, Oct 10', counts: '4 days · 6 stops', footer: { kind: 'next', symbol: 'sunset', text: 'Next: Horseshoe Bend · Sunset from 17:25, Wed' }, width: 360 }), { caption: 'Next session: window-kind icon (text/secondary) + two-line "Next: …"' }),
        cell('sunrise window', tripCard({ name: 'Eastern Sierra', dates: 'Fri 9 – Sun, Oct 11', counts: '3 days · 6 stops', footer: { kind: 'next', symbol: 'sunrise', text: 'Next: Convict Lake · Sunrise from 07:12, Sat' }, width: 360 }), { caption: 'The icon follows the window kind (sunrise, sunset, moon…)' }),
        cell('no stops', tripCard({ name: 'Weekend on the coast', dates: 'Thu 3 – Sat, Dec 5', counts: '3 days · 0 stops', footer: { kind: 'none' }, width: 360 }), { caption: 'No stops: accent plus.circle, secondary text' }),
        cell('all passed', tripCard({ name: 'Yosemite', dates: 'Sat 14 – Sun, Nov 15', counts: '2 days · 3 stops', footer: { kind: 'passed' }, width: 360 }), { caption: 'All sessions passed: checkmark.circle, secondary' }),
        cell('long name', tripCard({ name: 'Long weekend in the high desert and canyons', dates: 'Wed 7 – Sat, Oct 10', counts: '4 days · 6 stops', footer: { kind: 'next', symbol: 'sunset', text: 'Next: Horseshoe Bend · Sunset from 17:25, Wed' }, width: 360 }), { caption: 'The name wraps to two lines, then truncates' }))),
    ], { direction: 'row' })),
], { gap: 24 });

const templateBoard = () => page([
  artboardHeader({ title: 'TemplateRow', type: 'TemplateRow (private)', file: 'Trips/TripsHomeView.swift', job: 'Starts a new trip from a template. Used in the All Trips empty state, max width 520.' }),
  col({ name: 'Content', gap: 24, align: 'flex-start' },
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Spot names', body: 'The first three distinct spots, joined with commas, then an ellipsis when there are more. Built from the source (TripTemplates), so Eastern Sierra reads Fossil Falls, Alabama Hills, Lake Sabrina…; the snapshot shows an older seed (Mobius Arch).', width: 340 })),
    themeBlocks(() => [
      section('Rows (max width 520)', col({ name: 'Rows', gap: d('space/sm') }, TEMPLATES.map((t) => cell(t.name, templateRow({ ...t, width: 520 }))))),
    ], { direction: 'row' })),
], { gap: 24 });

const menuBoard = () => page([
  artboardHeader({ title: 'TripContextMenu', type: 'TripContextMenu', file: 'Shell/SidebarView.swift', job: 'Acts on a trip from a sidebar row or a TripCard: Open, Duplicate, Share…, divider, Delete Trip. Undoable.' }),
  col({ name: 'Content', gap: 24, align: 'flex-start' },
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Behaviour', body: 'Duplicate creates "<name> copy" and opens it. Share… is a ShareLink to a .iter file. Delete Trip is destructive; if the trip is selected, All Trips is selected first.', width: 340 })),
    themeBlocks(() => [
      section('Menu', cell('menu', tripContextMenu({ width: 200 }))),
      section('Menu, Open highlighted', cell('menu highlighted', tripContextMenu({ highlight: 'Open', width: 200 }))),
      section('On a TripCard (right-click)', el('div', { name: 'Card With Menu', style: { position: 'relative', display: 'flex', width: 420, height: 270, flexShrink: 0 } },
        tripCard({ name: 'Canyon Country', dates: 'Wed 7 – Sat, Oct 10', counts: '4 days · 6 stops', footer: { kind: 'next', symbol: 'sunset', text: 'Next: Horseshoe Bend · Sunset from 17:25, Wed' }, width: 360 }),
        tripContextMenu({ x: 210, y: 110, width: 200, name: 'TripContextMenu / On Card' }))),
    ], { direction: 'row' })),
], { gap: 24 });

export const artboards = [
  { id: 'C-trip-card', name: 'TripCard', section: 'components', width: 1368, height: 1176, themes: ['light'], covers: ['Component/TripCard'], render: cardBoard },
  { id: 'C-template-row', name: 'TemplateRow', section: 'components', width: 1304, height: 640, themes: ['light'], covers: ['Component/TemplateRow'], render: templateBoard },
  { id: 'C-trip-context-menu', name: 'TripContextMenu', section: 'components', width: 1016, height: 1008, themes: ['light'],
    covers: ['Component/TripContextMenu', 'Menus/Trip context menu'], render: menuBoard },
];
