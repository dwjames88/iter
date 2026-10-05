// h.mjs - tiny HTML builder obeying Paper's rules. Every element gets a layer-name and box-sizing:border-box;
// styles are objects (camelCase -> kebab) or strings; text is escaped; forbidden CSS throws at build time.
//
// Exports
//   el(tag, {name, style, attrs}, ...children)  tag: 'div'|'span'|'a'. name REQUIRED (<= 50 chars).
//        children: strings (escaped text), Html values from other helpers, arrays (flattened), null/false (skipped).
//        NEVER build html by template-string concatenation of helper results; pass them as children.
//   row(opts, ...children) / col(opts, ...children)   flex row / column. opts: {name, gap, pad, align, justify, wrap,
//        grow (true: flex 1 1 0; 'auto': flex 1 1 auto, use for page-level columns whose height must follow content), noshrink, w, h, bg, radius, clip, style}. gap/pad/w/h: number (px) or CSS string (use d('space/md')).
//        pad may be [vertical, horizontal] or [t, r, b, l]. align -> align-items, justify -> justify-content.
//   text(str, {name, font, color, align, wrap, grow, noshrink, style})  one text node, one style. font = font('headline');
//        color = token name 'text/secondary' or a CSS value. Default nowrap; pass wrap:true to allow wrapping.
//   svgEl(name, {width, height, viewBox, style}, innerSvg)  named <svg> (children need no names). svg(str) = raw passthrough.
//   raw(htmlString)      mark a trusted string as Html.     esc(str)   escape text.
//   styleString(style)   object|string -> validated css text.    px(v)  number -> 'Npx'.
//   spacer(name?)        flex:1 empty element.
import { resolveColor } from './tokens.mjs';

export class Html {
  constructor(s) { this.s = s; }
  toString() { return this.s; }
}
export const raw = (s) => new Html(String(s));
export const svg = raw;
export const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
export const px = (v) => (typeof v === 'number' ? (v === 0 ? '0' : `${v}px`) : v);

const UNITLESS = new Set(['opacity', 'flex', 'flexGrow', 'flexShrink', 'fontWeight', 'zIndex', 'lineHeight', 'order', 'scale', 'strokeWidth']);
const kebab = (k) => k.replace(/[A-Z]/g, (m) => '-' + m.toLowerCase());
const FORBIDDEN_STR = [/(^|[;\s])margin[a-z-]*\s*:/i, /display\s*:\s*(grid|inline)/i, /(^|[;\s])float\s*:/i];

export function styleString(style) {
  if (!style) return '';
  if (typeof style === 'string') {
    for (const re of FORBIDDEN_STR) if (re.test(style)) throw new Error(`Forbidden CSS in style string: ${style.slice(0, 120)}`);
    return style.replace(/;\s*$/, '');
  }
  const parts = [];
  for (const [k, v] of Object.entries(style)) {
    if (v === undefined || v === null || v === false) continue;
    const prop = kebab(k);
    if (/^margin/.test(prop)) throw new Error(`Forbidden CSS "${prop}" (use padding/gap)`);
    if (prop === 'float') throw new Error('Forbidden CSS "float"');
    if (prop === 'display' && /^(grid|inline)/.test(String(v))) throw new Error(`Forbidden CSS "display:${v}"`);
    const val = typeof v === 'number' && !UNITLESS.has(k) ? px(v) : v;
    parts.push(`${prop}:${val}`);
  }
  return parts.join(';');
}

const TAGS = new Set(['div', 'span', 'a']);
function flat(children, out = []) {
  for (const ch of children) {
    if (ch == null || ch === false || ch === true) continue;
    if (Array.isArray(ch)) flat(ch, out);
    else out.push(ch);
  }
  return out;
}

export function el(tag, opts = {}, ...children) {
  const { name, style, attrs } = opts;
  if (!TAGS.has(tag)) throw new Error(`el: tag <${tag}> not allowed (use div/span/a; svg via svgEl)`);
  if (!name || typeof name !== 'string') throw new Error(`el(<${tag}>): "name" (layer-name) is required`);
  if (name.length > 50) throw new Error(`el: layer-name longer than 50 chars: "${name}"`);
  let a = '';
  if (attrs) for (const [k, v] of Object.entries(attrs)) {
    if (['class', 'style', 'layer-name'].includes(k)) throw new Error(`el: attribute "${k}" not allowed`);
    a += ` ${k}="${esc(v)}"`;
  }
  const kids = flat(children);
  const hasHtml = kids.some((k) => k instanceof Html);
  const inner = kids.map((k) => (k instanceof Html ? k.s : esc(k))).join(hasHtml ? '\n' : '');
  const st = styleString({ boxSizing: 'border-box' }) + (style ? ';' + styleString(style) : '');
  return new Html(`<${tag} layer-name="${esc(name)}"${a} style="${st}">${hasHtml ? '\n' + inner + '\n' : inner}</${tag}>`);
}

function boxStyle(o, base) {
  const s = { ...base };
  if (o.gap !== undefined) s.gap = px(o.gap);
  if (o.pad !== undefined) s.padding = Array.isArray(o.pad) ? o.pad.map(px).join(' ') : px(o.pad);
  if (o.align) s.alignItems = o.align;
  if (o.justify) s.justifyContent = o.justify;
  if (o.wrap) s.flexWrap = 'wrap';
  if (o.grow) { s.flex = o.grow === 'auto' ? '1 1 auto' : '1 1 0'; s.minWidth = 0; }
  if (o.noshrink) s.flexShrink = 0;
  if (o.w !== undefined) s.width = px(o.w);
  if (o.h !== undefined) s.height = px(o.h);
  if (o.bg) s.background = resolveColor(o.bg);
  if (o.radius !== undefined) s.borderRadius = px(o.radius);
  if (o.clip) s.overflow = 'hidden';
  if (o.border) s.border = o.border;
  return typeof o.style === 'string' ? styleString(s) + ';' + styleString(o.style) : { ...s, ...(o.style || {}) };
}
export function row(o = {}, ...children) {
  return el('div', { name: o.name, attrs: o.attrs, style: boxStyle(o, { display: 'flex', flexDirection: 'row' }) }, ...children);
}
export function col(o = {}, ...children) {
  return el('div', { name: o.name, attrs: o.attrs, style: boxStyle(o, { display: 'flex', flexDirection: 'column' }) }, ...children);
}
export function spacer(name = 'Spacer') {
  return el('div', { name, style: { flex: '1 1 0', minWidth: 0, minHeight: 0 } });
}
export function text(str, o = {}) {
  const s = String(str);
  const st = {};
  if (o.color) st.color = resolveColor(o.color);
  if (o.align) st.textAlign = o.align;
  if (!o.wrap) st.whiteSpace = 'nowrap';
  if (o.grow) { st.flex = '1 1 0'; st.minWidth = 0; }
  if (o.noshrink) st.flexShrink = 0;
  if (o.w !== undefined) st.width = px(o.w);
  let style = styleString(st);
  if (o.font) style = o.font + (style ? ';' + style : '');
  if (typeof o.style === 'string') style += ';' + styleString(o.style); else if (o.style) style += ';' + styleString(o.style);
  return el('div', { name: o.name || s.slice(0, 40) || 'Text', attrs: o.attrs, style: style }, s);
}
export function svgEl(name, o = {}, inner = '') {
  if (!name || name.length > 50) throw new Error(`svgEl: bad layer-name "${name}"`);
  const { width, height, viewBox, style, attrs } = o;
  const a = attrs ? Object.entries(attrs).map(([k, v]) => ` ${k}="${esc(v)}"`).join('') : '';
  const st = `box-sizing:border-box;display:block;flex-shrink:0${style ? ';' + styleString(style) : ''}`;
  return new Html(`<svg layer-name="${esc(name)}" xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="${viewBox || `0 0 ${width} ${height}`}"${a} style="${st}">${inner instanceof Html ? inner.s : inner}</svg>`);
}
