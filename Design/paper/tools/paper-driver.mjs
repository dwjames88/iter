#!/usr/bin/env node
// paper-driver.mjs - bookkeeping for placing artboards on the Paper canvas through the MCP tools (route B).
// The agent makes the Paper calls; this script says exactly what each next call is and records the node IDs that come back,
// so parents, clone sources and override targets are always resolved from real IDs, never guessed.
//
// State: Design/paper/build-state/<artboard file with / -> __>.json  (machine record; node IDs are not for the owner).
//
//   node tools/paper-driver.mjs start  <file>                       -> create_artboard args for the artboard (light/regular)
//   node tools/paper-driver.mjs init   <file> <artboardNodeId>      -> records the new artboard, queues its canvas position
//   node tools/paper-driver.mjs next   <file>                       -> the next call: write_html (fragment or clone) / flush / review / done
//   node tools/paper-driver.mjs record <file> <seq> <id,id,...>     -> records createdNodes IDs (in response order) for fragment <seq>
//   node tools/paper-driver.mjs flush  <file>                       -> batched set_text_content / update_styles / rename_nodes payloads
//   node tools/paper-driver.mjs flushed <file>                      -> marks the pending batch as sent
//   node tools/paper-driver.mjs reviewed <file> "<note>"            -> marks the artboard reviewed (after screenshot + finish_working_on_nodes)
//   node tools/paper-driver.mjs dup    <file>                       -> (dark twins) duplicate_nodes args for the light twin
//   node tools/paper-driver.mjs dup-record <file> <newRootId> <mapJsonFile>  -> records descendantIdMap, queues move + dark styles
//   node tools/paper-driver.mjs status [<file>]                     -> progress of one or all artboards
//
// <file> is the artboard path under artboards/, e.g. foundations/F02-type-scale.html (as in layout.json).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse, styleOf } from './lib/dom.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const paperDir = path.resolve(here, '..');
const abDir = path.join(paperDir, 'artboards');
const stateDir = path.join(paperDir, 'build-state');
const FILE_ID = '01M46EFK4QR1BT4YSNYVKWC5XM';
const PAGES = { Foundations: 'p-1-0', Components: 'p-2-0', 'Screens (Light)': 'p-3-0', 'Screens (Dark)': 'p-4-0', Flows: 'p-5-0' };
const BATCH = 50;

const die = (m) => { console.error(`ERROR: ${m}`); process.exit(1); };
const out = (o) => console.log(typeof o === 'string' ? o : JSON.stringify(o, null, 1));

// ---------- layout and manifests ----------
const layout = JSON.parse(fs.readFileSync(path.join(abDir, 'layout.json'), 'utf8'));
function layoutItem(file) {
  for (const [page, v] of Object.entries(layout.pages)) for (const r of v.rows) for (const it of r.items) if (it.file === file) return { ...it, page };
  die(`no layout entry for ${file}`);
}
const fragFile = (file) => path.join(abDir, file.replace(/\.html$/, '.fragments.json'));
const manifestOf = (file) => JSON.parse(fs.readFileSync(fragFile(file), 'utf8'));
function fullTree(file) {
  const html = fs.readFileSync(path.join(abDir, file), 'utf8');
  return parse(html.slice(html.indexOf('<div layer-name=')));
}
function parseAll(html) { return parse(`<div layer-name="__wrap">${html}</div>`).children.filter((c) => c.text === undefined); }

// ---------- tree paths (same convention as lib/fragments.mjs: layer-names joined by '/', repeated sibling names get #2, #3) ----------
const nameOf = (n) => n.attrs['layer-name'] || n.tag;
function segNames(children) {
  const seen = {};
  return children.map((ch) => {
    if (ch.text !== undefined) return null;
    const nm = nameOf(ch);
    seen[nm] = (seen[nm] || 0) + 1;
    return seen[nm] > 1 ? `${nm}#${seen[nm]}` : nm;
  });
}
// index: path -> {node, parentPath, childPaths:[...]}; root path = root name
function indexTree(root) {
  const idx = new Map();
  const visit = (n, p, parentPath) => {
    const names = segNames(n.children);
    const childPaths = [];
    if (n.tag !== 'svg') n.children.forEach((ch, i) => { if (ch.text === undefined) childPaths.push(`${p}/${names[i]}`); });
    idx.set(p, { node: n, parentPath, childPaths });
    if (n.tag !== 'svg') n.children.forEach((ch, i) => { if (ch.text === undefined) visit(ch, `${p}/${names[i]}`, p); });
  };
  visit(root, nameOf(root), null);
  return idx;
}
// pre-order of the subtree at p (svg = leaf), restricted to the shape of fragment node f (trunks write only leading children)
// Paper lists absolutely positioned children after their in-flow siblings (stable), so its createdNodes come in that order.
const isAbs = (idx, p) => styleOf(idx.get(p).node).position === 'absolute';
const paperOrder = (idx, pairs) => [...pairs.filter((x) => !isAbs(idx, x[0])), ...pairs.filter((x) => isAbs(idx, x[0]))];
function pairedPreorder(idx, p, f, acc) {
  acc.push(p);
  const e = idx.get(p);
  if (e.node.tag === 'svg') return acc;
  const fk = f.children.filter((c) => c.text === undefined);
  const pairs = fk.map((fc, i) => {
    const cp = e.childPaths[i];
    if (!cp) die(`fragment has more children than the artboard tree under ${p}`);
    if (nameOf(idx.get(cp).node) !== nameOf(fc)) die(`fragment child "${nameOf(fc)}" does not match tree child "${nameOf(idx.get(cp).node)}" under ${p}`);
    return [cp, fc];
  });
  for (const [cp, fc] of paperOrder(idx, pairs)) pairedPreorder(idx, cp, fc, acc);
  return acc;
}
function fullPreorder(idx, p, acc = []) { acc.push(p); const e = idx.get(p); for (const c of e.childPaths) fullPreorder(idx, c, acc); return acc; }
const camel = (k) => k.replace(/-([a-z])/g, (_, c) => c.toUpperCase());
const leafText = (n) => (n.tag !== 'svg' && n.children.length && n.children.every((c) => c.text !== undefined) ? n.children.map((c) => c.text).join('') : null);
const decode = (s) => s.replace(/&#(\d+);/g, (_, d) => String.fromCharCode(+d)).replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));

// ---------- state ----------
const stateFile = (file) => path.join(stateDir, file.replace(/\.html$/, '').replace(/\//g, '__') + '.json');
function load(file) { const f = stateFile(file); return fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : null; }
function save(st) { fs.mkdirSync(stateDir, { recursive: true }); st.updatedAt = new Date().toISOString(); fs.writeFileSync(stateFile(st.file), JSON.stringify(st, null, 1) + '\n'); }
function need(file) { const st = load(file); if (!st) die(`no state for ${file}; run start/init (or dup) first`); return st; }
const emptyPending = () => ({ text: {}, styles: {}, names: {} });

// Paper turns some text-only elements (seen: fixed width + nowrap) into a Frame holding a Text child named after its content.
// Such a child is recorded at "<path>/#text". Text styles then live on the Text child, box styles on the Frame.
const TEXT_PROPS = /^(color|font|line-height|letter-spacing|text-|white-space|word-|overflow-wrap|-webkit-line-clamp)/;
function queueDiff(st, id, textId, a, b) {
  const sa = styleOf(a), sb = styleOf(b);
  const box = {}, txt = {};
  for (const k of new Set([...Object.keys(sa), ...Object.keys(sb)])) {
    if (sa[k] === sb[k]) continue;
    const v = sb[k] ?? '';
    if (textId && TEXT_PROPS.test(k)) txt[camel(k)] = v; else box[camel(k)] = v;
  }
  if (Object.keys(box).length) st.pending.styles[id] = { ...(st.pending.styles[id] || {}), ...box };
  if (Object.keys(txt).length) st.pending.styles[textId] = { ...(st.pending.styles[textId] || {}), ...txt };
  const ta = leafText(a), tb = leafText(b);
  if (tb !== null && ta !== tb) st.pending.text[textId || id] = decode(tb);
  if (nameOf(a) !== nameOf(b)) st.pending.names[id] = nameOf(b);
}
// canvas pre-order of a recorded subtree: tree pre-order plus "#text" children where Paper made them
function canvasPreorder(st, idx, p, acc = []) {
  acc.push(p);
  if (st.nodes[`${p}/#text`]) acc.push(`${p}/#text`);
  for (let i = 0; st.nodes[`${p}/#svg${i}`]; i++) acc.push(`${p}/#svg${i}`);
  for (const [c] of paperOrder(idx, idx.get(p).childPaths.map((c) => [c]))) canvasPreorder(st, idx, c, acc);
  return acc;
}
const norm = (s) => decode(String(s)).replace(/\s+/g, ' ').trim();
function nameMatches(created, want) {
  const c = norm(created), w = norm(want);
  if (c === w) return true;
  if (c.endsWith('…')) return w.startsWith(c.slice(0, -1).trimEnd()) || w.slice(0, 49) === c.slice(0, -1);
  return w.length > 50 && w.startsWith(c);
}
// align Paper's createdNodes [{id,name}] with the expected tree paths. Extra nodes Paper adds are recorded too:
//   a Text child inside a wrapped text element -> "<path>/#text"; the inner shapes of an inline SVG -> "<path>/#svg0", "#svg1", ...
function align(idx, expected, created) {
  const res = [];
  let k = 0;
  for (let i = 0; i < expected.length; i++) {
    const p = expected[i];
    const node = idx.get(p).node;
    const want = nameOf(node);
    const c = created[k];
    if (!c) die(`ran out of created nodes at expected "${want}" (${p})`);
    if (!nameMatches(c.name, want)) die(`created node ${c.id} "${c.name}" does not match expected "${want}" (${p}). Created list:\n${created.map((x) => `  ${x.id}=${x.name}`).join('\n')}`);
    res.push([p, c.id]); k++;
    const nextWant = expected[i + 1] ? nameOf(idx.get(expected[i + 1]).node) : null;
    const lt = leafText(node);
    let svgN = 0, gotText = false;
    while (created[k] && !(nextWant !== null && nameMatches(created[k].name, nextWant))) {
      const x = created[k];
      if (lt !== null && !gotText && nameMatches(x.name, lt)) { res.push([`${p}/#text`, x.id]); gotText = true; k++; continue; }
      if (node.tag === 'svg') { res.push([`${p}/#svg${svgN++}`, x.id]); k++; continue; }
      die(`unexpected created node ${x.id} "${x.name}" after "${want}" (${p}); next expected "${nextWant}". Created list:\n${created.map((y) => `  ${y.id}=${y.name}`).join('\n')}`);
    }
  }
  if (k !== created.length) die(`${created.length - k} created nodes left over after alignment`);
  return res;
}
// read "id=name" lines from stdin (or a comma list of ids without names)
function readCreated(arg) {
  if (arg) return arg.split(',').map((s) => ({ id: s.trim() })).filter((x) => x.id);
  const txt = fs.readFileSync(0, 'utf8');
  return txt.split('\n').map((l) => l.replace(/\r$/, '')).filter((l) => l.trim()).map((l) => { const e = l.indexOf('='); if (e < 0) die(`bad line (want id=name): ${l}`); return { id: l.slice(0, e).trim(), name: l.slice(e + 1).trim() }; });
}
const pendingCount = (p) => Object.keys(p.text).length + Object.keys(p.styles).length + Object.keys(p.names).length;

function printWrite(h, html) {
  console.log(`write_html  fragment ${h.seq} of ${h.of}${h.clone ? ' (CLONE: record ALL createdNodes ids)' : ''}`);
  console.log(`fileId=${FILE_ID}  targetNodeId=${h.targetNodeId}  mode=insert-children`);
  console.log('html (verbatim, between the markers):');
  console.log('-----BEGIN HTML-----');
  console.log(html);
  console.log('-----END HTML-----');
}

// ---------- commands ----------
const [cmd, file, ...rest] = process.argv.slice(2);

if (cmd === 'status') {
  const files = file ? [file] : (fs.existsSync(stateDir) ? fs.readdirSync(stateDir).map((f) => JSON.parse(fs.readFileSync(path.join(stateDir, f), 'utf8')).file) : []);
  for (const f of files) {
    const st = load(f); if (!st) { out(`${f}: not started`); continue; }
    const m = manifestOf(f);
    out(`${f}: ${st.phase}; fragments ${st.done.length}/${st.dup ? 'dup' : m.fragments.length}; pending ${pendingCount(st.pending)}; reviewed ${!!st.reviewed}`);
  }
  process.exit(0);
}
if (!file) die('usage: see header');

if (cmd === 'start') {
  if (load(file)) die(`state exists for ${file}: ${JSON.stringify(load(file).phase)}. Use next.`);
  const m = manifestOf(file);
  const it = layoutItem(file);
  out({ tool: 'create_artboard', args: { fileId: FILE_ID, pageId: PAGES[it.page], name: m.artboard.name, styles: { ...m.artboard.styles } } });
  process.exit(0);
}

if (cmd === 'init') {
  const [abId] = rest; if (!abId) die('init <file> <artboardNodeId>');
  if (load(file)) die('state exists');
  const m = manifestOf(file);
  const it = layoutItem(file);
  const tree = fullTree(file);
  const st = { file, name: m.artboard.name, page: it.page, pageId: PAGES[it.page], fileId: FILE_ID, artboardId: abId, phase: 'writing', done: [], nodes: { [nameOf(tree)]: abId }, created: { [nameOf(tree)]: true }, pending: emptyPending(), calls: 1 };
  st.pending.styles[abId] = { left: `${it.x}px`, top: `${it.y}px` };
  save(st);
  out(`ok: ${m.artboard.name} -> ${abId}; ${m.fragments.length} fragments; position queued (${it.x}, ${it.y})`);
  process.exit(0);
}

if (cmd === 'next') {
  const st = need(file);
  if (st.phase === 'done') { out({ op: 'done' }); process.exit(0); }
  if (st.dup) {
    if (pendingCount(st.pending)) { out({ op: 'flush', note: `run: flush ${file}` }); process.exit(0); }
    out({ op: 'review', note: 'get_screenshot of the artboard root, judge, fix, then finish_working_on_nodes and reviewed' , artboardId: st.artboardId });
    process.exit(0);
  }
  const m = manifestOf(file);
  const f = m.fragments.find((x) => !st.done.includes(x.seq));
  if (!f) {
    if (pendingCount(st.pending)) { out({ op: 'flush', note: `run: flush ${file}` }); process.exit(0); }
    out({ op: 'review', artboardId: st.artboardId, sections: (indexTree(fullTree(file)).get(nameOf(fullTree(file))).childPaths.map((p) => ({ path: p, id: st.nodes[p] }))), note: 'screenshot each section (or the artboard), judge, fix, finish_working_on_nodes, then: reviewed <file> "<note>"' });
    process.exit(0);
  }
  if (pendingCount(st.pending) >= BATCH) { out({ op: 'flush', note: `pending overrides reached ${BATCH}; run: flush ${file}` }); process.exit(0); }
  const parentId = st.nodes[f.parentPath];
  if (!parentId) die(`parent ${f.parentPath} of fragment ${f.seq} has no node id yet`);
  if (f.kind === 'write') {
    printWrite({ seq: f.seq, of: m.fragments.length, targetNodeId: parentId }, f.html);
  } else {
    const srcId = st.nodes[f.sourcePath];
    if (!srcId) die(`clone source ${f.sourcePath} has no node id`);
    printWrite({ seq: f.seq, of: m.fragments.length, targetNodeId: parentId, clone: true }, `<x-paper-clone node-id="${srcId}" />`);
  }
  process.exit(0);
}

if (cmd === 'record') {
  const st = need(file);
  const [seqS, idsS] = rest;
  const seq = +seqS;
  const created = readCreated(idsS);
  const m = manifestOf(file);
  const f = m.fragments.find((x) => x.seq === seq);
  if (!f) die(`no fragment ${seq}`);
  if (st.done.includes(seq)) die(`fragment ${seq} already recorded`);
  const tree = fullTree(file);
  const idx = indexTree(tree);
  const parent = idx.get(f.parentPath);
  if (!parent) die(`parent path not in tree: ${f.parentPath}`);
  const uncreated = parent.childPaths.filter((p) => !st.created[p]);
  let pairs = [];
  if (f.kind === 'write') {
    const expected = [];
    const tops = parseAll(f.html);
    tops.forEach((t, i) => {
      const p = uncreated[i];
      if (!p) die('more top-level elements than uncreated children');
      if (nameOf(idx.get(p).node) !== nameOf(t)) die(`top element "${nameOf(t)}" != expected "${nameOf(idx.get(p).node)}"`);
      pairedPreorder(idx, p, t, expected);
    });
    if (created.some((c) => c.name === undefined)) {
      if (created.length !== expected.length) die(`got ${created.length} ids without names, expected ${expected.length}. Re-run record with "id=name" lines on stdin (see brief).`);
      pairs = expected.map((p, i) => [p, created[i].id]);
    } else pairs = align(idx, expected, created);
  } else {
    const tgt = uncreated[0];
    const srcTree = fullPreorder(idx, f.sourcePath), tgtTree = fullPreorder(idx, tgt);
    if (srcTree.length !== tgtTree.length) die(`clone shape mismatch: source ${srcTree.length} nodes, target ${tgtTree.length}`);
    const srcCanvas = canvasPreorder(st, idx, f.sourcePath);
    if (created.length !== srcCanvas.length) die(`clone returned ${created.length} nodes, expected ${srcCanvas.length} (the source subtree as it is on the canvas). Paste all createdNodes.`);
    const toTgt = new Map(srcTree.map((s, i) => [s, tgtTree[i]]));
    srcCanvas.forEach((sp, i) => {
      const isText = sp.endsWith('/#text');
      const base = isText ? sp.slice(0, -6) : sp;
      pairs.push([isText ? `${toTgt.get(base)}/#text` : toTgt.get(base), created[i].id]);
    });
    const idOf = new Map(pairs);
    srcTree.forEach((sp, i) => { const tp = tgtTree[i]; queueDiff(st, idOf.get(tp), idOf.get(`${tp}/#text`), idx.get(sp).node, idx.get(tp).node); });
  }
  for (const [p, id] of pairs) { st.nodes[p] = id; st.created[p] = true; }
  st.done.push(seq);
  st.calls = (st.calls || 0) + 1;
  save(st);
  const left = m.fragments.length - st.done.length;
  out(`ok: fragment ${seq} recorded (${pairs.length} nodes); ${left} left; pending overrides ${pendingCount(st.pending)}`);
  process.exit(0);
}

if (cmd === 'flush') {
  const st = need(file);
  const p = st.pending;
  const calls = [];
  const chunk = (arr) => { const r = []; for (let i = 0; i < arr.length; i += BATCH) r.push(arr.slice(i, i + BATCH)); return r; };
  const texts = Object.entries(p.text).map(([nodeId, textContent]) => ({ nodeId, textContent }));
  for (const c of chunk(texts)) calls.push({ tool: 'set_text_content', args: { fileId: FILE_ID, updates: c } });
  const styles = Object.entries(p.styles).map(([id, s]) => ({ nodeIds: [id], styles: s }));
  for (const c of chunk(styles)) calls.push({ tool: 'update_styles', args: { fileId: FILE_ID, updates: c } });
  const names = Object.entries(p.names).map(([nodeId, name]) => ({ nodeId, name }));
  for (const c of chunk(names)) calls.push({ tool: 'rename_nodes', args: { fileId: FILE_ID, updates: c } });
  if (st.dup && st.dup.moveTo && !st.dup.moved) calls.unshift({ tool: 'move_nodes', args: { fileId: FILE_ID, moves: [{ nodeId: st.artboardId, parentId: st.dup.moveTo }] } });
  out({ calls, note: `make these ${calls.length} calls in order, then run: flushed ${file}` });
  process.exit(0);
}

if (cmd === 'flushed') {
  const st = need(file);
  const n = Object.keys(st.pending.text).length ? 1 : 0;
  st.calls = (st.calls || 0) + Math.ceil(Object.keys(st.pending.text).length / BATCH) + Math.ceil(Object.keys(st.pending.styles).length / BATCH) + Math.ceil(Object.keys(st.pending.names).length / BATCH) + (st.dup && st.dup.moveTo && !st.dup.moved ? 1 : 0);
  if (st.dup) st.dup.moved = true;
  st.pending = emptyPending();
  void n;
  save(st);
  out('ok: pending batch cleared');
  process.exit(0);
}

if (cmd === 'reviewed') {
  const st = need(file);
  st.reviewed = rest.join(' ') || true;
  st.phase = 'done';
  save(st);
  out('ok: reviewed');
  process.exit(0);
}

if (cmd === 'dup') {
  if (load(file)) die('state exists');
  const m = manifestOf(file);
  if (!m.duplicateOf) die(`${file} is not a duplicate twin`);
  const lightFile = file.replace('/dark/', '/light/').replace('--dark.html', '--light.html');
  const lst = load(lightFile);
  if (!lst || lst.phase !== 'done') die(`light twin ${lightFile} is not finished`);
  out({ tool: 'duplicate_nodes', args: { fileId: FILE_ID, nodes: [{ id: lst.artboardId }] }, then: `save the descendantIdMap JSON to a file and run: dup-record ${file} <newArtboardId> <thatFile>` });
  process.exit(0);
}

if (cmd === 'dup-record') {
  const [newId, mapFile] = rest;
  if (!newId || !mapFile) die('dup-record <file> <newRootId> <mapJsonFile>');
  const m = manifestOf(file);
  const lightFile = file.replace('/dark/', '/light/').replace('--dark.html', '--light.html');
  const lst = load(lightFile);
  let map = JSON.parse(fs.readFileSync(mapFile, 'utf8'));
  if (map.descendantIdMap) map = map.descendantIdMap;
  const it = layoutItem(file);
  const lt = fullTree(lightFile), dt = fullTree(file);
  const li = indexTree(lt), di = indexTree(dt);
  const lp = fullPreorder(li, nameOf(lt)), dp = fullPreorder(di, nameOf(dt));
  if (lp.length !== dp.length) die(`light/dark shape mismatch ${lp.length} vs ${dp.length}`);
  const st = { file, name: m.artboard.name, page: it.page, pageId: PAGES[it.page], fileId: FILE_ID, artboardId: newId, phase: 'styling', done: [], nodes: {}, created: {}, pending: emptyPending(), calls: 1, dup: { of: lightFile, moveTo: `root_node_${PAGES[it.page]}` } };
  let missing = 0;
  lp.forEach((p, i) => {
    const oldId = lst.nodes[p];
    const nid = i === 0 ? newId : map[oldId];
    if (!nid) { missing++; return; }
    st.nodes[dp[i]] = nid;
    const oldT = lst.nodes[`${p}/#text`];
    const tid = oldT ? map[oldT] : undefined;
    if (oldT && !tid) { missing++; return; }
    if (tid) st.nodes[`${dp[i]}/#text`] = tid;
    queueDiff(st, nid, tid, li.get(p).node, di.get(dp[i]).node);
    // inner SVG shapes: Paper made one layer per element; pair them with the html elements in pre-order
    if (lst.nodes[`${p}/#svg0`]) {
      const kids = (n, a = []) => { for (const c of n.children) if (c.text === undefined) { a.push(c); kids(c, a); } return a; };
      const lk = kids(li.get(p).node), dk = kids(di.get(dp[i]).node);
      let n = 0; while (lst.nodes[`${p}/#svg${n}`]) n++;
      for (let j = 0; j < n; j++) { const sid = map[lst.nodes[`${p}/#svg${j}`]]; if (sid) st.nodes[`${dp[i]}/#svg${j}`] = sid; }
      if (n === lk.length && lk.length === dk.length) lk.forEach((ln, j) => { const sid = st.nodes[`${dp[i]}/#svg${j}`]; if (sid) queueDiff(st, sid, undefined, ln, dk[j]); });
      else (st.warnings ||= []).push(`svg ${dp[i]}: ${n} layers on canvas vs ${lk.length} html shapes; inner shape colours not swapped`);
    }
  });
  if (missing) die(`${missing} light nodes have no new id in the map`);
  st.pending.styles[newId] = { ...(st.pending.styles[newId] || {}), left: `${it.x}px`, top: `${it.y}px` };
  st.pending.names[newId] = m.artboard.name;
  save(st);
  out(`ok: ${m.artboard.name} -> ${newId}; ${Object.keys(st.nodes).length} nodes mapped; pending ${pendingCount(st.pending)}. Next: flush ${file}`);
  process.exit(0);
}

die(`unknown command ${cmd}`);
