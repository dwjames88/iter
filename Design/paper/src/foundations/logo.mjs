// F06 Logo and app icon. First Light artwork: source SVGs from Brand/logo (First Light files) or the Vantage finalists;
// their outlined paths are parsed here and re-emitted with every fill rewritten to a token var. Clear space and
// minimum sizes are DERIVED from the mark (the dot diameter and the 16 px favicon), not typed in.
//   ink   = text/primary (espresso on paper, cream on the dark ground)   dot = brand/dot
//   There is no brand ink or paper token; text/primary and background/window are the canvas-token route (reported).
import { col, row, text, el, svgEl, raw } from '../../tools/lib/h.mjs';
import { c, d, canvas, font, withTheme } from '../../tools/lib/tokens.mjs';
import { note } from '../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, section, cell, page } from '../../tools/lib/specimens.mjs';
import { loadLogo, logoSvgInner, pathBox, sourceFills, brandNotes, colour } from './tokdata.mjs';

const L = {
  lockup: loadLogo('lockup-firstlight'), lockupDark: loadLogo('lockup-firstlight-dark'), symbol: loadLogo('symbol-firstlight'),
  icon: loadLogo('app-icon-firstlight'), lockupMono: loadLogo('lockup-mono'), symbolMono: loadLogo('symbol-mono'), fav: loadLogo('favicon-16'),
};

// ---- drift check: do the token colours still equal the source file's fills? (build log only) ----------------------
(function drift() {
  const eq = (a, b) => a.toLowerCase() === b.toLowerCase();
  const chk = (logo, wants) => sourceFills(logo).forEach((f, i) => { if (/^#/.test(f) && wants[i] && !eq(f, wants[i])) console.warn(`logo drift: ${logo.name} part ${i} fill ${f} differs from token ${wants[i]}`); });
  const ink = colour('text/primary'), dot = colour('brand/dot');
  chk(L.lockup, [ink.light, dot.light]); chk(L.lockupDark, [ink.dark, dot.dark]); chk(L.symbol, [ink.light, dot.light]);
  chk(L.icon, [ink.light, ink.dark, dot.dark]); chk(L.fav, [null, dot.light]);
})();

// ---- geometry derived from the artwork ---------------------------------------------------------------------------------
const vbw = (l) => l.viewBox[2], vbh = (l) => l.viewBox[3];
const dotBox = (l) => pathBox(l.parts[l.parts.length - 1].attrs.d);
const margin = (key, l) => brandNotes?.metrics?.clip_margin?.[key] ?? Math.min(...l.parts.filter((p) => p.tag === 'path').map((p) => pathBox(p.attrs.d)).flatMap((b) => [b.x, b.y]));
const M = { lockup: margin('lockup', L.lockup), symbol: margin('symbol', L.symbol), icon: 0 };
const D = dotBox(L.lockup).w;                       // dot diameter in lockup units (also the i-stem is about 128)
const DSYM = dotBox(L.symbol).w;
const DICON = dotBox(L.icon).w;
const favDot = 2 * parseFloat(/a\s*([\d.]+)/.exec(L.fav.parts[1].attrs.d)[1]); // the 16 px favicon's dot, in px
const artH = { lockup: vbh(L.lockup) - 2 * M.lockup, symbol: vbh(L.symbol) - 2 * M.symbol, icon: vbh(L.icon) };
const MIN = { lockup: Math.round((favDot * artH.lockup) / D), symbol: Math.round((favDot * artH.symbol) / DSYM), icon: Math.round((favDot * artH.icon) / DICON) };

// ---- emitters -----------------------------------------------------------------------------------------------------------
const ink = () => c('text/primary');
const dotFill = () => c('brand/dot');
const svgOf = (logo, fills, h, name) => svgEl(name, { width: Math.round((h * vbw(logo)) / vbh(logo) * 100) / 100, height: h, viewBox: logo.viewBox.join(' ') }, raw(logoSvgInner(logo, fills)));
const iconSvg = (h, name) => svgOf(L.icon, [withTheme('light', ink), withTheme('dark', ink), withTheme('dark', dotFill)], h, name);
const hairline = () => `${d('stroke/hairline')} solid ${canvas('specimen/border')}`;

function themed() {
  return [
    section('Lockup', row({ name: 'Lockup Row', gap: 40, align: 'center' },
      cell('lockup', svgOf(L.lockup, [ink(), dotFill()], 120, 'Logo / Lockup')),
      cell('symbol', svgOf(L.symbol, [ink(), dotFill()], 120, 'Logo / Symbol')))),
    section('Mono', row({ name: 'Mono Row', gap: 40, align: 'center' },
      cell('lockup mono', svgOf(L.lockupMono, [ink()], 72, 'Logo / Lockup Mono'), { caption: 'One ink: text/primary' }),
      cell('symbol mono', svgOf(L.symbolMono, [ink()], 72, 'Logo / Symbol Mono')),
      cell('reverse', el('div', { name: 'Reverse Ground', style: { display: 'flex', padding: d('space/md'), background: c('text/primary'), borderRadius: d('radius/card') } }, svgOf(L.lockupMono, [c('background/window')], 48, 'Logo / Lockup Reverse')), { caption: 'Paper on ink' }),
      cell('on accent', el('div', { name: 'Accent Ground', style: { display: 'flex', padding: d('space/md'), background: c('accent/emphasis'), borderRadius: d('radius/card') } }, svgOf(L.lockupMono, [c('accent/onAccent')], 48, 'Logo / Lockup On Accent')), { caption: 'accent/onAccent on accent/emphasis' }))),
    section('Favicon redraw (pixel snapped)', row({ name: 'Favicon Row', gap: 40, align: 'flex-end' },
      cell('favicon 16', svgOf(L.fav, [ink(), dotFill()], 16, 'Logo / Favicon 16'), { caption: '16 px' }),
      cell('favicon 64', svgOf(L.fav, [ink(), dotFill()], 64, 'Logo / Favicon 64'), { caption: 'same artwork at 4x' }))),
  ];
}

function appIcon() {
  const sizes = [256, 128, 64, 32, 16];
  return row({ name: 'App Icon Sizes', gap: 32, align: 'flex-end' },
    sizes.map((s) => cell(`icon ${s}`, iconSvg(s, `App Icon / ${s}`), { caption: `${s} px` })));
}

function clearSpace() {
  const m = M.lockup, pad = 30;
  const vx = m - D - pad, vy = m - D - pad, vw = vbw(L.lockup) - 2 * m + 2 * D + 2 * pad, vh = artH.lockup + 2 * D + 2 * pad;
  const W = 720, H = Math.round((W * vh) / vw);
  const acc = c('accent/primary');
  const tint = (p) => `color-mix(in srgb, ${acc} ${p}%, transparent)`;
  const aw = vbw(L.lockup) - 2 * m, ah = artH.lockup;
  const sq = (x, y) => `<rect x="${x}" y="${y}" width="${D}" height="${D}" style="fill:${tint(28)};stroke:${acc}" stroke-width="3"/>`;
  const inner = `<rect x="${m - D}" y="${m - D}" width="${aw + 2 * D}" height="${ah + 2 * D}" style="fill:${tint(8)};stroke:${acc}" stroke-width="3" stroke-dasharray="14 10"/>`
    + `<rect x="${m}" y="${m}" width="${aw}" height="${ah}" style="fill:${c('background/window')};stroke:${acc}" stroke-width="3"/>`
    + logoSvgInner(L.lockup, [ink(), dotFill()])
    + sq(m - D, m + ah / 2 - D / 2) + sq(m + aw, m + ah / 2 - D / 2) + sq(m + aw / 2 - D / 2, m - D) + sq(m + aw / 2 - D / 2, m + ah);
  return svgEl('Clear Space Diagram', { width: W, height: H, viewBox: `${vx} ${vy} ${vw} ${vh}` }, raw(inner));
}

function minimums() {
  const lock = (h) => svgOf(L.lockup, [ink(), dotFill()], Math.round((h * vbh(L.lockup)) / artH.lockup * 10) / 10, `Logo / Lockup ${h}px`);
  const sym = (h) => svgOf(L.symbol, [ink(), dotFill()], Math.round((h * vbh(L.symbol)) / artH.symbol * 10) / 10, `Logo / Symbol ${h}px`);
  const item = (label, node, cap) => cell(label, node, { caption: cap });
  return row({ name: 'Minimum Sizes', gap: 48, align: 'flex-end' },
    item('lockup min', lock(MIN.lockup), `Lockup: ${MIN.lockup} px mark height`),
    item('lockup 2x', lock(MIN.lockup * 2), `${MIN.lockup * 2} px`),
    item('symbol min', sym(MIN.symbol), `Symbol: ${MIN.symbol} px`),
    item('favicon', svgOf(L.fav, [ink(), dotFill()], 16, 'Logo / Favicon 16'), 'Below that: the favicon redraw, 16 px'),
    item('icon min', iconSvg(MIN.icon, `App Icon / ${MIN.icon}`), `App icon: ${MIN.icon} px`));
}

function board() {
  const x = Math.round(D * 10) / 10;
  return page([
    artboardHeader({ title: 'Logo and app icon', type: 'Brand', file: 'Brand/logo/*.svg (First Light) · fills from brand/dot and text/primary', job: 'The i with a step and a coral dot, set in Geist 600 and outlined. One lockup, one symbol, one app icon, mono variants for one-ink uses. Fills are token variables: ink is text/primary, the dot is brand/dot.' }),
    row({ name: 'Notes', gap: d('space/md'), align: 'flex-start' },
      note({ title: 'Clear space', body: `Keep one dot diameter (x = ${x} units in the lockup artwork, the width of the i's dot) clear on every side of the artwork. The dashed box is the clear zone; the four squares are x.`, width: 380 }),
      note({ title: 'Minimum sizes', body: `Derived from the 16 px favicon, whose dot is ${favDot} px, the smallest dot we draw. Scale the artwork so its dot is never smaller: lockup ${MIN.lockup} px, symbol ${MIN.symbol} px, app icon ${MIN.icon} px tall. Below that, use the pixel-snapped favicon redraw.`, width: 380 }),
      note({ title: 'Colour roles', body: 'No brand ink or paper token exists. Ink is text/primary and paper is background/window; the dot is brand/dot (graphic only, never text). The app icon is theme independent: its ground is the light ink, its i the dark-mode ink, its dot the dark-mode dot.', width: 380 })),
    themeBlocks(themed, { gap: 24, width: 740 }),
    row({ name: 'Icon And Rules', gap: 40, align: 'flex-start' },
      col({ name: 'App Icon Block', gap: d('space/md'), noshrink: true },
        text('App icon', { name: 'Section Title', font: font('title/section'), color: canvas('label/title') }),
        appIcon()),
      col({ name: 'Clear Space Block', gap: d('space/md'), noshrink: true },
        text('Clear space', { name: 'Section Title', font: font('title/section'), color: canvas('label/title') }),
        clearSpace())),
    col({ name: 'Minimum Sizes Block', gap: d('space/md') },
      text('Minimum sizes', { name: 'Section Title', font: font('title/section'), color: canvas('label/title') }),
      minimums()),
  ], { gap: 32, pad: 40 });
}

export const artboards = [
  { id: 'F06-logo-app-icon', name: 'F06 Logo & app icon', section: 'foundations', width: 1640, height: 1416, themes: ['light'], covers: [], render: board },
];
