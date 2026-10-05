// icons.mjs - SF Symbols as inline SVG.
//   icon(symbolName, {size=16, color='text/primary', weight?, name?})
//     -> <svg layer-name="Icon / <symbolName>" width=size height=size viewBox=<symbol viewBox> style="fill:<token>">
//        The symbol keeps its aspect ratio, centred in a size x size box. color: token name or CSS value.
//        weight: 'regular' (default) | 'medium' | 'semibold' | 'bold': faked by a stroke in the same colour
//        (the symbol data is one weight). Missing symbol -> neutral rounded-square outline stand-in (no text),
//        still named "Icon / <name>", recorded in missingSymbols().
//   hasSymbol(name), missingSymbols() -> sorted array of names requested but absent from symbols/symbols.json.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { svgEl, raw } from './h.mjs';
import { resolveColor } from './tokens.mjs';

const file = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'symbols', 'symbols.json');
let DATA = null;
const missing = new Set();
function data() {
  if (DATA) return DATA;
  try { DATA = JSON.parse(fs.readFileSync(file, 'utf8')); } catch { DATA = {}; }
  return DATA;
}
export const hasSymbol = (n) => n in data();
export const missingSymbols = () => [...missing].sort();

const STROKE = { regular: 0, medium: 0.03, semibold: 0.06, bold: 0.1 }; // fraction of the symbol width

export function icon(symbolName, { size = 16, color = 'text/primary', weight = 'regular', name } = {}) {
  const col = resolveColor(color);
  const full = name || `Icon / ${symbolName}`;
  const layer = full.length > 50 ? full.slice(0, 49) + '\u2026' : full; // layer-name max 50 chars
  const sym = data()[symbolName];
  if (!sym) {
    missing.add(symbolName);
    const r = Math.max(2, size * 0.2);
    const inset = Math.max(1, size * 0.1);
    return svgEl(layer, { width: size, height: size, viewBox: `0 0 ${size} ${size}`, attrs: { 'data-missing-symbol': symbolName } },
      raw(`<rect x="${inset}" y="${inset}" width="${size - 2 * inset}" height="${size - 2 * inset}" rx="${r}" fill="none" style="stroke:${col}" stroke-width="1.25"/>`));
  }
  const sw = (STROKE[weight] ?? 0) * sym.w;
  const stroke = sw ? `;stroke:${col};stroke-width:${sw.toFixed(2)};stroke-linejoin:round` : '';
  return svgEl(layer, { width: size, height: size, viewBox: sym.viewBox, attrs: { preserveAspectRatio: 'xMidYMid meet' }, style: `fill:${col}${stroke}` },
    raw(`<path d="${sym.d}"/>`));
}
