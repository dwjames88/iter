// Component artboard "System components": every system control as Iter configures it. The component names and the
// "how Iter uses it" text are read from Design/COMPONENTS.md ("## System components") at build time; each specimen is
// drawn with the shared control helpers, once in light and once in dark.
import path from 'node:path';
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font, withTheme } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { button, segmented, popUpButton, searchField, stepper, checkbox, datePicker, spinner, divider, formGroup, listSection, listRow, contentUnavailable } from '../../../tools/lib/controls.mjs';
import { toolbarButton, toolbarGroup, sidebar, menu, popover, alertPanel, mapPlaceholder, note } from '../../../tools/lib/chrome.mjs';
import { artboardHeader, page } from '../../../tools/lib/specimens.mjs';
import { mdTable, designDir } from '../../foundations/tokdata.mjs';

const hair = () => `${d('stroke/hairline')} solid ${canvas('specimen/border')}`;

const toggle = (on) => row({ name: `Toggle / ${on ? 'On' : 'Off'}`, align: 'center', noshrink: true, w: 38, h: 22, radius: 999, bg: on ? c('accent/primary') : canvas('control/segmented-track'), style: { padding: 2, justifyContent: on ? 'flex-end' : 'flex-start' } },
  el('div', { name: 'Knob', style: { width: 18, height: 18, borderRadius: '999px', background: c('background/content'), boxShadow: canvas('shadow/button'), flexShrink: 0 } }));

const ground = (children) => el('div', { name: 'Backdrop', style: { position: 'relative', width: 250, height: 96, display: 'flex', borderRadius: d('radius/card'), overflow: 'hidden', background: `linear-gradient(120deg, ${c('sky/blueHour')} 0 40%, ${c('light/ramp/good')} 40% 70%, ${c('route/active')} 70%)` } }, children);
const mat = (label, key) => el('div', { name: `Material / ${label}`, style: { position: 'absolute', left: 16, right: 16, top: 16, bottom: 16, display: 'flex', alignItems: 'center', justifyContent: 'center', background: canvas(key), border: `1px solid ${canvas('material/stroke')}`, borderRadius: d('radius/panel'), boxShadow: key === 'material/regular' ? canvas('shadow/material') : undefined } }, text(label, { name: 'Label', font: font('callout'), color: 'text/primary' }));

const SPEC = {
  NavigationSplitView: () => col({ name: 'Sidebar Specimen', w: 240, h: 232, radius: d('radius/panel'), clip: true, style: { background: canvas('chrome/sidebar'), border: `1px solid ${canvas('chrome/sidebar-stroke')}` } }, sidebar({ selected: 'explore', sampleBanner: false })),
  List: () => col({ name: 'List Specimen', w: 250 }, listSection({ header: 'Spots', count: 3, rows: [
    listRow({ selected: true, children: [icon('mappin', { size: 14, color: 'accent/primary' }), text('Horseshoe Bend', { name: 'Title', font: font('body'), color: 'text/primary' })] }),
    listRow({ children: [icon('mappin', { size: 14, color: 'accent/primary' }), text('Monument Valley', { name: 'Title', font: font('body'), color: 'text/primary' })] }),
    listRow({ children: [icon('mappin', { size: 14, color: 'accent/primary' }), text('Dead Horse Point', { name: 'Title', font: font('body'), color: 'text/primary' })] })] })),
  HSplitView: () => row({ name: 'HSplitView Specimen', w: 250, h: 90, radius: d('radius/control'), clip: true, style: { border: hair() } },
    el('div', { name: 'Plan Pane', style: { flex: '1 1 0', background: c('background/window'), display: 'flex', alignItems: 'center', justifyContent: 'center' } }, text('Plan', { name: 'Label', font: font('callout'), color: 'text/secondary' })),
    el('div', { name: 'Divider', style: { width: d('stroke/hairline'), background: c('separator/default'), flexShrink: 0 } }),
    el('div', { name: 'Map Pane', style: { flex: '1 1 0', background: c('background/control'), display: 'flex', alignItems: 'center', justifyContent: 'center' } }, text('Map', { name: 'Label', font: font('callout'), color: 'text/secondary' }))),
  Toolbar: () => row({ name: 'Toolbar Specimen', align: 'center', gap: d('space/md'), w: 250 }, toolbarButton('plus'), text('Explore', { name: 'Window Title', font: font('title/section', { size: 15, weight: 'semibold', lineHeight: 20 }), color: 'text/primary', grow: true }), toolbarGroup([['square.and.arrow.up'], ['line.3.horizontal.decrease.circle']])),
  searchable: () => searchField({ placeholder: 'Search spots and places', width: 250 }),
  ContentUnavailableView: () => contentUnavailable({ symbol: 'bookmark', title: 'Nothing saved yet', description: 'Save a spot from Explore or Scout and it shows up here with today\'s light.', buttons: [button('Browse Explore', { kind: 'bordered' })] }),
  Map: () => mapPlaceholder({ width: 250, height: 110, label: 'Map placeholder (swap)' }),
  LookAroundPreview: () => el('div', { name: 'Look Around (swap)', style: { width: 250, height: 112, display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column', gap: 4, background: c('background/control'), borderRadius: d('radius/card'), border: hair() } }, icon('binoculars', { size: 20, color: 'text/tertiary' }), text('Look Around (swap)', { name: 'Caption', font: font('caption'), color: 'text/tertiary' })),
  Picker: () => col({ name: 'Picker Specimen', gap: d('space/sm'), align: 'flex-start' }, segmented(['Sunrise', 'Sunset', 'Blue hour', 'Night'], 1), popUpButton('Each Spot\'s Best', { width: 200 })),
  Menu: () => menu([{ label: 'Change Dates…', shortcut: '⇧⌘D' }, { label: 'Export…', shortcut: '⇧⌘E' }, 'Duplicate', '-', { label: 'Delete Trip', destructive: true }], { width: 240 }),
  ShareLink: () => row({ name: 'ShareLink Specimen', gap: d('space/md'), align: 'center' }, button('Share', { icon: 'square.and.arrow.up' }), toolbarButton('square.and.arrow.up')),
  DatePicker: () => formGroup({ width: 270, rows: [
    { label: 'Set-up time', control: stepper(20) }, { label: 'Date', control: datePicker('Wed 7 Oct 2026') }, { label: 'Toggle, off', control: toggle(false) }, { label: 'Toggle, on', control: toggle(true) }] }),
  Sheet: () => col({ name: 'Dialogs Specimen', gap: d('space/md'), align: 'flex-start' }, popover({ width: 250, height: 52, arrow: null, body: row({ name: 'Popover Body', align: 'center', gap: d('space/sm'), style: { padding: d('space/md') } }, text('Set up 20 min before the window', { name: 'Label', font: font('body'), color: 'text/primary' })) }),
    alertPanel({ title: 'Delete all trips and spots?', message: 'This can\'t be undone.', buttons: [{ label: 'Delete Everything', destructive: true, kind: 'prominent' }, { label: 'Cancel', kind: 'bordered' }], width: 250 })),
  TabView: () => row({ name: 'Settings Tab Bar', gap: d('space/xs'), w: 330, noshrink: true, pad: 3, radius: 999, bg: canvas('control/segmented-track') },
    [['gearshape', 'General', true], ['cloud.sun', 'Weather'], ['sparkles', 'Apple Intelligence'], ['info.circle', 'About']].map(([ic, lb, sel]) =>
      col({ name: `Tab / ${lb}`, align: 'center', gap: 2, justify: 'center', radius: 999, style: { flex: sel ? '0 0 auto' : '1 1 auto', padding: '6px 10px', background: sel ? canvas('control/segmented-thumb') : undefined } }, icon(ic, { size: 14, color: sel ? 'accent/primary' : 'text/secondary' }), text(lb, { name: 'Label', font: font('caption'), color: 'text/primary' })))),
  Materials: () => col({ name: 'Materials Specimen', gap: d('space/sm') }, ground(mat('regularMaterial', 'material/regular')), ground(mat('bar material', 'material/bar'))),
  ProgressView: () => col({ name: 'Progress Specimen', gap: d('space/md') },
    row({ name: 'Small', align: 'center', gap: d('space/sm') }, spinner(16), text('Checking Apple Weather…', { name: 'Label', font: font('body'), color: 'text/secondary' })),
    row({ name: 'Large', align: 'center', gap: d('space/md') }, spinner(32), text('Scout is looking…', { name: 'Label', font: font('headline'), color: 'text/primary' }))),
  Buttons: () => col({ name: 'Buttons Specimen', gap: d('space/sm'), align: 'flex-start' },
    row({ name: 'Row 1', gap: d('space/sm'), align: 'center' }, button('Add Spot', { kind: 'prominent' }), button('Cancel', { kind: 'bordered' }), button('Add Spot', { kind: 'prominent', disabled: true })),
    row({ name: 'Row 2', gap: d('space/md'), align: 'center' }, button('Explain', { kind: 'borderless', icon: 'apple.intelligence' }), button('Legal attribution', { kind: 'link' }), button('Open', { kind: 'plain' }))),
};

function themedPanel(fn, theme) {
  return withTheme(theme, () => el('div', { name: `Specimen / ${theme}`, style: { width: 392, minHeight: 120, flexShrink: 0, display: 'flex', flexDirection: 'column', alignItems: 'flex-start', justifyContent: 'center', padding: d('space/lg'), background: c('background/window'), border: hair(), borderRadius: d('radius/card') } }, fn()));
}

const rows = mdTable(path.join(designDir, 'COMPONENTS.md'), 'System components');

function card([name, usage]) {
  const key = Object.keys(SPEC).find((k) => name.startsWith(k));
  if (!key) throw new Error(`System components: no specimen for "${name}"`);
  return row({ name: `System / ${name}`.slice(0, 50), gap: d('space/lg'), align: 'flex-start', w: 1164, noshrink: true, pad: d('space/lg'), radius: d('radius/card'), style: { background: canvas('specimen/background'), border: hair() } },
    col({ name: 'Description', gap: d('space/xs'), w: 300, noshrink: true },
      text(name, { name: 'System Name', font: font('headline'), color: canvas('label/title'), wrap: true }),
      text(usage, { name: 'How Iter Uses It', font: font('callout'), color: canvas('label/body'), wrap: true })),
    themedPanel(SPEC[key], 'light'), themedPanel(SPEC[key], 'dark'));
}

function board() {
  const pairs = [];
  for (let i = 0; i < rows.length; i += 2) pairs.push(rows.slice(i, i + 2));
  return page([
    artboardHeader({ title: 'System components', type: 'macOS 26 controls', file: 'Design/COMPONENTS.md · System components', job: 'Iter relies on these system controls and does not restyle them: it configures them. Each is drawn with the macOS 26 look, light and dark, with the notes on how Iter uses it. Coral enters only through the app accent.' }),
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Stand-ins', body: 'MapKit, Look Around, materials and the system tab bar are drawn as stand-ins (named with (swap)); the Settings tab bar follows the standard macOS Settings look, not the broken snapshot.', width: 420 })),
    col({ name: 'Components', gap: d('space/lg') }, pairs.map((p, i) => row({ name: `Row ${i + 1}`, gap: d('space/lg'), align: 'flex-start' }, p.map(card)))),
  ], { gap: 28, pad: 40 });
}

export const artboards = [
  { id: 'C-system-components', name: 'System components', section: 'components', width: 2432, height: 2512, themes: ['light'], covers: ['Component/System components'], render: board },
];
