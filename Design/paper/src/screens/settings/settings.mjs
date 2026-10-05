// Screens: Settings window (App/Sources/Settings/SettingsView.swift). 552 pt wide (layout/listMax + space/xxl), four tabs,
// each pane a grouped Form. Drawn as the standard macOS 26 Settings window (tab bar in the toolbar), not the snapshot's
// broken offscreen tab strip.
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { col, row, text, el, svgEl, raw } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { button, popUpButton, stepper, spinner } from '../../../tools/lib/controls.mjs';
import { trafficLights } from '../../../tools/lib/chrome.mjs';
import { sampleDataLabel, weatherAttribution } from '../../../tools/lib/lightindex.mjs';
import { groupedForm } from '../../components/trips-home/trips-home.mjs';

const W = 552;
const TABS = [['general', 'General', 'gearshape'], ['weather', 'Weather', 'cloud.sun'], ['intelligence', 'Apple Intelligence', 'sparkles'], ['about', 'About', 'info.circle']];

function tabBar(selected) {
  return row({ name: 'Tab Bar', justify: 'center', align: 'flex-start', gap: d('space/xs'), style: { padding: '0 16px 10px', flexShrink: 0 } },
    TABS.map(([key, label, sym]) => col({ name: `Tab / ${label}`, align: 'center', gap: 2, noshrink: true,
      style: { padding: '6px 12px', borderRadius: 14, background: key === selected ? canvas('selection/tint') : undefined, minWidth: 64 } },
    icon(sym, { size: 20, color: key === selected ? 'accent/primary' : 'text/secondary' }),
    text(label, { name: 'Tab Label', font: font('caption'), color: key === selected ? 'accent/text' : 'text/secondary' }))));
}

function settingsWindow({ tab, height, body }) {
  const title = TABS.find((t) => t[0] === tab)[1];
  return el('div', { name: 'Settings Window', style: { width: W, height, display: 'flex', flexDirection: 'column', position: 'relative', overflow: 'hidden', borderRadius: 26, background: canvas('sheet/background'), border: `1px solid ${canvas('window/outline')}`, flexShrink: 0 } },
    row({ name: 'Title Bar', align: 'center', style: { height: 44, padding: '0 18px', flexShrink: 0, position: 'relative' } },
      trafficLights(),
      row({ name: 'Title Slot', justify: 'center', grow: true }, text(title, { name: 'Window Title', font: font('title/section', { size: 15, weight: 'semibold', lineHeight: 20 }), color: 'text/primary' })),
      el('div', { name: 'Title Balance', style: { width: 62, flexShrink: 0 } })),
    tabBar(tab),
    col({ name: `Pane / ${title}`, gap: d('space/lg'), grow: true, style: { padding: `${d('space/sm')} ${d('space/lg')} ${d('space/lg')}`, minHeight: 0 } }, body));
}

// ---- row builders ------------------------------------------------------------------------------------------------
const labelIcon = (sym, color, label, name = 'Status') => row({ name, align: 'center', gap: d('space/sm') },
  icon(sym, { size: 16, color }), text(label, { name: 'Label', font: font('body'), color: 'text/primary' }));
const statusRow = (sym, color, label, trailing) => ({ node: row({ name: 'Status Row', align: 'center', justify: 'space-between', gap: d('space/lg'), style: { minHeight: 36, padding: `${d('space/xs')} ${d('space/md')}` } },
  labelIcon(sym, color, label), trailing || null) });
const checkingRow = () => ({ node: row({ name: 'Status Row', align: 'center', gap: d('space/sm'), style: { minHeight: 36, padding: `${d('space/xs')} ${d('space/md')}` } },
  spinner(16), text('Checking Apple Weather…', { name: 'Label', font: font('body'), color: 'text/primary' })) });
const caption = (t) => ({ caption: t });

// ---- panes ---------------------------------------------------------------------------------------------------------
const general = () => [
  groupedForm({ name: 'Section / Show light for', rows: [{ label: 'Show light for', control: popUpButton("Each Spot's Best") }],
    footer: "Which light the scores show on Explore, Saved and in lists. A spot's page always shows every window." }),
  groupedForm({ name: 'Section / Temperature', rows: [{ label: 'Temperature', control: popUpButton('System') }] }),
  groupedForm({ name: 'Section / Set-up time', rows: [{ label: 'Set-up time before a window', control: row({ name: 'Set-up Value', align: 'center', gap: d('space/sm') },
    text('20 min', { name: 'Value', font: font('body', { }), color: 'text/primary', style: { fontVariantNumeric: 'tabular-nums' } }), stepper()) }],
  footer: 'How long before a light window starts that a new stop wants you set up. Each stop can change it.' }),
];

const sampleRows = () => [
  { label: 'Sample Data', control: sampleDataLabel({ style: 'inline' }) },
  caption('Scores use made-up weather, not Apple Weather. Turn this off in the Debug menu.'),
];
const stepRow = (n, node) => row({ name: `Step ${n}`, align: 'flex-start', gap: d('space/sm') },
  text(`${n}.`, { name: 'Step Number', font: font('body'), color: 'text/secondary', style: { fontVariantNumeric: 'tabular-nums' } }), node);
const stepText = (t) => text(t, { name: 'Step Text', font: font('body'), color: 'text/primary', wrap: true, grow: true });
const mono = "ui-monospace, 'SF Mono', Menlo, monospace";

const weatherNotEnabled = () => [
  groupedForm({ header: 'Forecast source', rows: [statusRow('exclamationmark.triangle.fill', 'status/warning', "Weather isn't enabled for this build.")] }),
  groupedForm({ header: 'To turn it on', rows: [{ node: col({ name: 'Steps', gap: d('space/sm'), style: { padding: `${d('space/sm')} ${d('space/md')}` } },
    stepRow(1, stepText('Sign in to Xcode with an Apple Developer Program account.')),
    stepRow(2, stepText('In Certificates, Identifiers & Profiles, enable WeatherKit for the App ID com.dwjames.iter, on both the Capabilities and App Services tabs.')),
    stepRow(3, row({ name: 'Step Text', gap: 4, grow: true, wrap: true },
      text('Build with', { name: 'Step Text', font: font('body'), color: 'text/primary' }),
      text('scripts/run.sh --weatherkit', { name: 'Code', font: font('body', { family: mono }), color: 'text/primary' }),
      text('.', { name: 'Step Text', font: font('body'), color: 'text/primary' })))) }],
  footer: 'Until then, sun and moon times are exact and light scores show “No forecast”.' }),
];
const weatherWorking = () => [
  groupedForm({ header: 'Forecast source', rows: [statusRow('checkmark.circle', 'text/primary', 'Apple Weather is working'), ...sampleRows()] }),
  groupedForm({ header: 'Attribution', rows: [{ node: row({ name: 'Attribution Row', style: { minHeight: 36, padding: `${d('space/sm')} ${d('space/md')}`, alignItems: 'center' } }, weatherAttribution({ sample: true })) }] }),
];
const weatherChecking = () => [groupedForm({ header: 'Forecast source', rows: [checkingRow()] })];
const weatherFailed = () => [
  groupedForm({ header: 'Forecast source', rows: [statusRow('exclamationmark.triangle.fill', 'status/warning', "Couldn't reach Apple Weather.", button('Check Again', { kind: 'bordered', size: 'regular' }))] }),
  groupedForm({ header: 'Detail', rows: [{ node: text('The operation couldn’t be completed. (WeatherDaemon.WDSClientError error 3.)', { name: 'Error Detail', font: font('caption'), color: 'text/secondary', wrap: true, style: { padding: `${d('space/sm')} ${d('space/md')}` } }) }] }),
];

const NOTICES = {
  ready: { sym: 'checkmark.circle', color: 'text/primary', title: 'Apple Intelligence is ready', detail: "Scout understands your request with the model on this Mac, then looks up real places in Apple Maps and Iter's curated list." },
  unavailable: { sym: 'exclamationmark.triangle', color: 'text/primary', title: "Scout isn't available right now", detail: "Apple Intelligence reported it can't run. Searching places in Explore still works." },
  off: { sym: 'sparkles', color: 'text/primary', title: 'Apple Intelligence is turned off', detail: 'Turn on Apple Intelligence in System Settings to describe the place you want in your own words.', action: 'Open System Settings' },
  device: { sym: 'macbook.slash', color: 'text/primary', title: "This Mac can't run Apple Intelligence", detail: "Scout needs Apple Intelligence, which this Mac doesn't support. Searching places in Explore works without it." },
  downloading: { sym: 'arrow.down.circle', color: 'text/primary', title: 'Apple Intelligence is still downloading', detail: 'Scout will be ready when the download finishes. It can take a while the first time.' },
};
const intelligence = (k) => () => {
  const n = NOTICES[k];
  return [groupedForm({ header: 'Scout', rows: [statusRow(n.sym, n.color, n.title), caption(n.detail),
    ...(n.action ? [{ node: row({ name: 'Action Row', style: { padding: `${d('space/sm')} ${d('space/md')}` } }, button(n.action, { kind: 'bordered', size: 'regular' })) }] : [])] })];
};

// About: the Logo image set, 64 pt high. Path data from Brand/logo/symbol-firstlight.svg; fills are tokens (ink and accent).
function logo() {
  const here = path.dirname(fileURLToPath(import.meta.url));
  // Brand/logo renamed the First Light files (symbol-firstlight.svg -> symbol.svg, same artwork) on 2026-10-05; accept either.
  const file = ['symbol-firstlight.svg', 'symbol.svg'].map((n) => path.resolve(here, '../../../../../Brand/logo', n)).find((f) => fs.existsSync(f));
  const paths = [...fs.readFileSync(file, 'utf8').matchAll(/<path[^>]* d="([^"]+)"/g)].map((m) => m[1]);
  const [vbw, vbh] = [274.4, 790];
  return svgEl('Logo', { width: Math.round(64 * vbw / vbh), height: 64, viewBox: `0 0 ${vbw} ${vbh}` },
    raw(`<path d="${paths[0]}" style="fill:${c('text/primary')}"/><path d="${paths[1]}" style="fill:${c('accent/primary')}"/>`));
}
const about = () => [col({ name: 'About', align: 'center', gap: d('space/md'), pad: d('space/xl') },
  logo(),
  text('Iter', { name: 'App Name', font: font('title/section'), color: 'text/primary' }),
  text('Version 0.1 (1)', { name: 'Version', font: font('caption'), color: 'text/secondary' }),
  text('Be in the right place when the light is right.', { name: 'Tagline', font: font('body'), color: 'text/primary' }),
  text("Sun and moon times are calculated on this Mac. Weather is from Apple Weather. Places and drive times are from Apple Maps, alongside Iter's curated spots.", { name: 'Data Sources', font: font('caption'), color: 'text/secondary', wrap: true, align: 'center', style: { maxWidth: 360 } }))];

const mk = (id, name, tab, height, pane, covers, extra = {}) => ({
  id, name, section: 'screens', width: W, height, covers, ...extra,
  render: () => settingsWindow({ tab, height, body: pane() }),
});
const SNAP = (n) => ({ snapshot: `snapshots/settings-${n}-{theme}-1280x820.png` });
const TAB_NOTE = 'The snapshot renders the tab bar as a blank strip with a black blob (offscreen artefact); drawn here as the standard macOS 26 Settings toolbar tabs.';
export const artboards = [
  mk('S-settings-general', 'Settings · General', 'general', 320, general, ['Settings/General'], { ...SNAP('general'), notes: [TAB_NOTE] }),
  mk('S-settings-weather-not-enabled', 'Settings · Weather, not enabled', 'weather', 352, weatherNotEnabled, ['Settings/Weather: not enabled'], { ...SNAP('weather'), notes: [TAB_NOTE] }),
  mk('S-settings-weather-working', 'Settings · Weather, working', 'weather', 336, weatherWorking, ['Settings/Weather: working (with sample data on)'], SNAP('weather-working')),
  mk('S-settings-weather-checking', 'Settings · Weather, checking', 'weather', 208, weatherChecking, ['Settings/Weather: checking']),
  mk('S-settings-weather-failed', 'Settings · Weather, failed', 'weather', 272, weatherFailed, ['Settings/Weather: failed'], { notes: ['Detail text is illustrative: it is the service error string.'] }),
  mk('S-settings-intelligence-unavailable', 'Settings · Intelligence, unavailable', 'intelligence', 248, intelligence('unavailable'), ['Settings/Apple Intelligence: unavailable'], SNAP('intelligence')),
  mk('S-settings-intelligence-ready', 'Settings · Intelligence, ready', 'intelligence', 264, intelligence('ready'), ['Settings/Apple Intelligence: ready, off, device, downloading']),
  mk('S-settings-intelligence-off', 'Settings · Intelligence, off', 'intelligence', 288, intelligence('off'), ['Settings/Apple Intelligence: ready, off, device, downloading']),
  mk('S-settings-intelligence-device', 'Settings · Intelligence, device', 'intelligence', 264, intelligence('device'), ['Settings/Apple Intelligence: ready, off, device, downloading']),
  mk('S-settings-intelligence-downloading', 'Settings · Intelligence, downloading', 'intelligence', 264, intelligence('downloading'), ['Settings/Apple Intelligence: ready, off, device, downloading']),
  mk('S-settings-about', 'Settings · About', 'about', 368, about, ['Settings/About'], SNAP('about')),
];
