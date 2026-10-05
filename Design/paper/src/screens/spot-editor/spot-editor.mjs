// Spot editor sheet: five states drawn over Explore in Add Spot mode (sheet 520 x 750).
// The Explore window behind is a minimal local version (list column, map, Add Spot banner, dropped pin), not D3's module.
import { col, row, text, el, raw } from '../../../tools/lib/h.mjs';
import { c, d, dv, canvas, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { divider, button, searchField } from '../../../tools/lib/controls.mjs';
import { lightBadge, sampleDataLabel } from '../../../tools/lib/lightindex.mjs';
import { macWindow, sidebar, toolbarButton, toolbarGroup, toolbarSearch, mapPlaceholder, sheet } from '../../../tools/lib/chrome.mjs';
import { spotEditorSheet, SHEET_W, CREATE, EDIT } from '../../components/saved-scout/spot-editor-sheet.mjs';

const W = 1280, H = 820;
const abs = (o) => ({ position: 'absolute', ...o });

const SPOTS = [
  ['Ancient Bristlecone Pine Forest', 'White Mountains, CA', 86, 'night', '19:54'],
  ['Mobius Arch, Alabama Hills', 'Lone Pine, CA', 86, 'night', '19:54'],
  ['Palouse Falls', 'Palouse Falls State Park, WA', 79, 'goldenEvening', '17:42'],
  ['Keyhole Arch, Pfeiffer Beach', 'Big Sur, CA', 75, 'goldenEvening', '18:09'],
  ['Bombay Beach', 'Salton Sea, CA', 74, 'goldenEvening', '17:47'],
  ['Hopi Point', 'Grand Canyon National Park, AZ', 73, 'goldenEvening', '17:30'],
  ['McWay Falls', 'Julia Pfeiffer Burns State Park, CA', 73, 'goldenEvening', '18:08'],
  ['Point Reyes Lighthouse', 'Point Reyes National Seashore, CA', 73, 'goldenEvening', '18:12'],
];

function exploreRow([name, locality, score, win, time], last) {
  return col({ name: `ExploreRow / ${name}`.slice(0, 50), style: { flexShrink: 0 } },
    row({ name: 'Row Content', align: 'center', gap: d('space/sm'), style: { padding: `${d('space/sm')} ${d('space/lg')}` } },
      col({ name: 'Name and Place', grow: true },
        text(name, { name: 'Name', font: font('headline'), color: 'text/primary' }),
        text(locality, { name: 'Locality', font: font('subheadline'), color: 'text/secondary' })),
      lightBadge({ style: 'regular', window: win, score })),
    last ? null : divider());
}

function exploreBehind() {
  const banner = row({ name: 'AddSpotBanner', align: 'center', gap: d('space/sm'), style: abs({ top: d('space/md'), left: '50%', transform: 'translateX(-50%)', padding: `${d('space/sm')} ${d('space/md')}`, borderRadius: '999px', background: canvas('material/regular'), border: `${d('stroke/regular')} solid ${c('accent/primary')}` }) },
    icon('mappin.and.ellipse', { size: 14, color: 'accent/primary' }),
    text('Click the map to drop a pin for your spot', { name: 'Message', font: font('body'), color: 'text/primary' }),
    button('Cancel', { size: 'small' }));
  const dropped = el('div', { name: 'Dropped Pin', style: abs({ left: 340, top: 300, display: 'flex' }) }, icon('mappin.circle.fill', { size: 28, color: 'map/pin' }));
  return row({ name: 'Explore (simplified)', grow: true, style: { minHeight: 0 } },
    col({ name: 'List Column', w: dv('layout/listIdeal'), noshrink: true, style: { minHeight: 0 } },
      col({ name: 'Header', gap: d('space/xs'), style: { padding: `${d('space/md')} ${d('space/lg')} ${d('space/sm')}`, flexShrink: 0 } },
        text("45 places · Tue, Oct 6, 2026 · Each spot's best", { name: 'Summary', font: font('subheadline'), color: 'text/secondary' }), sampleDataLabel()),
      divider(),
      col({ name: 'List', grow: true, style: { minHeight: 0, overflow: 'hidden' } }, SPOTS.map((s, i) => exploreRow(s, i === SPOTS.length - 1)))),
    divider({ vertical: true }),
    mapPlaceholder({ grow: true, label: 'Map placeholder: swap for a map image', children: [banner, dropped] }));
}

// the shared sheet() helper draws its own panel; here we need our own 520 x 750 panel, so build the overlay by hand.
function overlayWith(opts) {
  return (ctx) => raw([
    el('div', { name: 'Scrim', style: abs({ top: 0, left: 0, right: 0, bottom: 0, background: canvas('scrim/sheet') }) }),
    el('div', { name: 'Sheet Position', style: abs({ top: 28, left: Math.round((ctx.width - SHEET_W) / 2), display: 'flex' }) }, spotEditorSheet(opts)),
  ].map(String).join('\n'));
}
function screen(opts) {
  return macWindow({ width: W, height: H, title: 'Explore', sidebar: sidebar({ selected: 'explore', sampleBanner: true }),
    toolbarTrailing: [toolbarSearch('Search spots and places', { width: 200 }), toolbarGroup([['chevron.left'], ['chevron.right']]), toolbarButton('sun.horizon', { menu: true }),
      toolbarButton('line.3.horizontal.decrease.circle'), toolbarButton('arrow.up.arrow.down'), toolbarButton('mappin.and.ellipse', { toggled: true })],
    detail: exploreBehind(), overlays: [overlayWith(opts)] });
}

const snap = (n) => `snapshots/editor-${n}-{theme}-1280x820.png`;
const WARN_FAILED = "Couldn't find this place's time zone, so using this Mac's.";
const WARN_LOOKING = "Using this Mac's time zone until the lookup finishes.";

export const artboards = [
  { id: 'S-editor-create', name: 'Spot editor · Create', section: 'screens', width: W, height: H, snapshot: snap('create'), covers: ['Spot editor sheet/Create'],
    render: () => screen(CREATE) },
  { id: 'S-editor-edit', name: 'Spot editor · Edit', section: 'screens', width: W, height: H, snapshot: snap('edit'), covers: ['Spot editor sheet/Edit'],
    notes: ['Edit opens from Saved or the Spot page; it is drawn over Explore here to share one backdrop with the other states.'],
    render: () => screen(EDIT) },
  { id: 'S-editor-lookup-failed', name: 'Spot editor · Lookup failed', section: 'screens', width: W, height: H, snapshot: snap('create-lookup-failed'), covers: ['Spot editor sheet/Create, lookup failed'],
    render: () => screen({ mode: 'create', name: '', place: '', timeZone: 'Mountain Time', warn: WARN_FAILED }) },
  { id: 'S-editor-looking-up', name: 'Spot editor · Looking up', section: 'screens', width: W, height: H, covers: ['Spot editor sheet/Looking up'],
    render: () => screen({ mode: 'create', name: '', place: '', timeZone: 'Mountain Time', warn: WARN_LOOKING, lookingUp: true }) },
  { id: 'S-editor-validation', name: 'Spot editor · Validation errors', section: 'screens', width: W, height: H, covers: ['Spot editor sheet/Validation errors'],
    notes: ['Shown after a failed save: blank name and an invalid walk-in. The pin has also been moved, so Reset Pin appears.'],
    render: () => screen({ mode: 'create', name: '', place: 'Moab, UT', timeZone: 'Mountain Time', nameProblem: true, walkIn: 'about 20', walkInProblem: true, coords: '36.5801, -118.2874', moved: true }) },
];
