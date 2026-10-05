import { readdirSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../..'); // Design/paper
const pages = ['foundations', 'components', 'screens-light', 'screens-dark', 'flows'];
const skip = new Set(['paste/foundations/002-F02-type-scale.html']);
const out = [];
let total = 0;
for (const p of pages) {
  const dir = join(root, 'paste', p);
  const files = readdirSync(dir).filter((f) => /^\d{3}-.*\.html$/.test(f)).sort();
  let n = 0;
  for (const f of files) {
    const rel = `paste/${p}/${f}`;
    if (skip.has(rel)) continue;
    out.push(rel);
    total += statSync(join(root, rel)).size;
    n++;
  }
  console.log(`${p}: ${n}`);
}
writeFileSync(join(here, 'ORDER.txt'), out.join('\n') + '\n');
console.log(`total: ${out.length} files, ${total} bytes`);
