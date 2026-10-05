// Saved: list, empty, no forecast, filter empty, delete confirmation, sort and filter menu.
// Source: App/Sources/Saved/SavedView.swift. Toolbar items come from the source (snapshots draw them as grey blocks).
import { col, row, text } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { divider, button, contentUnavailable } from '../../../tools/lib/controls.mjs';
import { weatherAttribution } from '../../../tools/lib/lightindex.mjs';
import { macWindow, sidebar, toolbarButton, toolbarSearch, menu, alert } from '../../../tools/lib/chrome.mjs';
import { savedRow, listItem, SAVED_SAMPLE } from '../../components/saved-scout/saved-scout.mjs';

const W = 1280, H = 820;

function bottomBar(count, { sample, attribution = true }) {
  return col({ name: 'Bottom Bar', style: { flexShrink: 0 } },
    divider(),
    row({ name: 'Bar Content', align: 'center', style: { padding: `${d('space/sm')} ${d('space/lg')}`, background: canvas('material/bar'), flexShrink: 0 } },
      text(`${count} spots`, { name: 'Count', font: font('caption'), color: 'text/secondary', grow: true }),
      attribution ? weatherAttribution({ sample }) : null));
}

const toolbar = () => [toolbarSearch('Search saved spots', { width: 220 }), toolbarButton('line.3.horizontal.decrease.circle', {})];

function listBody(rows, { sample, selected, attribution = true }) {
  return col({ name: 'Saved List', grow: true, style: { minHeight: 0 } },
    col({ name: 'List', grow: true, pad: [10, 10, 0, 10], style: { minHeight: 0 } },
      rows.map((r, i) => listItem(savedRow(r), { last: i === rows.length - 1, selected: selected === i }))),
    bottomBar(rows.length, { sample, attribution }));
}

function win({ detail, overlays, hasToolbar = true, sample = true }) {
  return macWindow({ width: W, height: H, title: 'Saved', sidebar: sidebar({ selected: 'saved', sampleBanner: sample }),
    toolbarTrailing: hasToolbar ? toolbar() : [], detail, overlays: overlays || [] });
}

const listRows = () => SAVED_SAMPLE;
const noForecastRows = () => SAVED_SAMPLE.map((r, i) => ({ ...r, score: undefined, reason: 'weatherServiceNotEnabled', tomorrow: i < 2 }));

const SORT_MENU = () => menu([
  { header: 'Sort By' }, { label: 'Name', checked: true }, { label: 'Light Today' }, { label: 'Kind' }, '-',
  { header: 'Show' }, { label: 'All Spots', checked: true }, { label: 'Added by You' }, { label: 'Curated' }, { label: 'Apple Maps' },
], { width: 200, x: W - 16 - 200 - 4, y: 56, name: 'Menu / Sort and Filter' });

const emptyDetail = () => col({ name: 'Saved Empty', grow: true, align: 'center', justify: 'center', style: { minHeight: 0 } },
  contentUnavailable({ symbol: 'bookmark', title: 'Nothing saved yet', description: 'Save a spot from Explore or Scout and it shows up here with today\'s light. Spots you add yourself live here too.',
    buttons: [button('Browse Explore', { kind: 'prominent' }), button('Add Your Own Spot')] }));

const filterEmptyDetail = () => col({ name: 'Saved Filter Empty', grow: true, style: { minHeight: 0 } },
  col({ name: 'Empty Area', grow: true, align: 'center', justify: 'center', style: { minHeight: 0 } },
    contentUnavailable({ symbol: 'line.3.horizontal.decrease.circle', title: 'No spots here', description: 'No saved spots match this filter.' })),
  bottomBar(0, { sample: true }));

const snap = (n) => `snapshots/saved-${n}-{theme}-1280x820.png`;

export const artboards = [
  { id: 'S-saved-list', name: 'Saved · List', section: 'screens', width: W, height: H, snapshot: snap('list'), covers: ['Saved/List'],
    render: () => win({ detail: listBody(listRows(), { sample: true }) }) },
  { id: 'S-saved-empty', name: 'Saved · Empty', section: 'screens', width: W, height: H, snapshot: snap('empty'), covers: ['Saved/Empty'],
    notes: ['The toolbar search and Sort and Filter menu belong to the list, so the empty state shows no toolbar items.'],
    render: () => win({ detail: emptyDetail(), hasToolbar: false }) },
  { id: 'S-saved-no-forecast', name: 'Saved · No forecast', section: 'screens', width: W, height: H, snapshot: snap('noforecast'), covers: ['Saved/No forecast'],
    render: () => win({ detail: listBody(noForecastRows(), { sample: false, attribution: false }), sample: false }) },
  { id: 'S-saved-filter-empty', name: 'Saved · Filter empty', section: 'screens', width: W, height: H, covers: ['Saved/Filter or search empty'],
    notes: ['A search with no match shows the system search-empty view ("No Results for “query”") instead of this one.'],
    render: () => win({ detail: filterEmptyDetail() }) },
  { id: 'S-saved-delete-confirm', name: 'Saved · Delete confirmation', section: 'screens', width: W, height: H, covers: ['Saved/Delete confirmation'],
    notes: ['A system confirmation dialog; drawn with the shared alert panel.'],
    render: () => win({ detail: listBody(listRows(), { sample: true }), overlays: [alert({ title: 'Delete “Back field at Lone Pine”?', message: 'It is also removed from 2 trip stops. You can undo this with Edit > Undo.', buttons: [{ label: 'Delete Spot', destructive: true }, { label: 'Cancel' }], width: 300 })] }) },
  { id: 'S-saved-sort-menu', name: 'Saved · Sort and filter menu', section: 'screens', width: W, height: H, covers: ['Menus/Saved sort and filter menu'],
    render: () => win({ detail: listBody(listRows(), { sample: true }), overlays: [SORT_MENU()] }) },
];
