#!/usr/bin/env node
// plan.mjs - ordered build stages for pushing the artboards into Paper, with call counts: artboards/plan.json + plan-tables.md
//   node Design/paper/tools/plan.mjs      (run build.mjs and calls.mjs first)
// ASSUMPTIONS (all stated in the output): create_tokens takes <= 100 tokens per call; get_guide 1, get_basic_info 1,
// get_font_family_info 2 (SF Pro, New York), create_page 1 per page (5), finish_working_on_nodes 1 per session (reserved in every
// budget); an artboard costs create_artboard 1 + its write_html/clone calls + batched update calls + 1 screenshot per top-level section
// (see calls.mjs); a dark twin costs duplicate_nodes 1 + ceil(changes/50) update_styles + 1 screenshot.
// "one write per artboard" variant: create 1 + write_html 1 + screenshot 1 = 3 per artboard (ignores Paper's ~15-line guidance).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { orderManifest, covRank } from './lib/order.mjs';
const paperDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const man = JSON.parse(fs.readFileSync(path.join(paperDir, 'artboards', 'manifest.json'), 'utf8'));
const calls = JSON.parse(fs.readFileSync(path.join(paperDir, 'artboards', 'calls.json'), 'utf8'));
const tokens = JSON.parse(fs.readFileSync(path.join(paperDir, 'tokens.paper.json'), 'utf8'));
const callsBy = new Map(calls.artboards.map((a) => [a.file + '.html', a.callsWithSavings]));
const TOKENS_PER_CALL = 100;
const OVERHEAD = { get_guide: 1, get_basic_info: 1, get_font_family_info: 2, create_page: 5, create_tokens: Math.ceil(tokens.length / TOKENS_PER_CALL) };
const setup = Object.values(OVERHEAD).reduce((a, b) => a + b, 0);
const FINISH = 1;

const ordered = orderManifest(man);
const cost = (e) => callsBy.get(e.file) ?? 0;
const used = new Set();
const isMenuOnly = (e) => (e.covers || []).length > 0 && e.covers.every((c) => c.startsWith('Menus/')) ;
const pick = (pred) => { const r = ordered.filter((e) => !used.has(e.file) && pred(e)); r.forEach((e) => used.add(e.file)); return r; };
const ids = (list, theme) => (e) => list.includes(e.id) && (!theme || e.theme === theme);
const FOUND1 = ['F01-colour', 'F02-type-scale', 'F07-light-index', 'F03-spacing-radii'];
const CORE = ['C-light-badge', 'C-light-badge-large', 'C-score-chip', 'C-no-forecast-ring', 'C-confidence-mark', 'C-sample-data-label', 'C-provenance-tag', 'C-warning-lines', 'C-weather-attribution'];
const KEY = ['S-shell-default', 'S-trips-list', 'S-trip-builder-default', 'S-explore-default', 'S-explore-selected', 'S-spot-sample', 'S-saved-list', 'S-scout-results'];
const stages = [];
const stage = (name, list, extra = 0) => stages.push({ name, artboards: list, extra });
stage('Setup: guide, basic info, fonts, pages, tokens', [], setup);
stage('Foundations: colour, type, Light Index, spacing', pick(ids(FOUND1)));
stage('Core components', pick(ids(CORE)));
stage('Key light screens', pick((e) => e.theme === 'light' && ids(KEY)(e)));
stage('Dark twins of the key screens', pick((e) => e.theme === 'dark' && KEY.includes(e.id)));
stage('Remaining domain components', pick((e) => e.page === 'Components' && !isMenuOnly(e) && !e.id.startsWith('M-')));
const is960 = (e) => e.page.startsWith('Screens') && e.width === 960;
const isMenuScreen = (e) => e.page.startsWith('Screens') && isMenuOnly(e);
stage('Remaining light screens (1280 and other sizes)', pick((e) => e.page === 'Screens (Light)' && !e.companionOf && !is960(e) && !isMenuScreen(e)));
stage('Remaining dark twins', pick((e) => e.page === 'Screens (Dark)' && !is960(e) && !isMenuScreen(e)));
stage('960 variants (light and dark)', pick((e) => is960(e) && !e.companionOf));
stage('Menus, popovers and system boards', pick((e) => (e.page === 'Components' && (isMenuOnly(e) || e.id.startsWith('M-'))) || (isMenuScreen(e) && !e.companionOf)));
stage('Flows: overview and the four journeys', pick((e) => e.page === 'Flows'));
stage('Note companions', pick((e) => !!e.companionOf));
stage('F04, F05, F06 and remaining foundations', pick((e) => e.page === 'Foundations'));
const left = ordered.filter((e) => !used.has(e.file));
if (left.length) stage('Anything else', pick(() => true));

let cum = 0;
for (const s of stages) { s.calls = s.extra + s.artboards.reduce((a, e) => a + cost(e), 0); cum += s.calls; s.cumulative = cum; }
const total = cum + FINISH;

function fit(budget) {
  let run = FINISH, full = [], partial = null;
  for (const [i, s] of stages.entries()) {
    if (run + s.calls <= budget) { run += s.calls; full.push(i); continue; }
    const inc = [], exc = [];
    let r = run + s.extra;
    if (s.extra && r > budget) { partial = { stage: i, name: s.name, included: [], excluded: s.artboards.map((e) => e.name + ' (' + e.theme + ')') }; break; }
    for (const e of s.artboards) { if (r + cost(e) <= budget) { r += cost(e); inc.push(e); } else exc.push(e); }
    run = r; partial = { stage: i, name: s.name, included: inc.map((e) => `${e.id} (${e.theme})`), excluded: exc.map((e) => `${e.id} (${e.theme})`) };
    break;
  }
  const count = full.reduce((a, i) => a + stages[i].artboards.length, 0) + (partial ? partial.included.length : 0);
  return { budget, calls: run, fullStages: full, partial, artboards: count };
}
const budgets = [100, 500, 2000].map(fit);
const nArt = man.length;
const variant = { artboards: nArt, calls: setup + FINISH + nArt * 3, note: 'create_artboard + one write_html + one screenshot per artboard; ignores Paper\'s ~15-line-per-write guidance, comparison only' };
const plan = {
  assumptions: ['create_tokens takes <= 100 tokens per call (' + tokens.length + ' entries in tokens.paper.json -> ' + OVERHEAD.create_tokens + ' calls)', 'get_guide 1, get_basic_info 1, get_font_family_info 2, create_page 5, finish_working_on_nodes 1 per session (reserved in every budget)', 'artboard calls from artboards/calls.json (writes + clones + batched overrides + screenshots; dark twins are duplicate_nodes + batched update_styles)'],
  overhead: { ...OVERHEAD, setup, finish: FINISH },
  stages: stages.map((s, i) => ({ n: i, name: s.name, calls: s.calls, cumulative: s.cumulative + FINISH, artboards: s.artboards.map((e) => ({ id: e.id, theme: e.theme, name: e.name, file: e.file, calls: cost(e) })) })),
  total: { calls: total, artboards: nArt },
  budgets, oneWritePerArtboard: variant,
};
fs.writeFileSync(path.join(paperDir, 'artboards', 'plan.json'), JSON.stringify(plan, null, 1));
let md = `# Build plan (generated by tools/plan.mjs)\n\nTotal: **${total} calls** for ${nArt} artboards. "One write per artboard" variant (against Paper's guidance): ${variant.calls} calls.\n\nAssumptions: ${plan.assumptions.join('; ')}.\n\n## Stages\n\n| # | Stage | Artboards | Calls | Cumulative |\n|---|---|---|---|---|\n`;
for (const s of plan.stages) md += `| ${s.n} | ${s.name} | ${s.artboards.length} | ${s.calls} | ${s.cumulative} |\n`;
md += '\n';
for (const s of plan.stages) { md += `### Stage ${s.n}: ${s.name}\n\n`; md += s.artboards.length ? s.artboards.map((a) => `- ${a.name}${a.theme === 'dark' ? ' (dark)' : ''} \`${a.id}\` ${a.calls}`).join('\n') + '\n\n' : `Overhead: ${Object.entries(OVERHEAD).map(([k, v]) => `${k} ${v}`).join(', ')}.\n\n`; }
md += '## What fits in a budget\n\n| Budget | Calls used | Artboards | Full stages | Partial stage |\n|---|---|---|---|---|\n';
for (const b of budgets) md += `| ${b.budget} | ${b.calls} | ${b.artboards} | ${b.fullStages.join(', ') || '-'} | ${b.partial ? `${b.partial.stage} (${b.partial.included.length} of ${b.partial.included.length + b.partial.excluded.length})` : '-'} |\n`;
for (const b of budgets) if (b.partial) md += `\n**Budget ${b.budget}, partial stage ${b.partial.stage} (${b.partial.name})**\n\n- included: ${b.partial.included.join(', ') || 'none'}\n- not included: ${b.partial.excluded.join(', ') || 'none'}\n`;
fs.writeFileSync(path.join(paperDir, 'artboards', 'plan-tables.md'), md);
console.log(stages.map((s, i) => `${i} ${s.name}: ${s.artboards.length} artboards, ${s.calls} calls, cum ${s.cumulative + FINISH}`).join('\n'));
for (const b of budgets) console.log(`budget ${b.budget}: ${b.calls} calls, ${b.artboards} artboards, full stages [${b.fullStages}], partial ${b.partial ? b.partial.stage + ' +' + b.partial.included.length : '-'}`);
console.log(`total ${total}; one-write variant ${variant.calls}`);
