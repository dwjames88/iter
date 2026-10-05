// Scout: idle, running, results (+ no forecast, checking the forecast), unavailable x3, no results, guardrail, other failures.
// Source: App/Sources/Scout/ScoutView.swift, ScoutText.swift. The toolbar is empty in the source (title only).
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, dv, canvas, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { divider, button, contentUnavailable } from '../../../tools/lib/controls.mjs';
import { weatherAttribution, sampleDataLabel } from '../../../tools/lib/lightindex.mjs';
import { macWindow, sidebar, mapPlaceholder, note } from '../../../tools/lib/chrome.mjs';
import { listItem, scoutResultRow, scoutProgress, cancelLarge, SCOUT_RESULTS, CATEGORY } from '../../components/saved-scout/saved-scout.mjs';

const W = 1280, H = 820;
const REQUEST = 'Foggy forest spots within two hours of Portland for sunrise';
const SOURCE_LINE = "Places come from Apple Maps and Iter's curated list. Iter checks every place exists; the notes are written by Apple Intelligence.";
const EXAMPLES = ['Foggy forest spots within two hours of Portland for sunrise', 'Waterfalls near Seattle that work on overcast days', 'Dark-sky places near Moab for the Milky Way', 'Coastal sunset viewpoints near Big Sur'];

// ---- request bar --------------------------------------------------------------------------------------------
function requestBar({ value, disabled = false, running = false }) {
  const field = row({ name: 'Request Field', align: 'center', grow: true, style: { height: d('size/control/heightLarge'), padding: `0 ${d('space/sm')}`, borderRadius: d('radius/control'), background: canvas('control/field'), border: `1px solid ${canvas('control/field-stroke')}` } },
    text(value || 'What are you looking for?', { name: value ? 'Value' : 'Placeholder', font: font('body'), color: disabled ? 'text/tertiary' : value ? 'text/primary' : 'text/tertiary' }));
  return col({ name: 'Request Bar', style: { flexShrink: 0 } },
    row({ name: 'Request Row', align: 'center', gap: d('space/sm'), pad: d('space/lg') },
      field,
      running ? button('Cancel', { kind: 'bordered', size: 'large' }) : button('Find Places', { kind: 'prominent', size: 'large', disabled: !value })),
    divider());
}

function win({ detail, bar, sample = true }) {
  return macWindow({ width: W, height: H, title: 'Scout', sidebar: sidebar({ selected: 'scout', sampleBanner: sample }),
    detail: col({ name: 'Scout', grow: true, style: { minHeight: 0 } }, bar || null, detail) });
}

// ---- states -------------------------------------------------------------------------------------------------
const idle = () => col({ name: 'Idle Scroll', grow: true, align: 'center', style: { minHeight: 0 } },
  col({ name: 'Idle Column', gap: d('space/lg'), pad: d('space/lg'), w: dv('layout/listMax') + dv('layout/listMin'), style: { maxWidth: '100%' } },
    text('Describe the scenery, the area and the light. Scout finds real places and shows how the light looks at each.', { name: 'Explanation', font: font('body'), color: 'text/secondary', wrap: true }),
    col({ name: 'Examples', gap: d('space/sm') },
      text('Try', { name: 'Heading', font: font('captionStrong'), color: 'text/secondary' }),
      EXAMPLES.map((e) => row({ name: `Example / ${e}`.slice(0, 50), align: 'center', gap: d('space/sm'), pad: d('space/md'),
        style: { background: c('background/control'), borderRadius: d('radius/card'), border: `${d('stroke/hairline')} solid ${c('separator/default')}` } },
      icon('text.magnifyingglass', { size: 14, color: 'accent/primary' }),
      text(e, { name: 'Example', font: font('body'), color: 'text/primary', grow: true })))),
    text(SOURCE_LINE, { name: 'Source Line', font: font('caption'), color: 'text/tertiary', wrap: true })));

const running = () => col({ name: 'Running', grow: true, align: 'center', justify: 'center', gap: d('space/lg'), style: { minHeight: 0 } },
  scoutProgress({ stage: 1, elapsed: '0:14' }), cancelLarge());

const notice = (symbol, title, description, buttons) => col({ name: 'Notice', grow: true, align: 'center', justify: 'center', style: { minHeight: 0 } },
  contentUnavailable({ symbol, title, description, buttons }));
const explore = () => button('Search Places in Explore');

// results ---------------------------------------------------------------------------------------------------
function marker({ x, y, label, symbol, selected }) {
  const s = selected ? 36 : 28;
  return col({ name: `Marker / ${label}`, align: 'center', gap: d('space/xxs'), style: { position: 'absolute', left: x - 50, top: y - s / 2, width: 100 } },
    row({ name: 'Balloon', align: 'center', justify: 'center', noshrink: true, w: s, h: s, radius: '999px', bg: c('accent/primary'), style: { border: `2px solid ${c('accent/onAccent')}`, boxShadow: canvas('shadow/button') } },
      icon(symbol, { size: selected ? 18 : 14, color: 'accent/onAccent' })),
    text(label, { name: 'Label', font: font('caption', { weight: selected ? 'semibold' : 'regular' }), color: canvas('label/title'), style: { whiteSpace: 'nowrap' } }));
}
const MARKERS = [
  { x: 90, y: 120, label: 'Hoyt Arboretum', symbol: CATEGORY.forest[0], selected: true },
  { x: 180, y: 180, label: 'Latourell Falls', symbol: CATEGORY.waterfall[0] },
  { x: 165, y: 600, label: 'Tunnel View', symbol: CATEGORY.landscape[0] },
  { x: 440, y: 560, label: 'Mesa Arch', symbol: CATEGORY.desert[0] },
];

function results({ rows, sample, attribution }) {
  const listW = dv('layout/listMax');
  return row({ name: 'Results', grow: true, style: { minHeight: 0 } },
    col({ name: 'Result List', w: listW, noshrink: true, style: { minHeight: 0 } },
      row({ name: 'List Header', align: 'baseline', gap: d('space/sm'), style: { padding: `${d('space/sm')} ${d('space/lg')}`, flexShrink: 0 } },
        text(`${rows.length} places for “${REQUEST}”`, { name: 'Count and Request', font: font('subheadline'), color: 'text/secondary', wrap: true, grow: true }),
        sample ? sampleDataLabel() : null),
      col({ name: 'List', grow: true, pad: [0, 10, 0, 10], style: { minHeight: 0, overflow: 'hidden' } },
        rows.map((r, i) => listItem(scoutResultRow(r), { selected: i === 0, last: i === rows.length - 1, padX: 10 }))),
      divider(),
      col({ name: 'List Footer', gap: d('space/xs'), pad: d('space/md'), style: { flexShrink: 0 } },
        text(SOURCE_LINE, { name: 'Source Line', font: font('caption'), color: 'text/secondary', wrap: true }),
        attribution ? weatherAttribution({ sample }) : null)),
    divider({ vertical: true }),
    mapPlaceholder({ grow: true, label: 'Map placeholder: swap for a map image', children: MARKERS.map(marker) }));
}

const SAMPLE_ROWS = SCOUT_RESULTS;
const NOFC_ROWS = SCOUT_RESULTS.map((r) => ({ ...r, light: 'noForecast', reason: 'weatherServiceNotEnabled' }));
const LOADING_ROWS = SCOUT_RESULTS.map((r, i) => (i === 0 ? { ...r, light: 'loading' } : r));

// other failures: four states in a 2x2 grid ------------------------------------------------------------------
function labelled(tag, inner) {
  return col({ name: `Failure / ${tag}`.slice(0, 50), grow: true, align: 'center', gap: d('space/md'), pad: d('space/xl'), style: { minWidth: 0 } },
    text(tag, { name: 'Failure Label', font: font('captionStrong'), color: canvas('note/text'), style: { padding: '1px 6px', borderRadius: 6, background: canvas('note/background'), border: `1px solid ${canvas('note/border')}` } }),
    inner);
}
const failureGrid = () => col({ name: 'Failures', grow: true, style: { minHeight: 0 } },
  row({ name: 'Failure Row 1', grow: true, style: { minHeight: 0 } },
    labelled('Too long', contentUnavailable({ symbol: 'text.line.first.and.arrowtriangle.forward', title: 'That request is too long', description: 'Shorten it to a sentence: the kind of place, the area and the light.', buttons: [button('Try Again', { kind: 'prominent' }), explore()] })),
    divider({ vertical: true }),
    labelled('Unsupported language', contentUnavailable({ symbol: 'character.bubble', title: "Scout doesn't support that language", description: "Apple Intelligence can't read this language yet. Try another language, or search in Explore.", buttons: [button('Try Again', { kind: 'prominent' }), explore()] }))),
  divider(),
  row({ name: 'Failure Row 2', grow: true, style: { minHeight: 0 } },
    labelled('Generic failure', contentUnavailable({ symbol: 'exclamationmark.triangle', title: "Scout couldn't finish", description: 'Something went wrong while searching. Try again, or search places in Explore.', buttons: [button('Try Again', { kind: 'prominent' }), explore()] })),
    divider({ vertical: true }),
    labelled('Unavailable, other reason (no request bar)', contentUnavailable({ symbol: 'exclamationmark.triangle', title: "Scout isn't available right now", description: "Apple Intelligence reported it can't run. Searching places in Explore still works.", buttons: [explore()] }))));

const snap = (n, small) => `snapshots/scout-${n}-{theme}-1280x820.png`;

export const artboards = [
  { id: 'S-scout-idle', name: 'Scout · Idle', section: 'screens', width: W, height: H, snapshot: snap('idle'), covers: ['Scout/Idle'],
    render: () => win({ bar: requestBar({ value: '' }), detail: idle() }) },
  { id: 'S-scout-running', name: 'Scout · Running', section: 'screens', width: W, height: H, snapshot: snap('running'), covers: ['Scout/Running'],
    render: () => win({ bar: requestBar({ value: REQUEST, disabled: true, running: true }), detail: running() }) },
  { id: 'S-scout-results', name: 'Scout · Results', section: 'screens', width: W, height: H, snapshot: snap('results'), covers: ['Scout/Results'],
    notes: ['Map markers: the source draws MapKit Markers tinted accent for every result (selected is larger). The snapshot stand-in draws the selected pin accent and the others grey; the source is followed.'],
    render: () => win({ bar: requestBar({ value: REQUEST }), detail: results({ rows: SAMPLE_ROWS, sample: true, attribution: true }) }) },
  { id: 'S-scout-results-loading', name: 'Scout · Checking the forecast', section: 'screens', width: W, height: H, covers: ['Scout/Checking the forecast'], duplicateOf: 'S-scout-results',
    render: () => win({ bar: requestBar({ value: REQUEST }), detail: results({ rows: LOADING_ROWS, sample: true, attribution: true }) }) },
  { id: 'S-scout-results-no-forecast', name: 'Scout · Results, no forecast', section: 'screens', width: W, height: H, snapshot: snap('results-noforecast'), covers: ['Scout/Results, no forecast'], duplicateOf: 'S-scout-results',
    render: () => win({ bar: requestBar({ value: REQUEST }), detail: results({ rows: NOFC_ROWS, sample: false, attribution: false }), sample: false }) },
  { id: 'S-scout-unavailable-off', name: 'Scout · Apple Intelligence off', section: 'screens', width: W, height: H, snapshot: snap('unavailable-not-enabled'), covers: ['Scout/Unavailable: Apple Intelligence off'],
    render: () => win({ detail: notice('sparkles', 'Apple Intelligence is turned off', 'Turn on Apple Intelligence in System Settings to describe the place you want in your own words.', [button('Open System Settings', { kind: 'prominent' }), explore()]) }) },
  { id: 'S-scout-unavailable-device', name: 'Scout · Unavailable, device', section: 'screens', width: W, height: H, snapshot: snap('unavailable-device'), covers: ['Scout/Unavailable: device'],
    render: () => win({ detail: notice('macbook.slash', "This Mac can't run Apple Intelligence", "Scout needs Apple Intelligence, which this Mac doesn't support. Searching places in Explore works without it.", [explore()]) }) },
  { id: 'S-scout-unavailable-downloading', name: 'Scout · Unavailable, downloading', section: 'screens', width: W, height: H, snapshot: snap('unavailable-downloading'), covers: ['Scout/Unavailable: downloading'],
    render: () => win({ detail: notice('arrow.down.circle', 'Apple Intelligence is still downloading', 'Scout will be ready when the download finishes. It can take a while the first time.', [explore()]) }) },
  { id: 'S-scout-no-results', name: 'Scout · No results', section: 'screens', width: W, height: H, snapshot: snap('no-results'), covers: ['Scout/No results'],
    render: () => win({ bar: requestBar({ value: REQUEST }), detail: notice('magnifyingglass', 'Nothing matched', 'Nothing matched; try a wider area or a simpler description.', [button('Try Again', { kind: 'prominent' }), explore()]) }) },
  { id: 'S-scout-guardrail', name: 'Scout · Guardrail', section: 'screens', width: W, height: H, snapshot: snap('guardrail'), covers: ['Scout/Guardrail'],
    render: () => win({ bar: requestBar({ value: REQUEST }), detail: notice('hand.raised', "Scout can't help with that request", 'Apple Intelligence declined it. Try describing the kind of scenery and the area you want.', [button('Try Again', { kind: 'prominent' }), explore()]) }) },
  { id: 'S-scout-other-failures', name: 'Scout · Other failures', section: 'screens', width: W, height: H, covers: ['Scout/Other failures'],
    notes: ['The four "other failure" empty states share one layout, so they are shown together in a 2 x 2 grid with a label each (labels are annotations, not UI). In the app each fills the content area alone, with the request bar shown except for "unavailable".'],
    render: () => win({ bar: requestBar({ value: REQUEST }), detail: failureGrid() }) },
];
