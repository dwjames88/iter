#!/usr/bin/env node
// paste-bundle.mjs - files for Paper's "import a local file" / paste (no MCP calls needed).
//   node Design/paper/tools/paste-bundle.mjs
// Writes, in canonical order (tools/lib/order.mjs), one file per artboard containing ONLY the root element
// (the element with data-artboard; no doctype, no <link>):
//   paste/<page>/<NN>-<stem>.html           var(--...) tokens intact, <img> assets as paper-asset:///<abs path>
//   paste-literal/<page>/<NN>-<stem>.html   every var(--...) resolved to its value (fallback if Paper rejects tokens)
//   paste/js/<stem>.js                      lazy data for preview.html's "Copy for Paper" buttons (window.__PASTE[stem])
// <page> is foundations | components | screens-light | screens-dark | flows; NN restarts per page. These directories are
// pure derivatives of artboards/ and large, so they are git-ignored (see Design/paper/.gitignore): rebuild with this script.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { orderManifest, PAGES } from './lib/order.mjs';
const paperDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const man = orderManifest(JSON.parse(fs.readFileSync(path.join(paperDir, 'artboards', 'manifest.json'), 'utf8')));
const css = fs.readFileSync(path.join(paperDir, 'tokens.css'), 'utf8');
const table = new Map([...css.matchAll(/^\s*(--[\w-]+):\s*(.+);\s*$/gm)].map((m) => [m[1], m[2]]));
const resolve = (v, d = 0) => v.replace(/var\((--[\w-]+)\)/g, (_, n) => { if (!table.has(n) || d > 8) throw new Error(`unknown ${n}`); return resolve(table.get(n), d + 1).replace(/"/g, "'"); });
const SLUG = { Foundations: 'foundations', Components: 'components', 'Screens (Light)': 'screens-light', 'Screens (Dark)': 'screens-dark', Flows: 'flows' };
for (const d of ['paste', 'paste-literal']) fs.rmSync(path.join(paperDir, d), { recursive: true, force: true });
fs.mkdirSync(path.join(paperDir, 'paste', 'js'), { recursive: true });
const counters = {};
let bytes = 0, bytesLit = 0;
for (const m of man) {
  const html = fs.readFileSync(path.join(paperDir, 'artboards', m.file), 'utf8');
  let root = html.slice(html.indexOf('<div layer-name='), html.lastIndexOf('</body>')).trim();
  root = root.replace(/src="(?:\.\.\/)+assets\/([^"]+)"/g, (_, r) => `src="paper-asset://${path.join(paperDir, 'assets', r)}"`);
  const n = (counters[m.page] = (counters[m.page] || 0) + 1);
  const stem = path.basename(m.file, '.html');
  const name = `${String(n).padStart(3, '0')}-${stem}.html`;
  for (const [dir, body] of [['paste', root], ['paste-literal', resolve(root)]]) {
    const out = path.join(paperDir, dir, SLUG[m.page], name);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, body);
    if (dir === 'paste') bytes += body.length; else bytesLit += body.length;
  }
  fs.writeFileSync(path.join(paperDir, 'paste', 'js', `${stem}.js`), `(window.__PASTE=window.__PASTE||{})[${JSON.stringify(stem)}]=${JSON.stringify(root)};\n`);
}
fs.writeFileSync(path.join(paperDir, '.gitignore'), '# derived from artboards/ by tools/paste-bundle.mjs (large; rebuild instead of committing)\n/paste/\n/paste-literal/\n');
console.log(`paste: ${man.length} files, ${(bytes / 1048576).toFixed(1)} MB; paste-literal ${(bytesLit / 1048576).toFixed(1)} MB; paste/js ~${(bytes / 1048576).toFixed(1)} MB (git-ignored)`);
