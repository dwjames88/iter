// dom.mjs - a tiny parser/serializer for the HTML our helpers emit (double-quoted attributes, no comments,
// void tags only inside <svg>). Used by build.mjs (fragments, literal mode) and check.mjs (linting).
//   parse(html)            -> root node {tag, attrs:{...}, children:[node|{text}]}   (first element)
//   styleOf(node)          -> {prop: value} from the style attribute
//   serialize(node)        -> compact html;  pretty(node, indent=0) -> array of lines (svg is one line)
//   walk(node, fn, path)   -> depth-first, fn(node, parent, pathArray)
const VOID = new Set(['img', 'path', 'circle', 'rect', 'line', 'ellipse', 'polyline', 'polygon', 'stop', 'br', 'img']);
// numeric entities (&#35; in hex labels) are decoded too, so fragments carry the character Paper should show
const unesc = (s) => s.replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&#(\d+);/g, (_, d) => String.fromCharCode(+d)).replace(/&amp;/g, '&');
export const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function parse(html) {
  let i = 0;
  const n = html.length;
  const attrRe = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:="([^"]*)")?/y;
  function parseEl() {
    // at '<'
    i++;
    let j = i;
    while (j < n && !/[\s/>]/.test(html[j])) j++;
    const tag = html.slice(i, j);
    i = j;
    const attrs = {};
    for (;;) {
      while (i < n && /\s/.test(html[i])) i++;
      if (html[i] === '>' || (html[i] === '/' && html[i + 1] === '>')) break;
      attrRe.lastIndex = i;
      const m = attrRe.exec(html);
      if (!m) throw new Error(`parse: bad attribute near "${html.slice(i, i + 40)}"`);
      attrs[m[1]] = m[2] === undefined ? '' : unesc(m[2]);
      i = attrRe.lastIndex;
    }
    const node = { tag, attrs, children: [] };
    if (html[i] === '/') { i += 2; return node; }
    i++;
    if (VOID.has(tag)) return node;
    for (;;) {
      if (i >= n) return node;
      if (html[i] === '<') {
        if (html[i + 1] === '/') { const e = html.indexOf('>', i); i = e + 1; return node; }
        node.children.push(parseEl());
      } else {
        let k = html.indexOf('<', i); if (k < 0) k = n;
        const t = html.slice(i, k);
        if (t.trim() !== '') node.children.push({ text: unesc(t) });
        i = k;
      }
    }
  }
  while (i < n && html[i] !== '<') i++;
  return parseEl();
}

export function styleOf(node) {
  const out = {};
  const s = node.attrs?.style || '';
  // split on ; not inside parentheses
  let depth = 0, cur = '';
  const parts = [];
  for (const ch of s) {
    if (ch === '(') depth++;
    if (ch === ')') depth--;
    if (ch === ';' && depth === 0) { parts.push(cur); cur = ''; } else cur += ch;
  }
  if (cur.trim()) parts.push(cur);
  for (const p of parts) {
    const k = p.indexOf(':');
    if (k > 0) out[p.slice(0, k).trim()] = p.slice(k + 1).trim();
  }
  return out;
}
export const styleToString = (st) => Object.entries(st).map(([k, v]) => `${k}:${v}`).join(';');

function attrString(node) {
  return Object.entries(node.attrs).map(([k, v]) => ` ${k}="${v.replace(/&/g, '&amp;').replace(/"/g, '&quot;')}"`).join('');
}
export function serialize(node) {
  if (node.text !== undefined) return esc(node.text);
  if (VOID.has(node.tag) && !node.children.length) return `<${node.tag}${attrString(node)}/>`;
  return `<${node.tag}${attrString(node)}>${node.children.map(serialize).join('')}</${node.tag}>`;
}
export function pretty(node, indent = 0) {
  const pad = '  '.repeat(indent);
  if (node.text !== undefined) return [pad + esc(node.text)];
  if (node.tag === 'svg' || VOID.has(node.tag)) return [pad + serialize(node)];
  if (node.children.every((ch) => ch.text !== undefined)) return [pad + serialize(node)];
  return [`${pad}<${node.tag}${attrString(node)}>`, ...node.children.flatMap((ch) => pretty(ch, indent + 1)), `${pad}</${node.tag}>`];
}
export function walk(node, fn, path = [], parent = null) {
  if (node.text !== undefined) return;
  fn(node, parent, path);
  for (const ch of node.children) walk(ch, fn, [...path, node], node);
}
