// render-info.mjs - helper for render.sh. `node render-info.mjs <file>` prints: "<W> <H> <relative-png-path> <snapshot-abs-or-dash>"
// `node render-info.mjs --side-html <renderPng> <snapshotPng> <out.html>` writes the comparison page and prints "<W> <H>".
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const paperDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const repo = path.resolve(paperDir, '..', '..');
const png = (f) => { const b = fs.readFileSync(f); return [b.readUInt32BE(16), b.readUInt32BE(20)]; };
const [a, b, c2, d2] = process.argv.slice(2);
if (a === '--side-html') {
  const [rw, rh] = png(b), [sw, sh] = png(c2);
  const sW = Math.round(sw * (rh / sh));
  const gap = 16;
  fs.writeFileSync(d2, `<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;background:#888;display:flex;gap:${gap}px;width:${rw + sW + gap}px;height:${rh}px"><img src="file://${b}" style="width:${rw}px;height:${rh}px;display:block"><img src="file://${c2}" style="width:${sW}px;height:${rh}px;display:block"></body></html>`);
  console.log(rw + sW + gap, rh);
} else {
  const file = path.resolve(a);
  const man = JSON.parse(fs.readFileSync(path.join(paperDir, fs.existsSync(path.join(paperDir, 'artboards-literal')) && file.includes('artboards-literal') ? 'artboards-literal' : 'artboards', 'manifest.json'), 'utf8'));
  const root = file.includes('artboards-literal') ? 'artboards-literal' : 'artboards';
  const rel = path.relative(path.join(paperDir, root), file);
  const m = man.find((e) => e.file === rel.split(path.sep).join('/'));
  if (!m) { console.error(`not in manifest: ${rel}`); process.exit(2); }
  console.log(m.width, m.height, rel.replace(/\.html$/, '.png'), m.snapshot ? path.join(repo, 'Design', m.snapshot) : '-');
}
