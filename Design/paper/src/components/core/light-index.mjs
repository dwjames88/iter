// Reference implementation: component artboards for the Light Index family (LightBadge, ScoreChip, NoForecastRing, ConfidenceMark).
// Copy this file's structure: one artboard per component, light and dark blocks side by side, labelled specimens, notes for deviations.
import { col, row, text, el, svgEl, raw } from '../../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../../tools/lib/tokens.mjs';
import { lightBadge, scoreChip, noForecastRing, confidenceMark, BAND_KEYS, BANDS, WINDOWS, CONFIDENCE, NO_FORECAST, bandFor } from '../../../tools/lib/lightindex.mjs';
import { note } from '../../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, section, gridRow, cell, colHeaders, page } from '../../../tools/lib/specimens.mjs';

const SCORE = { poor: 22, fair: 48, good: 66, great: 81, epic: 94 };
const RANGE = { poor: '10–34', fair: '38–58', good: '55–75', great: '72–100', epic: '84–100' };
const CONF = ['high', 'medium', 'low'];
const cap = (s) => s[0].toUpperCase() + s.slice(1);

const HEAD = { title: 'LightBadge', type: 'LightBadge', file: 'Components/LightBadge.swift', job: 'One Light Index window: the window name always beside the number, the band word and confidence; or a hollow dashed ring and the reason when there is no forecast.' };
const NOTES_A = () => [
  note({ title: 'Deviation 1: no band word in compact', body: 'Compact badges (map pins, Saved, Scout and Add Stop rows) show the number and short window name but not the band word. The VoiceOver label includes it. Reproduced as built; the design pass decides on a word, a glyph or nothing.' }),
  note({ title: 'Deviation 7: literal opacity 0.85', body: 'Low confidence fades the whole chip to 85% opacity. 0.85 is a literal in LightBadge.swift, not a token (here --opacity-low-confidence in canvas-tokens.json).' }),
  note({ title: 'Chip width', body: 'The horizontal padding (2 x 4) sits outside the min-width frame (28 regular, 18 compact), so chips are 36 and 26 pt wide at minimum. Built size is drawn.' }),
  note({ title: 'Rule: never alone', body: 'Every score names its window. No forecast is a ring and a reason, never a number and never a low score.' })];
const boardOf = (title, notes, body) => page([
  artboardHeader({ ...HEAD, title }),
  col({ name: 'Content', gap: 24, align: 'flex-start' }, row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' }, notes), themeBlocks(body)),
], { gap: 24 });

const lightBadgeSmall = () => boardOf('LightBadge · Compact and Regular', NOTES_A(), () => [
  ...['compact', 'regular'].map((style) => section(`${cap(style)} · scored`,
    colHeaders(['High confidence', 'Medium confidence', 'Low (85% opacity)'], { widths: [190, 190, 190] }),
    BAND_KEYS.map((b) => gridRow(BANDS[b].name, CONF.map((cf) => cell(`${style} ${b} ${cf}`, lightBadge({ style, window: 'goldenEvening', score: SCORE[b], band: b, confidence: cf }), { width: 190 })), { gap: 0 })))),
  section('Windows (good band, high confidence)',
    colHeaders(['Compact', 'Regular'], { widths: [190, 220] }),
    Object.keys(WINDOWS).map((k) => gridRow(WINDOWS[k].short, [
      cell(`compact ${k}`, lightBadge({ style: 'compact', window: k, score: 66, band: 'good' }), { width: 190 }),
      cell(`regular ${k}`, lightBadge({ style: 'regular', window: k, score: 66, band: 'good' }), { width: 220 }),
    ], { gap: 0 }))),
]);

const lightBadgeLarge = () => boardOf('LightBadge · Large, Sample, No forecast', [
  note({ title: 'Large badge', body: 'Headline "Sunset · 87", band word with "Likely 72–100" when the range is not a single value, then confidence. The 64 pt chip uses radius card and type/score/large.' }),
  note({ title: 'No forecast', body: 'Compact and regular never show a reason; only the large badge prints the sentence. Short forms ("Weather off", "Offline", "Too far ahead", "Passed", "Loading") are used in rows.' })], () => [
  section('Large · scored',
    colHeaders(['High confidence', 'Medium · with range', 'Low · with range'], { widths: [230, 230, 230] }),
    BAND_KEYS.map((b) => gridRow(BANDS[b].name, [
      cell(`large ${b} high`, lightBadge({ style: 'large', window: 'goldenEvening', score: SCORE[b], band: b, confidence: 'high' }), { width: 230 }),
      cell(`large ${b} medium`, lightBadge({ style: 'large', window: 'goldenEvening', score: SCORE[b], band: b, confidence: 'medium', range: RANGE[b] }), { width: 230 }),
      cell(`large ${b} low`, lightBadge({ style: 'large', window: 'goldenEvening', score: SCORE[b], band: b, confidence: 'low', range: RANGE[b] }), { width: 230 }),
    ], { gap: 0 }))),
  section('Sample data (showsSource)',
    row({ name: 'Sample Row', gap: 32, wrap: true },
      cell('regular sample', lightBadge({ style: 'regular', window: 'goldenEvening', score: 81, band: 'great', sample: true })),
      cell('large sample', lightBadge({ style: 'large', window: 'goldenEvening', score: 81, band: 'great', range: '72–100', confidence: 'medium', sample: true })))),
  section('No forecast',
    row({ name: 'No Forecast Short', gap: 32, wrap: true },
      cell('compact no forecast', lightBadge({ style: 'compact', window: 'goldenEvening', reason: 'inThePast' }), { caption: 'compact: ring + short name, no reason' }),
      cell('regular no forecast', lightBadge({ style: 'regular', window: 'goldenEvening', reason: 'inThePast' }), { caption: 'regular: "No forecast", no reason' })),
    col({ name: 'No Forecast Large', gap: d('space/lg') },
      Object.keys(NO_FORECAST).map((r) => cell(`large ${r}`, lightBadge({ style: 'large', window: 'goldenEvening', reason: r }), { caption: `Short form in rows: "${NO_FORECAST[r].short}"` })))),
]);

const chipBoard = () => {
  const widths = (size) => (size === 'large' ? 120 : 110);
  const body = () => [
    ...['compact', 'regular', 'large'].map((size) => section(size[0].toUpperCase() + size.slice(1),
      colHeaders(['Normal', 'Low confidence'], { widths: [widths(size), widths(size)] }),
      BAND_KEYS.map((b) => gridRow(BANDS[b].name, [false, true].map((low) => cell(`${size} ${b}${low ? ' low' : ''}`, scoreChip({ score: SCORE[b], band: b, size, lowConfidence: low }), { width: widths(size) })), { gap: 0 })))),
    section('Widths: one, two and three digits',
      row({ name: 'Digits', gap: 24, align: 'center' }, [7, 72, 100].map((n) => cell(`digits ${n}`, row({ name: `Digits ${n}`, gap: 12, align: 'center' }, scoreChip({ score: n, size: 'compact' }), scoreChip({ score: n, size: 'regular' })))))),
  ];
  return page([
    artboardHeader({ title: 'ScoreChip', type: 'ScoreChip', file: 'Components/LightBadge.swift', job: 'The number on its band fill: one amber hue ordered by lightness, with a hairline so pale bands show against the window.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Deviation 7: literal opacity 0.85', body: 'Low confidence opacity 0.85 is hard-coded in ScoreChip (LightBadge.swift:124).' }),
        note({ title: 'Sizes', body: 'compact 18 high, regular 22 high, large 64 square (radius card). Text uses type/score/badge, medium and large with tabular numerals. Band colours are the Light Index ramp: never green, red or coral.' })),
      themeBlocks(body)),
  ], { gap: 24 });
};

const ringBoard = () => {
  const pin = () => el('div', { name: 'NoForecast Pin Dot', style: { width: 12, height: 12, borderRadius: '999px', background: c('background/content'), border: `${d('stroke/regular')} solid ${c('status/noForecast')}`, flexShrink: 0 } });
  const body = () => [
    section('Diameters',
      row({ name: 'Rings', gap: 32, align: 'flex-end' },
        [[16, 'Scout row (size/icon/medium)'], [18, 'compact (size/badge/heightCompact)'], [22, 'regular, outlook cells (size/badge/height)'], [64, 'large, lead card (size/lightRing/large)']].map(([dia, cap2]) =>
          cell(`ring ${dia}`, noForecastRing(dia), { caption: `${dia} · ${cap2}`, width: 150 })))),
    section('Map-pin variant (inside ExplorePinView)', row({ name: 'Pin Variant', gap: 24 }, cell('pin dot', pin(), { caption: '12 pt dot, fill background/content, 1.5 pt ring' }))),
    section('In context', row({ name: 'Context', gap: 32, wrap: true },
      cell('compact', lightBadge({ style: 'compact', window: 'goldenMorning', reason: 'beyondHorizon' })),
      cell('regular', lightBadge({ style: 'regular', window: 'goldenMorning', reason: 'beyondHorizon' })))),
  ];
  return page([
    artboardHeader({ title: 'NoForecastRing', type: 'NoForecastRing', file: 'Components/LightBadge.swift', job: 'The "no forecast" mark: a hollow circle with a dashed outline, no fill, no number. Unknown is not poor.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Anatomy', body: 'Circle, stroke inside, 1.5 pt in status/noForecast, dashed 4 on / 3 off. Hidden from VoiceOver: the parent speaks the reason.' })),
      themeBlocks(body)),
  ], { gap: 24 });
};

const confBoard = () => {
  const body = () => [
    section('Levels', row({ name: 'Levels', gap: 40, align: 'flex-end' }, ['low', 'medium', 'high'].map((l) =>
      cell(`confidence ${l}`, confidenceMark(l), { caption: `${CONFIDENCE[l].short} · ${CONFIDENCE[l].bars} bar${CONFIDENCE[l].bars > 1 ? 's' : ''}`, width: 90 })))),
    section('In context (regular and large badges)', row({ name: 'Context', gap: 32, wrap: true },
      cell('regular medium', lightBadge({ style: 'regular', window: 'goldenEvening', score: 66, band: 'good', confidence: 'medium' })),
      cell('large low', lightBadge({ style: 'large', window: 'goldenEvening', score: 66, band: 'good', confidence: 'low', range: '55–75' })))),
  ];
  return page([
    artboardHeader({ title: 'ConfidenceMark', type: 'ConfidenceMark', file: 'Components/LightBadge.swift', job: 'How far to trust the score, as three ascending bars: low 1, medium 2, high 3.' }),
    col({ name: 'Content', gap: 24, align: 'flex-start' },
      row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
        note({ title: 'Anatomy', body: 'Three bars 2 pt wide, heights 1/3, 2/3 and full of 14 pt, 1 pt gap, radius 1. Filled bars text/secondary, empty bars separator/default. Accessibility label "High confidence" (Medium, Low).' })),
      themeBlocks(body)),
  ], { gap: 24 });
};

export const artboards = [
  { id: 'C-light-badge', name: 'LightBadge · Compact, Regular', section: 'components', width: 1632, height: 1128, themes: ['light'], covers: ['Component/LightBadge'], notes: ['Deviation 1: no band word in compact', 'Deviation 7: literal opacity 0.85'], render: lightBadgeSmall },
  { id: 'C-light-badge-large', name: 'LightBadge · Large, No forecast', section: 'components', width: 1872, height: 1504, themes: ['light'], covers: ['Component/LightBadge'], render: lightBadgeLarge },
  { id: 'C-score-chip', name: 'ScoreChip', section: 'components', width: 1200, height: 1320, themes: ['light'], covers: ['Component/ScoreChip'], notes: ['Deviation 7: literal opacity 0.85'], render: chipBoard },
  { id: 'C-no-forecast-ring', name: 'NoForecastRing', section: 'components', width: 1564, height: 640, themes: ['light'], covers: ['Component/NoForecastRing'], render: ringBoard },
  { id: 'C-confidence-mark', name: 'ConfidenceMark', section: 'components', width: 1200, height: 552, themes: ['light'], covers: ['Component/ConfidenceMark'], render: confBoard },
];
