// Explore screen states (D3). Source: App/Sources/Explore/ExploreView.swift (toolbar, split view) and the components in
// src/components/explore/explore.mjs. Toolbar items come from the source (the snapshots draw them as grey blocks).
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { divider } from '../../../tools/lib/controls.mjs';
import { macWindow, sidebar, toolbarButton, toolbarGroup } from '../../../tools/lib/chrome.mjs';
import {
  LIST_W, ROWS_DEFAULT, ROWS_NOFORECAST, exploreListPanel, exploreMapPane, pinAt, pinChip,
  spotContextMenu, addToTripMenu, tripDaysMenu, filtersMenu, categorySubmenu, sortMenu,
} from '../../components/explore/explore.mjs';

const abs = (o) => ({ position: 'absolute', ...o });
const CHROME_W = 2, SIDEBAR_W = 240, TOOLBAR_H = 52;

// Toolbar, trailing items left to right as the source declares them: date control, Light, Filters, Sort, Add Spot, then the
// system search field (placement .toolbar, which macOS puts at the trailing edge).
function dateField(value) {
  return row({ name: 'Date Picker', align: 'center', style: { padding: '0 10px', height: 34 }, noshrink: true },
    text(value, { name: 'Value', font: font('body'), color: 'text/primary' }));
}
function toolbarSearchField({ value, width = 190 } = {}) {
  return row({ name: 'Toolbar Search', align: 'center', gap: d('space/sm'), noshrink: true,
    style: { width, height: 34, padding: `0 ${d('space/md')}`, borderRadius: '999px', background: canvas('chrome/control'), border: `1px solid ${canvas('chrome/control-stroke')}`, boxShadow: canvas('shadow/control') } },
  icon('magnifyingglass', { size: 14, color: 'text/secondary' }),
  text(value || 'Search spots and places', { name: value ? 'Query' : 'Prompt', font: font('body'), color: value ? 'text/primary' : 'text/tertiary' }));
}
function toolbarItems({ filters = 0, addSpot = false, query, date = '10/6/2026', today = true, filtersOpen = false, sortOpen = false, overflow = false } = {}) {
  const items = [
    toolbarGroup([['chevron.left'], dateField(date), ['chevron.right']]),
    toolbarButton(null, { label: 'Today', disabled: today }),
    toolbarButton('sun.horizon', { menu: true }),
    toolbarButton(filters ? 'line.3.horizontal.decrease.circle.fill' : 'line.3.horizontal.decrease.circle', { menu: true, label: filters ? String(filters) : undefined, toggled: filtersOpen }),
    toolbarButton('arrow.up.arrow.down', { menu: true, toggled: sortOpen }),
    toolbarButton('mappin.and.ellipse', { toggled: addSpot }),
    toolbarSearchField({ value: query }),
  ];
  // Narrow window: the trailing item (search) collapses into the overflow capsule. Inferred (the snapshot draws grey blocks).
  return overflow ? [...items.slice(0, -1), overflowButton()] : items;
}
function overflowButton() {
  return row({ name: 'Toolbar Overflow', align: 'center', justify: 'center', noshrink: true,
    style: { height: 34, minWidth: 34, borderRadius: '999px', background: canvas('chrome/control'), border: `1px solid ${canvas('chrome/control-stroke')}`, boxShadow: canvas('shadow/control') } },
  icon('chevron.right.2', { size: 14, color: 'text/primary' }));
}

// The window. Detail = list column | hairline | map pane.
function explore({ width = 1280, height = 820, sample = true, tb = {}, list, map, overlays = [], listW = LIST_W }) {
  const mapW = width - CHROME_W - SIDEBAR_W - listW - 1;
  const bodyH = height - CHROME_W - TOOLBAR_H;
  return macWindow({
    width, height, title: 'Explore',
    sidebar: sidebar({ selected: 'explore', sampleBanner: sample }),
    toolbarTrailing: toolbarItems(tb),
    detail: row({ name: 'Explore Split', grow: true, style: { minHeight: 0 } },
      exploreListPanel({ height: bodyH, width: listW, ...list }),
      divider({ vertical: true, name: 'Split Divider' }),
      exploreMapPane({ width: mapW, height: bodyH, ...map })),
    overlays,
  });
}

const spots = (rows, count = 45) => [{ title: 'Spots', count, rows }];
const base = () => ({ list: { header: { count: 45, sample: true }, sections: spots(ROWS_DEFAULT) }, map: {} });
const mesaPin = { kind: 'goldenMorning', time: '07:20' };

// ---- states ------------------------------------------------------------------------------------------------------------------------
const stateDefault = () => explore(base());
const stateDefault960 = () => explore({ width: 960, height: 640, listW: 300, tb: { overflow: true }, list: { header: { count: 45, sample: true }, sections: spots(ROWS_DEFAULT.slice(0, 7)) }, map: {} });
const stateSelected = () => explore({ ...base(), map: { selected: mesaPin, card: { kind: 'passed' } } });
const stateNoForecast = () => explore({
  sample: false,
  list: { header: { count: 45, notice: 'weatherServiceNotEnabled' }, sections: spots(ROWS_NOFORECAST), footer: null },
  map: { mode: 'noforecast', selected: mesaPin, card: { kind: 'passed' } },
});
const stateFilteredEmpty = () => explore({
  tb: { filters: 1 },
  list: { header: { count: 0, sample: true }, empty: 'filters' },
  map: { mode: 'none' },
});
const stateAddSpot = () => explore({ ...base(), tb: { addSpot: true }, map: { banner: true } });

// Apple Maps search: "antelope" matches one curated spot and four Apple Maps places (illustrative; scores are sample weather).
const SEARCH_ROWS = {
  spots: [{ name: 'Upper Antelope Canyon', locality: 'Page, AZ', kind: 'goldenEvening', score: 71, time: '17:41' }],
  maps: [
    { name: 'Lower Antelope Canyon', locality: 'Page, AZ', kind: 'goldenEvening', score: 71, time: '17:41' },
    { name: 'Antelope Island State Park', locality: 'Syracuse, UT', kind: 'goldenEvening', score: 66, time: '18:15', conf: 'low' },
    { name: 'Antelope Valley California Poppy Reserve', locality: 'Lancaster, CA', kind: 'goldenEvening', score: 62, time: '18:03' },
    { name: 'Antelope Canyon Navajo Tribal Park', locality: 'Page, AZ', kind: 'goldenEvening', score: 58, time: '17:41' },
  ],
};
function searchPins(w, h) {
  const at = (fxv, fyv) => [fxv * w, fyv * h];
  return [
    pinAt(...at(0.62, 0.34), pinChip({ kind: 'goldenEvening', score: 71 })),
    pinAt(...at(0.58, 0.40), pinChip({ kind: 'goldenEvening', score: 71 })),
    pinAt(...at(0.50, 0.12), pinChip({ kind: 'goldenEvening', score: 66 })),
    pinAt(...at(0.12, 0.74), pinChip({ kind: 'goldenEvening', score: 62 })),
    pinAt(...at(0.66, 0.45), pinChip({ kind: 'goldenEvening', score: 58 })),
  ];
}
const mapWOf = (w) => w - CHROME_W - SIDEBAR_W - LIST_W - 1;
const stateSearchResults = () => explore({
  tb: { query: 'antelope' },
  list: { header: { count: 5, sample: true }, sections: [{ title: 'Spots', rows: SEARCH_ROWS.spots }, { title: 'Apple Maps', rows: SEARCH_ROWS.maps }] },
  map: { pins: searchPins(mapWOf(1280), 820 - CHROME_W - TOOLBAR_H) },
});
const stateSearchNothing = () => explore({
  tb: { query: 'zzxq' },
  list: { header: { count: 0, sample: true }, empty: 'places', emptyOpts: { query: 'zzxq' } },
  map: { mode: 'none' },
});
const stateSearchFailed = () => explore({
  tb: { query: 'antelope' },
  list: { header: { count: 45, sample: true, search: { state: 'failed', query: 'antelope' } }, sections: spots(ROWS_DEFAULT) },
  map: {},
});
// Polar day, no window: illustrative. No curated spot is polar, so Night on 21 Jun is shown for spots where it does not occur.
const POLAR_ROWS = [
  { name: 'Haystack Rock', locality: 'Cannon Beach, OR', noWindow: true },
  { name: 'Palouse Falls', locality: 'Palouse Falls State Park, WA', noWindow: true },
  { name: 'Reflection Lakes', locality: 'Mount Rainier National Park, WA', noWindow: true },
  { name: 'Trillium Lake', locality: 'Mount Hood National Forest, OR', noWindow: true },
  { name: 'Mobius Arch, Alabama Hills', locality: 'Lone Pine, CA', kind: 'night', score: 72, time: '22:41', conf: 'low' },
  { name: 'Ancient Bristlecone Pine Forest', locality: 'White Mountains, CA', kind: 'night', score: 70, time: '22:39', conf: 'low' },
];
const statePolar = () => explore({
  tb: { date: '6/21/2026', today: false },
  list: { header: { count: 45, day: 'Sun, Jun 21, 2026', intent: 'Night', sample: true }, sections: spots([...POLAR_ROWS]) },
  map: { selected: { name: 'Haystack Rock', pos: { fx: 0.12, fy: 0.12 } }, card: { name: 'Haystack Rock', locality: 'Cannon Beach, OR', kind: 'none', saved: false }, mode: 'noforecast' },
});
const stateScored = () => explore({
  list: { header: { count: 45, sample: true }, sections: spots(ROWS_DEFAULT.map((r) => (r.name === 'Hopi Point' ? { ...r, selected: true } : r))) },
  map: { selected: { kind: 'goldenEvening', score: 73, time: '17:30', pos: { fx: (1213 - 813) / 1187, fy: (849 - 81) / 1200 } },
    card: { name: 'Hopi Point', locality: 'Grand Canyon National Park, AZ', kind: 'scored', saved: false } },
});

// ---- menus ---------------------------------------------------------------------------------------------------------------------------
// Menus are drawn open over a state (absolute overlays). Positions are window coordinates.
const over = (...kids) => () => el('div', { name: 'Open Menus', style: abs({ top: 0, left: 0, width: 0, height: 0, overflow: 'visible' }) }, kids);
const stateContextMenu = () => explore({
  list: { header: { count: 45, sample: true }, sections: spots(ROWS_DEFAULT.map((r) => (r.name === 'Hopi Point' ? { ...r, selected: true } : r))) },
  map: {},
  overlays: [over(
    spotContextMenu({ x: 420, y: 466, width: 200, highlightAdd: true }),
    addToTripMenu({ x: 626, y: 520, highlightTrip: true }),
    tripDaysMenu({ x: 836, y: 520, highlight: true }))],
});
const stateFiltersMenu = () => explore({
  ...base(), tb: { filters: 1, filtersOpen: true },
  overlays: [over(filtersMenu({ x: 880, y: 58, width: 190, highlight: 'Category', active: true }), categorySubmenu({ x: 1076, y: 58, checked: 0 }))],
});
const stateSortMenu = () => explore({
  ...base(), tb: { sortOpen: true },
  overlays: [over(sortMenu({ x: 1010, y: 58, width: 240 }))],
});

const snap = (n) => `snapshots/explore-${n}-{theme}-1280x820.png`;
export const artboards = [
  { id: 'S-explore-default', name: 'Explore · Default', section: 'screens', width: 1280, height: 820, snapshot: snap('default'), covers: ['Explore/Default'],
    notes: ['List width: the source frames the list column 300 min / 360 ideal / 520 max; the snapshots show it at 520 (the max). Drawn at the 360 ideal. Owner to decide.'], render: stateDefault },
  { id: 'S-explore-default-960', name: 'Explore · Default', section: 'screens', width: 960, height: 640, snapshot: 'snapshots/explore-default-{theme}-960x640.png', covers: ['Explore/Default'],
    notes: ['Toolbar overflow is inferred (the snapshot draws grey blocks): items that do not fit (the search field) collapse into the trailing overflow capsule. The list column is at its 300 minimum; the map is narrower. The capsule holds the chevron.right.2 symbol.'], render: stateDefault960 },
  { id: 'S-explore-selected', name: 'Explore · Selected with place card', section: 'screens', width: 1280, height: 820, snapshot: snap('selected'), covers: ['Explore/Selected, with place card'],
    notes: ['Save symbol: the card shows bookmark.fill ("Saved"); SCREENS.md says a filled star'], render: stateSelected },
  { id: 'S-explore-no-forecast', name: 'Explore · No forecast', section: 'screens', width: 1280, height: 820, snapshot: snap('noforecast'), covers: ['Explore/No forecast'], render: stateNoForecast },
  { id: 'S-explore-filtered-empty', name: 'Explore · Filtered empty', section: 'screens', width: 1280, height: 820, snapshot: snap('filtered-empty'), covers: ['Explore/Filtered empty'], render: stateFilteredEmpty },
  { id: 'S-explore-add-spot', name: 'Explore · Add Spot mode', section: 'screens', width: 1280, height: 820, snapshot: snap('addspot-mode'), covers: ['Explore/Add Spot mode'], render: stateAddSpot },
  { id: 'S-explore-search-results', name: 'Explore · Apple Maps results', section: 'screens', width: 1280, height: 820, covers: ['Explore/Apple Maps search results'],
    notes: ['Not in the snapshots. Apple Maps rows carry no provenance tag in the source (SCREENS.md says they are tagged). Place names and scores are illustrative.'], render: stateSearchResults },
  { id: 'S-explore-search-nothing', name: 'Explore · Search found nothing', section: 'screens', width: 1280, height: 820, covers: ['Explore/Search found nothing'], render: stateSearchNothing },
  { id: 'S-explore-search-failed', name: 'Explore · Search failed', section: 'screens', width: 1280, height: 820, covers: ['Explore/Search failed'], render: stateSearchFailed },
  { id: 'S-explore-polar', name: 'Explore · Polar day, no window', section: 'screens', width: 1280, height: 820, covers: ['Explore/Polar day, no window'],
    notes: ['Not in the snapshots. Illustrative: no curated spot is polar, so Night on 21 Jun stands in for a window that does not occur.'], render: statePolar },
  { id: 'S-explore-scored-card', name: 'Explore · Scored place card', section: 'screens', width: 1280, height: 820, covers: ['Explore/Scored place card'],
    notes: ['Not in the snapshots (the fixtures select Mesa Arch, whose window has passed).'], render: stateScored },
  { id: 'S-explore-menu-context', name: 'Explore · Spot context menu', section: 'screens', width: 1280, height: 820, covers: ['Menus/Spot and pin context menu', 'Menus/AddToTripMenu'], render: stateContextMenu },
  { id: 'S-explore-menu-filters', name: 'Explore · Filters menu', section: 'screens', width: 1280, height: 820, covers: ['Menus/Explore filters and sort menus'], render: stateFiltersMenu },
  { id: 'S-explore-menu-sort', name: 'Explore · Sort menu', section: 'screens', width: 1280, height: 820, covers: ['Menus/Explore filters and sort menus'], render: stateSortMenu },
];
