// F07 Light Index language: bands, confidence, no-forecast reasons, windows, reasons (factors). Tables come from
// tools/lib/lightindex.mjs (which mirrors LightText.swift / IterCore); colours are tokens; fill and text roles are read
// from tokens.json. Factor sentences are the app's strings (App/Sources/Text/LightText.swift).
import { col, row, text, el } from '../../tools/lib/h.mjs';
import { c, d, canvas, font, dv, currentTheme } from '../../tools/lib/tokens.mjs';
import { icon } from '../../tools/lib/icons.mjs';
import { scoreChip, lightBadge, confidenceMark, noForecastRing, BANDS, BAND_KEYS, WINDOWS, CONFIDENCE, NO_FORECAST, NO_FORECAST_LABEL } from '../../tools/lib/lightindex.mjs';
import { note } from '../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, section, page } from '../../tools/lib/specimens.mjs';
import { colour, contrast, ratio } from './tokdata.mjs';

const cap = (s) => s[0].toUpperCase() + s.slice(1);
const SAMPLE = { poor: 22, fair: 48, good: 66, great: 81, epic: 94 };
const keys = BAND_KEYS;
const rangeOf = (i) => `${BANDS[keys[i]].min}–${i + 1 < keys.length ? BANDS[keys[i + 1]].min - 1 : 100}`;
const FACTORS = [
  ['Low cloud', '29%', 'Low cloud can block the sun at the horizon.', 'Little low cloud: the horizon should be open.'],
  ['Mid and high cloud', '41%', 'A thick upper deck mutes the colour.', 'Mid and high cloud catches colour.'],
  ['Cloud cover', '55%', 'Heavy cloud cover.', 'Cloud cover suits this window.'],
  ['Clear sky', '12%', 'Bare sky: clean light, flat colour.', 'Clear sky for stars.'],
  ['Rain', '10%', 'Rain is likely.', 'Little chance of rain.'],
  ['Visibility', '15 mi', 'Haze or fog cuts visibility.', 'Good visibility.'],
  ['Moonlight', '30%', 'A bright moon is up and washes out stars.', 'Moon down or thin: a dark sky.'],
  ['Wind', '12 mph', 'Strong wind: tripods and reflections suffer.', 'Light wind.'],
  ['Sun direction', '34°', 'The sun is off-axis from the classic view.', 'The sun lines up with the classic view.'],
];
const lab = (t, w, o = {}) => text(t, { name: `Cell / ${t}`.slice(0, 50), font: o.font || font('callout'), color: o.color || 'text/primary', w, noshrink: true, wrap: !!o.wrap, style: o.style });

function signedBar(points) {
  const track = 2 * (dv('size/icon/large') + dv('space/md')) + 4; // 72 wide track per COMPONENTS.md
  const len = Math.max(2, Math.abs(points) * 0.8);
  return row({ name: 'SignedBar', align: 'center', noshrink: true, w: track, style: { height: d('size/confidenceMark'), position: 'relative' } },
    el('div', { name: 'Centre Line', style: { position: 'absolute', left: track / 2, top: 0, width: d('stroke/thin'), height: '100%', background: c('separator/default') } }),
    el('div', { name: 'Bar', style: { position: 'absolute', top: 3, height: d('space/sm'), width: len, left: points >= 0 ? track / 2 : track / 2 - len, background: points >= 0 ? c('accent/primary') : c('status/warning') } }));
}

function body() {
  return [
    section('Bands: one amber hue, ordered by lightness', col({ name: 'Bands', gap: d('space/sm') },
      keys.map((b, i) => {
        const fill = colour(`light/ramp/${b}`), ink = colour(`light/rampText/${b}`);
        return row({ name: `Band / ${b}`, align: 'center', gap: d('space/lg') },
          scoreChip({ score: SAMPLE[b], band: b, size: 'large' }),
          col({ name: 'Band Text', gap: 0, w: 120, noshrink: true }, text(BANDS[b].name, { name: 'Band Word', font: font('headline'), color: 'text/primary' }), text(`Score ${rangeOf(i)}`, { name: 'Score Range', font: font('callout'), color: 'text/secondary' })),
          scoreChip({ score: SAMPLE[b], band: b, size: 'regular' }), scoreChip({ score: SAMPLE[b], band: b, size: 'compact' }),
          col({ name: 'Tokens', gap: 0 }, text(`light/ramp/${b} · light/rampText/${b}`, { name: 'Token Names', font: font('captionStrong'), color: 'text/primary' }),
            text(`Text on fill ${(() => { const dk = currentTheme() === 'dark'; return ratio(contrast(dk ? fill.dark : fill.light, dk ? ink.dark : ink.light)); })()}`, { name: 'Contrast', font: font('caption'), color: 'text/secondary' })));
      }))),
    section('Windows', col({ name: 'Windows', gap: d('space/sm') },
      row({ name: 'Window Headers', gap: d('space/lg') }, lab('', 28), lab('Name', 160, { font: font('captionStrong'), color: 'text/secondary' }), lab('Short (pins)', 100, { font: font('captionStrong'), color: 'text/secondary' }), lab('Symbol', 160, { font: font('captionStrong'), color: 'text/secondary' }), lab('Badge', 200, { font: font('captionStrong'), color: 'text/secondary' })),
      Object.entries(WINDOWS).map(([k, w]) => row({ name: `Window / ${w.name}`, align: 'center', gap: d('space/lg') },
        row({ name: 'Icon Slot', w: 28, noshrink: true, align: 'center', justify: 'center' }, icon(w.symbol, { size: 18, color: 'text/primary' })),
        lab(w.name, 160, { font: font('bodyEmphasis') }), lab(w.short, 100), lab(w.symbol, 160, { color: 'text/secondary' }),
        lightBadge({ style: 'regular', window: k, score: SAMPLE.good, band: 'good' }))))),
    section('Confidence', row({ name: 'Confidence', gap: 40, align: 'flex-start' },
      ['low', 'medium', 'high'].map((l) => col({ name: `Confidence / ${l}`, gap: d('space/xs'), w: 190, noshrink: true }, confidenceMark(l), text(CONFIDENCE[l].name, { name: 'Name', font: font('bodyEmphasis'), color: 'text/primary' }), text(`${CONFIDENCE[l].bars} bar${CONFIDENCE[l].bars > 1 ? 's' : ''}${l === 'low' ? ' · chip at 85% opacity' : ''}`, { name: 'Bars', font: font('callout'), color: 'text/secondary' }))))),
    section('No forecast: a ring and a reason, never a number', col({ name: 'No Forecast', gap: d('space/sm') },
      row({ name: 'Reason Headers', gap: d('space/lg') }, lab('', 30), lab('Short (rows)', 110, { font: font('captionStrong'), color: 'text/secondary' }), lab('Long (large surfaces)', 520, { font: font('captionStrong'), color: 'text/secondary' })),
      Object.entries(NO_FORECAST).map(([k, r]) => row({ name: `Reason / ${k}`, align: 'center', gap: d('space/lg') },
        row({ name: 'Ring Slot', w: 30, noshrink: true, justify: 'center' }, noForecastRing(22)),
        lab(r.short, 110, { font: font('bodyEmphasis') }), lab(r.long, 520, { wrap: true, color: 'text/secondary' }))),
      row({ name: 'No Forecast Badges', gap: 28, align: 'center', style: { paddingTop: 8 } },
        lightBadge({ style: 'large', window: 'goldenEvening', reason: 'beyondHorizon' }), text(`“${NO_FORECAST_LABEL}”`, { name: 'Label', font: font('callout'), color: 'text/secondary' })))),
    section('Reasons: why the score is what it is', col({ name: 'Reasons', gap: d('space/sm') },
      row({ name: 'Factor Headers', gap: d('space/lg') }, lab('Factor', 130, { font: font('captionStrong'), color: 'text/secondary' }), lab('Value', 64, { font: font('captionStrong'), color: 'text/secondary' }), lab('Hurts', 72, { font: font('captionStrong'), color: 'text/secondary' }), lab('Helps', 72, { font: font('captionStrong'), color: 'text/secondary' }), lab('When it hurts · when it helps', 310, { font: font('captionStrong'), color: 'text/secondary' })),
      FACTORS.map(([n, v, hurts, helps], i) => row({ name: `Factor / ${n}`, align: 'center', gap: d('space/lg') },
        lab(n, 130, { font: font('bodyEmphasis') }), lab(v, 64, { font: font('time'), color: 'text/secondary' }), signedBar(-(8 + i * 3)), signedBar(10 + i * 4),
        col({ name: 'Sentences', gap: 0, w: 310, noshrink: true }, text(hurts, { name: 'Hurts', font: font('callout'), color: 'text/primary', wrap: true }), text(helps, { name: 'Helps', font: font('callout'), color: 'text/secondary', wrap: true })))))),
  ];
}

function board() {
  return page([
    artboardHeader({ title: 'Light Index language', type: 'LightBadge · LightText', file: 'App/Sources/Components/LightBadge.swift · App/Sources/Text/LightText.swift', job: 'A score is always a window and a number and a band word; confidence is shown; no forecast is a ring and a reason. Colour never carries the band alone.' }),
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Never green, never coral', body: 'The ramp is amber. Coral is the accent and the route; warnings are violet, failure is raspberry. Unknown is neutral grey, never a low score.', width: 360 }),
      note({ title: 'Thresholds', body: 'Band edges live in IterCore (Light.swift), not in tokens: Poor below 40, Fair 40, Good 58, Great 74, Epic 88. The ranges shown are computed from those minimums.', width: 360 }),
      note({ title: 'Sample bars', body: 'Signed bars use illustrative points; the real ones scale to the largest factor (minimum 10). Colour follows the effect: accent for helps, status/warning for hurts, with the signed number as the other cue.', width: 360 })),
    themeBlocks(body, { gap: 24, width: 800 }),
  ], { gap: 24, pad: 40 });
}

export const artboards = [
  { id: 'F07-light-index', name: 'F07 Light Index language', section: 'foundations', width: 1736, height: 1824, themes: ['light'], covers: [], render: board },
];
