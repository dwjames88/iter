// Reference implementation: honesty and provenance components (SampleDataLabel, WeatherAttributionView, ProvenanceTag, Warning lines).
import { col, row, text } from '../../../tools/lib/h.mjs';
import { d } from '../../../tools/lib/tokens.mjs';
import { sampleDataLabel, weatherAttribution, provenanceTag, warningLine, ORIGINS } from '../../../tools/lib/lightindex.mjs';
import { note } from '../../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, section, cell, page } from '../../../tools/lib/specimens.mjs';

const frame = (children, o = {}) => page([
  artboardHeader(o.header),
  col({ name: 'Content', gap: 24, align: 'flex-start' },
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' }, o.notes),
    themeBlocks(children)),
], { gap: 24 });

const sampleBoard = () => frame(() => [
  section('Inline', row({ name: 'Inline', gap: 32 }, cell('inline', sampleDataLabel({ style: 'inline' }), { caption: 'flask + "Sample data", type/captionStrong, status/warning' }))),
  section('Banner (full width of its container)', row({ name: 'Banners', gap: 32, align: 'flex-start' },
    cell('banner sidebar width', col({ name: 'Container 224', w: 224 }, sampleDataLabel({ style: 'banner' })), { caption: 'in the sidebar (224 wide, as at ideal sidebar width)' }),
    cell('banner wide', col({ name: 'Container 360', w: 360 }, sampleDataLabel({ style: 'banner' })), { caption: 'wider: text stays on two lines' }))),
], {
  header: { title: 'SampleDataLabel', type: 'SampleDataLabel', file: 'Components/SampleDataLabel.swift', job: 'Says that scores come from made-up weather. Inline in headers, footers and reasons; banner at the bottom of the sidebar.' },
  notes: [
    note({ title: 'Deviation 2: can appear twice on a screen', body: 'The inline label can show in a header and again in the attribution footer (Explore, Scout, Settings > Weather). The rule says once per screen. Reproduced as built.' }),
    note({ title: 'Banner anatomy', body: 'Padding space/sm, radius control, fill background/control, 1 pt status/warning border. Violet always carries the flask icon.' })],
});

const attrBoard = () => frame(() => [
  section('Apple Weather (sample data off)', cell('apple weather', weatherAttribution({ sample: false }), { caption: 'Mark stand-in "Apple Weather Mark (swap)": replace with the combined mark image, 14 pt high, light or dark per appearance' })),
  section('Sample data on', cell('sample', weatherAttribution({ sample: true }), { caption: 'The inline label replaces the whole row' })),
  section('No attribution loaded, sample off', cell('empty', col({ name: 'Empty Footer', h: 14, w: 160 }, text('(nothing is drawn)', { name: 'Hint', font: 'font-size:10px', color: 'text/tertiary' })), { caption: 'No-forecast screens have an empty footer' })),
], {
  header: { title: 'WeatherAttributionView', type: 'WeatherAttributionView', file: 'Components/WeatherAttributionView.swift', job: 'The legal attribution that must appear wherever Apple Weather data appears.' },
  notes: [note({ title: 'Mark is a stand-in', body: 'The real mark is an image from WeatherKit attribution info. It is drawn here as the Apple glyph plus the word Weather, named so it can be swapped.' })],
});

const provBoard = () => frame(() => [
  section('Origins', row({ name: 'Tags', gap: 24 }, ORIGINS.map((o) => cell(`tag ${o}`, provenanceTag(o), { caption: o === 'Scout' ? 'Scout results use Curated or Apple Maps only' : undefined })))),
], {
  header: { title: 'ProvenanceTag', type: 'ProvenanceTag', file: 'Components/ProvenanceTag.swift', job: 'Where a spot came from: a capsule with a hairline outline and no fill.' },
  notes: [note({ title: 'Where it shows', body: 'Explore place card (always), Explore rows (only "Added by you"), Spot header, Saved rows, Scout rows.' })],
});

const warnBoard = () => frame(() => [
  section('Warning (status/warning, caption)', col({ name: 'Warnings', gap: d('space/md') },
    [
      "Out of order: this Sunrise is earlier than the previous stop's Sunset",
      'No Sunset window on this day at this place',
      "Drive doesn't fit: 2 hr, 58 min short",
      "Couldn't find this place's time zone, so using this Mac's.",
      'Couldn’t search Apple Maps for “Horseshoe Bend”.',
    ].map((t, i) => cell(`warning ${i + 1}`, warningLine(t), { width: 360 })))),
  section('Warning (callout, as in Change Dates)', cell('callout', warningLine('2 stops will move to Day 3, the new last day. You can undo this.', { font: 'callout' }), { width: 360 })),
  section('Danger (status/danger): Spot editor validation', cell('danger', warningLine('Enter a latitude between −90 and 90.', { kind: 'danger' }), { width: 360 })),
], {
  header: { title: 'Warning lines', type: 'IssueLine and inline equivalents', file: 'Trips/StopRow.swift', job: 'A warning is violet and always carries an icon. Failures and validation are crimson with an icon.' },
  notes: [note({ title: 'Pattern, not one component', body: 'IssueLine in StopRow.swift; the same pattern is inline in the Change Dates sheet, Spot editor and Explore search error. Validation wording for the danger line is illustrative.' })],
});

export const artboards = [
  { id: 'C-sample-data-label', name: 'SampleDataLabel', section: 'components', width: 1448, height: 544, themes: ['light'], covers: ['Component/SampleDataLabel'], notes: ['Deviation 2: Sample data can appear twice'], render: sampleBoard },
  { id: 'C-weather-attribution', name: 'WeatherAttributionView', section: 'components', width: 1376, height: 584, themes: ['light'], covers: ['Component/WeatherAttributionView'], render: attrBoard },
  { id: 'C-provenance-tag', name: 'ProvenanceTag', section: 'components', width: 1264, height: 408, themes: ['light'], covers: ['Component/ProvenanceTag'], render: provBoard },
  { id: 'C-warning-lines', name: 'Warning lines', section: 'components', width: 1264, height: 664, themes: ['light'], covers: ['Component/Warning lines'], render: warnBoard },
];
