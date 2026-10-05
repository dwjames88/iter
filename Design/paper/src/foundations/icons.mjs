// F05 Iconography: every SF Symbol the app uses, by name, from tools/symbols/symbols.json + USAGE.json.
import { col, row, text } from '../../tools/lib/h.mjs';
import { c, d, canvas, font, dv, withTheme } from '../../tools/lib/tokens.mjs';
import { icon, hasSymbol } from '../../tools/lib/icons.mjs';
import { note } from '../../tools/lib/chrome.mjs';
import { artboardHeader, section, cell, page } from '../../tools/lib/specimens.mjs';
import fs from 'node:fs';
import path from 'node:path';
import { designDir, dimensions } from './tokdata.mjs';

const USAGE = JSON.parse(fs.readFileSync(path.join(designDir, 'paper', 'tools', 'symbols', 'USAGE.json'), 'utf8'));
const where = (refs) => {
  const set = new Set();
  for (const r of refs) {
    const m = /^App\/Sources\/([^/]+)\//.exec(r);
    if (m) set.add(m[1]); else if (r.startsWith('Packages/')) set.add('IterKit'); else if (r.startsWith('Design/COMPONENTS')) set.add('Components doc'); else if (r.startsWith('Design/SCREENS')) set.add('Screens doc'); else set.add('Design chrome');
  }
  return [...set].join(', ');
};

function glyph(name, theme) {
  return withTheme(theme, () => col({ name: `Tile / ${theme}`, align: 'center', justify: 'center', noshrink: true, w: 56, h: 44, radius: d('radius/control'), bg: c('background/window'), style: { border: `${d('stroke/hairline')} solid ${canvas('specimen/border')}` } },
    icon(name, { size: dimensions['size/icon/large'].value, color: 'text/primary' })));
}

function tileFor(name) {
  const missing = !hasSymbol(name);
  return row({ name: `Symbol / ${name}`.slice(0, 50), align: 'center', gap: d('space/sm'), w: 372, noshrink: true },
    glyph(name, 'light'),
    col({ name: 'Labels', gap: 0, grow: true },
      text(name, { name: 'Symbol Name', font: font('bodyEmphasis'), color: canvas('label/title'), wrap: true, style: { wordBreak: 'break-all' } }),
      text(missing ? 'Stand-in drawn: symbol not exported' : where(USAGE[name]), { name: 'Used In', font: font('caption'), color: canvas('label/body'), wrap: true })));
}

function board() {
  const names = Object.keys(USAGE).sort();
  const sizeRow = ['small', 'medium', 'large'].map((s) => cell(`icon ${s}`, row({ name: `Icon ${s}`, gap: d('space/md'), align: 'center' },
    ['text/primary', 'text/secondary', 'accent/primary'].map((col2) => icon('sunset', { size: dimensions[`size/icon/${s}`].value, color: col2 }))),
  { caption: `size/icon/${s} · ${dimensions[`size/icon/${s}`].value} px` }));
  const isApp = (n) => USAGE[n].some((r) => /^(App\/|Packages\/|Design\/)/.test(r));
  const appNames = names.filter(isApp), chromeNames = names.filter((n) => !isApp(n));
  const missing = names.filter((n) => !hasSymbol(n));
  return page([
    artboardHeader({ title: 'Iconography', type: 'SF Symbols', file: 'tools/symbols/symbols.json · USAGE.json', job: `${names.length} symbols, all system SF Symbols at the symbol's native weight, sized from the three icon tokens and coloured with text, accent or status tokens. Each tile shows the glyph with the part of the app that uses it.` }),
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Colour rule', body: 'Icons that act are accent/primary; informational icons are text/primary or text/secondary; warnings are status/warning and always paired with words. No green anywhere.', width: 360 }),
      missing.length ? note({ title: 'Not exported yet', body: `${missing.join(', ')}: shown as a neutral outlined stand-in named Icon / <symbol>.`, width: 360 }) : null),
    section('Sizes', row({ name: 'Sizes', gap: 48 }, sizeRow)),
    section(`Used by the app (${appNames.length})`, row({ name: 'Symbol Grid / App', wrap: true, gap: 20, align: 'flex-start' }, appNames.map(tileFor))),
    section(`Design-file chrome only (${chromeNames.length})`, row({ name: 'Symbol Grid / Chrome', wrap: true, gap: 20, align: 'flex-start' }, chromeNames.map(tileFor))),
  ], { gap: 28, pad: 40 });
}

export const artboards = [
  { id: 'F05-iconography', name: 'F05 Iconography', section: 'foundations', width: 1640, height: Math.ceil((400 + Math.ceil(Object.keys(USAGE).length / 4) * 64 + 72) / 8) * 8, themes: ['light'], covers: [], render: board },
];
