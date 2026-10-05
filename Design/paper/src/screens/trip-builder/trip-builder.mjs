// Trip builder screens (D2). The window is built from the same component functions as the component specimens.
import { col, row, text, el, raw } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { divider, button, contentUnavailable, spinner } from '../../../tools/lib/controls.mjs';
import { macWindow, sidebar, toolbarButton, popover, menu, note } from '../../../tools/lib/chrome.mjs';
import { tripHeader, tripPlanList, tripRouteMap, connectorRow, stopRow, addStopBody, canyonCountry, conflictTrip, item, OVERNIGHT, SHORT, CANYON_STOPS, FITS } from '../../components/trip-builder/parts.mjs';

const TOOLBAR = 52;
const DEVIATION_PIN = 'The active-day pin is accent/emphasis (TripRouteMap.swift); the snapshot stand-in draws map/pin. The source is drawn.';

function toolbar(extra = []) {
  return [extra, toolbarButton('square.and.arrow.up', { label: undefined }), toolbarButton('ellipsis.circle')];
}

// Where the scrolled list is cut (on a row boundary) so no element is clipped half way. Tuned per window size.
function cutFor(trip, width) {
  const w960 = width < 1000;
  if (trip.cutAt) return trip.cutAt[w960 ? '960' : '1280'];
  return undefined;
}

function split({ width, height, trip, overlayList = [], fetching = false }) {
  const detailW = width - 242;
  const leftW = Math.max(360, Math.min(520, detailW - 300));
  const mapW = detailW - leftW - 1;
  const mapH = height - TOOLBAR - 2;
  const left = col({ name: 'Plan Column', w: leftW, noshrink: true, style: { minHeight: 0 } },
    tripHeader({ name: trip.name, dates: trip.dates, counts: trip.counts, driving: trip.driving }),
    divider(),
    tripPlanList({ caption: trip.caption, days: trip.days, attribution: trip.attribution, sample: trip.sample, cut: cutFor(trip, width) }));
  const map = tripRouteMap({ width: mapW, height: mapH, pins: trip.pins, legs: trip.legs, activeDay: trip.activeDay, days: trip.dayTabs });
  return { node: row({ name: 'Split View', grow: true, style: { minHeight: 0 } }, left, divider({ vertical: true, name: 'Split Divider' }), map), leftW, mapW };
}

// The sidebar truncates long trip names with an ellipsis.
const sbName = (n) => (n.length > 22 ? n.slice(0, 21) + '…' : n);

function builderWindow({ width, height, trip, overlays = [], fetching = false }) {
  const { node } = split({ width, height, trip });
  return macWindow({
    width, height, hideTitle: true,
    sidebar: sidebar({ selected: sbName(trip.name), trips: [sbName(trip.name)], sampleBanner: trip.sample !== false }),
    toolbarTrailing: toolbar(fetching ? [spinner(16)] : []),
    detail: node, overlays,
  });
}

function missingWindow({ width, height }) {
  return macWindow({
    width, height, hideTitle: true,
    sidebar: sidebar({ selected: 'trips', trips: [], sampleBanner: true }),
    detail: col({ name: 'Trip Not Found', grow: true, align: 'center', justify: 'center', style: { background: c('background/window'), minHeight: 0 } },
      contentUnavailable({ symbol: 'map', title: 'Trip Not Found', description: 'This trip was deleted or its creation was undone.', buttons: [button('Back to All Trips', { kind: 'prominent' })] })),
  });
}

// "A stop row (detail)": four stops in a 560 pt column.
function stopRowStudy(width, height) {
  const f = true;
  const stops = conflictTrip().days.flatMap((x) => x.items);
  const list = col({ name: 'Plan Column 560', w: 560, noshrink: true, style: { padding: `${d('space/lg')}`, background: c('background/content'), borderRadius: d('radius/card') } },
    connectorRow({ drive: null }),
    stopRow(stops[0].stop),
    connectorRow(stops[1].connector), stopRow(stops[1].stop),
    connectorRow(stops[2].connector), stopRow(stops[2].stop),
    connectorRow(stops[3].connector), stopRow(stops[3].stop));
  return col({ name: 'Study Page', grow: true, pad: 32, gap: 24, style: { background: c('background/window'), minHeight: 0 } },
    text('A stop row (detail)', { name: 'Title', font: font('title/section', { size: 22, lineHeight: 28, weight: 'semibold' }), color: canvas('label/title') }),
    row({ name: 'Study Body', gap: 32, align: 'flex-start' }, list,
      col({ name: 'Study Notes', gap: d('space/md'), noshrink: true },
        note({ title: 'What it shows', body: 'First stop with "Set up by" only (no drive) under a connector with no drive text yet (loading); "Leave · park · set up by"; "walk-in unknown"; an out-of-order line; the Overnight connector; an infeasible drive; the Evening blue hour window.', width: 280 }),
        note({ title: 'Snapshot crop', body: 'The snapshot is the same column cropped from a taller list. The first connector there is the rail alone: MapKit has not answered yet.', width: 280 }))));
}

function addStopOverlay() {
  return () => raw(String(popover({ width: 480, height: 504, arrow: 'top', arrowOffset: 30, x: 244, y: 312, name: 'AddStopPopover', body: addStopBody({ anchor: 'Horseshoe Bend' }) })));
}

const SNAP = (n, sz) => `snapshots/${n}-{theme}-${sz}.png`;
const TB = 'Trip builder';
const mk = (id, name, w, h, covers, snap, render, extra = {}) => ({ id, name, section: 'screens', width: w, height: h, covers, snapshot: snap, render, ...extra });

export const artboards = [
  mk('S-trip-builder-default', 'Trip builder · Default', 1280, 820, [`${TB}/Default, sample weather`], SNAP('trip-builder', '1280x820'),
    () => builderWindow({ width: 1280, height: 820, trip: canyonCountry() }),
    { notes: ['Active-day pins are accent/emphasis.', 'Days 3 and 4 are not in the snapshots; their times and scores are illustrative.'] }),
  mk('S-trip-builder-default-960', 'Trip builder · Default', 960, 640, [`${TB}/Default, sample weather`], SNAP('trip-builder', '960x640'),
    () => builderWindow({ width: 960, height: 640, trip: canyonCountry() })),
  mk('S-trip-builder-noforecast', 'Trip builder · No forecast', 1280, 820, [`${TB}/No forecast`], SNAP('trip-builder-noforecast', '1280x820'),
    () => builderWindow({ width: 1280, height: 820, trip: canyonCountry({ forecast: false }) })),
  mk('S-trip-builder-noforecast-960', 'Trip builder · No forecast', 960, 640, [`${TB}/No forecast`], SNAP('trip-builder-noforecast', '960x640'),
    () => builderWindow({ width: 960, height: 640, trip: canyonCountry({ forecast: false }) })),
  mk('S-trip-builder-conflict', 'Trip builder · Conflict', 1280, 820, [`${TB}/Conflict and suggestion`], SNAP('trip-builder-conflict', '1280x820'),
    () => builderWindow({ width: 1280, height: 820, trip: conflictTrip() })),
  mk('S-trip-builder-conflict-960', 'Trip builder · Conflict', 960, 640, [`${TB}/Conflict and suggestion`], SNAP('trip-builder-conflict', '960x640'),
    () => builderWindow({ width: 960, height: 640, trip: conflictTrip() })),
  mk('S-trip-builder-missing', 'Trip builder · Missing trip', 1280, 820, [`${TB}/Missing trip`], SNAP('trip-builder-missing', '1280x820'),
    () => missingWindow({ width: 1280, height: 820 })),
  mk('S-trip-builder-stoprow', 'Trip builder · A stop row', 1280, 820, [`${TB}/A stop row (detail)`], SNAP('trip-stoprow', '1280x820'),
    () => stopRowStudy(1280, 820)),
  mk('S-trip-builder-fetching', 'Trip builder · Fetching drives', 1280, 820, [`${TB}/Fetching drives`], undefined,
    () => builderWindow({ width: 1280, height: 820, trip: canyonCountry(), fetching: true })),
  mk('S-trip-builder-dragging', 'Trip builder · Dragging a stop', 1280, 820, [`${TB}/Dragging`], undefined,
    () => builderWindow({ width: 1280, height: 820, trip: (() => { const t = canyonCountry(); t.days[1].dropTarget = true; return t; })() })),
  mk('S-trip-builder-estimated', 'Trip builder · Estimated drive', 1280, 820, [`${TB}/Estimated drive`], undefined,
    () => builderWindow({ width: 1280, height: 820, trip: (() => { const t = canyonCountry(); t.driving = '376 mi · 8 hr, 39 min driving (estimated)'; t.days[1].items[1].connector = { drive: '3 hr, 8 min · 136 mi', estimated: true }; return t; })() })),
  mk('S-trip-builder-window-missing', 'Trip builder · Window missing', 1280, 820, [`${TB}/Window missing`], undefined,
    () => builderWindow({ width: 1280, height: 820, trip: (() => {
      const t = canyonCountry(); const s = t.days[1].items[0].stop;
      s.issues = ['No Sunrise window on this day at this place'];
      s.session = 'Sunrise · no window this day';
      s.badge = null;
      return t; })() })),
  mk('S-trip-builder-add-stop', 'Trip builder · Add Stop popover', 1280, 820, [], undefined,
    () => builderWindow({ width: 1280, height: 820, trip: canyonCountry(), overlays: [addStopOverlay()] })),
];
