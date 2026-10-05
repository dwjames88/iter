#!/usr/bin/env node
// check.mjs - lints and verifies built artboards. Exits non-zero on any ERROR.
//   node Design/paper/tools/check.mjs [--fast] [--strict] [filter...]
//   --fast    skip the headless-Chrome overflow pass      --strict  uncovered SCREENS/COMPONENTS rows are errors
//   filter    only artboards whose id/file contains one of the strings (coverage and totals still use the whole manifest)
// Checks: (a) coverage of SCREENS.md States + "Menus, popovers and dialogs" rows and COMPONENTS.md ### headings (+ System
//   components); unknown `covers` entries = error. (b) literal colours in src/**, tools/lib/**, artboards/** (allowed in
//   tokens.css, canvas-tokens.json, gen-tokens.mjs, symbols data). (c) forbidden CSS/tags/attrs in artboards, <style>, class,
//   var() names missing from tokens.css, fragments over the line limit. (d) layer-name on every element in the root (<=50 chars,
//   svg children exempt) and box-sizing:border-box. (e) overflow (descendants beyond the root, children wider than their non-clipping parent, clipped/overflowing text), in headless Chrome (batches of 8 embedded artboards,
//   sequential, one --dump-dom run per batch): no descendant beyond the root, root scroll size == size; WARN for clipped or
//   overflowing text boxes; reports `fit` (natural height, rounded up to 8). (f) sizes: warn > 200 KB per file.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { parse, styleOf } from './lib/dom.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const paperDir = path.resolve(here, '..');
const repo = path.resolve(paperDir, '..', '..');
const argv = process.argv.slice(2);
const FAST = argv.includes('--fast'), STRICT = argv.includes('--strict');
const filters = argv.filter((a) => !a.startsWith('--'));
const SCRATCH = '/tmp/scratch/scratchpad/paper/check';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const MAX_LINES = 15, WARN_BYTES = 200 * 1024;

const manifestPath = path.join(paperDir, 'artboards', 'manifest.json');
if (!fs.existsSync(manifestPath)) { console.error('no artboards/manifest.json: run build.mjs first'); process.exit(1); }
const manifestAll = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const manifest = filters.length ? manifestAll.filter((m) => filters.some((f) => m.id.includes(f) || m.file.includes(f))) : manifestAll;

const issues = new Map(); // file -> [{level, msg}]
const add = (file, level, msg) => { if (!issues.has(file)) issues.set(file, []); issues.get(file).push({ level, msg }); };
const rel = (p) => path.relative(paperDir, p);

// ---------- (a) coverage -----------------------------------------------------------------------------------
const norm = (s) => s.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/\s+/g, ' ').trim();
function expectedCoverage() {
  const out = [];
  const screens = fs.readFileSync(path.join(repo, 'Design', 'SCREENS.md'), 'utf8').split('\n');
  let h2 = '', inTable = null;
  for (const line of screens) {
    const m = line.match(/^## (.+)/);
    if (m) { h2 = m[1].trim(); inTable = null; continue; }
    if (/^\|\s*State\s*\|/.test(line) || /^\|\s*Element\s*\|/.test(line)) { inTable = /Element/.test(line) ? 'menus' : 'states'; continue; }
    if (inTable && /^\|\s*-/.test(line)) continue;
    if (inTable && line.startsWith('|')) {
      const cell = norm(line.split('|')[1] || '');
      if (!cell) continue;
      if (inTable === 'menus' && h2.startsWith('Menus')) out.push(`Menus/${cell}`);
      else if (inTable === 'states') out.push(`${h2}/${cell}`);
    } else if (inTable && !line.startsWith('|')) inTable = null;
  }
  const comps = fs.readFileSync(path.join(repo, 'Design', 'COMPONENTS.md'), 'utf8').split('\n');
  for (const line of comps) {
    const m = line.match(/^### (.+)/);
    if (m) out.push(`Component/${m[1].trim()}`);
    if (/^## System components/.test(line)) out.push('Component/System components');
  }
  return out;
}
const expected = expectedCoverage();
const expectedSet = new Set(expected);
const covered = new Set();
for (const m of manifestAll) for (const cv of m.covers || []) {
  const n = norm(cv);
  covered.add(n);
  if (!expectedSet.has(n)) add(m.file, 'ERROR', `covers entry matches nothing (typo?): "${cv}"`);
}
const uncovered = expected.filter((e) => !covered.has(e));

// ---------- (b) literal colours ---------------------------------------------------------------------------
const NAMED = 'aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightslategray lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue slateblue slategray snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white whitesmoke yellow yellowgreen'.split(' ');
const namedRe = new RegExp(`^(${NAMED.join('|')})$`, 'i');
const HEX = /#[0-9a-fA-F]{3,8}\b/;
// Output (html): strict, any literal colour function / quoted named colour is an error.
const FUNC_STRICT = /(?<![\w.])(rgba?|hsla?|hwb|lab|lch|oklab|oklch)\s*\(/i;
// Source (js): only colour literals used as CSS values: numeric-argument colour functions, or a css property key followed by a named colour.
const FUNC_JS = /(?<![\w.])(rgba?|hsla?|hwb|oklch|oklab)\s*\(\s*[\d.]+%?\s*[,\s\/]/i;
const COLOR_PROP = /(?:^|[^\w-])(color|background(?:-color)?|border(?:-[a-z]+)*|fill|stroke|outline(?:-color)?|box-shadow|text-shadow|caret-color|stop-color)\s*:\s*['"]?([a-zA-Z]+)\b/g;
const COLOR_PROP_JS = /\b(color|background|backgroundColor|border\w*|fill|stroke|outline\w*|stopColor|caretColor|boxShadow)\s*[:=]\s*['"`]\s*([a-zA-Z]+)\b/g;
function scanText(file, text, kind) {
  let t = text;
  if (kind === 'js') t = t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[\s;,(])\/\/.*$/gm, '$1');
  t = t.replace(/url\(#[^)]*\)/g, '');
  const lines = t.split('\n');
  lines.forEach((ln, i) => {
    if (HEX.test(ln)) add(file, 'ERROR', `literal hex colour at line ${i + 1}: ${ln.trim().slice(0, 100)}`);
    if ((kind === 'js' ? FUNC_JS : FUNC_STRICT).test(ln)) add(file, 'ERROR', `literal colour function at line ${i + 1}: ${ln.trim().slice(0, 100)}`);
    for (const m of ln.matchAll(kind === 'js' ? COLOR_PROP_JS : COLOR_PROP)) if (namedRe.test(m[2])) add(file, 'ERROR', `named colour "${m[2]}" at line ${i + 1}`);
    if (kind !== 'js') for (const m of ln.matchAll(/(?:fill|stroke|stop-color)="(white|black|red|blue|green|gray|grey|yellow|orange|purple|pink)"/gi)) add(file, 'ERROR', `named colour attribute ${m[0]} at line ${i + 1}`);
  });
}
function* files(dir, exts) {
  if (!fs.existsSync(dir)) return;
  for (const n of fs.readdirSync(dir)) {
    const p = path.join(dir, n);
    const st = fs.statSync(p);
    if (st.isDirectory()) yield* files(p, exts);
    else if (exts.some((e) => n.endsWith(e))) yield p;
  }
}
for (const dir of [path.join(paperDir, 'src'), path.join(here, 'lib')]) for (const f of files(dir, ['.mjs'])) scanText(rel(f), fs.readFileSync(f, 'utf8'), 'js');

// ---------- (c)(d) per-artboard structure -------------------------------------------------------------------
const cssNames = new Set([...fs.readFileSync(path.join(paperDir, 'tokens.css'), 'utf8').matchAll(/^\s*(--[\w-]+):/gm)].map((m) => m[1]));
const FORBIDDEN_TAGS = new Set(['table', 'tr', 'td', 'th', 'thead', 'tbody', 'style', 'script', 'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'ul', 'ol', 'li', 'button', 'input', 'form']);
const roots = new Map();
for (const m of manifest) {
  const fp = path.join(paperDir, 'artboards', m.file);
  if (!fs.existsSync(fp)) { add(m.file, 'ERROR', 'file missing: rebuild'); continue; }
  const html = fs.readFileSync(fp, 'utf8');
  if (m.bytes > WARN_BYTES || html.length > WARN_BYTES) add(m.file, 'WARN', `file is ${(Buffer.byteLength(html) / 1024).toFixed(0)} KB (> 200 KB; Paper per-call limit undocumented)`);
  if (/<style[\s>]/i.test(html)) add(m.file, 'ERROR', '<style> block present');
  const i = html.indexOf('<div layer-name=');
  const body = html.slice(i, html.lastIndexOf('</body>'));
  scanText(m.file, body.replace(/layer-name="[^"]*"/g, ''), 'html');
  for (const v of body.matchAll(/var\((--[\w-]+)/g)) if (!cssNames.has(v[1])) add(m.file, 'ERROR', `var(${v[1]}) is not defined in tokens.css`);
  let root;
  try { root = parse(body); } catch (e) { add(m.file, 'ERROR', `cannot parse: ${e.message}`); continue; }
  roots.set(m.file, { root, html: body });
  const seen = { count: 0 };
  (function walk(n, isRoot) {
    if (n.text !== undefined) return;
    seen.count++;
    const ln = n.attrs['layer-name'];
    const label = ln || `<${n.tag}>`;
    if (n.tag === 'img') {
      if (!n.attrs['data-asset']) add(m.file, 'ERROR', `<img> only via lib asset() (${label})`);
      else if (!fs.existsSync(path.join(paperDir, 'assets', n.attrs['data-asset']))) add(m.file, 'ERROR', `asset file missing: assets/${n.attrs['data-asset']}`);
      else if (!fs.existsSync(path.resolve(path.dirname(fp), n.attrs.src || ''))) add(m.file, 'ERROR', `img src does not resolve from the artboard file: ${n.attrs.src}`);
    }
    if (FORBIDDEN_TAGS.has(n.tag)) add(m.file, 'ERROR', `forbidden tag <${n.tag}> (${label})`);
    if (!ln || !ln.trim()) add(m.file, 'ERROR', `element <${n.tag}> without layer-name`);
    else if (ln.length > 50) add(m.file, 'ERROR', `layer-name > 50 chars: "${ln}"`);
    if ('class' in n.attrs) add(m.file, 'ERROR', `class attribute on "${label}"`);
    if (n.attrs.id !== undefined && n.tag !== 'svg') add(m.file, 'WARN', `id attribute on "${label}"`);
    const st = styleOf(n);
    for (const [k, v] of Object.entries(st)) {
      if (/^margin/.test(k)) add(m.file, 'ERROR', `margin on "${label}" (${k})`);
      if (k === 'float') add(m.file, 'ERROR', `float on "${label}"`);
      if (k === 'display' && /^(grid|inline)/.test(v)) add(m.file, 'ERROR', `display:${v} on "${label}"`);
      if (k === 'background' || k === 'color') { /* literal colours scanned above */ }
      if (k === 'position' && v === 'absolute' && isRoot) add(m.file, 'ERROR', 'root must not be absolute');
    }
    if (!isRoot && st['box-sizing'] !== 'border-box') add(m.file, 'ERROR', `"${label}" lacks box-sizing:border-box`);
    if (n.tag === 'svg') return; // svg children exempt
    n.children.forEach((c) => walk(c, false));
  })(root, true);
  // fragments
  const ff = fp.replace(/\.html$/, '.fragments.json');
  if (fs.existsSync(ff)) {
    const fr = JSON.parse(fs.readFileSync(ff, 'utf8'));
    for (const f of fr.fragments) if (f.kind === 'write' && f.lines > MAX_LINES) add(m.file, 'ERROR', `fragment #${f.seq} has ${f.lines} lines (> ${MAX_LINES}) under ${f.parentPath}`);
  } else add(m.file, 'ERROR', 'fragments.json missing');
}
// whole-page absolute-cover check: one absolute element as big as the root (except "Scrim")
for (const [file, { root }] of roots) {
  const ab = styleOf(root);
  const w = parseFloat(ab.width), h = parseFloat(ab.height);
  (function walk(n) {
    if (n.text !== undefined || n.tag === 'svg') return;
    const s = styleOf(n);
    if (s.position === 'absolute' && s.top === '0' && s.left === '0' && s.right === '0' && s.bottom === '0' && n.attrs['layer-name'] !== 'Scrim' && n.attrs['layer-name'] !== 'Map Art')
      add(file, 'ERROR', `absolute element covering its whole parent: "${n.attrs['layer-name']}" (only Scrim allowed)`);
    n.children.forEach(walk);
  })(root);
}

// ---------- (e) overflow in headless Chrome ------------------------------------------------------------------
const measured = new Map();
function chromePass() {
  fs.mkdirSync(SCRATCH, { recursive: true });
  const list = manifest.filter((m) => roots.has(m.file));
  const BATCH = 8;
  for (let b = 0; b < list.length; b += BATCH) {
    const batch = list.slice(b, b + BATCH);
    const slots = batch.map((m, i) => `<div data-slot="${i}" data-file="${m.file}" style="display:block;position:relative;width:${m.width}px;height:${m.height}px;margin:0 0 0 0;overflow:visible">${roots.get(m.file).html}</div>`).join('\n');
    const script = `<script>
function run(){const res=[];document.querySelectorAll('[data-slot]').forEach(function(slot){
 var root=slot.querySelector('[data-artboard]'),r=root.getBoundingClientRect(),o={file:slot.getAttribute('data-file'),issues:[],warns:[]};
 if(root.scrollWidth>root.clientWidth+1||root.scrollHeight>root.clientHeight+1)o.issues.push('root content overflows: scroll '+root.scrollWidth+'x'+root.scrollHeight+' vs '+root.clientWidth+'x'+root.clientHeight);
 var beyond=0,clip=0,tov=0,cov=0;
 root.querySelectorAll('*').forEach(function(e){
  if(e.closest('svg')&&e.tagName.toLowerCase()!=='svg')return;
  var b=e.getBoundingClientRect();if(b.width===0&&b.height===0)return;
  var nm=e.getAttribute('layer-name')||e.tagName;
  if(b.left<r.left-0.5||b.top<r.top-0.5||b.right>r.right+0.5||b.bottom>r.bottom+0.5){if(beyond++<6)o.issues.push('"'+nm+'" extends beyond the artboard ('+Math.round(b.left-r.left)+','+Math.round(b.top-r.top)+' '+Math.round(b.width)+'x'+Math.round(b.height)+')');}
  var cs=getComputedStyle(e);
  if(e!==root&&cs.overflow==='hidden'&&(e.scrollWidth>e.clientWidth+1||e.scrollHeight>e.clientHeight+1)){if(clip++<4)o.warns.push('"'+nm+'" clips its content ('+e.scrollWidth+'x'+e.scrollHeight+' in '+e.clientWidth+'x'+e.clientHeight+')');}
  if(e.children.length===0&&e.tagName!=='svg'&&e.textContent&&e.scrollWidth>e.clientWidth+1){if(tov++<4)o.warns.push('text "'+nm+'" overflows its box ('+e.scrollWidth+' > '+e.clientWidth+')');}
  else if(e!==root&&e.tagName!=='svg'&&e.children.length>0&&cs.overflow!=='hidden'&&e.scrollWidth>e.clientWidth+1){if(cov++<6)o.issues.push('"'+nm+'" children overflow its content box horizontally ('+e.scrollWidth+' > '+e.clientWidth+')');}
 });
 var h0=root.style.height;root.style.height='auto';o.fitH=root.offsetHeight;root.style.height=h0;
 res.push(o);});
 document.body.innerHTML='<pre id="__r">'+JSON.stringify(res).replace(/</g,'\\\\u003c')+'</pre>';}
window.addEventListener('load',function(){setTimeout(run,50)});
</script>`;
    const page = `<!doctype html><html><head><meta charset="utf-8"><link rel="stylesheet" href="file://${path.join(paperDir, 'tokens.css')}"></head><body style="margin:0">\n${slots}\n${script}</body></html>`;
    const pf = path.join(SCRATCH, `batch-${b / BATCH}.html`);
    fs.writeFileSync(pf, page);
    const r = spawnSync('nice', ['-n', '10', CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--allow-file-access-from-files', '--virtual-time-budget=8000', '--window-size=2400,1600', '--dump-dom', `file://${pf}`], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
    const mm = /<pre id="__r">([\s\S]*?)<\/pre>/.exec(r.stdout || '');
    if (!mm) { for (const m of batch) add(m.file, 'ERROR', 'Chrome overflow pass produced no result'); continue; }
    const data = JSON.parse(mm[1].replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&'));
    for (const o of data) {
      measured.set(o.file, o.fitH);
      o.issues.forEach((s) => add(o.file, 'ERROR', s));
      o.warns.forEach((s) => add(o.file, 'WARN', s));
    }
  }
}
if (!FAST) chromePass();

// ---------- report --------------------------------------------------------------------------------------------
let errors = 0, warns = 0;
const pad = (s, n) => String(s).padEnd(n);
for (const [file, list] of [...issues.entries()].sort()) {
  if (filters.length && !filters.some((f) => file.includes(f)) ) continue;
  for (const it of list) { console.log(`${it.level} ${file}: ${it.msg}`); if (it.level === 'ERROR') errors++; else warns++; }
}
if (!filters.length || true) {
  if (uncovered.length) {
    console.log(`\n${STRICT ? 'ERROR' : 'INFO'} coverage: ${uncovered.length} of ${expected.length} expected entries not covered yet`);
    if (STRICT) errors += uncovered.length;
    if (argv.includes('--list-uncovered') || uncovered.length <= 12) uncovered.forEach((u) => console.log(`  - ${u}`));
    else console.log('  (pass --list-uncovered to list them)');
  } else console.log(`\ncoverage: all ${expected.length} expected entries covered`);
}
console.log('\n' + [pad('artboard', 34), pad('size', 11), pad('KB', 6), pad('writes', 7), pad('clones', 7), pad('fit H', 7), pad('errs', 5), 'warns'].join(' '));
let totalBytes = 0;
for (const m of manifest) {
  const l = issues.get(m.file) || [];
  totalBytes += m.bytes;
  const fit = measured.get(m.file);
  console.log([pad(m.file.replace(/\.html$/, '').slice(-34), 34), pad(`${m.width}x${m.height}`, 11), pad((m.bytes / 1024).toFixed(0), 6), pad(m.fragments?.writes ?? '-', 7), pad(m.fragments?.clones ?? '-', 7), pad(fit ? Math.ceil(fit / 8) * 8 : '-', 7), pad(l.filter((x) => x.level === 'ERROR').length, 5), l.filter((x) => x.level === 'WARN').length].join(' '));
}
console.log(`\n${manifest.length} artboards, ${(totalBytes / 1024).toFixed(0)} KB total, ${errors} error(s), ${warns} warning(s)${FAST ? ' (Chrome pass skipped)' : ''}`);
process.exit(errors ? 1 : 0);
