// Reference implementation: screen artboards. The Shell: sidebar and detail (All Trips selected, Canyon Country trip).
// Copy this structure for screens: macWindow({...}) fills the artboard; the detail is built from components; both themes are
// produced by the builder (screens default to ['light','dark']), so render() just calls c()/canvas() and never names a theme.
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, dv, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { divider } from '../../../tools/lib/controls.mjs';
import { macWindow, sidebar, toolbarButton } from '../../../tools/lib/chrome.mjs';
import { tripCard } from '../../components/trips-home/trips-home.mjs';

function allTrips(windowWidth, sidebarWidth) {
  const margin = dv('space/xl'), gap = dv('space/lg'), min = dv('layout/listMin'), ideal = dv('layout/listIdeal');
  const avail = windowWidth - 2 - sidebarWidth - 2 * margin;
  const cols = Math.max(1, Math.floor((avail + gap) / (min + gap)));
  const w = Math.min(ideal, (avail - (cols - 1) * gap) / cols);
  return col({ name: 'All Trips', grow: true, pad: d('space/xl'), style: { background: c('background/window'), minHeight: 0, alignItems: 'flex-start' } },
    row({ name: 'Trip Grid', gap: d('space/lg'), align: 'flex-start', wrap: true },
      tripCard({ name: 'Canyon Country', dates: 'Wed 7 – Sat, Oct 10', counts: '4 days · 6 stops', footer: { kind: 'next', symbol: 'sunset', text: 'Next: Horseshoe Bend · Sunset from 17:25, Wed' }, width: w })));
}

function shell({ width, height, sampleBanner }) {
  return macWindow({
    width, height, title: 'All Trips',
    sidebar: sidebar({ selected: 'trips', trips: ['Canyon Country'], sampleBanner }),
    toolbarTrailing: [toolbarButton('plus')],
    detail: allTrips(width, 240),
  });
}

const snap = (s) => (s === '1280x820' ? 'snapshots/shell-default-{theme}-1280x820.png' : 'snapshots/shell-default-{theme}-960x640.png');
export const artboards = [
  { id: 'S-shell-default', name: 'Shell · Default', section: 'screens', width: 1280, height: 820, snapshot: snap('1280x820'),
    covers: ['Shell: sidebar and detail/Default (sample data on)', 'Shell: sidebar and detail/Trip renamed or created'],
    notes: ['Sidebar rows follow the store, so "Trip renamed or created" is this artboard with a different row label.'], render: () => shell({ width: 1280, height: 820, sampleBanner: true }) },
  { id: 'S-shell-default-960', name: 'Shell · Default', section: 'screens', width: 960, height: 640, snapshot: snap('960x640'),
    covers: ['Shell: sidebar and detail/Default (sample data on)'], duplicateOf: undefined, render: () => shell({ width: 960, height: 640, sampleBanner: true }) },
  { id: 'S-shell-no-banner', name: 'Shell · No sample banner', section: 'screens', width: 1280, height: 820,
    covers: ['Shell: sidebar and detail/No sample banner'], render: () => shell({ width: 1280, height: 820, sampleBanner: false }) },
  { id: 'S-shell-no-banner-960', name: 'Shell · No sample banner', section: 'screens', width: 960, height: 640,
    covers: ['Shell: sidebar and detail/No sample banner'], render: () => shell({ width: 960, height: 640, sampleBanner: false }) },
];
