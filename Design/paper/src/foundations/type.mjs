// F02 Type scale: every type token. Family, size, weight, line height and the text style are read from
// Design/tokens.json and tools/canvas-tokens.json (line heights) at build time; only the sample words are authored.
import { col, row, text, el } from '../../tools/lib/h.mjs';
import { c, d, canvas, font, withTheme } from '../../tools/lib/tokens.mjs';
import { note } from '../../tools/lib/chrome.mjs';
import { artboardHeader, page } from '../../tools/lib/specimens.mjs';
import { typography, canvasData } from './tokdata.mjs';

const SAMPLE = {
  'type/title/spot': 'Horseshoe Bend',
  'type/title/section': 'When to go',
  'type/headline': 'Sunset · 87',
  'type/body': 'Be in the right place when the light is right.',
  'type/bodyEmphasis': 'Mid and high cloud',
  'type/callout': 'Mid and high cloud catches colour.',
  'type/subheadline': 'Great · Likely 72–100',
  'type/footnote': 'Updated 09:00',
  'type/caption': 'Sample data',
  'type/captionStrong': 'Sunset',
  'type/score/large': '87',
  'type/score/medium': '66',
  'type/score/badge': '48',
  'type/time': '19:04–19:39',
  'type/timeSmall': '07:21',
};
const WEIGHTS = { 400: 'Regular', 500: 'Medium', 600: 'Semibold', 700: 'Bold' };
const W = { token: 168, sample: 330, spec: 280, job: 360 };

function specimen(name, theme) {
  return withTheme(theme, () => el('div', { name: `Specimen / ${theme}`, style: { width: W.sample, flexShrink: 0, display: 'flex', alignItems: 'center', padding: `${d('space/md')} ${d('space/md')}`, minHeight: 56, background: c('background/window'), border: `${d('stroke/hairline')} solid ${canvas('specimen/border')}`, borderRadius: d('radius/control'), overflow: 'hidden' } },
    text(SAMPLE[name] || 'Horseshoe Bend', { name: 'Sample', font: font(name), color: 'text/primary' })));
}

function typeRow(name) {
  const t = typography[name];
  const lh = canvasData.lineHeights[t.textStyle]?.lineHeight;
  return row({ name: `Style / ${name}`.slice(0, 50), align: 'center', gap: d('space/lg'), pad: [d('space/sm'), 0], style: { borderBottom: `${d('stroke/hairline')} solid ${canvas('specimen/border')}` } },
    text(name, { name: 'Token Name', font: font('bodyEmphasis'), color: canvas('label/title'), w: W.token, noshrink: true }),
    specimen(name, 'light'), specimen(name, 'dark'),
    col({ name: 'Spec', gap: d('space/xxs'), w: W.spec, noshrink: true },
      text(`${t.family} · ${t.size} / ${lh ?? '?'} px`, { name: 'Family Size Leading', font: font('time'), color: canvas('label/title') }),
      text(`${WEIGHTS[t.weight] || t.weight} ${t.weight} · ${t.design}${t.digits ? ' · tabular digits' : ''}`, { name: 'Weight Design', font: font('callout'), color: canvas('label/body') }),
      text(`Text style: ${t.textStyle}`, { name: 'Text Style', font: font('callout'), color: canvas('label/body') })),
    text(t.desc, { name: 'Job', font: font('callout'), color: canvas('label/title'), wrap: true, grow: true }));
}

function typeBoard() {
  const names = Object.keys(typography);
  const head = (label, w, extra) => text(label, { name: `Column / ${label}`, font: font('captionStrong'), color: canvas('label/body'), w, noshrink: true, ...extra });
  return page([
    artboardHeader({ title: 'Type scale', type: 'IterFont', file: 'Packages/IterKit/Sources/IterDesign/IterFont.swift · Design/tokens.json', job: `${Object.keys(typography).length} semantic styles on system fonts: SF Pro for everything, New York (serif) for place names. Each maps to a system text style, so system sizing still applies. Monospaced digits for scores and times.` }),
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Deviation 5: serif beyond place names', body: 'type/title/spot (New York) is also used for trip names and the empty-state headline, not only for place names.', width: 360 }),
      note({ title: 'Line heights', body: 'Line heights are not in tokens.json; they are Apple\'s macOS leading for each text style (tools/canvas-tokens.json) and are used for the px line-height here.', width: 360 }),
      note({ title: 'Families', body: 'Sans is SF Pro with SF Pro Text, -apple-system and system-ui as fallbacks; serif is New York with ui-serif. System fonts only, no web fonts.', width: 360 })),
    col({ name: 'Type Styles', gap: 0 },
      row({ name: 'Column Headers', align: 'flex-end', gap: d('space/lg'), pad: [0, 0, d('space/xs'), 0], style: { borderBottom: `${d('stroke/hairline')} solid ${canvas('specimen/border')}` } },
        head('Token', W.token), head('Light', W.sample), head('Dark', W.sample), head('Family · size / leading', W.spec), text('Job', { name: 'Column / Job', font: font('captionStrong'), color: canvas('label/body'), grow: true })),
      names.map(typeRow)),
  ], { gap: 28, pad: 40 });
}

export const artboards = [
  { id: 'F02-type-scale', name: 'F02 Type scale', section: 'foundations', width: 1640, height: 1424, themes: ['light'], covers: [], notes: ['Deviation 5: serif beyond place names'], render: typeBoard },
];
