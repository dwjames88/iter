// tokdata.mjs - build-time data for the foundations and system-component artboards (domain D6).
// Everything on the foundations pages that is a value, a role description or a contrast ratio is read here from
// Design/tokens.json (+ tools/canvas-tokens.json for canvas-only values) when the page is built, never typed in, so the
// pages stay correct after a retheme and a regeneration. No artboards of its own.
//
//   COLOURS            [{name, group, light, dark, desc, system}]  every colour token, tokens.json order. light/dark are
//                      '#rrggbb' strings read from the data (they are only ever shown as text or fed to contrast()).
//   colour(name)       one entry (throws on unknown)
//   contrast(a, b)     WCAG 2.x contrast ratio of two '#rrggbb' strings
//   ratio(n)           '4.18:1'
//   dimensions         { 'space/md': {value, desc}, ... }     typography { 'type/headline': {...} }
//   canvasData         parsed tools/canvas-tokens.json
//   hexText(hex, opts) text node showing a hex value; the leading '#' is an HTML entity so the value is displayed, not
//                      authored as a literal colour (check.mjs flags a literal #rrggbb in output files)
//   mdTable(file, h2)  rows of the first markdown table under "## <h2>" -> arrays of cell strings, markup stripped
//   loadLogo(name)     {file, viewBox:[w,h], parts:[{tag, attrs}]} from Brand/logo (First Light); throws if the file is missing
//   logoSvg(logo, fills, {name,width,height})   re-emit the parts with fills = array of CSS colours (token vars)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { raw } from '../../tools/lib/h.mjs';
import { styleString } from '../../tools/lib/h.mjs';
import { resolveColor } from '../../tools/lib/tokens.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const designDir = path.resolve(here, '..', '..', '..');
export const repoDir = path.resolve(designDir, '..');
const TOKENS = JSON.parse(fs.readFileSync(path.join(designDir, 'tokens.json'), 'utf8'));
export const canvasData = JSON.parse(fs.readFileSync(path.join(designDir, 'paper', 'tools', 'canvas-tokens.json'), 'utf8'));
const EXT = 'com.dwjames.iter';

export const COLOURS = [];
export const dimensions = {};
export const typography = {};
(function walk(node, prefix) {
  for (const [k, v] of Object.entries(node)) {
    if (k.startsWith('$')) continue;
    const name = prefix + k;
    if (v && typeof v === 'object' && '$type' in v) {
      const ext = (v.$extensions || {})[EXT] || {};
      if (v.$type === 'color') {
        COLOURS.push({ name, group: name.split('/')[0], light: v.$value.hex.toLowerCase(), dark: String(ext.dark || v.$value.hex).toLowerCase(), desc: v.$description || '', system: ext.system || '' });
      } else if (v.$type === 'dimension') {
        dimensions[name] = { value: v.$value.value, unit: v.$value.unit, desc: v.$description || '' };
      } else if (v.$type === 'typography') {
        typography[name] = { family: v.$value.fontFamily, size: v.$value.fontSize.value, weight: v.$value.fontWeight, desc: v.$description || '', textStyle: ext.textStyle, design: ext.design, digits: !!ext.monospacedDigits };
      }
    } else if (v && typeof v === 'object') walk(v, name + '/');
  }
})(TOKENS, '');

export function colour(name) {
  const e = COLOURS.find((x) => x.name === name);
  if (!e) throw new Error(`colour('${name}'): not in tokens.json`);
  return e;
}

// ---- WCAG 2.x --------------------------------------------------------------------------------------------------
const lin = (v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
const rgb = (h) => { const s = h.replace('#', ''); return [0, 2, 4].map((i) => parseInt(s.slice(i, i + 2), 16)); };
export const luminance = (h) => { const [r, g, b] = rgb(h); return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b); };
export function contrast(a, b) {
  const la = luminance(a), lb = luminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}
export const ratio = (n) => `${n.toFixed(2)}:1`;
export const upper = (h) => h.toUpperCase();

// ---- a hex value shown as text -----------------------------------------------------------------------------------
export function hexText(hex, { font, color = 'text/secondary', name = 'Hex Value', w } = {}) {
  const st = (font ? font + ';' : '') + styleString({ color: resolveColor(color), whiteSpace: 'nowrap', width: w, flexShrink: w ? 0 : undefined });
  return raw(`<div layer-name="${name}" style="box-sizing:border-box;${st}">&#35;${upper(hex).replace('#', '')}</div>`);
}

// ---- markdown tables ---------------------------------------------------------------------------------------------
export function mdTable(file, h2) {
  const lines = fs.readFileSync(file, 'utf8').split('\n');
  let i = lines.findIndex((l) => l.trim() === `## ${h2}`);
  if (i < 0) throw new Error(`mdTable: "## ${h2}" not found in ${file}`);
  while (i < lines.length && !lines[i].startsWith('|')) i++;
  const rows = [];
  for (; i < lines.length && lines[i].startsWith('|'); i++) {
    const cells = lines[i].replace(/^\||\|\s*$/g, '').split('|').map((s) => s.trim());
    if (cells.every((c) => /^:?-+:?$/.test(c))) continue;
    rows.push(cells.map((s) => s.replace(/\*\*/g, '').replace(/`/g, '').replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')));
  }
  return rows.slice(1); // drop the header row
}

// ---- logo ----------------------------------------------------------------------------------------------------------
export const brandNotes = (() => {
  try { return JSON.parse(fs.readFileSync(path.join(repoDir, 'Brand', 'logo', 'notes.json'), 'utf8')); } catch { return null; }
})();

export function loadLogo(name) {
  // Brand/logo only: no fallback to older artwork, a missing or renamed file must stop the build.
  const file = path.join(repoDir, 'Brand', 'logo', `${name}.svg`);
  if (!fs.existsSync(file)) throw new Error(`logo "${name}.svg" not found in Brand/logo (First Light files are lockup, lockup-dark, symbol, symbol-dark, app-icon, favicon-16; gold files are in _retired)`);
  const src = fs.readFileSync(file, 'utf8');
  const vb = /viewBox="([^"]+)"/.exec(src)[1].trim().split(/\s+/).map(Number);
  const parts = [];
  for (const m of src.matchAll(/<(path|rect)\b([^>]*?)\/?>/g)) {
    const attrs = {};
    for (const a of m[2].matchAll(/([\w-]+)="([^"]*)"/g)) attrs[a[1]] = a[2];
    parts.push({ tag: m[1], attrs });
  }
  return { name, file, viewBox: vb, parts };
}

// Bounding box of the absolute-coordinate path data our logo files use (M L H V C Q Z, plus a relative arc for the favicon dot).
export function pathBox(d) {
  const toks = d.match(/[A-Za-z]|-?\d*\.?\d+(?:e-?\d+)?/g) || [];
  let x = 0, y = 0, cmd = 'M';
  const xs = [], ys = [];
  const push = (px, py) => { xs.push(px); ys.push(py); };
  let i = 0;
  const num = () => parseFloat(toks[i++]);
  while (i < toks.length) {
    if (/[A-Za-z]/.test(toks[i])) cmd = toks[i++];
    if (cmd === 'Z' || cmd === 'z') continue;
    if (cmd === 'M' || cmd === 'L') { x = num(); y = num(); push(x, y); if (cmd === 'M') cmd = 'L'; }
    else if (cmd === 'H') { x = num(); push(x, y); }
    else if (cmd === 'V') { y = num(); push(x, y); }
    else if (cmd === 'C') { for (let k = 0; k < 3; k++) { const a = num(), b = num(); push(a, b); x = a; y = b; } }
    else if (cmd === 'Q') { for (let k = 0; k < 2; k++) { const a = num(), b = num(); push(a, b); x = a; y = b; } }
    else if (cmd === 'm' || cmd === 'l') { x += num(); y += num(); push(x, y); if (cmd === 'm') cmd = 'l'; }
    else if (cmd === 'h') { x += num(); push(x, y); }
    else if (cmd === 'v') { y += num(); push(x, y); }
    else throw new Error(`pathBox: unsupported command ${cmd}`);
  }
  return { x: Math.min(...xs), y: Math.min(...ys), w: Math.max(...xs) - Math.min(...xs), h: Math.max(...ys) - Math.min(...ys) };
}

export function logoSvgInner(logo, fills) {
  return logo.parts.map((p, i) => {
    const fill = fills[Math.min(i, fills.length - 1)];
    if (p.tag === 'rect') return `<rect x="${p.attrs.x || 0}" y="${p.attrs.y || 0}" width="${p.attrs.width}" height="${p.attrs.height}"${p.attrs.rx ? ` rx="${p.attrs.rx}"` : ''} style="fill:${fill}"/>`;
    return `<path d="${p.attrs.d}" style="fill:${fill}"/>`;
  }).join('');
}

// Source fill colours of a logo file, for drift checking against the tokens ('currentColor' for mono parts).
export const sourceFills = (logo) => logo.parts.map((p) => p.attrs.fill || '');

export const artboards = [];
