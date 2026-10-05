// Spot page: all nine states at 1280 x 2600 (the full scroll length of the snapshots), plus Sample at 960 x 640.
// Built from the same component functions as the component artboards (src/components/spot/*).
import { col, row, el } from '../../../tools/lib/h.mjs';
import { d } from '../../../tools/lib/tokens.mjs';
import { c } from '../../../tools/lib/tokens.mjs';
import { macWindow, sidebar, toolbarButton, note, foldMarker } from '../../../tools/lib/chrome.mjs';
import { vm } from '../../components/spot/spot-model.mjs';
import { spotColumn } from '../../components/spot/spot-facts.mjs';

const abs = (o) => ({ position: 'absolute', ...o });

export const NOTES = {
  picker: { title: 'Intent picker: names only', body: 'The source gives each segment a Label with a symbol (sunrise, sunset, sun.horizon, moon.stars), but the macOS segmented control in the snapshots shows the names only. The snapshot is followed.' },
  addToTrip: { title: 'Add to Trip is prominent', body: 'SpotHeaderView sets .buttonStyle(.borderedProminent) on the Add to Trip menu and SCREENS.md says "prominent menu"; the snapshots show it as a plain bordered button. Source followed.' },
  hourlyColour: { title: 'Weather symbols are single-colour here', body: 'The app renders the hourly symbols with .symbolRenderingMode(.multicolor); the symbol export is one weight and one colour, so they are drawn in text/secondary.' },
  fold: { title: 'Dark and light', body: 'Chart colours come from sky/*, cloud/*, map/sun, map/moon and status tokens, so both appearances are the same drawing.' },
  lookAround: { title: 'Look Around is absent', body: 'LookAroundSection only draws live, and only where Apple has imagery. See its component artboard.' },
  zoomArc: { title: 'Arc does not zoom', body: 'Zooming narrows the time domain of the timeline and the hourly strip only. The sky arc draws the whole day (only its markers follow the marker time).' },
  chevron: { title: 'Chevron drawn open', body: 'The expanded row chevron rotates 90 degrees in the app; here it is the chevron.down symbol, because Paper has no rotation to rely on.' },
  explainCopy: { title: 'Explanation text is illustrative', body: 'The explanation comes from Apple Intelligence at run time; this sentence is written only from the listed factors to show the done state.' },
  bestTab: { title: 'Best tab colour', body: 'The outlook Best tag is accent/emphasis (WhenToGoView.swift).' },
  signedBar: { title: 'Signed bars are grey', body: 'Every signed bar is text/secondary: direction is the left or right side, and colour must not read as good or bad.' },
  updated: { title: '"Updated 09:00"', body: 'Shown in the Mac\'s zone (Pacific in the fixtures), so it reads 09:00 although the fetch is 10:00 in Denver.' },
};

function pageWindow({ width, height, m, notes = [], expanded, explain, explainText }) {
  const detailW = width - 2 - 240;
  const colW = Math.min(940, detailW);
  const body = col({ name: 'Spot Page Scroll', grow: true, align: 'center', style: { minHeight: 0, overflow: 'hidden', background: c('background/window') } },
    spotColumn(m, { width: colW, expanded, explain, explainText }));
  const noteRow = notes.length ? el('div', { name: 'Notes', style: abs({ left: 280, top: 2140, display: 'flex', flexDirection: 'row', gap: 12, alignItems: 'flex-start', flexWrap: 'wrap', width: width - 320 }) }, notes.map((k) => note({ ...NOTES[k], width: 280 }))) : null;
  return macWindow({
    width, height, title: m.spot.name,
    sidebar: sidebar({ selected: 'explore', trips: ['Canyon Country'], sampleBanner: m.sample }),
    toolbarLeading: [toolbarButton('chevron.left')],
    detail: body,
    overlays: height > 2300 ? [foldMarker(820), noteRow] : [],
  });
}

const EXPLAIN_TEXT = 'Mid and high cloud covers 29% of the sky, which should catch colour as the sun comes up. Low cloud is only 6%, so the horizon looks open, and visibility is a clear 15 mi. The forecast is about 6 days out, so treat 87 as a guide rather than a promise.';

function state({ id, name, key, o = {}, covers, notes, nk, snapshot, ex }) {
  return { id, name, section: 'screens', width: 1280, height: 2600, snapshot: snapshot ?? `snapshots/spot-${key === 'user' ? 'user' : nk}-{theme}-1280x2600.png`, covers, notes: notes.map((k) => NOTES[k].title),
    render: () => pageWindow({ width: 1280, height: 2600, m: vm(key, o), notes, ...(ex || {}) }) };
}

export const artboards = [
  state({ id: 'S-spot-sample', name: 'Spot page · Sample (scored)', key: 'sample', nk: 'sample', covers: ['Spot page/Sample (scored)'], notes: ['picker', 'addToTrip', 'bestTab', 'hourlyColour', 'updated', 'lookAround'] }),
  state({ id: 'S-spot-window-expanded', name: 'Spot page · Window expanded', key: 'sample', nk: 'window-expanded', o: { expanded: ['goldenMorning'] }, ex: { expanded: ['goldenMorning'] }, covers: ['Spot page/Window expanded'], notes: ['chevron', 'signedBar'] }),
  state({ id: 'S-spot-no-forecast', name: 'Spot page · No forecast', key: 'noforecast', nk: 'noforecast', covers: ['Spot page/No forecast'], notes: [] }),
  state({ id: 'S-spot-failed', name: 'Spot page · Failed', key: 'failed', nk: 'failed', covers: ['Spot page/Failed'], notes: [] }),
  state({ id: 'S-spot-polar', name: 'Spot page · Polar', key: 'polar', nk: 'polar', covers: ['Spot page/Polar'], notes: [] }),
  state({ id: 'S-spot-user', name: 'Spot page · User spot', key: 'user', nk: 'user', covers: ['Spot page/User spot'], notes: [] }),
  state({ id: 'S-spot-loading', name: 'Spot page · Loading forecast', key: 'noforecast', nk: 'noforecast', o: { loading: true }, snapshot: undefined, covers: ['Spot page/Loading forecast'], notes: [] }),
  state({ id: 'S-spot-explanation', name: 'Spot page · Explanation states', key: 'sample', nk: 'window-expanded', o: { expanded: ['goldenMorning'] }, snapshot: undefined, ex: { expanded: ['goldenMorning'], explain: 'done', explainText: EXPLAIN_TEXT }, covers: ['Spot page/Explanation states'], notes: ['explainCopy'] }),
  state({ id: 'S-spot-zoomed', name: 'Spot page · Zoomed timeline', key: 'sample', nk: 'sample', o: { focus: 'sunrise' }, snapshot: undefined, covers: ['Spot page/Zoomed timeline'], notes: ['zoomArc'] }),
  { id: 'S-spot-sample-960', name: 'Spot page · Sample (scored)', section: 'screens', width: 960, height: 2200, snapshot: 'snapshots/spot-sample-{theme}-960x640.png', covers: ['Spot page/Sample (scored)'], notes: [],
    render: () => pageWindow({ width: 960, height: 2200, m: vm('sample') }) },
];
for (const a of artboards) if (a.snapshot === undefined) delete a.snapshot;
