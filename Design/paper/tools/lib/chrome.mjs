// chrome.mjs - macOS 26 (Tahoe, Liquid Glass) window chrome and system surfaces.
//
//   macWindow({width, height, title, toolbarLeading=[], toolbarTrailing=[], sidebar, detail, sidebarWidth=240,
//              hideTitle=false, sidebarToolbar, overlays=[], detailBackground})
//        The window fills width x height exactly (rounded 26, outline). Layout: floating glass sidebar panel (inset 8,
//        traffic lights + sidebar toolbar + sidebar content) and the detail column (52 high unified toolbar, then `detail`).
//        sidebar: Html from sidebar() (or any), or null for a hidden sidebar (traffic lights move to the toolbar).
//        toolbarLeading / toolbarTrailing: arrays of Html (toolbarButton/toolbarGroup/toolbarSearch/...).
//        sidebarToolbar: array of Html placed in the sidebar header before the sidebar toggle (default: New Trip `plus`).
//        overlays: Html or functions ({width,height}) => Html (sheet(), alert() return such functions); drawn above, absolutely.
//        detail should be a flex child that fills (e.g. col({grow:true}) / mapPlaceholder with grow).
//   sidebar({selected:'trips'|'explore'|'saved'|'scout'|<trip name>, trips:['Canyon Country'], sampleBanner:true})
//   toolbarButton(symbol, {label, menu, toggled, disabled, bare})   glass capsule (34 high); bare:true = cell inside a group
//   toolbarGroup([ [symbol, opts] | Html ])                          items sharing one glass capsule
//   toolbarSearch(prompt, {width=220})                               toolbar search field
//   sheet({width, height, title, body, buttons, top=28}) -> overlay function       sheetPanel(opts) -> the panel only
//   alert({title, message, buttons:['OK']|[{label, kind, destructive}], width=280}) -> overlay function; alertPanel(opts)
//   popover({width, height, arrow:'top'|'bottom'|'left'|'right'|null, arrowOffset, body, x, y})
//   menu(items, {width, x, y})   items: 'Label' | '-' | {label, shortcut, icon, checked, submenu, disabled, destructive,
//                                highlight, header, divider:true}      x,y given -> absolutely positioned
//   mapPlaceholder({width, height, label, grow, children})           named "Map placeholder (swap)"; children = absolutely positioned pins/cards
//   note({title, body, width=260})                                   annotation card "Note / <title>"
//   foldMarker(y, {label:'Fold · 820'})                              dashed annotation line at y
//   materialSurface({kind, radius, stroke, shadow})   style object for any translucent surface (regular|bar|menu|sheet|glass)
//   trafficLights()
import { el, row, col, text, svgEl, raw, spacer } from './h.mjs';
import { c, d, canvas, font, op, dv } from './tokens.mjs';
import { icon } from './icons.mjs';
import { button, divider } from './controls.mjs';
import { sampleDataLabel } from './lightindex.mjs';

const TOOLBAR_H = 52, BTN = 34, WIN_R = 26, INSET = 8, PANEL_R = 18;
// materialSurface({kind:'regular'|'bar'|'menu'|'sheet'|'glass'='regular', radius, stroke=true, shadow=true}) -> style object
// (spread into an el/col/row `style`). Translucent token fill + backdrop blur/saturate (macOS materials blur what is behind them).
// backdrop-filter in Paper is unconfirmed: the fill is 92-96% opaque so the surface reads acceptably without the blur.
const MATERIALS = { regular: ['material/regular', 'material/stroke', 'shadow/material', 24], bar: ['material/bar', 'material/stroke', null, 24], menu: ['menu/background', 'menu/stroke', 'shadow/menu', 30], sheet: ['sheet/background', null, 'shadow/sheet', 30], glass: ['chrome/control', 'chrome/control-stroke', 'shadow/control', 16] };
export function materialSurface({ kind = 'regular', radius, stroke = true, shadow = true } = {}) {
  const m = MATERIALS[kind];
  if (!m) throw new Error(`materialSurface: unknown kind "${kind}"`);
  const st = { background: canvas(m[0]), backdropFilter: `blur(${m[3]}px) saturate(1.6)` };
  if (stroke && m[1]) st.border = `1px solid ${canvas(m[1])}`;
  if (shadow && m[2]) st.boxShadow = canvas(m[2]);
  if (radius !== undefined) st.borderRadius = typeof radius === 'number' ? `${radius}px` : radius;
  return st;
}
const abs = (o) => ({ position: 'absolute', ...o });

export function trafficLights() {
  const dot = (nm, k) => el('div', { name: nm, style: { width: 14, height: 14, borderRadius: '999px', background: canvas(`traffic/${k}`), border: `0.5px solid ${canvas(`traffic/${k}-stroke`)}`, flexShrink: 0 } });
  return row({ name: 'Traffic Lights', align: 'center', gap: 8, noshrink: true }, dot('Close', 'close'), dot('Minimize', 'minimize'), dot('Zoom', 'zoom'));
}

function cell(symbol, { label, menu, toggled, disabled } = {}) {
  const fg = disabled ? 'text/quaternary' : 'text/primary';
  return row({ name: `Toolbar Item / ${label || symbol}`.slice(0, 50), align: 'center', justify: 'center', gap: d('space/xs'), noshrink: true,
    style: { height: BTN, minWidth: BTN, padding: label || menu ? `0 ${menu && !label ? 10 : 14}px` : '0', borderRadius: '999px', background: toggled ? canvas('chrome/control-active') : undefined } },
  symbol ? icon(symbol, { size: 16, color: fg }) : null,
  label ? text(label, { name: 'Label', font: font('body'), color: fg }) : null,
  menu ? icon('chevron.down', { size: 9, color: 'text/secondary', weight: 'bold' }) : null);
}
const glass = (name, children) => row({ name, align: 'center', noshrink: true,
  style: { height: BTN, ...materialSurface({ kind: 'glass', radius: 999 }) } }, children);

export function toolbarButton(symbol, opts = {}) {
  const x = cell(symbol, opts);
  return opts.bare ? x : glass(`Toolbar Button / ${opts.label || symbol}`.slice(0, 50), x);
}
export function toolbarGroup(items) {
  return glass('Toolbar Group', items.map((it) => (Array.isArray(it) ? cell(it[0], it[1] || {}) : it)));
}
export function toolbarSearch(prompt = 'Search', { width = 220 } = {}) {
  return row({ name: 'Toolbar Search', align: 'center', gap: d('space/sm'), noshrink: true,
    style: { width, height: BTN, padding: `0 ${d('space/md')}`, ...materialSurface({ kind: 'glass', radius: 999 }) } },
  icon('magnifyingglass', { size: 14, color: 'text/secondary' }),
  text(prompt, { name: 'Prompt', font: font('body'), color: 'text/tertiary' }));
}

// ---- sidebar ---------------------------------------------------------------------------------------------
const NAV = [
  ['trips', 'All Trips', 'map'],
  ['explore', 'Explore', 'binoculars'],
  ['saved', 'Saved', 'bookmark'],
  ['scout', 'Scout', 'sparkle.magnifyingglass'],
];
function sideRow(label, sym, selected) {
  return row({ name: `Sidebar Row / ${label}`.slice(0, 50), align: 'center', gap: d('space/sm'), bg: selected ? canvas('selection/tint') : undefined,
    style: { height: 32, padding: '0 10px', borderRadius: 10, flexShrink: 0 } },
  row({ name: 'Icon Slot', align: 'center', justify: 'center', noshrink: true, w: 24 }, icon(sym, { size: 17, color: 'accent/primary' })),
  text(label, { name: 'Label', font: font('body'), color: 'text/primary' }));
}
function sideHeader(label) {
  return text(label, { name: `Section Header / ${label}`, font: font('callout', { weight: 'semibold' }), color: 'text/secondary', style: { padding: '14px 10px 6px', flexShrink: 0 } });
}
export function sidebar({ selected = 'trips', trips = ['Canyon Country'], sampleBanner = true } = {}) {
  const sel = (key) => selected === key;
  return col({ name: 'Sidebar', grow: true, style: { minHeight: 0 } },
    col({ name: 'Sidebar List', grow: true, pad: [0, 6, 0, 6], style: { minHeight: 0 } },
      sideHeader('Trips'),
      sideRow('All Trips', 'map', sel('trips')),
      trips.map((t) => sideRow(t, 'point.topleft.down.to.point.bottomright.curvepath', selected === t)),
      sideHeader('Find'),
      sideRow('Explore', 'binoculars', sel('explore')),
      sideRow('Saved', 'bookmark', sel('saved')),
      sideRow('Scout', 'sparkle.magnifyingglass', sel('scout'))),
    sampleBanner ? col({ name: 'Sidebar Bottom Inset', pad: d('space/sm'), style: { flexShrink: 0 } }, sampleDataLabel({ style: 'banner' })) : null);
}

// ---- window ----------------------------------------------------------------------------------------------
export function macWindow({ width, height, title, toolbarLeading = [], toolbarTrailing = [], sidebar: side, detail, sidebarWidth = 240, hideTitle = false, sidebarToolbar, overlays = [], detailBackground } = {}) {
  if (!width || !height) throw new Error('macWindow: width and height required');
  const toggle = toolbarButton('sidebar.left', {});
  const sbTools = sidebarToolbar ?? [toolbarButton('plus')];
  const titleEl = !hideTitle && title ? text(title, { name: 'Window Title', font: font('title/section', { size: 15, weight: 'semibold', lineHeight: 20 }), color: 'text/primary' }) : null;
  const sidebarCol = side ? el('div', { name: 'Sidebar Column', style: { width: sidebarWidth, flexShrink: 0, padding: `${INSET}px 4px ${INSET}px ${INSET}px`, display: 'flex', flexDirection: 'column', alignSelf: 'stretch' } },
    col({ name: 'Sidebar Panel', grow: true, radius: PANEL_R, clip: true, style: { background: canvas('chrome/sidebar'), backdropFilter: 'blur(30px) saturate(1.6)', border: `1px solid ${canvas('chrome/sidebar-stroke')}`, minHeight: 0, flex: '1 1 0' } },
      row({ name: 'Sidebar Toolbar', align: 'center', gap: d('space/sm'), style: { height: TOOLBAR_H - INSET, padding: `0 ${d('space/sm')} 0 14px`, flexShrink: 0 } },
        trafficLights(), spacer(), sbTools, toggle),
      side)) : null;
  const detailToolbar = row({ name: 'Toolbar', align: 'center', gap: d('space/md'), style: { height: TOOLBAR_H, padding: `0 16px 0 ${side ? 20 : 14}px`, flexShrink: 0, background: canvas('chrome/titlebar') } },
    side ? null : [trafficLights(), toggle],
    toolbarLeading, titleEl, spacer(), toolbarTrailing);
  const detailCol = col({ name: 'Detail', grow: true, style: { minHeight: 0, background: detailBackground ? c(detailBackground) : c('background/window') } }, detailToolbar, detail);
  const ctx = { width, height, sidebarWidth };
  return el('div', { name: 'Window', style: { width, height, position: 'relative', display: 'flex', flexDirection: 'row', overflow: 'hidden', borderRadius: WIN_R, background: c('background/window'), border: `1px solid ${canvas('window/outline')}`, flexShrink: 0 } },
    sidebarCol, detailCol,
    (Array.isArray(overlays) ? overlays : [overlays]).map((o) => (typeof o === 'function' ? o(ctx) : o)));
}
// ---- sheets, alerts, menus, popovers -----------------------------------------------------------------------
export function sheetPanel({ width = 480, height, title, body, buttons = [] } = {}) {
  return col({ name: `Sheet / ${title || 'Untitled'}`.slice(0, 50), pad: 20, gap: d('space/lg'), w: width, h: height, noshrink: true,
    style: { ...materialSurface({ kind: 'sheet', radius: 26 }) } },
  title ? text(title, { name: 'Title', font: font('title/section', { weight: 'semibold' }), color: 'text/primary' }) : null,
  col({ name: 'Sheet Body', grow: height ? true : false, style: { minHeight: 0 } }, body),
  buttons.length ? row({ name: 'Sheet Buttons', align: 'center', justify: 'flex-end', gap: d('space/sm') }, buttons) : null);
}
function scrim() { return el('div', { name: 'Scrim', style: abs({ top: 0, left: 0, right: 0, bottom: 0, background: canvas('scrim/sheet') }) }); }
export function sheet(opts = {}) {
  const { width = 480, top = 28 } = opts;
  return (ctx) => raw([scrim(), el('div', { name: 'Sheet Position', style: abs({ top, left: Math.round((ctx.width - width) / 2), display: 'flex' }) }, sheetPanel(opts))].map(String).join('\n'));
}
export function alertPanel({ title, message, buttons = ['OK'], width = 280 } = {}) {
  const btns = buttons.map((b, i) => {
    const o = typeof b === 'string' ? { label: b } : b;
    return button(o.label, { kind: o.kind || (i === 0 ? 'prominent' : 'bordered'), size: 'large', destructive: o.destructive, width: '100%' });
  });
  return col({ name: `Alert / ${title}`.slice(0, 50), align: 'center', gap: d('space/md'), pad: 20, w: width, noshrink: true,
    style: { ...materialSurface({ kind: 'sheet', radius: 26 }) } },
  el('div', { name: 'App Icon (swap)', style: { width: 56, height: 56, borderRadius: 13, background: c('accent/primary'), display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 } },
    el('div', { name: 'Dot', style: { width: 14, height: 14, borderRadius: '999px', background: c('accent/onAccent') } })),
  text(title, { name: 'Title', font: font('headline'), color: 'text/primary', align: 'center', wrap: true }),
  message ? text(message, { name: 'Message', font: font('callout'), color: 'text/secondary', align: 'center', wrap: true }) : null,
  col({ name: 'Alert Buttons', gap: d('space/sm'), style: { alignSelf: 'stretch', paddingTop: 4 } }, btns));
}
export function alert(opts = {}) {
  const { width = 280 } = opts;
  return (ctx) => raw([scrim(), el('div', { name: 'Alert Position', style: abs({ top: Math.round(ctx.height * 0.28), left: Math.round((ctx.width - width) / 2), display: 'flex' }) }, alertPanel(opts))].map(String).join('\n'));
}

const panel = (name, extra) => ({ ...materialSurface({ kind: 'menu' }), ...extra });

export function popover({ width, height, arrow = 'top', arrowOffset, body, x, y, name = 'Popover' } = {}) {
  const AW = 22, AH = 11;
  const pos = x !== undefined ? abs({ left: x, top: y }) : { position: 'relative' };
  let arrowEl = null;
  if (arrow) {
    const off = arrowOffset ?? ((arrow === 'top' || arrow === 'bottom' ? width : height) / 2 - AW / 2);
    const rot = { top: 0, bottom: 180, left: 270, right: 90 }[arrow];
    const place = { top: { top: -AH + 1, left: off }, bottom: { bottom: -AH + 1, left: off }, left: { left: -AH + 1 - (AW - AH) / 2 + (AW - AH) / 2, top: off }, right: { right: -AH + 1, top: off } }[arrow];
    const vb = arrow === 'top' || arrow === 'bottom' ? [AW, AH] : [AH, AW];
    const path = { top: `M0 ${AH} L${AW / 2} 0 L${AW} ${AH}`, bottom: `M0 0 L${AW / 2} ${AH} L${AW} 0`, left: `M${AH} 0 L0 ${AW / 2} L${AH} ${AW}`, right: `M0 0 L${AH} ${AW / 2} L0 ${AW}` }[arrow];
    arrowEl = svgEl('Popover Arrow', { width: vb[0], height: vb[1], style: abs({ ...place }) },
      raw(`<path d="${path}" style="fill:${canvas('menu/background')};stroke:${canvas('menu/stroke')}" stroke-width="1"/>`));
  }
  return el('div', { name, style: { ...pos, width, height, flexShrink: 0, display: 'flex', borderRadius: 14, ...panel() } },
    arrowEl,
    el('div', { name: 'Popover Content', style: { width: '100%', height: '100%', display: 'flex', flexDirection: 'column', overflow: 'hidden', borderRadius: 14, position: 'relative' } }, body));
}

export function menu(items, { width, x, y, name = 'Menu' } = {}) {
  const list = items.map((i) => (i === '-' ? { divider: true } : typeof i === 'string' ? { label: i } : i));
  const lead = list.some((i) => i.checked || i.icon);
  const rows = list.map((it) => {
    if (it.divider) return el('div', { name: 'Menu Divider', style: { padding: '5px 8px', display: 'flex', flexDirection: 'column', flexShrink: 0 } }, divider());
    if (it.header) return text(it.header, { name: `Menu Header / ${it.header}`.slice(0, 50), font: font('subheadline', { weight: 'semibold' }), color: 'text/secondary', style: { padding: '6px 10px 2px' } });
    const hi = it.highlight;
    const fg = hi ? 'accent/onAccent' : it.disabled ? 'text/quaternary' : it.destructive ? 'status/danger' : 'text/primary';
    const fg2 = hi ? 'accent/onAccent' : 'text/secondary';
    return row({ name: `Menu Item / ${it.label}`.slice(0, 50), align: 'center', gap: d('space/sm'), style: { height: 26, padding: '0 10px', borderRadius: 8, flexShrink: 0, background: hi ? canvas('menu/highlight') : undefined } },
      lead ? row({ name: 'Leading Slot', align: 'center', justify: 'center', noshrink: true, w: 16 }, it.checked ? icon('checkmark', { size: 11, color: fg, weight: 'semibold' }) : it.icon ? icon(it.icon, { size: 14, color: fg }) : null) : null,
      text(it.label, { name: 'Label', font: font('body'), color: fg, grow: true }),
      it.shortcut ? text(it.shortcut, { name: 'Shortcut', font: font('body'), color: fg2, style: { paddingLeft: 24 } }) : null,
      it.submenu ? icon('chevron.right', { size: 10, color: fg2, weight: 'semibold' }) : null);
  });
  const pos = x !== undefined ? abs({ left: x, top: y }) : {};
  return col({ name, w: width, style: { ...pos, padding: 6, borderRadius: 14, flexShrink: 0, minWidth: 180, ...panel() } }, rows);
}

// ---- map placeholder, annotations --------------------------------------------------------------------------
export function mapPlaceholder({ width, height, label = 'Map placeholder — swap for a map image', grow = false, children = [] } = {}) {
  const line = canvas('map/line'), major = canvas('map/line-major');
  const W = 1000, Hh = 700;
  const g = `<g fill="none" stroke-linecap="round" stroke-linejoin="round">
<path d="M-20 520 C 160 470, 280 560, 430 500 S 700 380, 1020 430" style="stroke:${major}" stroke-width="5"/>
<path d="M120 -20 C 180 150, 140 280, 260 380 S 380 600, 340 720" style="stroke:${major}" stroke-width="4"/>
<path d="M-20 240 C 150 210, 300 260, 470 190 S 760 120, 1020 170" style="stroke:${line}" stroke-width="3"/>
<path d="M560 -20 C 600 130, 540 260, 640 360 S 780 560, 740 720" style="stroke:${line}" stroke-width="3"/>
<path d="M820 -20 C 800 100, 900 200, 860 330 S 940 520, 1020 600" style="stroke:${line}" stroke-width="2"/>
<path d="M-20 650 C 200 620, 380 700, 600 640 S 880 600, 1020 690" style="stroke:${line}" stroke-width="2"/>
<ellipse cx="760" cy="520" rx="210" ry="120" style="stroke:${line}" stroke-width="1.5"/>
<ellipse cx="760" cy="520" rx="150" ry="82" style="stroke:${line}" stroke-width="1.5"/>
<ellipse cx="760" cy="520" rx="90" ry="46" style="stroke:${line}" stroke-width="1.5"/>
<ellipse cx="270" cy="170" rx="170" ry="90" style="stroke:${line}" stroke-width="1.5"/>
<ellipse cx="270" cy="170" rx="100" ry="50" style="stroke:${line}" stroke-width="1.5"/>
</g>`;
  const art = el('div', { name: 'Map Art', style: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, display: 'flex' } },
    svgEl('Roads and Contours', { width: '100%', height: '100%', viewBox: `0 0 ${W} ${Hh}`, attrs: { preserveAspectRatio: 'xMidYMid slice' } }, raw(g)));
  return el('div', { name: 'Map placeholder (swap)', style: { position: 'relative', display: 'flex', overflow: 'hidden', background: canvas('map/ground'), width: grow ? undefined : width, height: grow ? undefined : height, flex: grow ? '1 1 0' : undefined, minWidth: 0, minHeight: 0, flexShrink: grow ? 1 : 0 } },
    art,
    text(label, { name: 'Map Caption', font: font('caption'), color: canvas('map/label'), style: abs({ left: 12, bottom: 10 }) }),
    children);
}

export function note({ title, body, width = 260 } = {}) {
  return col({ name: `Note / ${title}`.slice(0, 50), w: width, gap: d('space/xs'), pad: d('space/md'), noshrink: true,
    style: { background: canvas('note/background'), border: `1px solid ${canvas('note/border')}`, borderRadius: d('radius/control') } },
  text(title, { name: 'Note Title', font: font('subheadline', { weight: 'semibold' }), color: canvas('note/text'), wrap: true }),
  text(body, { name: 'Note Body', font: font('subheadline'), color: canvas('note/text'), wrap: true }));
}

export function foldMarker(y, { label = 'Fold · 820' } = {}) {
  return el('div', { name: 'Fold Marker', style: abs({ top: y, left: 0, right: 0, height: 0, borderTop: `1px dashed ${canvas('note/border')}` }) },
    text(label, { name: 'Fold Label', font: font('caption', { weight: 'semibold' }), color: canvas('note/text'), style: abs({ top: -10, right: 12, padding: '1px 6px', borderRadius: 6, background: canvas('note/background'), border: `1px solid ${canvas('note/border')}` }) }));
}
