// tokens.mjs - token helpers. Reads tools/token-map.json (written by gen-tokens.mjs). All names below use the
// app's slash names (as in Design/tokens.json); the emitted CSS uses the Paper/Tailwind names.
//
// Exports
//   c(name)              colour -> 'var(--color-accent-primary)' or, when the theme being rendered is dark,
//                        'var(--color-dark-accent-primary)'. Throws on unknown / non-colour names.
//   d(name)              dimension -> 'var(--spacing-md)' / 'var(--radius-card)' / 'var(--container-layout-list-ideal)'
//   canvas(name)         canvas-only colour or shadow, themed like c(). name: 'desktop', 'window/outline',
//                        'shadow/window' (a leading 'canvas/' is allowed).
//   dv(name)             numeric px value of a dimension token (SVG geometry): dv("stroke/regular") -> 1.5
//   resolveColor(v)      token name or CSS colour value -> CSS colour value (used by helpers that take `color`)
//   dv(name)             numeric px of a dimension token (SVG geometry): dv("stroke/regular") -> 1.5
//   resolveColor(v)      token name or CSS colour -> CSS colour (helpers taking `color` use it)
//   op(name)             opacity token -> 'var(--opacity-low-confidence)'   (use as `opacity: op('low-confidence')`)
//   font(style, extra?)  CSS declarations string: font-family/size/weight/line-height (+ tabular-nums when the token
//                        says monospaced digits). style: 'headline', 'title/spot', 'score/badge', 'type/headline'.
//                        extra: {size, weight, lineHeight, family} overrides (px numbers ok; weight may be 'regular'|'medium'|'semibold'|'bold'
//                        or a number) for chrome and small deviations only.
//   withTheme(theme, fn) run fn with theme 'light'|'dark'; returns fn's value; restores the previous theme.
//   currentTheme()       'light' | 'dark'
//   hasToken(name)       boolean
//   tokenNames(kind?)    list of app token names ('color','font',...)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const mapFile = path.join(here, '..', 'token-map.json');
let MAP = null;
function load() {
  if (!MAP) {
    if (!fs.existsSync(mapFile)) throw new Error('tools/token-map.json missing: run `node Design/paper/tools/gen-tokens.mjs`');
    MAP = JSON.parse(fs.readFileSync(mapFile, 'utf8')).tokens;
  }
  return MAP;
}

let theme = 'light';
export function currentTheme() { return theme; }
export function withTheme(t, fn) {
  if (t !== 'light' && t !== 'dark') throw new Error(`withTheme: unknown theme "${t}"`);
  const prev = theme;
  theme = t;
  try { return fn(); } finally { theme = prev; }
}

function suggest(name, pool) {
  const base = name.split('/').pop().toLowerCase();
  const hits = pool.filter((n) => n.toLowerCase().includes(base) || name.toLowerCase().includes(n.split('/').pop().toLowerCase())).slice(0, 6);
  return hits.length ? ` Did you mean: ${hits.join(', ')}?` : '';
}
function lookup(name, kinds, helper) {
  const m = load();
  const e = m[name];
  if (!e) {
    const pool = Object.keys(m).filter((k) => kinds.includes(m[k].type));
    throw new Error(`${helper}('${name}'): unknown token.${suggest(name, pool)} (tokens come from Design/tokens.json; a rename needs the source updated)`);
  }
  if (!kinds.includes(e.type)) throw new Error(`${helper}('${name}'): this is a ${e.type} token, not one of ${kinds.join('/')}. ${e.type === 'color' ? "Use c()." : e.type === 'font' ? 'Use font().' : 'Use d().'}`);
  return e;
}

export function hasToken(name) { return name in load(); }
export function tokenNames(kind) { const m = load(); return Object.keys(m).filter((k) => !kind || m[k].type === kind); }

export function c(name) {
  if (name.startsWith('canvas/')) return canvas(name);
  const e = lookup(name, ['color'], 'c');
  if (e.canvas) throw new Error(`c('${name}'): canvas token, use canvas()`);
  return `var(${e.names[theme === 'dark' ? 1 : 0]})`;
}
export function d(name) {
  const e = lookup(name, ['spacing', 'radius', 'container'], 'd');
  return `var(${e.names[0]})`;
}
export function canvas(name) {
  const key = name.startsWith('canvas/') ? name : `canvas/${name}`;
  const m = load();
  const e = m[key];
  if (!e || !e.canvas) throw new Error(`canvas('${name}'): unknown canvas token.${suggest(key, Object.keys(m).filter((k) => m[k].canvas))}`);
  return `var(${e.names[theme === 'dark' ? 1 : 0]})`;
}
export function op(name) {
  const e = lookup(name.startsWith('opacity/') ? name : `opacity/${name}`, ['opacity'], 'op');
  return `var(${e.names[0]})`;
}
function weightVar(w) {
  const names = new Set(Object.values(load()).filter((e) => e.type === 'font').map((e) => e.names.weight));
  const v = `--font-weight-${w}`;
  if (!names.has(v)) throw new Error(`font(): weight '${w}' is not a token (available: ${[...names].map((n) => n.replace('--font-weight-', '')).join(', ')}); use a number for a one-off`);
  return `var(${v})`;
}
const px = (v) => (typeof v === 'number' ? `${v}px` : v);
export function font(style, extra = {}) {
  const key = style.startsWith('type/') ? style : `type/${style}`;
  const e = lookup(key, ['font'], 'font');
  const n = e.names;
  const fam = extra.family ?? `var(${n.family})`;
  const size = extra.size !== undefined ? px(extra.size) : `var(${n.size})`;
  const weight = extra.weight === undefined ? `var(${n.weight})` : (/^[a-z]+$/.test(String(extra.weight)) ? weightVar(extra.weight) : extra.weight);
  const lh = extra.lineHeight !== undefined ? px(extra.lineHeight) : `var(${n.lineHeight})`;
  let s = `font-family:${fam};font-size:${size};font-weight:${weight};line-height:${lh}`;
  if (e.numeric) s += ';font-variant-numeric:tabular-nums';
  return s;
}

// resolveColor(v): a token name ('text/secondary') -> c(name); a CSS value ('var(...)', 'transparent', 'currentColor') passes through.
export function resolveColor(v) {
  if (v == null) return v;
  if (/^(var\(|color-mix\(|transparent$|currentColor$|inherit$|none$)/.test(v)) return v;
  return c(v);
}

// dv(name): the numeric px value of a dimension token (for SVG geometry that needs numbers): dv('stroke/regular') -> 1.5
export function dv(name) {
  const e = lookup(name, ['spacing', 'radius', 'container'], 'dv');
  return e.value;
}
