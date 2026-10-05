// System surfaces and menus rows (SCREENS.md "Menus, popovers and dialogs"): alerts and dialogs, share sheet,
// file importer/exporter, and a reference of every screen's window title bar and toolbar. All of these are drawn by macOS;
// they are simplified stand-ins labelled as system UI so the owner can swap in real system captures.
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { button, popUpButton, textField, divider, spinner } from '../../../tools/lib/controls.mjs';
import { alertPanel, popover, note, trafficLights, toolbarButton, toolbarGroup, toolbarSearch } from '../../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, section, cell, page } from '../../../tools/lib/specimens.mjs';

const notes = (...n) => row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' }, n);

// ---- Alerts and dialogs --------------------------------------------------------------------------------------------
const alertsBoard = () => page([
  artboardHeader({ title: 'Alerts and dialogs', type: 'System alerts and confirmation dialogs', file: 'AppCommands, RootView, TripFlows, TripBuilderView, SavedView, SpotHeaderView',
    job: 'Every alert and confirmation dialog in the app. All are system chrome (NSAlert and SwiftUI .alert / .confirmationDialog); strings are the app\'s.' }),
  col({ name: 'Content', gap: 24, align: 'flex-start' },
    notes(
      note({ title: 'System UI', body: 'Drawn with the shared alert panel (app icon stand-in, bold title, grey message, full-width buttons). The real alerts are macOS system dialogs; confirmation dialogs attach to the window as sheets.', width: 340 }),
      note({ title: 'Delete spot: two wordings', body: 'Spot page: "Delete “name”?", "…You can undo this with Edit > Undo.", button Delete. Saved: same title, "…You can undo this.", button Delete Spot. Reproduced as built.', width: 340 }),
      note({ title: 'Reset All Data…', body: 'Debug menu only. NSAlert with the critical style: the first button (Delete Everything) is the destructive default.', width: 340 })),
    themeBlocks(() => col({ name: 'Alert Grid', gap: d('space/xl') },
      row({ name: 'Row 1', gap: d('space/xl'), align: 'flex-start' },
        cell('reset all data', alertPanel({ title: 'Delete all trips and spots?', message: "This can't be undone.", buttons: [{ label: 'Delete Everything', destructive: true }, { label: 'Cancel' }] }), { width: 280, caption: 'Debug > Reset All Data…' }),
        cell('import trip failed', alertPanel({ title: "Couldn't Import Trip", message: "This file isn't an Iter trip, or it is damaged. Nothing was imported.", buttons: ['OK'] }), { width: 280, caption: 'Import Trip… (⌘O). Other reasons: newer file format; "Iter couldn\'t read that file."' }),
        cell('couldnt open trip', alertPanel({ title: "Couldn't open this trip", message: "The file isn't a readable Iter trip.", buttons: ['OK'] }), { width: 280, caption: 'A .iter file opened from Finder. Other: "It was made by a newer version of Iter."' })),
      row({ name: 'Row 2', gap: d('space/xl'), align: 'flex-start' },
        cell('couldnt export trip', alertPanel({ title: "Couldn't Export Trip", message: "The trip couldn't be saved to that location.", buttons: ['OK'] }), { width: 280, caption: 'Trip actions > Export…' }),
        cell('delete spot page', alertPanel({ title: 'Delete “Roadside Pullout”?', message: 'It is also removed from 2 trip stops. You can undo this with Edit > Undo.', buttons: [{ label: 'Delete', destructive: true }, { label: 'Cancel' }] }), { width: 280, caption: 'Spot page, your own spot' }),
        cell('delete spot saved', alertPanel({ title: 'Delete “Roadside Pullout”?', message: 'It is also removed from 2 trip stops. You can undo this.', buttons: [{ label: 'Delete Spot', destructive: true }, { label: 'Cancel' }] }), { width: 280, caption: 'Saved list, your own spot' }))), { direction: 'column' }),
  ),
], { gap: 24 });

// ---- Share sheet ---------------------------------------------------------------------------------------------------
const tile = (name) => el('div', { name: `App Icon (swap) / ${name}`.slice(0, 50), style: { width: 22, height: 22, borderRadius: 6, background: canvas('control/segmented-track'), border: `1px solid ${canvas('control/button-stroke')}`, flexShrink: 0 } });
const shareRow = (label, sel) => row({ name: `Share Item / ${label}`.slice(0, 50), align: 'center', gap: d('space/sm'), bg: sel ? canvas('menu/highlight') : undefined, radius: 8, style: { height: 28, padding: '0 10px', flexShrink: 0 } },
  tile(label), text(label, { name: 'Label', font: font('body'), color: sel ? 'accent/onAccent' : 'text/primary' }));
function shareBody(preview, sub, items) {
  return col({ name: 'Share Content', pad: 6, gap: 2 },
    row({ name: 'Preview', align: 'center', gap: d('space/md'), style: { padding: '8px 10px' } },
      el('div', { name: 'File Icon (swap)', style: { width: 40, height: 40, borderRadius: 8, background: canvas('control/segmented-track'), border: `1px solid ${canvas('control/button-stroke')}`, flexShrink: 0 } }),
      col({ name: 'Preview Text' }, text(preview, { name: 'Name', font: font('headline'), color: 'text/primary' }), text(sub, { name: 'Detail', font: font('caption'), color: 'text/secondary' }))),
    el('div', { name: 'Divider Inset', style: { display: 'flex', flexDirection: 'column', padding: '4px 8px' } }, divider()),
    items.map((it, i) => shareRow(it, false)),
    el('div', { name: 'Divider Inset', style: { display: 'flex', flexDirection: 'column', padding: '4px 8px' } }, divider()),
    row({ name: 'Share Item / Edit Extensions', align: 'center', style: { height: 28, padding: '0 10px' } }, text('Edit Extensions…', { name: 'Label', font: font('body'), color: 'text/primary' })));
}
const shareBoard = () => page([
  artboardHeader({ title: 'Share sheet', type: 'ShareLink', file: 'Trips/TripBuilderView.swift (toolbar Share), Shell/SidebarView.swift (context menu), Spot/SpotHeaderView.swift', job: 'The system share popover. A trip is shared as an .iter file; a spot as an Apple Maps link.' }),
  col({ name: 'Content', gap: 24, align: 'flex-start' },
    notes(note({ title: 'System UI', body: 'The share popover is macOS-owned and its destinations depend on the Mac. Drawn as a simplified stand-in; the icon tiles are placeholders (named "App Icon (swap)").', width: 340 })),
    themeBlocks(() => row({ name: 'Share Popovers', gap: 40, align: 'flex-start', style: { paddingTop: 12 } },
      cell('trip share', popover({ width: 260, arrow: 'top', arrowOffset: 200, body: shareBody('Canyon Country.iter', 'Iter Trip · 4 KB', ['AirDrop', 'Messages', 'Mail', 'Notes', 'Reminders']) , height: 292 }), { caption: 'Trip: shares Canyon Country.iter (a ShareLink to a TripDocument)' }),
      cell('spot share', popover({ width: 260, arrow: 'top', arrowOffset: 200, body: shareBody('Horseshoe Bend', 'Apple Maps link', ['Copy Link', 'AirDrop', 'Messages', 'Mail', 'Notes']), height: 292 }), { caption: 'Spot: shares an Apple Maps link' })), { direction: 'row' })),
], { gap: 24 });

// ---- File importer and exporter ------------------------------------------------------------------------------------
const sideItem = (t, sel) => row({ name: `Panel Sidebar Row / ${t}`, align: 'center', bg: sel ? canvas('selection/tint') : undefined, radius: 8, style: { height: 26, padding: '0 10px', flexShrink: 0 } },
  text(t, { name: 'Label', font: font('body'), color: 'text/primary' }));
const fileRow = (name, date, sel, dim) => row({ name: `File Row / ${name}`, align: 'center', gap: d('space/md'), bg: sel ? c('accent/primary') : undefined, radius: 6, style: { height: 24, padding: '0 8px', flexShrink: 0 } },
  text(name, { name: 'File Name', font: font('body'), color: sel ? 'accent/onAccent' : dim ? 'text/quaternary' : 'text/primary', grow: true }),
  text(date, { name: 'Date Modified', font: font('body'), color: sel ? 'accent/onAccent' : dim ? 'text/quaternary' : 'text/secondary', w: 140, style: { flexShrink: 0 } }));
const panelShell = (title, body, buttons) => col({ name: `System Panel / ${title}`.slice(0, 50), w: 560, noshrink: true,
  style: { background: canvas('sheet/background'), borderRadius: 26, boxShadow: canvas('shadow/sheet'), overflow: 'hidden', border: `1px solid ${canvas('window/outline')}` } },
row({ name: 'Panel Title Bar', align: 'center', style: { height: 44, padding: '0 18px', flexShrink: 0 } }, trafficLights()),
body,
row({ name: 'Panel Buttons', justify: 'flex-end', gap: d('space/sm'), style: { padding: '12px 20px 20px' } }, buttons));
const openPanel = () => panelShell('Open', col({ name: 'Open Body', gap: d('space/md'), style: { padding: '0 20px' } },
  row({ name: 'Location Bar', align: 'center', gap: d('space/sm') }, popUpButton('Documents', { width: 200 }), text('Choose an Iter trip (.iter) or JSON file', { name: 'Prompt', font: font('callout'), color: 'text/secondary' })),
  row({ name: 'Browser', gap: d('space/md'), style: { height: 200 } },
    col({ name: 'Panel Sidebar', gap: 2, w: 140, noshrink: true }, text('Favorites', { name: 'Section', font: font('caption'), color: 'text/secondary', style: { padding: '2px 10px' } }), ['Recents', 'Desktop', 'Documents', 'Downloads'].map((t) => sideItem(t, t === 'Documents'))),
    col({ name: 'File List', grow: true, gap: 2, style: { minHeight: 0 } },
      row({ name: 'List Header', style: { padding: '0 8px 4px', gap: d('space/md') } }, text('Name', { name: 'Name Column', font: font('caption'), color: 'text/secondary', grow: true }), text('Date Modified', { name: 'Date Column', font: font('caption'), color: 'text/secondary', w: 140, style: { flexShrink: 0 } })),
      fileRow('Canyon Country.iter', 'Today, 09:41', true), fileRow('Eastern Sierra.iter', 'Yesterday', false), fileRow('Notes.txt', '3 Oct 2026', false, true)))),
[button('Cancel'), button('Open', { kind: 'prominent' })]);
const savePanel = () => panelShell('Save', col({ name: 'Save Body', gap: d('space/lg'), style: { padding: '0 20px' } },
  row({ name: 'Save As Row', align: 'center', gap: d('space/md') }, text('Save As:', { name: 'Label', font: font('body'), color: 'text/primary', w: 64, style: { flexShrink: 0 } }), textField({ value: 'Canyon Country.iter', width: 360 })),
  row({ name: 'Where Row', align: 'center', gap: d('space/md') }, text('Where:', { name: 'Label', font: font('body'), color: 'text/primary', w: 64, style: { flexShrink: 0 } }), popUpButton('Documents', { width: 200 })),
  text('The default name comes from the trip name.', { name: 'Hint', font: font('caption'), color: 'text/secondary', style: { paddingLeft: 76 } })),
[button('Cancel'), button('Save', { kind: 'prominent' })]);
const panelsBoard = () => page([
  artboardHeader({ title: 'File importer and exporter', type: 'fileImporter / fileExporter', file: 'Trips/TripFlows.swift (Import Trip…), Trips/TripBuilderView.swift (Export…)', job: 'System open and save panels. Import accepts .iter and .json; the export file name derives from the trip name.' }),
  col({ name: 'Content', gap: 24, align: 'flex-start' },
    notes(note({ title: 'System UI, simplified', body: 'The real panels are macOS-owned (sidebar, columns, search, tags). Drawn only to show where the app\'s name, types and default file name appear.', width: 340 })),
    themeBlocks(() => row({ name: 'Panels', gap: 32, align: 'flex-start' },
      cell('open panel', openPanel(), { caption: 'Import Trip… (⌘O)' }), cell('save panel', savePanel(), { caption: 'Export… (⇧⌘E)' })), { direction: 'column' })),
], { gap: 24 });

// ---- Window title bar and toolbars -------------------------------------------------------------------------------
const TB = 52;
const titleEl = (t) => text(t, { name: 'Window Title', font: font('title/section', { size: 15, weight: 'semibold', lineHeight: 20 }), color: 'text/primary' });
const strip = (label, { title, trailing = [], leading = [], note: n }) => col({ name: `Toolbar Reference / ${label}`.slice(0, 50), gap: d('space/xs') },
  text(label, { name: 'Screen Name', font: font('subheadline', { weight: 'semibold' }), color: 'text/primary' }),
  row({ name: 'Toolbar', align: 'center', gap: d('space/md'), w: 1000, style: { height: TB, padding: '0 16px 0 20px', borderRadius: 14, background: canvas('chrome/titlebar'), border: `1px solid ${canvas('window/outline')}`, flexShrink: 0 } },
    trafficLights(), toolbarButton('sidebar.left'), leading, title ? titleEl(title) : null, el('div', { name: 'Spacer', style: { flex: '1 1 0' } }), trailing),
  n ? text(n, { name: 'Note', font: font('caption'), color: 'text/secondary' }) : null);
const dateText = (t) => row({ name: 'Date Field', align: 'center', style: { height: 34, padding: '0 10px' } }, text(t, { name: 'Date', font: font('body'), color: 'text/primary' }));
const toolbarsBoard = () => page([
  artboardHeader({ title: 'Window title bar and toolbars', type: 'Window chrome', file: 'each screen\'s .toolbar / .navigationTitle', job: 'Reference of the title bar and toolbar of every screen: traffic lights, sidebar toggle, title, trailing items (macOS 26 glass). Settings is its own window; see the Settings artboards.' }),
  col({ name: 'Content', gap: 24, align: 'flex-start' },
    notes(note({ title: 'Why this exists', body: 'The snapshots draw toolbar items as blank rounded squares and omit the traffic lights. Items here come from the SwiftUI toolbars. The sidebar has its own toolbar: New Trip (plus), tooltip "New Trip (⌘N)".', width: 420 })),
    themeBlocks(() => col({ name: 'Toolbars', gap: d('space/xl') },
      strip('All Trips (list)', { title: 'All Trips', trailing: [toolbarButton('plus')], note: 'New Trip (⌘N). Hidden in the empty state, which has its own New Trip button.' }),
      strip('Trip builder', { trailing: [spinner(16), toolbarButton('square.and.arrow.up'), toolbarButton('ellipsis.circle')], note: 'Window title removed (the trip name is the header). Spinner while fetching drive times; Share; Trip Actions.' }),
      strip('Explore', { title: 'Explore', trailing: [toolbarSearch('Search spots and places', { width: 200 }), toolbarGroup([['chevron.left'], dateText('10/6/2026'), ['chevron.right'], ['', { label: 'Today', disabled: true }]]), toolbarButton('sun.horizon', { menu: true }), toolbarButton('line.3.horizontal.decrease.circle', { menu: true }), toolbarButton('arrow.up.arrow.down', { menu: true }), toolbarButton('mappin.and.ellipse')],
        note: 'Search, date group (⌘[ ⌘] and Today), Light menu, Filters, Sort, Add Spot toggle.' }),
      strip('Spot page', { title: 'Horseshoe Bend', note: 'No toolbar items: Add to Trip, Save, Share, Edit and Delete sit in the page header.' }),
      strip('Saved', { title: 'Saved', trailing: [toolbarSearch('Search saved spots', { width: 200 }), toolbarButton('line.3.horizontal.decrease.circle', { menu: true })], note: 'Search field and the Sort and Filter menu.' }),
      strip('Scout', { title: 'Scout', note: 'No toolbar items.' })), { direction: 'column' })),
], { gap: 24 });

export const artboards = [
  { id: 'M-alerts-dialogs', name: 'Alerts and dialogs', section: 'components', width: 1152, height: 1600, themes: ['light'], covers: ['Menus/Alerts and dialogs'], render: alertsBoard },
  { id: 'M-share-sheet', name: 'Share sheet', section: 'components', width: 1408, height: 680, themes: ['light'], covers: ['Menus/Share sheet'], render: shareBoard },
  { id: 'M-file-panels', name: 'File importer and exporter', section: 'components', width: 1264, height: 1176, themes: ['light'], covers: ['Menus/File importer and exporter'], render: panelsBoard },
  { id: 'M-window-toolbars', name: 'Window title bar and toolbars', section: 'components', width: 1160, height: 1752, themes: ['light'], covers: ['Menus/Window title bar and toolbars'], render: toolbarsBoard },
];
