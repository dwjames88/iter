// order.mjs - the ONE canonical artboard order, used by preview.html, INDEX.md, layout.json and the build plan.
//   PAGES                                  ['Foundations','Components','Screens (Light)','Screens (Dark)','Flows']
//   orderManifest(entries) -> entries sorted: page order, then
//     Foundations: F01..F07 by id.   Components: COMPONENTS.md `###` order (= its section order: Light Index, Honesty, Shared,
//     Shell, Trips, Explore, Spot page, Saved and Scout), then "System components", then boards that only cover Menus/ rows.
//     Screens: SCREENS.md section order, within a section the States-table row order, 1280-wide before 960, each followed
//     by its --notes companion; Screens (Dark) in the same order.   Flows: overview, then the four journeys.
//   groupOf(entry) -> {key, label}  the row/section a manifest entry belongs to (SCREENS.md H2, COMPONENTS.md ## group, ...)
//   rankOf(entry)  -> sortable number
// Artboards with empty `covers` inherit the section of the nearest sibling in the same source module (placed after its rows).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const paperDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const repo = path.resolve(paperDir, '..', '..');
export const PAGES = ['Foundations', 'Components', 'Screens (Light)', 'Screens (Dark)', 'Flows'];
const FLOW_ORDER = ['F-flows-overview', 'F-flow-plan-trip', 'F-flow-explore-save', 'F-flow-read-spot', 'F-flow-scout'];
const norm = (s) => s.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1').replace(/\s+/g, ' ').trim();

let TABLES = null;
function tables() {
  if (TABLES) return TABLES;
  const screens = []; // {key:'H2/State', h2}
  const h2s = [];
  let h2 = '', inTable = null;
  for (const line of fs.readFileSync(path.join(repo, 'Design', 'SCREENS.md'), 'utf8').split('\n')) {
    const m = line.match(/^## (.+)/);
    if (m) { h2 = m[1].trim(); inTable = null; if (!h2s.includes(h2)) h2s.push(h2); continue; }
    if (/^\|\s*State\s*\|/.test(line)) { inTable = 'states'; continue; }
    if (/^\|\s*Element\s*\|/.test(line)) { inTable = 'menus'; continue; }
    if (inTable && /^\|\s*-/.test(line)) continue;
    if (inTable && line.startsWith('|')) {
      const cell = norm(line.split('|')[1] || '');
      if (cell) screens.push({ key: inTable === 'menus' ? `Menus/${cell}` : `${h2}/${cell}`, h2: inTable === 'menus' ? 'Menus, popovers and dialogs' : h2 });
    } else if (inTable) inTable = null;
  }
  const comps = []; // {key:'Component/X', group}
  let grp = '';
  for (const line of fs.readFileSync(path.join(repo, 'Design', 'COMPONENTS.md'), 'utf8').split('\n')) {
    const g = line.match(/^## (.+)/);
    if (g) { grp = g[1].trim(); if (grp === 'System components') comps.push({ key: 'Component/System components', group: grp }); continue; }
    const m = line.match(/^### (.+)/);
    if (m) comps.push({ key: `Component/${m[1].trim()}`, group: grp });
  }
  TABLES = { screens, comps, h2s };
  return TABLES;
}

function covRank(e) {
  const t = tables();
  let best = null, group = null, kind = null;
  for (const cv of e.covers || []) {
    const n = norm(cv);
    let i = t.screens.findIndex((x) => x.key === n);
    if (i >= 0 && e.section === 'screens') { if (best === null || i < best) { best = i; group = t.screens[i].h2; kind = 'screen'; } continue; }
    i = t.comps.findIndex((x) => x.key === n);
    if (i >= 0) { if (kind !== 'comp' || i < best) { best = i; group = t.comps[i].group; kind = 'comp'; } continue; }
    i = t.screens.findIndex((x) => x.key === n);
    if (i >= 0 && kind !== 'comp' && (best === null || i < best)) { best = 100000 + i; group = 'Menus, popovers and dialogs'; kind = 'menu'; }
  }
  return best === null ? null : { rank: best, group, kind };
}

export function orderManifest(entries) {
  // pass 1: ranks from covers; companions take their parent's; empty covers inherit from siblings in the same source
  const byId = new Map();
  for (const e of entries) if (!e.companionOf) byId.set(`${e.id}|${e.theme}`, e);
  const bySource = new Map();
  for (const e of entries) if (!e.companionOf) { const r = covRank(e); if (r) { const a = bySource.get(e.source) || []; a.push(r); bySource.set(e.source, a); } }
  const key = new Map();
  for (const e of entries) {
    if (e.companionOf) continue;
    let r = covRank(e), inherited = false;
    if (!r) {
      const sib = bySource.get(e.source);
      if (sib && sib.length) { const m = sib.reduce((a, b) => (a.rank < b.rank ? a : b)); r = { rank: m.rank + 0.5, group: m.group, kind: m.kind }; inherited = true; }
    }
    key.set(e, { r: r || { rank: 1e6, group: 'Other', kind: 'other' }, inherited });
  }
  const sortKey = (e) => {
    const base = e.companionOf ? byId.get(`${e.companionOf}|${e.theme}`) || [...byId.values()].find((x) => x.id === e.companionOf) : e;
    const k = key.get(base) || { r: { rank: 1e6, group: 'Other', kind: 'other' } };
    const wide = base && base.width < 1000 && base.width !== 552 ? 1 : 0; // 960 variants after 1280
    return [PAGES.indexOf(e.page), k.r.rank, wide, base ? base.id : e.id, e.companionOf ? 1 : 0];
  };
  const flowIdx = (e) => { const b = e.companionOf || e.id; const i = FLOW_ORDER.indexOf(b); return i < 0 ? 99 : i; };
  return [...entries].sort((a, b) => {
    if (a.page === 'Flows' && b.page === 'Flows') return flowIdx(a) - flowIdx(b) || (a.companionOf ? 1 : 0) - (b.companionOf ? 1 : 0);
    if (a.page === 'Foundations' && b.page === 'Foundations') return a.id.localeCompare(b.id);
    const A = sortKey(a), B = sortKey(b);
    for (let i = 0; i < A.length; i++) if (A[i] !== B[i]) return typeof A[i] === 'number' ? A[i] - B[i] : String(A[i]).localeCompare(String(B[i]));
    return 0;
  });
}

export function groupOf(e) {
  if (e.page === 'Foundations') return { key: 'Foundations', label: 'Foundations' };
  if (e.page === 'Flows') return { key: 'Flows', label: 'Flows' };
  const base = e.companionOf ? { ...e, covers: [] } : e;
  const r = covRank(e);
  if (r) return { key: r.group, label: r.group };
  return { key: `src:${e.source}`, label: 'Other' };
}
export { covRank };
