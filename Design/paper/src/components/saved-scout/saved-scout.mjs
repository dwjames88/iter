// D5 components: SavedRow, ScoutResultRow, ScoutProgress (+ helpers shared by the Saved and Scout screens).
// Sources: App/Sources/Saved/SavedView.swift (SavedRow), App/Sources/Scout/ScoutView.swift (ScoutResultRow, running view).
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { divider, button, spinner } from '../../../tools/lib/controls.mjs';
import { lightBadge, provenanceTag, noForecastRing, NO_FORECAST, bandFor } from '../../../tools/lib/lightindex.mjs';
import { note } from '../../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, section, cell, page } from '../../../tools/lib/specimens.mjs';

export const CATEGORY = {
  landscape: ['mountain.2', 'Landscape'], astro: ['sparkles', 'Astro'], architecture: ['building.columns', 'Architecture'],
  street: ['figure.walk', 'Street'], coast: ['water.waves', 'Coast'], wildlife: ['pawprint', 'Wildlife'], desert: ['sun.dust', 'Desert'],
  waterfall: ['drop', 'Waterfall'], forest: ['tree', 'Forest'], urban: ['building.2', 'Urban'],
};

// ---- SavedRow -----------------------------------------------------------------------------------------------
export function savedRow({ name, locality, category = 'landscape', origin = 'Curated', window = 'goldenMorning', score, band, confidence = 'high', tomorrow = false, reason }) {
  const scored = typeof score === 'number';
  return row({ name: `SavedRow / ${name}`.slice(0, 50), align: 'center', gap: d('space/md'), style: { padding: `${d('space/xs')} 0` } },
    row({ name: 'Category Slot', align: 'center', justify: 'center', noshrink: true, w: 32 }, icon(CATEGORY[category][0], { size: 20, color: 'text/secondary' })),
    col({ name: 'Name and Place', gap: d('space/xxs'), grow: true },
      text(name, { name: 'Name', font: font('headline'), color: 'text/primary' }),
      row({ name: 'Locality and Origin', align: 'center', gap: d('space/sm') },
        text(locality || CATEGORY[category][1], { name: 'Locality', font: font('subheadline'), color: 'text/secondary' }),
        provenanceTag(origin))),
    col({ name: 'Light', align: 'flex-end', gap: d('space/xxs'), noshrink: true },
      scored ? lightBadge({ style: 'compact', window, score, band, confidence }) : lightBadge({ style: 'compact', window, reason }),
      tomorrow ? text('Tomorrow', { name: 'Tomorrow', font: font('caption'), color: 'text/secondary' }) : null,
      !scored && reason ? text(NO_FORECAST[reason].short, { name: 'Reason', font: font('caption'), color: 'text/secondary' }) : null));
}

// A row as the system inset List draws it: selection pill, optional hairline below (inset to the name column).
export function listItem(content, { selected = false, last = false, name = 'List Row', padX = 10 } = {}) {
  return col({ name, style: { flexShrink: 0 } },
    row({ name: 'Row Surface', align: 'center', radius: 10, bg: selected ? canvas('selection/tint') : undefined, style: { padding: `${d('space/xs')} ${padX}px`, flexShrink: 0 } },
      el('div', { name: 'Row Content', style: { display: 'flex', flexDirection: 'column', flex: '1 1 0', minWidth: 0 } }, content)),
    last ? null : el('div', { name: 'Separator', style: { paddingLeft: 54, display: 'flex', flexDirection: 'column' } }, divider()));
}

export const SAVED_SAMPLE = [
  { name: 'Back field at Lone Pine', locality: 'Lone Pine, CA', category: 'landscape', origin: 'Added by you', window: 'goldenMorning', score: 87, tomorrow: true },
  { name: 'Mesa Arch', locality: 'Canyonlands National Park, UT', category: 'desert', origin: 'Curated', window: 'goldenMorning', score: 68, tomorrow: true },
  { name: 'Tunnel View', locality: 'Yosemite National Park, CA', category: 'landscape', origin: 'Curated', window: 'goldenEvening', score: 5, tomorrow: false },
];

// ---- ScoutResultRow ---------------------------------------------------------------------------------------
function capsuleStyle(extra) {
  return { height: 22, padding: `0 10px`, borderRadius: '999px', flexShrink: 0, background: canvas('control/button'), border: `1px solid ${canvas('control/button-stroke')}`, boxShadow: canvas('shadow/button'), ...extra };
}
function smallButton(label, opts = {}) { return button(label, { kind: 'bordered', size: 'small', ...opts }); }
function addToTrip() {
  return row({ name: 'Button / Add to Trip', align: 'center', gap: d('space/xs'), style: capsuleStyle({ padding: `0 ${d('space/sm')} 0 10px` }) },
    icon('plus.circle', { size: 12, color: 'text/primary' }),
    text('Add to Trip', { name: 'Label', font: font('body'), color: 'text/primary' }),
    icon('chevron.down', { size: 8, color: 'text/secondary', weight: 'bold' }));
}

export function scoutResultRow({ name, locality, origin = 'Apple Maps', window = 'goldenMorning', score, band, confidence = 'high', day, drive, why, saved = false, light = 'scored', reason = 'weatherServiceNotEnabled' }) {
  const lightLine = light === 'scored'
    ? row({ name: 'Light Line', align: 'center', gap: d('space/sm') }, lightBadge({ style: 'compact', window, score, band, confidence }), text(day, { name: 'Day', font: font('caption'), color: 'text/secondary' }))
    : light === 'loading'
      ? row({ name: 'Light Line / Loading', align: 'center', gap: d('space/sm') }, spinner(14), text('Checking the forecast', { name: 'Loading', font: font('caption'), color: 'text/secondary' }))
      : row({ name: 'Light Line / No forecast', align: 'center', gap: d('space/sm') }, noForecastRing(16), text(NO_FORECAST[reason].short, { name: 'Reason', font: font('caption'), color: 'text/secondary' }));
  return col({ name: `ScoutResultRow / ${name}`.slice(0, 50), gap: d('space/sm'), style: { padding: `${d('space/sm')} 0` } },
    row({ name: 'Title Line', align: 'flex-start', gap: d('space/sm') },
      col({ name: 'Name and Place', grow: true },
        text(name, { name: 'Name', font: font('headline'), color: 'text/primary' }),
        locality ? text(locality, { name: 'Locality', font: font('subheadline'), color: 'text/secondary' }) : null),
      provenanceTag(origin)),
    row({ name: 'Light and Drive', align: 'center', gap: d('space/md') }, lightLine,
      drive ? row({ name: 'Drive', align: 'center', gap: d('space/xs') }, icon('car', { size: 12, color: 'text/secondary' }), text(drive, { name: 'Drive Time', font: font('caption'), color: 'text/secondary' })) : null),
    why ? col({ name: 'Scout Note', gap: d('space/xxs') },
      row({ name: 'Note Label', align: 'center', gap: d('space/xs') }, icon('sparkles', { size: 11, color: 'text/secondary' }), text("Scout's note", { name: 'Label', font: font('captionStrong'), color: 'text/secondary' })),
      text(why, { name: 'Note', font: font('callout'), color: 'text/primary', wrap: true })) : null,
    row({ name: 'Actions', align: 'center', gap: d('space/sm') }, smallButton('Open'),
      smallButton(saved ? 'Saved' : 'Save', { icon: saved ? 'bookmark.fill' : 'bookmark' }), addToTrip()));
}

export const SCOUT_RESULTS = [
  { name: 'Hoyt Arboretum', locality: 'Portland, OR', origin: 'Apple Maps', score: 87, day: 'Wed, Oct 7, 2026', drive: '12 min drive', why: 'Tall conifers hold fog well into the morning, and the paths run east so the first sun comes through the trunks.', saved: false },
  { name: 'Latourell Falls', locality: 'Corbett, OR', origin: 'Apple Maps', score: 86, day: 'Wed, Oct 14, 2026', drive: '38 min drive', why: 'A tall waterfall in a mossy gorge; overcast keeps the water even.', saved: false },
  { name: 'Tunnel View', locality: 'Yosemite National Park, CA', origin: 'Curated', score: 87, day: 'Thu, Oct 15, 2026', drive: '1 hr, 35 min drive', why: 'Valley fog fills below the viewpoint at first light.', saved: true },
  { name: 'Mesa Arch', locality: 'Canyonlands National Park, UT', origin: 'Curated', score: 87, day: 'Mon, Oct 12, 2026', saved: true },
];

// ---- ScoutProgress ----------------------------------------------------------------------------------------
export const STAGES = ['Understanding your request', 'Searching near Portland, Oregon', 'Checking the drive to Hood River', 'Choosing the best matches'];
export function scoutProgress({ stage = 1, elapsed, stageText }) {
  return col({ name: 'ScoutProgress', align: 'center', gap: d('space/md') },
    spinner(32),
    text(stageText || STAGES[stage], { name: 'Stage', font: font('headline'), color: 'text/primary' }),
    row({ name: 'Stage Capsules', gap: d('space/xs') }, [0, 1, 2, 3].map((i) => el('div', { name: `Capsule ${i + 1}`, style: { width: d('space/xl'), height: d('space/xs'), borderRadius: '999px', background: i <= stage ? c('accent/primary') : c('separator/default'), flexShrink: 0 } }))),
    text(`Step ${stage + 1} of 4`, { name: 'Step', font: font('caption'), color: 'text/secondary' }),
    elapsed ? col({ name: 'Slow Notice', align: 'center', gap: d('space/xxs') },
      text(elapsed, { name: 'Elapsed', font: font('time'), color: 'text/secondary' }),
      text('Still working. A request can take up to a minute.', { name: 'Slow Message', font: font('caption'), color: 'text/secondary' })) : null);
}
export const cancelLarge = () => button('Cancel', { kind: 'bordered', size: 'large' });

// ---- component artboards ----------------------------------------------------------------------------------
const savedBoard = () => {
  const body = () => [
    section('Scored · tomorrow · selected',
      col({ name: 'Scored Rows', w: 640, gap: 0 },
        listItem(savedRow(SAVED_SAMPLE[0]), { selected: true }),
        listItem(savedRow(SAVED_SAMPLE[1])),
        listItem(savedRow(SAVED_SAMPLE[2]), { last: true }))),
    section('No forecast (ring plus short reason)',
      col({ name: 'No Forecast Rows', w: 640, gap: 0 },
        listItem(savedRow({ ...SAVED_SAMPLE[0], score: undefined, reason: 'weatherServiceNotEnabled', tomorrow: false })),
        listItem(savedRow({ ...SAVED_SAMPLE[1], score: undefined, reason: 'serviceFailed' }), { last: true }))),
    section('No locality (category shown instead)',
      col({ name: 'No Locality Row', w: 640 }, listItem(savedRow({ name: 'Roadside pullout', locality: '', category: 'desert', origin: 'Added by you', window: 'goldenEvening', score: 66 }), { last: true }))),
  ];
  return page([
    artboardHeader({ title: 'SavedRow', type: 'SavedRow (private)', file: 'Saved/SavedView.swift', job: 'A kept spot and today\'s light: category symbol, name, locality and origin on the left; a compact LightBadge with "Tomorrow" or the short no-forecast reason on the right.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Anatomy', body: 'Gap space/md, vertical padding space/xs. 32 pt category column (title3, text/secondary), name type/headline, locality type/subheadline plus ProvenanceTag (gap space/sm), trailing column gap space/xxs.' }),
        note({ title: 'Doc vs source', body: 'COMPONENTS.md says gap space/sm between locality and tag and does not name the name-to-locality gap; source uses space/xxs between name and locality line. Source followed.' }),
        note({ title: 'Selection and separators', body: 'The row has no custom selection; the system inset List draws the selection pill and separators. Drawn here for reference.' })),
      themeBlocks(body)),
  ], { gap: 24 });
};

const scoutRowBoard = () => {
  const body = () => [
    section('Scored · with note · unsaved',
      col({ name: 'Scored', w: 400 }, listItem(scoutResultRow(SCOUT_RESULTS[0]), { selected: true, last: true, padX: 10 }))),
    section('Scored · saved · no note',
      col({ name: 'Saved No Note', w: 400 }, listItem(scoutResultRow(SCOUT_RESULTS[3]), { last: true }))),
    section('No forecast',
      col({ name: 'No Forecast', w: 400 }, listItem(scoutResultRow({ ...SCOUT_RESULTS[1], light: 'noForecast', reason: 'weatherServiceNotEnabled' }), { last: true }))),
    section('Checking the forecast',
      col({ name: 'Loading', w: 400 }, listItem(scoutResultRow({ ...SCOUT_RESULTS[2], light: 'loading' }), { last: true }))),
  ];
  return page([
    artboardHeader({ title: 'ScoutResultRow', type: 'ScoutResultRow (private)', file: 'Scout/ScoutView.swift', job: 'One suggested place: its light and drive, the scout\'s own note (always labelled), and Open, Save and Add to Trip.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Light-line states', body: 'Scored: compact badge and the day. No forecast: 16 pt ring and the short reason (tooltip carries the long reason). Loading: small spinner and "Checking the forecast".' }),
        note({ title: 'Never unlabelled', body: 'The model\'s sentence always sits under the "Scout\'s note" sparkle label. Iter\'s own facts (light, drive, origin) are never mixed into it.' }),
        note({ title: 'Buttons', body: 'Small, bordered. Add to Trip is the AddToTripMenu rendered as a button-style menu: plus.circle, label, chevron.' })),
      themeBlocks(body)),
  ], { gap: 24 });
};

const progressBoard = () => {
  const body = () => [
    section('Stages', col({ name: 'Stage Grid', gap: 32 }, [0, 1, 2, 3].map((i) => cell(`stage ${i + 1}`, scoutProgress({ stage: i }), { width: 360 })))),
    section('After 10 seconds', cell('slow', col({ name: 'Slow Stack', align: 'center', gap: d('space/md'), w: 360 }, scoutProgress({ stage: 1, elapsed: '0:14' }), cancelLarge()), { width: 360 })),
  ];
  return page([
    artboardHeader({ title: 'ScoutProgress', type: 'running view', file: 'Scout/ScoutView.swift', job: 'Real progress for a slow request: spinner, the stage in words, four capsules and "Step n of 4", then the elapsed time once it passes 10 seconds.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Anatomy', body: 'Centred stack, gap space/md. Capsules are 24 x 4 (space/xl by space/xs), accent up to and including the current stage, separator/default after. The place in stages 2 and 3 comes from the request ("Searching near Portland, Oregon"; "Checking the drive to <place>").' }),
        note({ title: 'Static spinner', body: 'The system spinner is drawn as one frame.' })),
      themeBlocks(body)),
  ], { gap: 24 });
};

export const artboards = [
  { id: 'C-saved-row', name: 'SavedRow', section: 'components', width: 1560, height: 880, themes: ['light'], covers: ['Component/SavedRow'], notes: ['Doc vs source: name-to-locality gap'], render: savedBoard },
  { id: 'C-scout-result-row', name: 'ScoutResultRow', section: 'components', width: 1160, height: 1120, themes: ['light'], covers: ['Component/ScoutResultRow'], render: scoutRowBoard },
  { id: 'C-scout-progress', name: 'ScoutProgress', section: 'components', width: 1160, height: 1144, themes: ['light'], covers: ['Component/ScoutProgress'], render: progressBoard },
];
