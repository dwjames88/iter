// SpotEditorSheet (App/Sources/Components/SpotEditorSheet.swift): 520 x 750 sheet, grouped form. Exported as spotEditorSheet(opts)
// and used by src/screens/spot-editor/spot-editor.mjs; the component artboard shows the same function in light and dark.
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { divider, button, checkbox, spinner } from '../../../tools/lib/controls.mjs';
import { mapPlaceholder, note } from '../../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, page } from '../../../tools/lib/specimens.mjs';
import { CATEGORY } from './saved-scout.mjs';

export const SHEET_W = 520, SHEET_H = 750;
const abs = (o) => ({ position: 'absolute', ...o });
const ROW_PAD = 10;

function groupBox(name, children) {
  return col({ name, bg: canvas('control/group'), radius: 12, clip: true, style: { flexShrink: 0 } }, children);
}
function formRow(label, control, { last = false, extra = null, align = 'center' } = {}) {
  return col({ name: `Row / ${label}`.slice(0, 50), style: { flexShrink: 0 } },
    row({ name: 'Row Line', align, justify: 'space-between', gap: d('space/lg'), style: { minHeight: 36, padding: `${d('space/xs')} ${ROW_PAD}px` } },
      text(label, { name: 'Label', font: font('body'), color: 'text/primary', noshrink: true }),
      control),
    extra,
    last ? null : el('div', { name: 'Row Separator', style: { padding: `0 ${ROW_PAD}px`, display: 'flex', flexDirection: 'column' } }, divider({ name: 'Separator' })));
}
const value = (v, ph) => text(v || ph, { name: v ? 'Value' : 'Placeholder', font: font('body'), color: v ? 'text/primary' : 'text/tertiary', style: { textAlign: 'right' } });
const sectionFooter = (children) => row({ name: 'Section Footer', align: 'center', gap: d('space/sm'), style: { padding: `0 ${ROW_PAD}px`, flexShrink: 0 } }, children);
const footText = (s, name = 'Footer') => text(s, { name, font: font('footnote'), color: 'text/secondary' });

export function problem(message) {
  return row({ name: 'Problem Line', align: 'flex-start', gap: d('space/xs'), style: { padding: `0 ${ROW_PAD}px ${d('space/sm')}` } },
    el('div', { name: 'Icon Slot', style: { display: 'flex', alignItems: 'center', height: 13, flexShrink: 0 } }, icon('exclamationmark.triangle.fill', { size: 11, color: 'status/danger' })),
    text(message, { name: 'Message', font: font('caption'), color: 'status/danger', wrap: true, grow: true }));
}

function pinMap({ movedLabel }) {
  const pin = icon('mappin', { size: 34, color: 'accent/primary' });
  return mapPlaceholder({ height: dvArc(), label: 'Map placeholder: swap for a map image', children: [
    el('div', { name: 'Pin (tip at map centre)', style: abs({ left: 'calc(50% - 17px)', top: `calc(50% - 34px)`, display: 'flex', filter: `drop-shadow(0 1px 1.5px color-mix(in srgb, ${c('text/primary')} 35%, transparent))` }) }, pin)] });
}
const dvArc = () => 168;

function categoryPicker(cat) {
  const [sym, label] = CATEGORY[cat];
  return row({ name: 'Category Picker', align: 'center', gap: d('space/sm'), noshrink: true },
    icon(sym, { size: 16, color: 'text/primary' }),
    text(label, { name: 'Value', font: font('body'), color: 'text/primary' }),
    col({ name: 'Picker Chevrons', align: 'center', justify: 'center', noshrink: true, style: { width: 22, height: 22, borderRadius: '999px', background: canvas('control/button'), border: `1px solid ${canvas('control/button-stroke')}` } },
      icon('chevron.up.chevron.down', { size: 10, color: 'text/secondary', weight: 'semibold' })));
}

function tzWarning(message) {
  return row({ name: 'Time Zone Warning', align: 'flex-start', gap: d('space/xs'), style: { maxWidth: 280, justifyContent: 'flex-end' } },
    el('div', { name: 'Icon Slot', style: { display: 'flex', alignItems: 'center', height: 13, flexShrink: 0 } }, icon('exclamationmark.triangle', { size: 11, color: 'status/warning' })),
    text(message, { name: 'Message', font: font('caption'), color: 'status/warning', wrap: true, style: { textAlign: 'right' } }));
}

const BEST = ['Sunrise', 'Sunset', 'Blue hour', 'Night sky', 'Midday', 'Overcast'];

/**
 * opts: {mode:'create'|'edit', name, place, category, timeZone, tzWarning, lookingUp, bestLight:[labels], walkIn, notes,
 *        nameProblem, walkInProblem, coords, moved}
 */
export function spotEditorSheet(o = {}) {
  const { mode = 'create', name = '', place = '', category = 'landscape', timeZone = 'Mountain Time', warn, lookingUp = false, best = [], walkIn = '', notes = '',
    nameProblem = false, walkInProblem = false, coords = '36.5786, -118.2920', moved = false } = o;
  const title = mode === 'create' ? 'New Spot' : 'Edit Spot';
  const nameControl = row({ name: 'Name Control', align: 'center', gap: d('space/sm') }, lookingUp ? spinner(14) : null, value(name, 'Name this spot'));
  const nameExtra = lookingUp ? text('Looking up this place…', { name: 'Lookup Progress', font: font('caption'), color: 'text/secondary', style: { padding: `0 ${ROW_PAD}px ${d('space/sm')}`, textAlign: 'right' } })
    : nameProblem ? problem('Name this spot to save it.') : null;
  const form = col({ name: 'Form', gap: d('space/xl'), style: { padding: '20px 20px 20px', flexShrink: 0 } },
    col({ name: 'Section / Pin', gap: d('space/sm') },
      groupBox('Group / Pin Map', col({ name: 'Map Inset', pad: ROW_PAD, style: { display: 'flex' } },
        el('div', { name: 'Pin Map Clip', style: { display: 'flex', flexDirection: 'column', borderRadius: d('radius/card'), overflow: 'hidden', border: `${d('stroke/hairline')} solid ${c('separator/default')}`, flexShrink: 0 } }, pinMap({})))),
      sectionFooter([footText('Drag the map to move the pin.', 'Hint'),
        text(coords, { name: 'Coordinates', font: font('footnote', { }), color: 'text/secondary', style: { fontVariantNumeric: 'tabular-nums' } }),
        el('div', { name: 'Footer Spacer', style: { flex: '1 1 0', minWidth: 0 } }),
        moved ? text('Reset Pin', { name: 'Reset Pin', font: font('footnote'), color: 'accent/text' }) : null])),
    groupBox('Group / Fields', [
      formRow('Name', nameControl, { extra: nameExtra }),
      formRow('Place', value(place, 'Park, town or region')),
      formRow('Category', categoryPicker(category)),
      formRow('Time zone', warn
        ? col({ name: 'Time Zone Value', align: 'flex-end' }, text(timeZone, { name: 'Value', font: font('body'), color: 'text/secondary' }), tzWarning(warn))
        : text(timeZone, { name: 'Value', font: font('body'), color: 'text/secondary' }), { last: true, align: warn ? 'flex-start' : 'center' }),
    ]),
    col({ name: 'Section / Best Light', gap: d('space/sm') },
      text('Best light (choose any)', { name: 'Header', font: font('subheadline', { weight: 'semibold' }), color: 'text/primary', style: { padding: `0 ${ROW_PAD}px` } }),
      groupBox('Group / Best Light', col({ name: 'Checkbox Grid', gap: d('space/sm'), style: { padding: `${d('space/sm')} ${ROW_PAD}px` } },
        [BEST.slice(0, 3), BEST.slice(3)].map((r, i) => row({ name: `Checkbox Row ${i + 1}`, gap: 0 },
          r.map((l) => el('div', { name: `Cell / ${l}`, style: { flex: '1 1 0', minWidth: 0, display: 'flex' } }, checkbox(l, best.includes(l)))))))),
      sectionFooter([footText('With none chosen, light is shown for sunset.')])),
    groupBox('Group / Walk-in and Notes', [
      formRow('Walk-in (minutes)', value(walkIn, 'Optional'), { extra: walkInProblem ? problem("Enter whole minutes from 0 to 600, or leave it empty if you don't know.") : null }),
      formRow('Notes', value(notes, 'Access, gear, crowds, permits'), { last: true }),
    ]));
  return col({ name: `Sheet / ${title}`, w: SHEET_W, h: SHEET_H, noshrink: true, clip: true, style: { background: canvas('sheet/background'), borderRadius: 26, boxShadow: canvas('shadow/sheet') } },
    text(title, { name: 'Title', font: font('title/section'), color: 'text/primary', style: { padding: `${d('space/lg')} ${d('space/lg')} ${d('space/sm')}`, flexShrink: 0 } }),
    col({ name: 'Form Scroll (clipped)', grow: true, clip: true, style: { minHeight: 0 } }, form),
    divider(),
    row({ name: 'Sheet Buttons', align: 'center', justify: 'flex-end', gap: d('space/sm'), pad: d('space/lg'), style: { flexShrink: 0 } },
      button('Cancel'), button(mode === 'create' ? 'Add Spot' : 'Save', { kind: 'prominent' })));
}

export const EDIT = { mode: 'edit', name: 'Back field at Lone Pine', place: 'Lone Pine, CA', timeZone: 'Pacific Time', best: ['Sunrise', 'Night sky'], walkIn: '12', notes: 'Park at the pullout; the gate is usually open before dawn.' };
export const CREATE = { mode: 'create', name: 'Dropped pin', place: 'Moab, UT', timeZone: 'Mountain Time' };

const board = () => {
  const body = (theme) => [
    row({ name: 'Sheets', gap: 24, align: 'flex-start' },
      spotEditorSheet(CREATE), spotEditorSheet(EDIT)),
  ];
  return page([
    artboardHeader({ title: 'SpotEditorSheet', type: 'SpotEditorSheet', file: 'Components/SpotEditorSheet.swift', job: 'Create a spot from a dropped pin, or edit one of your own. Anything you type is yours; a lookup never overwrites it. Fixed 520 x 750 pt.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Create and edit', body: 'Left: create (lookup filled name, place and zone, no best light ticked, button "Add Spot"). Right: edit (values held, Sunrise and Night sky ticked, button "Save").' }),
        note({ title: 'Form scrolls', body: 'The grouped form scrolls inside the fixed 520 x 750 frame. With errors, a lookup line or a multi-line Notes (3 to 6 lines) it is taller than the frame and is cut at the divider (see the screen states). The snapshot crops it the same way.' }),
        note({ title: 'Map and pin', body: 'The pin map is 168 high, 12 pt corners and a hairline. The mappin symbol (largest title size, accent, small shadow) has its tip on the map centre; the map moves under it. The map itself is a placeholder to swap.' })),
      themeBlocks(body)),
  ], { gap: 24 });
};

export const artboards = [
  { id: 'C-spot-editor-sheet', name: 'SpotEditorSheet', section: 'components', width: 2300, height: 1136, themes: ['light'], covers: ['Component/SpotEditorSheet'], render: board },
];
