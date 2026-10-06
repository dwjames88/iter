// 20-option-b: Option B, "replacing the places list". Selecting a spot turns the list column into the Light panel (widths unchanged).
import { el, row, col, text } from '../../../../paper/tools/lib/h.mjs';
import { c, canvas, font } from '../../../../paper/tools/lib/tokens.mjs';
import { icon } from '../../../../paper/tools/lib/icons.mjs';
import { exploreWindow, defaultMap, mapPin, pinChip } from '../shell.mjs';
import { lightPanel, listB, slimCard } from '../option-b/panel-b.mjs';

const cardOverlay = (w) => el('div', { name: 'Card Position', style: { position: 'absolute', right: 12, bottom: 12, display: 'flex' } }, slimCard({ width: w }));
const listWin = () => {
  const w = 1280 - 240 - 360;
  return exploreWindow({ width: 1280, height: 820, list: listB(), map: defaultMap({ width: w, height: 768, selectedName: null, children: [mapPin(0.2 * w, 0.5 * 768, pinChip({ score: 76 }))] }) });
};
const panelWin = (width, height, opts = {}) => exploreWindow({ width, height, list: lightPanel({ width: width >= 1280 ? 360 : 340, ...opts }), overlay: cardOverlay(360) });
const L1280 = () => panelWin(1280, 820);
const L960 = () => panelWin(960, 652, { band: 80, plot: 96 });
const SUN1280 = () => panelWin(1280, 820, { zoom: 2 });

const shadowed = (h) => el('div', { name: 'Window Shadow', style: { display: 'flex', borderRadius: 26, boxShadow: canvas('shadow/material') } }, h);
const cap = (t) => text(t, { name: 'Caption', font: font('title/section', { size: 15, lineHeight: 20 }), color: 'text/primary' });
const pair = () => {
  const W = 1280, G = 40, X2 = W + G, MID = 44 + 410;
  return col({ name: 'Pair Board', style: { width: 2600, height: 880, background: c('background/systemWindow'), position: 'relative' } },
    row({ name: 'Caption 1', style: { position: 'absolute', left: 12, top: 12 } }, cap('Places list')),
    row({ name: 'Caption 2', style: { position: 'absolute', left: X2 + 12, top: 12 } }, cap('Bixby Bridge selected — Light panel')),
    el('div', { name: 'Window 1', style: { position: 'absolute', left: 0, top: 44 } }, shadowed(listWin())),
    el('div', { name: 'Window 2', style: { position: 'absolute', left: X2, top: 44 } }, shadowed(L1280())),
    row({ name: 'Arrow', align: 'center', justify: 'center', style: { position: 'absolute', left: W + G / 2 - 14, top: MID - 14, width: 28, height: 28, background: c('accent/primary'), borderRadius: 999, boxShadow: canvas('shadow/button') } },
      icon('chevron.right', { size: 13, color: 'accent/onAccent', weight: 'bold' })),
    col({ name: 'Transition Label', align: 'center', gap: 0, style: { position: 'absolute', left: W + G / 2 - 52, top: MID + 20, width: 104, padding: '4px 0', borderRadius: 10, background: c('background/systemWindow'), border: `0.5px solid ${c('separator/default')}` } },
      text('Select a place', { name: 'Forward', font: font('caption', { size: 11 }), color: 'text/secondary' }), text('Esc to go back', { name: 'Back', font: font('caption', { size: 11 }), color: 'text/secondary' })));
};

export const artboards = [
  { id: 'B-1280-list-light', width: 1280, height: 820, appearance: 'light', html: listWin },
  { id: 'B-1280-list-dark', width: 1280, height: 820, appearance: 'dark', html: listWin },
  { id: 'B-1280-light-light', width: 1280, height: 820, appearance: 'light', html: L1280 },
  { id: 'B-1280-light-dark', width: 1280, height: 820, appearance: 'dark', html: L1280 },
  { id: 'B-960-light-light', width: 960, height: 652, appearance: 'light', html: L960 },
  { id: 'B-960-light-dark', width: 960, height: 652, appearance: 'dark', html: L960 },
  { id: 'B-1280-sunset-light', width: 1280, height: 820, appearance: 'light', html: SUN1280 },
  { id: 'B-pair-light', width: 2600, height: 880, appearance: 'light', html: pair },
  { id: 'B-pair-dark', width: 2600, height: 880, appearance: 'dark', html: pair },
];
