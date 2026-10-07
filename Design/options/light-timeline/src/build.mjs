#!/usr/bin/env node
/* README-dev (kept here on purpose; no other docs)
 * Light-timeline option mockups for Iter. Paper-form HTML (inline styles, layer-name attributes, flex layout), built with the helpers in
 * Design/paper/tools/lib (imported, never modified). Output: Design/options/light-timeline/artboards/<id>.html, one complete page per
 * artboard at exactly width x height, every var(--token) resolved to its literal value (light or dark set), plus artboards/manifest.json.
 *
 * Build:    node Design/options/light-timeline/src/build.mjs [id-or-file ...]      (no args = every src/artboards/*.mjs)
 * Render:   Design/options/light-timeline/tools/render.sh [--2x] [id ...]           (no ids = every artboard in the manifest)
 *           -> /tmp/iter-scratch/timeline-options/renders/<id>.png
 *              (and <id>@2x.png with --2x). Headless Chrome only; nothing opens a window.
 * An artboard module (src/artboards/NN-name.mjs) exports `artboards = [{ id, width, height, appearance: 'light'|'dark', html }]` where
 * html is a FUNCTION returning Html/string. It runs inside withTheme(appearance), so c()/canvas() resolve to that theme.
 * Pieces: src/data.mjs (data + sky), src/shell.mjs (window + components), src/timeline-h.mjs, src/timeline-v.mjs (timelines).
 * Dark mode = the --color-dark-* token set; the dark window is espresso (background/window #150C0A), not grey.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { withTheme } from '../../../paper/tools/lib/tokens.mjs';
import { missingSymbols } from '../../../paper/tools/lib/icons.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const css = fs.readFileSync(path.resolve(root, '../../paper/tokens.css'), 'utf8');
const TOK = new Map([...css.matchAll(/^\s*(--[\w-]+):\s*(.+);\s*$/gm)].map((m) => [m[1], m[2]]));
const lit = (s, depth = 0) => s.replace(/var\((--[\w-]+)\)/g, (_, n) => {
  if (!TOK.has(n) || depth > 8) throw new Error(`unknown token ${n}`);
  return lit(TOK.get(n), depth + 1).replace(/"/g, "'");
});

const args = process.argv.slice(2);
const dir = path.join(here, 'artboards');
const files = fs.readdirSync(dir).filter((f) => f.endsWith('.mjs')).sort();
const outDir = path.join(root, 'artboards');
fs.mkdirSync(outDir, { recursive: true });
const manPath = path.join(outDir, 'manifest.json');
let manifest = args.length && fs.existsSync(manPath) ? JSON.parse(fs.readFileSync(manPath, 'utf8')) : [];
for (const f of files) {
  const mod = await import(pathToFileURL(path.join(dir, f)).href);
  for (const a of mod.artboards) {
    if (args.length && !args.some((x) => a.id.includes(x) || f.includes(x))) continue;
    const inner = withTheme(a.appearance, () => String(a.html()));
    const page = `<!doctype html>\n<html><head><meta charset="utf-8"><title>${a.id}</title><meta name="viewport" content="width=${a.width}">\n<style>html,body{margin:0;padding:0;background:transparent;width:${a.width}px;height:${a.height}px;overflow:hidden}body{-webkit-font-smoothing:antialiased;font-family:-apple-system,'SF Pro',system-ui,sans-serif}</style></head>\n<body>\n<div layer-name="${a.id} · ${a.appearance} · ${a.width}" data-artboard style="box-sizing:border-box;position:relative;width:${a.width}px;height:${a.height}px;overflow:hidden;display:flex;flex-direction:column">\n${lit(inner)}\n</div>\n</body></html>\n`;
    if (/var\(--/.test(page)) throw new Error(`${a.id}: unresolved var()`);
    fs.writeFileSync(path.join(outDir, `${a.id}.html`), page);
    manifest = manifest.filter((m) => m.id !== a.id).concat({ id: a.id, file: `${a.id}.html`, width: a.width, height: a.height, appearance: a.appearance });
    console.log(`built ${a.id} (${a.width}x${a.height} ${a.appearance})`);
  }
}
manifest.sort((a, b) => a.id.localeCompare(b.id));
fs.writeFileSync(manPath, JSON.stringify(manifest, null, 1));
if (missingSymbols().length) console.warn('missing symbols:', missingSymbols().join(', '));
