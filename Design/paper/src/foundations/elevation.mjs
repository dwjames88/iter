// F04 Elevation & materials. The app is flat: First Light paper, cards with a hairline, and system materials/shadows
// for what floats. Names, roles and (for the fills) the colours are read from tools/canvas-tokens.json via the canvas()
// helper at build time; nothing is typed in.
import { col, row, text, el } from '../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../tools/lib/tokens.mjs';
import { note } from '../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, section, page } from '../../tools/lib/specimens.mjs';
import { canvasData } from './tokdata.mjs';

const desc = (k) => canvasData.colors[k]?.$description || '';
const hair = () => `${d('stroke/hairline')} solid ${c('separator/default')}`;

// A busy ground so translucency is visible: two token colours split diagonally.
const ground = (children, w = 300, h = 120) => el('div', { name: 'Backdrop', style: { position: 'relative', width: w, height: h, flexShrink: 0, display: 'flex', borderRadius: d('radius/card'), overflow: 'hidden', background: `linear-gradient(120deg, ${c('sky/blueHour')} 0 40%, ${c('light/ramp/good')} 40% 70%, ${c('route/active')} 70%)` } }, children);

function surface(label, key, shadowKey, o = {}) {
  const fill = canvas(key);
  const card = el('div', { name: `Surface / ${label}`.slice(0, 50), style: { position: 'absolute', left: 24, top: 20, right: 24, bottom: 20, display: 'flex', alignItems: 'center', justifyContent: 'center', background: fill, border: o.stroke ? `1px solid ${canvas(o.stroke)}` : undefined, borderRadius: d(o.radius || 'radius/panel'), boxShadow: shadowKey ? canvas(shadowKey) : undefined } },
    text(label, { name: 'Label', font: font('callout'), color: 'text/primary' }));
  return col({ name: `Specimen / ${label}`.slice(0, 50), gap: d('space/xs'), w: 300, noshrink: true },
    ground(card),
    text(`${key}${shadowKey ? ' + ' + shadowKey : ''}`, { name: 'Tokens', font: font('captionStrong'), color: 'text/primary' }),
    text(desc(key) || desc(shadowKey), { name: 'Role', font: font('caption'), color: 'text/secondary', wrap: true }));
}

function flat(label, bg, strokeTok) {
  return col({ name: `Specimen / ${label}`.slice(0, 50), gap: d('space/xs'), w: 300, noshrink: true },
    el('div', { name: 'Paper', style: { width: 300, height: 120, display: 'flex', alignItems: 'center', justifyContent: 'center', background: c('background/window'), borderRadius: d('radius/card'), border: hair() } },
      el('div', { name: `Card / ${label}`.slice(0, 50), style: { width: 220, height: 72, display: 'flex', alignItems: 'center', justifyContent: 'center', background: c(bg), borderRadius: d('radius/card'), border: `${d('stroke/hairline')} solid ${c(strokeTok)}` } },
        text(label, { name: 'Label', font: font('callout'), color: 'text/primary' }))),
    text(`${bg} · ${d('stroke/hairline') && 'stroke/hairline'} ${strokeTok}`, { name: 'Tokens', font: font('captionStrong'), color: 'text/primary' }));
}

function body() {
  return [
    section('Flat: paper and cards', row({ name: 'Flat', gap: d('space/xl'), wrap: true },
      flat('Card on paper', 'background/control', 'separator/default'),
      flat('List on paper', 'background/content', 'separator/default'))),
    section('Materials (what floats over the map)', row({ name: 'Materials', gap: d('space/xl'), wrap: true },
      surface('regularMaterial', 'material/regular', 'shadow/material', { stroke: 'material/stroke' }),
      surface('bar material', 'material/bar', null, { stroke: 'material/stroke', radius: 'radius/control' }))),
    section('Sheets, menus and popovers', row({ name: 'Floating', gap: d('space/xl'), wrap: true },
      surface('Sheet', 'sheet/background', 'shadow/sheet', { radius: 'radius/panel' }),
      surface('Menu and popover', 'menu/background', 'shadow/menu', { stroke: 'menu/stroke', radius: 'radius/control' }),
      surface('Toolbar control', 'chrome/control', 'shadow/control', { stroke: 'chrome/control-stroke', radius: 'radius/panel' }))),
    section('Scrim', col({ name: 'Scrim Specimen', gap: d('space/xs'), w: 300 },
      ground(el('div', { name: 'Scrim', style: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, background: canvas('scrim/sheet') } })),
      text('scrim/sheet', { name: 'Tokens', font: font('captionStrong'), color: 'text/primary' }),
      text(desc('scrim/sheet'), { name: 'Role', font: font('caption'), color: 'text/secondary', wrap: true }))),
  ];
}

function board() {
  return page([
    artboardHeader({ title: 'Elevation and materials', type: 'Materials', file: 'App/Sources (regularMaterial, bar) · tools/canvas-tokens.json', job: 'Iter draws flat: paper, cards with a hairline. Only what floats (place card, Add Spot banner, route day picker, sheets, menus) takes a system material and a soft shadow. These are canvas stand-ins for the macOS values; each sits over a coloured backdrop so the translucency shows.' }),
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Materials are system-drawn', body: 'regularMaterial and bar are Apple materials. Snapshots draw them as flat background/content; the fills here approximate the macOS 26 look and are canvas tokens, not app tokens.', width: 360 }),
      note({ title: 'Shadows are canvas only', body: 'tokens.json has no elevation tokens. The shadows come from tools/canvas-tokens.json and are CSS-only (Paper has no shadow token type). The one in-app shadow is the spot-editor pin (radius = stroke/regular).', width: 360 })),
    themeBlocks(body, { gap: 24, width: 686 }),
  ], { gap: 24, pad: 40 });
}

export const artboards = [
  { id: 'F04-elevation', name: 'F04 Elevation & materials', section: 'foundations', width: 1480, height: 1368, themes: ['light'], covers: [], render: board },
];
