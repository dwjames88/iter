#!/usr/bin/env node
// log-table.mjs - rewrites the generated parts of BUILD-LOG.md from build-state/ and artboards/plan.json:
//   the artboard status table (every artboard, in build order) and the machine id table.
// Review notes come from each state's `reviewed` text. Lines between the BEGIN/END markers are replaced.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const paperDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const plan = JSON.parse(fs.readFileSync(path.join(paperDir, 'artboards', 'plan.json'), 'utf8'));
const layout = JSON.parse(fs.readFileSync(path.join(paperDir, 'artboards', 'layout.json'), 'utf8'));
const pageOf = {};
for (const [page, v] of Object.entries(layout.pages)) for (const r of v.rows) for (const it of r.items) pageOf[it.file] = page;
const stateDir = path.join(paperDir, 'build-state');
const load = (file) => { const f = path.join(stateDir, file.replace(/\.html$/, '').replace(/\//g, '__') + '.json'); return fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null; };
const fragCount = (file) => { try { return JSON.parse(fs.readFileSync(path.join(paperDir, 'artboards', file.replace(/\.html$/, '.fragments.json')), 'utf8')).fragments.length; } catch { return '?'; } };
const esc = (s) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');
const rows = [], ids = [];
const counts = { reviewed: 0, placed: 0, progress: 0, none: 0 };
for (const st of plan.stages) for (const a of st.artboards || []) {
  const file = a.file;
  const s = load(file);
  let status = 'not started', note = '';
  if (s) {
    if (s.reviewed) { status = 'reviewed'; note = s.reviewed === true ? '' : s.reviewed; counts.reviewed++; }
    else if (s.dup) { status = 'in progress (dark styling)'; counts.progress++; }
    else {
      const n = fragCount(file);
      if (s.done.length >= n) { status = 'placed, not reviewed'; counts.placed++; }
      else { const next = Math.min(...Array.from({ length: n }, (_, i) => i + 1).filter((q) => !s.done.includes(q))); status = `in progress (next fragment ${next} of ${n})`; counts.progress++; }
    }
    ids.push(`| ${esc(s.name)} | ${s.artboardId} | ${file} |`);
  } else counts.none++;
  rows.push(`| ${st.n} | ${esc(a.name)} | ${pageOf[file] || ''} | ${status} | ${esc(note)} |`);
}
const table = [`Reviewed ${counts.reviewed}, placed ${counts.placed}, in progress ${counts.progress}, not started ${counts.none} (of ${rows.length}).`, '', '| Stage | Artboard | Page | Status | Review notes |', '|---|---|---|---|---|', ...rows].join('\n');
const idTable = ['| Artboard | Node id | Source |', '|---|---|---|', ...ids].join('\n');
const logPath = path.join(paperDir, 'BUILD-LOG.md');
let log = fs.readFileSync(logPath, 'utf8');
const put = (name, body) => {
  const a = `<!-- BEGIN ${name} -->`, b = `<!-- END ${name} -->`;
  if (!log.includes(a)) throw new Error(`missing marker ${a}`);
  log = log.slice(0, log.indexOf(a) + a.length) + '\n' + body + '\n' + log.slice(log.indexOf(b));
};
put('ARTBOARDS', table);
put('IDS', idTable);
fs.writeFileSync(logPath, log);
console.log(table.split('\n')[0]);
