#!/usr/bin/env node
// calls.mjs - estimates the number of Paper MCP calls needed to create every artboard.
//   node Design/paper/tools/calls.mjs      reads artboards/**/*.fragments.json, writes artboards/calls.json, prints a table
// Per artboard: 1 create_artboard + write_html calls (writes + clones; a clone is one write_html carrying x-paper-clone)
//   + 1 get_screenshot review per top-level section of the artboard root (min 1).
// "with savings": clones as above; an artboard with duplicateOf costs 1 duplicate_nodes + ceil(changes/50) update_styles
//   (ASSUMPTION: update_styles accepts a batch of up to 50 nodes) + 1 screenshot, instead of creating from scratch.
// "without savings": every fragment is a write (no clones, no duplicates).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const paperDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.join(paperDir, 'artboards');
function* walk(d) { for (const n of fs.readdirSync(d)) { const p = path.join(d, n); if (fs.statSync(p).isDirectory()) yield* walk(p); else if (n.endsWith('.fragments.json')) yield p; } }
const rows = [];
const pages = {};
for (const f of walk(root)) {
  const fr = JSON.parse(fs.readFileSync(f, 'utf8'));
  const { artboard, stats } = fr;
  const review = Math.max(1, stats.topLevel || 1);
  const without = 1 + stats.writesNoClone + review;
  // a clone is 1 write_html; its overrides (style/text/name changes and var-swapped nodes) cost 1 batched call per 50
  let ov = 0;
  for (const f of fr.fragments) if (f.kind === 'clone') ov += Object.keys(f.styleOverrides || {}).length + Object.keys(f.textOverrides || {}).length + Object.keys(f.nameOverrides || {}).length + (f.varRule ? f.varRule.nodes : 0);
  const ovCalls = Math.ceil(ov / 50);
  let withS = 1 + stats.writes + stats.clones + ovCalls + review;
  let dupCalls = null;
  if (fr.duplicateOf) {
    const n = fr.duplicateOf.changedCount;
    dupCalls = 1 + fr.duplicateOf.updateStylesCalls + 1;
    withS = Math.min(withS, dupCalls);
  }
  rows.push({ file: path.relative(root, f).replace('.fragments.json', ''), name: artboard.name, page: artboard.page, writes: stats.writes, clones: stats.clones, review, createArtboard: 1, duplicateOf: fr.duplicateOf ? fr.duplicateOf.id : null, duplicateCalls: dupCalls, callsWithSavings: withS, callsWithoutSavings: without });
  const p = (pages[artboard.page] ||= { artboards: 0, withSavings: 0, withoutSavings: 0 });
  p.artboards++; p.withSavings += withS; p.withoutSavings += without;
}
rows.sort((a, b) => a.file.localeCompare(b.file));
const total = Object.values(pages).reduce((a, p) => ({ artboards: a.artboards + p.artboards, withSavings: a.withSavings + p.withSavings, withoutSavings: a.withoutSavings + p.withoutSavings }), { artboards: 0, withSavings: 0, withoutSavings: 0 });
fs.writeFileSync(path.join(root, 'calls.json'), JSON.stringify({ assumptions: ['update_styles batches up to 50 nodes per call', 'one get_screenshot per top-level child of the artboard root', 'a clone is one write_html call (x-paper-clone); its overrides are batched into 1 update_styles/set_text_content call per 50 changed nodes, per artboard'], pages, total, artboards: rows }, null, 1));
const pad = (s, n) => String(s).padEnd(n);
console.log(pad('artboard', 40), pad('writes', 7), pad('clones', 7), pad('dup', 5), pad('with', 6), 'without');
for (const r of rows) console.log(pad(r.file.slice(-40), 40), pad(r.writes, 7), pad(r.clones, 7), pad(r.duplicateCalls ?? '-', 5), pad(r.callsWithSavings, 6), r.callsWithoutSavings);
console.log('\nper page:'); for (const [k, v] of Object.entries(pages)) console.log(`  ${pad(k, 18)} ${v.artboards} artboards  ${v.withSavings} calls with savings, ${v.withoutSavings} without`);
console.log(`  TOTAL ${total.artboards} artboards  ${total.withSavings} with savings, ${total.withoutSavings} without`);
