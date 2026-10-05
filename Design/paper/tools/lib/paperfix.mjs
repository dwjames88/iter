// paperfix.mjs - small, visually neutral rewrites so Paper lays text out the way a browser does.
// Found on the canvas on 2026-10-05 (probe artboard, then deleted):
//  A. A text-only element with a px width and white-space:nowrap becomes a Frame (the width) holding a Text that hugs its
//     content at the start, so text-align:center/right is lost. Adding display:flex + justify-content (center / flex-end)
//     puts the Text where the browser puts the line. In a browser the result is identical.
//  B. A text-only nowrap element WITHOUT a px width becomes a hugging Text (width max-content), so in a column flex parent
//     it sits at the start instead of being centred or right-aligned across the parent. Adding align-self (center /
//     flex-end) gives the same picture. Applied only when the element draws no box (no background, border or padding) and
//     does not grow, so shrinking it to its content is invisible in a browser.
//  C. Paper drops a whole `border` / `border-*` / `outline` declaration whose width is a var() (the hairline vanished), and
//     ignores var() inside SVG stroke-width / stroke-dasharray / fill-opacity / opacity. Those dimension and opacity
//     tokens are written as their literal values there (colour tokens stay var(), which Paper keeps bound).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse, styleOf, styleToString, serialize } from './dom.mjs';

const tokensCss = fs.readFileSync(path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'tokens.css'), 'utf8');
const TOK = new Map([...tokensCss.matchAll(/^\s*(--[\w-]+):\s*(.+);\s*$/gm)].map((m) => [m[1], m[2]]));
const LITERAL_IN = /^(border|border-top|border-right|border-bottom|border-left|outline|border-width|stroke-width|stroke-dasharray|stroke-dashoffset|fill-opacity|stroke-opacity)$/;
const literalDims = (v) => v.replace(/var\((--(?:spacing|opacity|radius)-[\w-]+)\)/g, (all, n) => (TOK.has(n) ? TOK.get(n) : all));
function literalize(n, inSvg) {
  if (n.text !== undefined) return 0;
  let changed = 0;
  const s = styleOf(n);
  let hit = false;
  for (const [k, v] of Object.entries(s)) {
    if ((LITERAL_IN.test(k) || (inSvg && k === 'opacity')) && /var\(--(spacing|opacity|radius)-/.test(v)) { s[k] = literalDims(v); hit = true; }
  }
  if (hit) { n.attrs.style = styleToString(s); changed++; }
  for (const c of n.children) changed += literalize(c, inSvg || n.tag === 'svg');
  return changed;
}

const isLeafText = (n) => n.tag !== 'svg' && n.children.length > 0 && n.children.every((c) => c.text !== undefined);
const drawsBox = (s) => Object.keys(s).some((k) => /^(background|border|padding|box-shadow|outline)/.test(k));

function fix(n, parentStyle) {
  if (n.text !== undefined || n.tag === 'svg') return 0;
  let changed = 0;
  const s = styleOf(n);
  if (isLeafText(n)) {
    const a = s['text-align'];
    if ((a === 'center' || a === 'right') && s['white-space'] === 'nowrap') {
      if (/^\d+(\.\d+)?px$/.test(s.width || '') && !s.display) {
        s.display = 'flex';
        s['justify-content'] = a === 'center' ? 'center' : 'flex-end';
        n.attrs.style = styleToString(s); changed++;
      } else if (!s.width && !s['align-self'] && !/^[1-9]/.test(s.flex || '') && !s['flex-grow'] && !drawsBox(s)
        && parentStyle && parentStyle.display === 'flex' && parentStyle['flex-direction'] === 'column'
        && (!parentStyle['align-items'] || parentStyle['align-items'] === 'stretch')) {
        s['align-self'] = a === 'center' ? 'center' : 'flex-end';
        n.attrs.style = styleToString(s); changed++;
      }
    }
  }
  for (const c of n.children) changed += fix(c, s);
  return changed;
}

// rootHtml: the artboard root element html. Returns {html, changed}.
export function paperFix(rootHtml) {
  const root = parse(rootHtml);
  const changed = fix(root, null) + literalize(root, false);
  return { html: changed ? serialize(root) : rootHtml, changed };
}
