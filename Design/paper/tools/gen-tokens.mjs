#!/usr/bin/env node
// gen-tokens.mjs - GENERATOR. Reads Design/tokens.json (+ tools/canvas-tokens.json) and writes:
//   Design/paper/tokens.css          CSS custom properties (browser preview; same names as Paper)
//   Design/paper/tokens.paper.json   the array for Paper's create_tokens: [{type,name,value,description}]
//   Design/paper/tools/token-map.json  app token name -> Paper/CSS name(s); read by tools/lib/tokens.mjs
// Run:  node Design/paper/tools/gen-tokens.mjs
//
// Naming follows Tailwind v4 theme namespaces (Paper's token types):
//   colour  accent/primary      -> --color-accent-primary (light), --color-dark-accent-primary (dark)
//   canvas  window/outline      -> --color-canvas-window-outline / --color-dark-canvas-window-outline
//   shadow  (canvas only)       -> --shadow-canvas-window / --shadow-dark-canvas-window (NOT sent to Paper: no shadow type)
//   space/*                     -> --spacing-<rest>             (type spacing)
//   radius/*                    -> --radius-<rest>              (type radius)
//   layout/*                    -> --container-layout-<rest>    (type container)
//   size|stroke|chart/*, other  -> --spacing-<path>             (type spacing; ASSUMPTION: Paper has no better type)
//   type/<style>                -> --text-<style> (size), --leading-<style>, --font-weight-<name>; families --font-sans/--font-serif
//                                  tabular numbers stay a literal font-variant-numeric style; --type-<style>-numeric is NOT emitted
//   opacities (canvas-tokens)   -> --opacity-<name>
// camelCase segments become kebab (status/noForecast -> status-no-forecast).
// Everything derives from the JSON: no Iter colour names are hard-coded here (only the ordering hint COLOR_ORDER).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const paperDir = path.resolve(here, '..');
const repo = path.resolve(paperDir, '..', '..');
const srcJson = path.join(repo, 'Design', 'tokens.json');
const canvasPath = path.join(here, 'canvas-tokens.json');

const kebab = (s) => s.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase();
const slug = (p) => p.split('/').map(kebab).join('-');
const WEIGHT_NAMES = { 100: 'thin', 200: 'extralight', 300: 'light', 400: 'regular', 500: 'medium', 600: 'semibold', 700: 'bold', 800: 'extrabold', 900: 'black' };
// Ordering hint for Paper's create_tokens (semantic colours first). Unknown groups sort before canvas.
const COLOR_ORDER = ['text', 'separator', 'background', 'accent', 'focus', 'route', 'status', 'light', 'sky', 'cloud', 'map', 'brand'];

const tokens = JSON.parse(fs.readFileSync(srcJson, 'utf8'));
const canvas = JSON.parse(fs.readFileSync(canvasPath, 'utf8'));

const errors = [];
const used = new Map(); // css name -> source
function claim(name, source) {
  if (used.has(name)) errors.push(`Name collision: ${name} <- "${source}" and "${used.get(name)}"`);
  used.set(name, source);
}

function* walk(node, prefix = '') {
  for (const [k, v] of Object.entries(node)) {
    if (k.startsWith('$') || v === null || typeof v !== 'object') continue;
    if ('$type' in v) yield [prefix + k, v];
    else yield* walk(v, prefix + k + '/');
  }
}

const ext = (t) => (t.$extensions && t.$extensions['com.dwjames.iter']) || {};
const hexUp = (h) => h.toUpperCase();
const px = (n) => `${n}px`;

// ---- collect -------------------------------------------------------------------------------------------
const colors = []; // {app, slug, light, dark, desc, group}
const dims = [];   // {app, type, name, value(number), desc}
const typeStyles = []; // {app, style, family, size, weight, textStyle, numeric, desc}
const families = new Set();

for (const [app, t] of walk(tokens)) {
  if (t.$type === 'color') {
    const light = hexUp(t.$value.hex);
    const dark = ext(t).dark ? hexUp(ext(t).dark) : light;
    if (!ext(t).dark) console.warn(`warn: ${app} has no dark value; reusing light`);
    colors.push({ app, slug: slug(app), light, dark, desc: t.$description || '', group: app.split('/')[0] });
  } else if (t.$type === 'dimension') {
    const g = app.split('/')[0];
    const rest = slug(app.split('/').slice(1).join('/'));
    let type = 'spacing', name;
    if (g === 'space') name = `--spacing-${rest}`;
    else if (g === 'radius') { type = 'radius'; name = `--radius-${rest}`; }
    else if (g === 'layout') { type = 'container'; name = `--container-${slug(app)}`; }
    else name = `--spacing-${slug(app)}`;
    dims.push({ app, type, name, value: t.$value.value, desc: t.$description || '' });
  } else if (t.$type === 'typography') {
    const style = slug(app.replace(/^type\//, ''));
    const e = ext(t);
    const serif = e.design === 'serif' || /new york/i.test(t.$value.fontFamily);
    families.add(serif ? 'serif' : 'sans');
    typeStyles.push({ app, style, family: serif ? 'serif' : 'sans', size: t.$value.fontSize.value, weight: t.$value.fontWeight, textStyle: e.textStyle, numeric: !!e.monospacedDigits, desc: t.$description || '' });
  } else {
    console.warn(`warn: unhandled token type ${t.$type} at ${app}`);
  }
}

// canvas colours
const canvasColors = [];
const mixCss = (spec, side) => {
  const base = colors.find((c) => c.app === spec.from);
  if (!base) { errors.push(`canvas colour mix references unknown token "${spec.from}"`); return '#000'; }
  const v = `var(--color-${side === 'dark' ? 'dark-' : ''}${base.slug})`;
  return spec.alpha >= 1 ? v : `color-mix(in srgb, ${v} ${Math.round(spec.alpha * 1000) / 10}%, transparent)`;
};
for (const [key, v] of Object.entries(canvas.colors)) {
  const isShadow = key.startsWith('shadow/');
  const val = (side) => (typeof v[side] === 'object' ? mixCss(v[side], side) : v[side]);
  const base = isShadow ? `canvas-${slug(key.replace(/^shadow\//, ''))}` : `canvas-${slug(key)}`;
  canvasColors.push({ app: `canvas/${key}`, key, isShadow, base, light: val('light'), dark: val('dark'), desc: v.$description || '' });
}
const opacities = Object.entries(canvas.opacities).filter(([k]) => !k.startsWith('$')).map(([k, v]) => ({ app: `opacity/${k}`, name: `--opacity-${slug(k)}`, value: v.value, desc: v.$description || '' }));

// ---- names / collisions ------------------------------------------------------------------------------------
for (const c of colors) { claim(`--color-${c.slug}`, c.app); claim(`--color-dark-${c.slug}`, c.app + ' (dark)'); }
for (const c of canvasColors) {
  if (c.isShadow) { claim(`--shadow-${c.base}`, c.app); claim(`--shadow-dark-${c.base}`, c.app + ' (dark)'); }
  else { claim(`--color-${c.base}`, c.app); claim(`--color-dark-${c.base}`, c.app + ' (dark)'); }
}
for (const d of dims) claim(d.name, d.app);
for (const f of families) claim(`--font-${f}`, `font family ${f}`);
const weightsUsed = new Set();
for (const t of typeStyles) {
  claim(`--text-${t.style}`, t.app + ' size'); claim(`--leading-${t.style}`, t.app + ' line-height');
  weightsUsed.add(t.weight);
  const lh = canvas.lineHeights[t.textStyle];
  if (!lh) errors.push(`No line height in canvas-tokens.json lineHeights for text style "${t.textStyle}" (${t.app})`);
}
for (const w of weightsUsed) claim(`--font-weight-${WEIGHT_NAMES[w] || w}`, `weight ${w}`);
for (const o of opacities) claim(o.name, o.app);
if (errors.length) { console.error(errors.join('\n')); process.exit(1); }

// ---- emit: map, paper tokens, css --------------------------------------------------------------------------
const map = {};
const paper = { color: [], colorDark: [], spacing: [], radius: [], container: [], fontFamily: [], fontSize: [], fontWeight: [], lineHeight: [], opacity: [] };
const cssLines = [];
const sec = (t) => cssLines.push('', `  /* ${t} */`);
const decl = (n, v) => cssLines.push(`  ${n}: ${v};`);
const colorRank = (g) => { const i = COLOR_ORDER.indexOf(g); return i < 0 ? COLOR_ORDER.length : i; };

const sortedColors = [...colors].sort((a, b) => colorRank(a.group) - colorRank(b.group));
sec('Colours (light). Dark twins follow with --color-dark-*.');
for (const c of sortedColors) {
  decl(`--color-${c.slug}`, c.light);
  map[c.app] = { type: 'color', names: [`--color-${c.slug}`, `--color-dark-${c.slug}`] };
  paper.color.push({ type: 'color', name: `color-${c.slug}`, value: c.light, description: c.desc });
  paper.colorDark.push({ type: 'color', name: `color-dark-${c.slug}`, value: c.dark, description: `${c.desc} (dark appearance)`.trim() });
}
sec('Colours (dark)');
for (const c of sortedColors) decl(`--color-dark-${c.slug}`, c.dark);

sec('Canvas colours (light): window chrome, glass, materials, system control fills, map placeholder, annotation furniture. Not in tokens.json.');
for (const c of canvasColors.filter((x) => !x.isShadow)) {
  decl(`--color-${c.base}`, c.light);
  map[c.app] = { type: 'color', canvas: true, names: [`--color-${c.base}`, `--color-dark-${c.base}`] };
  paper.color.push({ type: 'color', name: `color-${c.base}`, value: c.light, description: c.desc });
  paper.colorDark.push({ type: 'color', name: `color-dark-${c.base}`, value: c.dark, description: `${c.desc} (dark appearance)`.trim() });
}
sec('Canvas colours (dark)');
for (const c of canvasColors.filter((x) => !x.isShadow)) decl(`--color-dark-${c.base}`, c.dark);
sec('Canvas shadows (box-shadow values; light then dark). Not sent to Paper.');
for (const c of canvasColors.filter((x) => x.isShadow)) {
  decl(`--shadow-${c.base}`, c.light);
  decl(`--shadow-dark-${c.base}`, c.dark);
  map[c.app] = { type: 'shadow', canvas: true, names: [`--shadow-${c.base}`, `--shadow-dark-${c.base}`] };
}

sec('Dimensions (px)');
for (const d of [...dims].sort((a, b) => a.value - b.value)) {
  decl(d.name, px(d.value));
  map[d.app] = { type: d.type, names: [d.name], value: d.value };
  paper[d.type].push({ type: d.type, name: d.name.slice(2), value: px(d.value), description: d.desc });
}

sec('Type');
const famVal = { sans: canvas.fontFamilies.sans, serif: canvas.fontFamilies.serif };
for (const f of families) {
  decl(`--font-${f}`, famVal[f]);
  paper.fontFamily.push({ type: 'fontFamily', name: `font-${f}`, value: famVal[f], description: f === 'serif' ? 'New York: spot and trip title voice' : 'SF Pro: system font' });
}
for (const w of [...weightsUsed].sort((a, b) => a - b)) {
  const n = `--font-weight-${WEIGHT_NAMES[w] || w}`;
  decl(n, String(w));
  paper.fontWeight.push({ type: 'fontWeight', name: n.slice(2), value: String(w), description: `Weight ${w}` });
}
for (const t of typeStyles) {
  const lh = canvas.lineHeights[t.textStyle].lineHeight;
  decl(`--text-${t.style}`, px(t.size));
  decl(`--leading-${t.style}`, px(lh));
  map[t.app] = {
    type: 'font', numeric: t.numeric,
    names: { family: `--font-${t.family}`, size: `--text-${t.style}`, weight: `--font-weight-${WEIGHT_NAMES[t.weight] || t.weight}`, lineHeight: `--leading-${t.style}` },
  };
  paper.fontSize.push({ type: 'fontSize', name: `text-${t.style}`, value: px(t.size), description: `${t.desc} (${t.textStyle})`.trim() });
  paper.lineHeight.push({ type: 'lineHeight', name: `leading-${t.style}`, value: px(lh), description: `Line height for ${t.app}: Apple macOS default leading for ${t.textStyle}` });
}
sec('Opacities (canvas-tokens.json; app literals, COMPONENTS.md deviation 7)');
for (const o of [...opacities].sort((a, b) => a.value - b.value)) {
  decl(o.name, String(o.value));
  map[o.app] = { type: 'opacity', names: [o.name] };
  paper.opacity.push({ type: 'opacity', name: o.name.slice(2), value: String(o.value), description: o.desc });
}

const byVal = (a, b) => parseFloat(a.value) - parseFloat(b.value);
const paperArray = [
  ...paper.color, ...paper.colorDark,
  ...paper.spacing.sort(byVal), ...paper.radius.sort(byVal), ...paper.container.sort(byVal),
  ...paper.fontFamily, ...paper.fontSize.sort(byVal), ...paper.fontWeight.sort(byVal),
  ...paper.lineHeight.sort(byVal), ...paper.opacity.sort(byVal),
];
// dedupe fontSize/lineHeight entries with identical names is impossible (names unique); equal values with different names are kept.

const header = `/* GENERATED FILE - DO NOT EDIT.
 * Sources: Design/tokens.json, Design/paper/tools/canvas-tokens.json
 * Command: node Design/paper/tools/gen-tokens.mjs
 * Names follow Tailwind v4 namespaces (see the header of tools/gen-tokens.mjs). Dark colours are a second flat set
 * (--color-dark-*), because Paper has no modes. */
`;
fs.writeFileSync(path.join(paperDir, 'tokens.css'), `${header}:root {${cssLines.join('\n')}\n}\n`);
fs.writeFileSync(path.join(paperDir, 'tokens.paper.json'), JSON.stringify(paperArray, null, 2) + '\n');
fs.writeFileSync(path.join(here, 'token-map.json'), JSON.stringify({
  $comment: 'GENERATED by gen-tokens.mjs. App token name -> Paper/CSS name(s). tokens.paper.json order: every light colour (semantic order: text, separator, background, accent, focus, route, status, light ramp, sky, cloud, map, brand, then canvas), then every dark colour in the same order; then spacing, radius, container, fontFamily, fontSize, fontWeight, lineHeight, opacity, each smallest value first. ASSUMPTIONS: size/*, stroke/* and chart/* dimensions are sent as spacing; layout/* as container; canvas shadows are CSS-only (Paper has no shadow token type); tabular numerals are a literal font-variant-numeric style. Translucent canvas colours are color-mix(in srgb, var(--color-x) N%, transparent).',
  tokens: map,
}, null, 2) + '\n');
console.log(`tokens.css: ${used.size} names; tokens.paper.json: ${paperArray.length} entries (${colors.length + canvasColors.filter((x) => !x.isShadow).length} colours x2, ${dims.length} dims, ${typeStyles.length} type styles, ${opacities.length} opacities)`);
