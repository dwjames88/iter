// F01 Colour: every colour token (name, light, dark, role, system alias), First Light as the single palette, the
// light ramp, and contrast ratios for the text pairs. All values, roles and ratios are read from Design/tokens.json
// when this module is built (see tokdata.mjs); only the list of PAIRS and the group titles are authored here.
import { col, row, text, el } from '../../tools/lib/h.mjs';
import { c, d, canvas, font, withTheme } from '../../tools/lib/tokens.mjs';
import { note } from '../../tools/lib/chrome.mjs';
import { artboardHeader, page } from '../../tools/lib/specimens.mjs';
import { COLOURS, colour, contrast, ratio, hexText } from './tokdata.mjs';

const GROUP_TITLES = {
  accent: 'Accent', selection: 'Selection', focus: 'Focus', route: 'Route', brand: 'Brand', map: 'Map',
  status: 'Status', sky: 'Sky bands', cloud: 'Cloud layers', light: 'Light Index ramp', text: 'Text',
  separator: 'Separator', background: 'Backgrounds',
};
const groupTitle = (g) => GROUP_TITLES[g] || g[0].toUpperCase() + g.slice(1);

// Contrast pairs: [foreground token, background token, rule]. Rules: text 4.5, graphic 3, decoration (no minimum, shown).
const PAIRS = [
  ['text/primary', 'background/window', 'text'], ['text/primary', 'background/control', 'text'],
  ['text/secondary', 'background/window', 'text'], ['text/secondary', 'background/control', 'text'], ['text/secondary', 'background/systemWindow', 'text'],
  ['text/tertiary', 'background/window', 'decoration'],
  ['accent/text', 'background/window', 'text'], ['accent/text', 'background/control', 'text'], ['accent/text', 'background/systemWindow', 'text'],
  ['accent/primary', 'background/window', 'graphic'], ['accent/primary', 'background/control', 'graphic'], ['accent/primary', 'background/systemWindow', 'graphic'],
  ['accent/onAccent', 'accent/emphasis', 'text'], ['accent/onAccent', 'accent/primary', 'graphic'],
  ['text/primary', 'selection/fill', 'text'], ['text/secondary', 'selection/fill', 'text'], ['accent/text', 'selection/fill', 'text'],
  ['focus/ring', 'background/window', 'graphic'], ['route/active', 'background/window', 'graphic'], ['route/inactive', 'background/window', 'graphic'],
  ['map/pin', 'background/window', 'graphic'], ['map/pinInactive', 'background/window', 'graphic'], ['map/sun', 'background/window', 'graphic'],
  ['status/warning', 'background/window', 'text'], ['status/warning', 'background/control', 'text'],
  ['status/danger', 'background/window', 'text'], ['status/danger', 'background/control', 'text'],
  ['status/noForecast', 'background/window', 'graphic'], ['brand/dot', 'background/window', 'logo'],
  ...['poor', 'fair', 'good', 'great', 'epic'].map((b) => [`light/rampText/${b}`, `light/ramp/${b}`, 'text']),
];
const RULE = { text: { min: 4.5, label: 'Text 4.5' }, graphic: { min: 3, label: 'Graphic 3' }, decoration: { min: 0, label: 'Decoration' }, logo: { min: 0, label: 'Logo (exempt)' } };

const hairline = () => `${d('stroke/hairline')} solid ${canvas('specimen/border')}`;
const COLW = { tiles: 200, name: 210, hex: 84, system: 150 };

// A swatch tile: the colour on that theme's paper, with its hairline, so pale colours stay visible.
function tile(token, theme) {
  return withTheme(theme, () => el('div', { name: `Swatch / ${theme}`, style: { width: 96, height: 48, padding: d('space/sm'), display: 'flex', background: c('background/window'), border: hairline(), borderRadius: d('radius/control'), flexShrink: 0 } },
    el('div', { name: 'Colour', style: { flex: '1 1 0', background: c(token), borderRadius: d('radius/badge'), border: `${d('stroke/hairline')} solid ${canvas('specimen/border')}` } })));
}

function tokenRow(e) {
  return row({ name: `Token / ${e.name}`.slice(0, 50), align: 'center', gap: d('space/lg'), pad: [d('space/xs'), 0] },
    row({ name: 'Swatches', gap: d('space/sm'), noshrink: true, w: COLW.tiles }, tile(e.name, 'light'), tile(e.name, 'dark')),
    text(e.name, { name: 'Token Name', font: font('bodyEmphasis'), color: canvas('label/title'), w: COLW.name, noshrink: true }),
    hexText(e.light, { font: font('time'), color: canvas('label/body'), name: 'Light Hex', w: COLW.hex }),
    hexText(e.dark, { font: font('time'), color: canvas('label/body'), name: 'Dark Hex', w: COLW.hex }),
    text(e.system || '', { name: 'System Alias', font: font('callout'), color: canvas('label/body'), w: COLW.system, noshrink: true }),
    text(e.desc, { name: 'Role', font: font('callout'), color: canvas('label/title'), wrap: true, grow: true }));
}

function headerRow() {
  const h = (label, w, extra = {}) => text(label, { name: `Column / ${label}`, font: font('captionStrong'), color: canvas('label/body'), w, noshrink: true, ...extra });
  return row({ name: 'Column Headers', align: 'flex-end', gap: d('space/lg'), pad: [0, 0, d('space/xs'), 0], style: { borderBottom: hairline() } },
    h('Light · Dark', COLW.tiles), h('Token', COLW.name), h('Light', COLW.hex), h('Dark', COLW.hex), h('System alias', COLW.system), text('Role: the one job', { name: 'Column / Role', font: font('captionStrong'), color: canvas('label/body'), grow: true }));
}

function palette() {
  const groups = [];
  for (const e of COLOURS) {
    let g = groups.find((x) => x.key === e.group);
    if (!g) { g = { key: e.group, items: [] }; groups.push(g); }
    g.items.push(e);
  }
  return col({ name: 'Colour Tokens', gap: d('space/xl') },
    headerRow(),
    groups.map((g) => col({ name: `Group / ${groupTitle(g.key)}`.slice(0, 50), gap: 0 },
      text(groupTitle(g.key), { name: 'Group Title', font: font('title/section'), color: canvas('label/title'), style: { paddingBottom: 4 } }),
      g.items.map(tokenRow))));
}

// ---- the light ramp ------------------------------------------------------------------------------------------------
const BANDS = ['poor', 'fair', 'good', 'great', 'epic'];
function ramp() {
  const bandCard = (theme) => withTheme(theme, () => col({ name: `Ramp / ${theme}`, gap: 0, radius: d('radius/card'), clip: true, bg: c('background/window'), style: { border: hairline(), flex: '1 1 0' } },
    text(theme === 'dark' ? 'DARK' : 'LIGHT', { name: 'Appearance', font: font('captionStrong'), color: 'text/secondary', style: { padding: `${d('space/md')} ${d('space/md')} ${d('space/sm')}`, letterSpacing: '0.08em' } }),
    row({ name: 'Ramp Bands', gap: 0, style: { alignItems: 'stretch' } },
      BANDS.map((b) => {
        const fill = colour(`light/ramp/${b}`), ink = colour(`light/rampText/${b}`);
        const ratioV = contrast(theme === 'dark' ? fill.dark : fill.light, theme === 'dark' ? ink.dark : ink.light);
        return col({ name: `Band / ${b}`, align: 'center', justify: 'center', gap: d('space/xs'), style: { flex: '1 1 0', minWidth: 0, height: 116, background: c(`light/ramp/${b}`) } },
          text(b[0].toUpperCase() + b.slice(1), { name: 'Band Word', font: font('headline'), color: `light/rampText/${b}` }),
          text(ratio(ratioV), { name: 'Text Contrast', font: font('timeSmall'), color: `light/rampText/${b}` }));
      }))));
  return col({ name: 'Light Index Ramp', gap: d('space/md') },
    text('Light ramp', { name: 'Section Title', font: font('title/section'), color: canvas('label/title') }),
    row({ name: 'Ramp Cards', gap: d('space/xl') }, bandCard('light'), bandCard('dark')));
}

// ---- contrast --------------------------------------------------------------------------------------------------------
const CW = { sample: 96, pair: 330, num: 76, rule: 100, verdict: 70 };
function contrastTable() {
  const th = (label, w) => text(label, { name: `Column / ${label}`, font: font('captionStrong'), color: canvas('label/body'), w, noshrink: true });
  const sample = (fg, bg, theme) => withTheme(theme, () => el('div', { name: `Sample / ${theme}`, style: { width: 44, height: 28, display: 'flex', alignItems: 'center', justifyContent: 'center', background: c(bg), border: hairline(), borderRadius: d('radius/badge'), flexShrink: 0 } },
    text('Aa', { name: 'Sample Text', font: font('headline'), color: fg })));
  const rows = PAIRS.map(([fg, bg, kind]) => {
    const a = colour(fg), b = colour(bg);
    const lr = contrast(a.light, b.light), dr = contrast(a.dark, b.dark);
    const rule = RULE[kind];
    const verdict = (v) => (rule.min === 0 ? '' : v >= rule.min ? 'Pass' : 'Below');
    const cellN = (v) => text(ratio(v), { name: 'Ratio', font: font('time'), color: canvas('label/title'), w: CW.num, noshrink: true });
    const cellV = (v) => text(verdict(v), { name: 'Verdict', font: font('captionStrong'), color: canvas('label/body'), w: CW.verdict, noshrink: true });
    return row({ name: `Pair / ${fg} on ${bg}`.slice(0, 50), align: 'center', gap: d('space/lg'), pad: [d('space/xs'), 0] },
      row({ name: 'Samples', gap: d('space/sm'), noshrink: true, w: CW.sample }, sample(fg, bg, 'light'), sample(fg, bg, 'dark')),
      text(`${fg} on ${bg}`, { name: 'Pair', font: font('body'), color: canvas('label/title'), w: CW.pair, noshrink: true }),
      cellN(lr), cellV(lr), cellN(dr), cellV(dr),
      text(rule.label, { name: 'Rule', font: font('callout'), color: canvas('label/body'), w: CW.rule, noshrink: true }));
  });
  return col({ name: 'Contrast Pairs', gap: d('space/sm') },
    text('Contrast, computed from the token values', { name: 'Section Title', font: font('title/section'), color: canvas('label/title') }),
    text('WCAG 2.x relative-luminance ratio of each pair, computed when this page is built from the light and dark values above, so it follows the tokens.', { name: 'Method', font: font('callout'), color: canvas('label/body'), wrap: true, style: { maxWidth: 900 } }),
    row({ name: 'Contrast Headers', align: 'flex-end', gap: d('space/lg'), pad: [0, 0, d('space/xs'), 0], style: { borderBottom: hairline() } },
      th('Light · Dark', CW.sample), th('Foreground on background', CW.pair), th('Light', CW.num), th('', CW.verdict), th('Dark', CW.num), th('', CW.verdict), th('Rule', CW.rule)),
    rows);
}

function colourBoard() {
  return page([
    artboardHeader({ title: 'Colour', type: 'IterColor', file: 'Packages/IterKit/Sources/IterDesign/IterColor.swift · Design/tokens.json', job: 'First Light is the palette: espresso ink, cream paper and a coral accent, with one amber ramp for the Light Index. Every token has one job. Values and roles are read from Design/tokens.json when this page is built.' }),
    text('Alpine was retired on 2026-10-05.', { name: 'Retired Line', font: font('callout'), color: canvas('label/body') }),
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Paper has no modes', body: 'Light and dark are two token sets (--color-* and --color-dark-*). Dark artboards reference the dark set, so each pair of swatches below is the same token in both appearances.', width: 320 }),
      note({ title: 'System alias', body: 'Only background/systemWindow aliases a system colour (for snapshot stand-ins of system-drawn surfaces). Everything else is a concrete First Light value.', width: 320 })),
    palette(),
    ramp(),
    contrastTable(),
  ], { gap: 32, pad: 40 });
}

export const artboards = [
  { id: 'F01-colour', name: 'F01 Colour', section: 'foundations', width: 1480, height: 5384, themes: ['light'], covers: [], render: colourBoard },
];
