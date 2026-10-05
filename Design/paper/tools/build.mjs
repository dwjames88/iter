#!/usr/bin/env node
// build.mjs - renders every artboard module to standalone HTML + manifest + Paper write fragments.
//   node Design/paper/tools/build.mjs [paths...] [--literal] [--max-lines N]
//   no paths  : every src/**/*.mjs; the manifest is rebuilt from scratch.
//   with paths: only those modules (files or folders); entries merge into the existing manifest.
//   --literal : write artboards-literal/ instead, with every var(--x) resolved to its value (fallback if Paper rejects tokens).
// Each src module exports `artboards`: [{ id, name, section, width, height, themes?, covers, snapshot?, notes?,
//   duplicateOf?: '<id>', background?: '<canvas token>', render }].
// Output: artboards/<section>/[light|dark/]<id>[--<theme>].html  (+ .fragments.json beside it) and artboards/manifest.json.
//   screens -> artboards/screens/<theme>/<id>--<theme>.html ; other sections: <id>.html, or <id>--<theme>.html when two themes.
// Artboard root: <div layer-name="<name> · Light · 1280" data-artboard style="width..;overflow:hidden;position:relative;display:flex;
//   flex-direction:column;background:token">. The standalone page links tokens.css (browser preview only).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { withTheme, canvas } from './lib/tokens.mjs';
import { missingSymbols } from './lib/icons.mjs';
import { parse, serialize, pretty, styleOf, styleToString } from './lib/dom.mjs';
import { paperFix } from './lib/paperfix.mjs';
import { buildFragments, diffForDuplicate } from './lib/fragments.mjs';
import { col } from './lib/h.mjs';
import { note } from './lib/chrome.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const paperDir = path.resolve(here, '..');
const srcDir = path.join(paperDir, 'src');
const args = process.argv.slice(2);
const literal = args.includes('--literal');
const mlIdx = args.indexOf('--max-lines');
const maxLines = mlIdx >= 0 ? Number(args[mlIdx + 1]) : 15;
const targets = args.filter((a, i) => !a.startsWith('--') && !(mlIdx >= 0 && i === mlIdx + 1));
const outDir = path.join(paperDir, literal ? 'artboards-literal' : 'artboards');

function discover(p) {
  const st = fs.statSync(p);
  if (st.isFile()) return [p];
  return fs.readdirSync(p).flatMap((n) => discover(path.join(p, n)));
}
const files = (targets.length ? targets.map((t) => path.resolve(t)) : [srcDir]).filter((p) => fs.existsSync(p)).flatMap(discover).filter((f) => f.endsWith('.mjs')).sort();

const PAGES = { foundations: 'Foundations', components: 'Components', flows: 'Flows' };
const pageFor = (section, theme) => (section === 'screens' ? (theme === 'dark' ? 'Screens (Dark)' : 'Screens (Light)') : PAGES[section] || section);
const cap = (s) => s[0].toUpperCase() + s.slice(1);

// token values for --literal
function tokenValues() {
  const css = fs.readFileSync(path.join(paperDir, 'tokens.css'), 'utf8');
  const m = new Map();
  for (const mm of css.matchAll(/^\s*(--[\w-]+):\s*(.+);\s*$/gm)) m.set(mm[1], mm[2]);
  const resolve = (v, depth = 0) => v.replace(/var\((--[\w-]+)\)/g, (_, n) => {
    if (!m.has(n) || depth > 8) throw new Error(`literal: unknown ${n}`);
    return resolve(m.get(n), depth + 1).replace(/"/g, "'"); // quotes inside style="..."
  });
  return (s) => resolve(s);
}
const toLiteral = literal ? tokenValues() : null;
const camel = (k) => k.replace(/-([a-z])/g, (_, ch) => ch.toUpperCase());

// ---- companion note artboards -------------------------------------------------------------------------------
// An artboard with a non-empty `notes` array that draws no `Note / ...` cards itself (and does not set notesInside)
// gets a companion artboard `<id>--notes` (320 wide, height fit, light only, same section/page) placed to its right.
// notes entries: 'Title: body' strings (title = text before the first ': ' when <= 60 chars) or {title, body}.
function noteSpec(n) {
  if (typeof n !== 'string') return n;
  const i = n.indexOf(': ');
  return i > 0 && i <= 60 ? { title: n.slice(0, i), body: n.slice(i + 2) } : { title: 'Note', body: n };
}
function companionOf(ab) {
  const specs = ab.notes.map(noteSpec);
  const est = (t, cpl) => Math.ceil(t.length / cpl) * 14;
  const h = Math.ceil((32 + specs.reduce((a, n) => a + 24 + est(n.title, 44) + est(n.body, 44) + 4, 0) + 12 * (specs.length - 1) + 24) / 8) * 8;
  return {
    id: `${ab.id}--notes`, name: `${ab.name.slice(0, 40).trim()} \u00b7 Notes`, section: ab.section, width: 320, height: h, themes: ['light'], covers: [], notes: [],
    isCompanion: true, companionOf: ab.id, background: 'artboard',
    render: () => col({ name: 'Notes', gap: 12, pad: 16 }, specs.map((n) => note({ title: String(n.title).slice(0, 44), body: n.body, width: 288 }))),
  };
}

const errors = [];
const built = []; // {meta, root(parsed), fragFile}
const byKey = new Map();

for (const file of files) {
  let mod;
  try { mod = await import(pathToFileURL(file).href); } catch (e) { errors.push(`${path.relative(paperDir, file)}: import failed: ${e.message}`); continue; }
  if (!Array.isArray(mod.artboards)) { errors.push(`${path.relative(paperDir, file)}: no \`artboards\` export`); continue; }
  const list = [...mod.artboards]; // companion note artboards are appended while iterating
  for (const ab of list) {
    try {
      for (const k of ['id', 'name', 'section', 'width', 'height', 'render']) if (ab[k] === undefined) throw new Error(`artboard missing "${k}"`);
      if (ab.name.length > (ab.isCompanion ? 50 : 40)) throw new Error(`name longer than 40 chars: "${ab.name}" (the root layer-name is <name> + ' · Light · 1280' and must stay <= 50, so the max name length is 50 minus the suffix length)`);
      if (!['foundations', 'components', 'screens', 'flows'].includes(ab.section)) throw new Error(`bad section "${ab.section}"`);
      const themes = ab.themes || (ab.section === 'screens' ? ['light', 'dark'] : ['light']);
      for (const theme of themes) {
        const suffix = ab.section === 'screens' || themes.length > 1 ? `--${theme}` : '';
        const label = ab.isCompanion ? ab.name : [ab.name, ab.section === 'screens' || themes.length > 1 ? cap(theme) : null, ab.section === 'screens' ? String(ab.width) : null].filter(Boolean).join(' · ');
        const dir = ab.section === 'screens' ? path.join(ab.section, theme) : ab.section;
        const rel = path.join(dir, `${ab.id}${suffix}.html`);
        if (label.length > 50) throw new Error(`root layer-name "${label}" is ${label.length} chars; max is 50, so the artboard name may be at most ${50 - (label.length - ab.name.length)} chars (50 minus the suffix length ${label.length - ab.name.length})`);
        const inner = withTheme(theme, () => String(ab.render()));
        if (theme === themes[0] && !ab.isCompanion && (ab.notes || []).length && !ab.notesInside && !inner.includes('layer-name="Note / ')) list.push(companionOf(ab));
        const bg = withTheme(theme, () => canvas(ab.background || (ab.section === 'screens' ? 'desktop' : 'artboard')));
        const rootStyle = `box-sizing:border-box;width:${ab.width}px;height:${ab.height}px;overflow:hidden;position:relative;display:flex;flex-direction:column;background:${bg}`;
        let rootHtml = `<div layer-name="${label.replace(/"/g, '&quot;')}" data-artboard style="${rootStyle}">\n${inner}\n</div>`;
        rootHtml = paperFix(rootHtml).html; // Paper text-alignment rewrites (tools/lib/paperfix.mjs)
        if (toLiteral) rootHtml = toLiteral(rootHtml);
        // assets: marker src="@asset:<rel>" -> relative path in the html, paper-asset:/// absolute in fragments
        const assetRel = '../'.repeat(rel.split(path.sep).length) + 'assets/';
        const fragHtml = rootHtml.replace(/@asset:([^"]+)/g, (_, r) => `paper-asset://${path.join(paperDir, 'assets', r)}`);
        rootHtml = rootHtml.replace(/@asset:([^"]+)/g, (_, r) => assetRel + r);
        const bodyBg = toLiteral ? toLiteral(bg) : bg;
        const depth = rel.split(path.sep).length; // dirs + file
        const href = '../'.repeat(depth) + 'tokens.css';
        const page = `<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n<title>${label.replace(/</g, '&lt;')}</title>\n<link rel="stylesheet" href="${href}">\n</head>\n<body style="margin:0;background:${bodyBg}">\n${rootHtml}\n</body>\n</html>\n`;
        const root = parse(fragHtml);
        const snapshot = ab.snapshot ? ab.snapshot.replace('{theme}', theme) : undefined;
        const meta = { id: ab.id, name: label, baseName: ab.name, section: ab.section, file: rel.split(path.sep).join('/'), width: ab.width, height: ab.height, theme, covers: ab.covers || [], snapshot, notes: ab.notes || [], bytes: Buffer.byteLength(page), page: pageFor(ab.section, theme), source: path.relative(paperDir, file), ...(ab.companionOf ? { companionOf: ab.companionOf } : {}) };
        const rec = { meta, root, page, ab, theme };
        built.push(rec);
        byKey.set(`${ab.id}|${theme}`, rec);
      }
    } catch (e) { errors.push(`${path.relative(paperDir, file)} [${ab.id || '?'}]: ${e.stack?.split('\n').slice(0, 3).join(' | ') || e.message}`); }
  }
}

function loadRoot(id, theme) {
  const rec = byKey.get(`${id}|${theme}`) || [...byKey.entries()].find(([k]) => k.startsWith(`${id}|`))?.[1];
  if (rec) return { root: rec.root, name: rec.meta.name, id };
  const man = path.join(outDir, 'manifest.json');
  if (!fs.existsSync(man)) return null;
  const m = JSON.parse(fs.readFileSync(man, 'utf8')).find((e) => e.id === id && (e.theme === theme)) || JSON.parse(fs.readFileSync(man, 'utf8')).find((e) => e.id === id);
  if (!m) return null;
  const html = fs.readFileSync(path.join(outDir, m.file), 'utf8');
  const i = html.indexOf('<div layer-name=');
  return { root: parse(html.slice(i)), name: m.name, id };
}

// write
fs.mkdirSync(outDir, { recursive: true });
const manifestPath = path.join(outDir, 'manifest.json');
let manifest = !targets.length || !fs.existsSync(manifestPath) ? [] : JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const key = (m) => `${m.id}|${m.theme}`;
const fresh = new Set(built.map((b) => key(b.meta)));
manifest = manifest.filter((m) => !fresh.has(key(m)));
for (const rec of built) {
  const { meta, root } = rec;
  const out = path.join(outDir, meta.file);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, rec.page);
  const rs = styleOf(root);
  const artboard = { name: meta.name, page: meta.page, width: meta.width, height: meta.height, styles: Object.fromEntries(Object.entries(rs).map(([k, v]) => [camel(k), v])) };
  let { fragments, stats } = buildFragments(root, { maxLines, clones: true });
  const noClone = buildFragments(root, { maxLines, clones: false });
  // clones break up merged sibling writes; keep whichever plan needs fewer calls
  if (noClone.fragments.length <= fragments.length) ({ fragments, stats } = noClone); // fragments.length = writes + clones = calls
  stats.writesNoClone = noClone.fragments.length;
  stats.topLevel = root.children.filter((x) => x.tag).length;
  const frag = { artboard, stats, fragments };
  // duplicates: dark screens duplicate their light twin; authors may set duplicateOf: '<id>'
  let dupSrc = null;
  if (rec.ab.duplicateOf) dupSrc = loadRoot(rec.ab.duplicateOf, meta.theme);
  else if (meta.section === 'screens' && meta.theme === 'dark') dupSrc = loadRoot(meta.id, 'light');
  if (dupSrc) {
    const dup = diffForDuplicate(dupSrc.root, root);
    if (dup) frag.duplicateOf = { artboard: dupSrc.name, id: dupSrc.id, ...dup };
    else console.warn(`note: ${meta.id} (${meta.theme}) differs structurally from ${dupSrc.id}; no duplicateOf emitted`);
  }
  for (const f of frag.fragments) if (f.html && f.html.includes('paper-asset:')) f.hasAsset = true;
  fs.writeFileSync(out.replace(/\.html$/, '.fragments.json'), JSON.stringify(frag, null, 1));
  meta.fragments = { writes: stats.writes, clones: stats.clones, writesNoClone: stats.writesNoClone, duplicateOf: frag.duplicateOf ? frag.duplicateOf.id : null };
  manifest.push(meta);
}
manifest.sort((a, b) => a.section.localeCompare(b.section) || a.id.localeCompare(b.id) || a.theme.localeCompare(b.theme));
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 1) + '\n');

const miss = missingSymbols();
console.log(`${literal ? 'literal ' : ''}build: ${built.length} artboard files from ${files.length} modules -> ${path.relative(paperDir, outDir)}/ (manifest: ${manifest.length} entries)`);
if (miss.length) console.log(`missing SF Symbols (stand-ins drawn): ${miss.join(', ')}`);
if (errors.length) { console.error('\nERRORS:\n' + errors.join('\n')); process.exit(1); }
