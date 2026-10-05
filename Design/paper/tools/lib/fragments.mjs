// fragments.mjs - splits an artboard tree into small Paper write_html calls ("fragments") and diffs trees.
//   buildFragments(root, {maxLines=15, clones=true}) -> {fragments, stats:{writes, clones}}
//     A subtree whose pretty-printed html is <= maxLines becomes one `write` fragment (adjacent small siblings are merged
//     while the total stays <= maxLines); a bigger node is written as an empty shell, then its children recursively.
//     CLONES: a subtree with the same skeleton (tags + style KEYS + svg size; layer-names and style VALUES ignored) as an
//     earlier subtree becomes one `clone` fragment. Overrides: styleOverrides {nodePath: {prop: value}}, textOverrides,
//     nameOverrides, plus `varRule` (replaceVarPrefix --color- -> --color-dark-) when the differences are only the dark swap.
//     A clone is used when its override count (rule = 1) is smaller than the line count of the subtree.
//   diffForDuplicate(baseRoot, root) -> null | {rule, changedNodes, exceptions, textChanges, ...}  (dark screen = duplicate of light)
// Node paths: layer-names joined with '/', repeated sibling names get '#2', '#3'. Fragment paths start at the artboard root name.
import { styleOf, pretty, serialize } from './dom.mjs';

export const VAR_RULES = [['--color-', '--color-dark-'], ['--shadow-', '--shadow-dark-']];
export const applyRule = (v) => { let r = v; for (const [a, b] of VAR_RULES) r = r.split(a).join(b); return r; };

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
const sigShape = (n) => (n.text !== undefined ? 'T' : `${n.tag}[${nameOf(n)}](${n.tag === 'svg' ? '' : n.children.map(sigShape).join(',')})`);
const sig = (n) => (n.text !== undefined ? 'T' : `${n.tag}[${Object.keys(styleOf(n)).sort().join(',')}${n.tag === 'svg' ? '|' + n.attrs.width + 'x' + n.attrs.height + '|' + (n.children.length) : ''}](${n.tag === 'svg' ? '' : n.children.map(sig).join(',')})`);

function pairDiff(a, b, rel, out) {
  if (a.text !== undefined) { if (a.text !== b.text) out.text.push({ path: rel, text: b.text }); return; }
  if (nameOf(a) !== nameOf(b)) out.names.push({ path: rel, name: nameOf(b) });
  const sa = styleOf(a), sb = styleOf(b);
  const ch = {}, from = {};
  let explainedHere = false;
  for (const k of new Set([...Object.keys(sa), ...Object.keys(sb)])) {
    if (sa[k] === sb[k]) continue;
    if (sa[k] != null && applyRule(sa[k]) === sb[k]) { explainedHere = true; continue; }
    ch[k] = sb[k] ?? null; from[k] = sa[k];
  }
  if (explainedHere) out.explained.push(rel);
  if (Object.keys(ch).length) out.styles.push({ path: rel, styles: ch, from });
  if (a.tag === 'svg') {
    const strip = (n) => serialize({ ...n, attrs: { ...n.attrs, style: '', 'layer-name': '' } });
    if (strip(a) !== strip(b) && applyRule(strip(a)) !== strip(b)) out.other.push(rel);
    return;
  }
  const names = segNames(a.children);
  a.children.forEach((x, i) => pairDiff(x, b.children[i], x.text !== undefined ? `${rel}/#text${i}` : `${rel}/${names[i]}`, out));
}
const newOut = () => ({ styles: [], text: [], names: [], other: [], explained: [] });
const costOf = (o) => (o.explained.length ? 1 : 0) + o.styles.length + o.text.length + o.names.length;

// trunk(n, path, budget): copy of n holding as many leading descendants as fit in `budget` pretty-printed lines.
// Returns {node, used, deferred:[{path, children}]} where deferred lists the children left out under each partially written node.
function trunk(n, path, budget) {
  const names = segNames(n.children);
  const copy = { tag: n.tag, attrs: n.attrs, children: [] };
  let used = 2;
  const deferred = [];
  for (let i = 0; i < n.children.length; i++) {
    const ch = n.children[i];
    if (ch.text !== undefined) { copy.children.push(ch); continue; }
    const L = pretty(ch).length;
    if (used + L <= budget) { copy.children.push(ch); used += L; continue; }
    const hasEl = ch.tag !== 'svg' && ch.children.some((x) => x.tag);
    const mixed = ch.children.some((x) => x.text !== undefined) && hasEl;
    if (hasEl && !mixed && budget - used >= 4) {
      const sub = trunk(ch, [...path, names[i]], budget - used);
      copy.children.push(sub.node); used += sub.used;
      deferred.push(...sub.deferred);
      if (i + 1 < n.children.length) deferred.push({ path, children: n.children.slice(i + 1) });
    } else {
      deferred.push({ path, children: n.children.slice(i) });
    }
    break;
  }
  if (copy.children.every((x) => x.text !== undefined)) used = 1;
  return { node: copy, used, deferred };
}

export function buildFragments(root, { maxLines = 15, clones = true } = {}) {
  const fragments = [];
  const sigs = new Map(); // sig -> {ref:{seq}, path, node}
  let seq = 0;
  const rootName = nameOf(root);
  const stats = { writes: 0, clones: 0 };

  function process(parentPathArr, parentSeq, children) {
    const names = segNames(children);
    let pending = null;
    const flush = () => {
      if (!pending) return;
      const g = pending; pending = null;
      g.ref.seq = ++seq;
      fragments.push({ seq: g.ref.seq, kind: 'write', parentPath: parentPathArr.join('/'), parentPathArray: parentPathArr, parentSeq, html: g.lines.join('\n'), lines: g.lines.length });
      stats.writes++;
    };
    children.forEach((ch, i) => {
      if (ch.text !== undefined) return;
      const lines = pretty(ch);
      const L = lines.length;
      const nodePath = [...parentPathArr, names[i]];
      const s = clones && L >= 3 ? sig(ch) : null;
      if (s) {
        const src = sigs.get(s);
        if (src) {
          const out = newOut();
          pairDiff(src.node, ch, '.', out);
          if (!out.other.length && costOf(out) < L) {
            if (pending && src.ref === pending.ref) flush();
            const so = {}; for (const x of out.styles) so[x.path] = x.styles;
            const to = {}; for (const x of out.text) to[x.path] = x.text;
            const no = {}; for (const x of out.names) no[x.path] = x.name;
            const f = { seq: ++seq, kind: 'clone', parentPath: parentPathArr.join('/'), parentPathArray: parentPathArr, parentSeq, sourceSeq: src.ref.seq, sourcePath: src.path.join('/'), sourcePathArray: src.path, styleOverrides: so, textOverrides: to, nameOverrides: no, lines: costOf(out) };
            if (out.explained.length) f.varRule = { replaceVarPrefix: VAR_RULES, nodes: out.explained.length };
            fragments.push(f);
            stats.clones++;
            return;
          }
        }
      }
      const mixed = ch.children.some((x) => x.text !== undefined) && ch.children.some((x) => x.tag);
      if (L <= maxLines || mixed) {
        if (pending && pending.lines.length + L > maxLines) flush();
        if (!pending) pending = { lines: [], ref: { seq: 0 } };
        pending.lines.push(...lines);
        if (s && !sigs.has(s)) sigs.set(s, { ref: pending.ref, path: nodePath, node: ch });
        return;
      }
      flush();
      // Too big for one write: write a TRUNK (the node plus as many leading descendants as fit in maxLines, depth first),
      // then write the cut-off remainder of each partially written node as further children (Paper appends in order).
      const tr = trunk(ch, nodePath, maxLines);
      const mySeq = ++seq;
      fragments.push({ seq: mySeq, kind: 'write', parentPath: parentPathArr.join('/'), parentPathArray: parentPathArr, parentSeq, html: pretty(tr.node).join('\n'), lines: pretty(tr.node).length, partial: tr.deferred.length > 0 });
      stats.writes++;
      for (const dfd of tr.deferred) process(dfd.path, mySeq, dfd.children);
      if (s && !sigs.has(s)) sigs.set(s, { ref: { seq: mySeq }, path: nodePath, node: ch });
    });
    flush();
  }
  process([rootName], 0, root.children);
  return { fragments, stats };
}

export function diffForDuplicate(base, root) {
  if (base.children.map(sigShape).join() !== root.children.map(sigShape).join()) return null;
  const out = newOut();
  pairDiff(base, root, '.', out);
  const n = out.explained.length + out.styles.length;
  return {
    rule: { replaceVarPrefix: VAR_RULES }, changedNodes: out.explained, exceptions: out.styles.map((x) => ({ path: x.path, styles: x.styles })),
    textChanges: out.text, svgChanged: out.other, nameChanges: out.names,
    changedCount: n + out.text.length, updateStylesCalls: Math.ceil((n + out.text.length) / 50),
  };
}
export const _debug = { sig, pairDiff, newOut, costOf };
