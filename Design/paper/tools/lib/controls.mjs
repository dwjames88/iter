// controls.mjs - macOS 26 system controls, drawn (not restyled). All return Html.
//   button(label, {kind:'prominent'|'bordered'|'borderless'|'link'|'plain'='bordered', size:'small'|'regular'|'large'='regular',
//                  icon:'symbol.name', destructive, disabled, width})
//   segmented(items, selectedIndex, {width})      items: strings or {icon} / {label, icon}
//   popUpButton(label, {width})                   capsule with up/down chevrons
//   pullDown(label, icon?, {width})               capsule with label (optional leading icon) and chevron.down
//   textField({value, placeholder, width, height, secure})    rounded text field
//   searchField({value, placeholder, width})      capsule with magnifying glass
//   stepper(value, {width})                       value text + stepper glyph
//   checkbox(label, checked)                      16pt box + label
//   datePicker(value, {width})                    compact date field with stepper glyph
//   spinner(size=16)                              indeterminate spinner (static frame)
//   formGroup({header, rows:[{label, control, help?}], footer, width})   grouped Form section
//   listSection({header, count, rows:[Html]})     List section with header (+ trailing count)
//   listRow({selected, children, name, pad})      list row, accent tint when selected
//   contentUnavailable({symbol, title, description, buttons:[Html]})   system empty state
//   divider({vertical, name})                     hairline separator
//   tooltip(text)                                 system tooltip
import { el, row, col, text, svgEl, raw, px } from './h.mjs';
import { c, d, canvas, font, op } from './tokens.mjs';
import { icon } from './icons.mjs';

const H = { small: 22, regular: 28, large: 36 };
const PADX = { small: 10, regular: 14, large: 18 };
const capsuleFx = () => ({ background: canvas('control/button'), border: `1px solid ${canvas('control/button-stroke')}`, boxShadow: canvas('shadow/button') });

export function button(label, { kind = 'bordered', size = 'regular', icon: sym, destructive = false, disabled = false, width } = {}) {
  const h = size === 'regular' ? d('size/control/height') : size === 'large' ? d('size/control/heightLarge') : H.small;
  const f = size === 'large' ? font('title/section', { size: 15, weight: 'regular', lineHeight: 20 }) : font('body');
  const fg = kind === 'prominent' ? (destructive ? 'accent/onAccent' : 'accent/onAccent')
    : destructive ? 'status/danger'
    : kind === 'borderless' || kind === 'link' ? 'accent/text'
    : 'text/primary';
  const st = { height: h, minWidth: kind === 'plain' ? undefined : undefined, width, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: d('space/xs'), borderRadius: '999px', flexShrink: 0 };
  if (kind === 'prominent') st.background = destructive ? c('status/danger') : c('accent/primary');
  else if (kind === 'bordered') Object.assign(st, capsuleFx());
  if (['prominent', 'bordered'].includes(kind)) st.padding = `0 ${PADX[size]}px`;
  else st.padding = `0 ${d('space/xs')}`;
  if (disabled) st.opacity = op('disabled');
  const iconSize = size === 'small' ? 12 : 14;
  return row({ name: `Button / ${label}`.slice(0, 50), style: st },
    sym ? icon(sym, { size: iconSize, color: fg }) : null,
    text(label, { name: 'Label', font: f, color: fg, style: kind === 'link' ? { textDecoration: 'none' } : undefined }));
}

export function segmented(items, selectedIndex = 0, { width } = {}) {
  const labels = items.map((i) => (typeof i === 'string' ? i : i.label || ''));
  const segW = Math.max(28, Math.round(Math.max(...labels.map((l) => l.length * 6.6)) + 24));
  return row({ name: 'Segmented Control', pad: 2, gap: 0, bg: canvas('control/segmented-track'), radius: 999, noshrink: true, w: width, style: { height: d('size/control/height'), alignItems: 'stretch' } },
    items.map((it, i) => {
      const o = typeof it === 'string' ? { label: it } : it;
      const sel = i === selectedIndex;
      return row({ name: `Segment / ${o.label || o.icon}`.slice(0, 50), justify: 'center', align: 'center', gap: d('space/xs'), radius: 999, w: width ? undefined : segW, grow: !!width,
        style: { background: sel ? canvas('control/segmented-thumb') : undefined, boxShadow: sel ? canvas('shadow/button') : undefined, flexShrink: 0 } },
      o.icon ? icon(o.icon, { size: 14, color: 'text/primary' }) : null,
      o.label ? text(o.label, { name: 'Label', font: font('body'), color: 'text/primary' }) : null);
    }));
}

export function popUpButton(label, { width } = {}) {
  return row({ name: `Pop-up Button / ${label}`.slice(0, 50), align: 'center', gap: d('space/sm'), w: width, justify: width ? 'space-between' : undefined, noshrink: true,
    style: { height: d('size/control/height'), padding: `0 ${d('space/sm')} 0 ${d('space/md')}`, borderRadius: '999px', ...capsuleFx() } },
  text(label, { name: 'Label', font: font('body'), color: 'text/primary' }),
  icon('chevron.up.chevron.down', { size: 10, color: 'text/secondary', weight: 'semibold' }));
}

export function pullDown(label, sym, { width } = {}) {
  return row({ name: `Pull-down Button / ${label}`.slice(0, 50), align: 'center', gap: d('space/xs'), w: width, noshrink: true,
    style: { height: d('size/control/height'), padding: `0 ${d('space/md')}`, borderRadius: '999px', ...capsuleFx() } },
  sym ? icon(sym, { size: 14, color: 'text/primary' }) : null,
  label ? text(label, { name: 'Label', font: font('body'), color: 'text/primary' }) : null,
  icon('chevron.down', { size: 9, color: 'text/secondary', weight: 'bold' }));
}

export function textField({ value, placeholder, width, height, secure = false } = {}) {
  const shown = value ? (secure ? '•'.repeat(value.length) : value) : placeholder || '';
  return row({ name: 'Text Field', align: 'center', w: width, noshrink: true,
    style: { height: height || d('size/control/height'), padding: `0 ${d('space/sm')}`, borderRadius: d('radius/control'), background: canvas('control/field'), border: `1px solid ${canvas('control/field-stroke')}` } },
  text(shown, { name: value ? 'Value' : 'Placeholder', font: font('body'), color: value ? 'text/primary' : 'text/tertiary' }));
}

export function searchField({ value, placeholder = 'Search', width = 220 } = {}) {
  return row({ name: 'Search Field', align: 'center', gap: d('space/xs'), w: width, noshrink: true,
    style: { height: d('size/control/height'), padding: `0 ${d('space/md')}`, borderRadius: '999px', background: canvas('control/field'), border: `1px solid ${canvas('control/field-stroke')}` } },
  icon('magnifyingglass', { size: 13, color: 'text/secondary' }),
  text(value || placeholder, { name: value ? 'Value' : 'Placeholder', font: font('body'), color: value ? 'text/primary' : 'text/tertiary' }));
}

function steps(name = 'Stepper Glyph') {
  return col({ name, align: 'center', justify: 'center', noshrink: true, style: { width: 19, height: d('size/control/height'), borderRadius: '999px', ...capsuleFx() } },
    icon('chevron.up.chevron.down', { size: 10, color: 'text/primary', weight: 'semibold' }));
}
export function stepper(value, { width } = {}) {
  return row({ name: 'Stepper', align: 'center', gap: d('space/sm'), noshrink: true },
    value !== undefined ? textField({ value: String(value), width: width || 56 }) : null, steps());
}

export function checkbox(label, checked = false) {
  const box = row({ name: 'Box', align: 'center', justify: 'center', noshrink: true,
    style: { width: 16, height: 16, borderRadius: 4, background: checked ? c('accent/primary') : canvas('control/checkbox'), border: checked ? 'none' : `1px solid ${canvas('control/checkbox-stroke')}` } },
  checked ? icon('checkmark', { size: 10, color: 'accent/onAccent', weight: 'bold' }) : null);
  return row({ name: `Checkbox / ${label}`.slice(0, 50), align: 'center', gap: d('space/sm'), noshrink: true }, box, text(label, { name: 'Label', font: font('body'), color: 'text/primary' }));
}

export function datePicker(value, { width } = {}) {
  return row({ name: 'Date Picker', align: 'center', gap: d('space/sm'), noshrink: true },
    row({ name: 'Date Field', align: 'center', w: width, style: { height: d('size/control/height'), padding: `0 ${d('space/md')}`, borderRadius: d('radius/control'), background: canvas('control/field'), border: `1px solid ${canvas('control/field-stroke')}` } },
      text(value, { name: 'Value', font: font('body'), color: 'text/primary' })),
    steps());
}

export function spinner(size = 16) {
  const r1 = size * 0.28, r2 = size * 0.46, ctr = size / 2;
  let ticks = '';
  for (let i = 0; i < 12; i++) {
    const a = (i / 12) * Math.PI * 2;
    const x1 = ctr + Math.sin(a) * r1, y1 = ctr - Math.cos(a) * r1, x2 = ctr + Math.sin(a) * r2, y2 = ctr - Math.cos(a) * r2;
    ticks += `<line x1="${x1.toFixed(2)}" y1="${y1.toFixed(2)}" x2="${x2.toFixed(2)}" y2="${y2.toFixed(2)}" stroke-opacity="${(0.15 + 0.85 * (i / 11)).toFixed(2)}" stroke-width="${Math.max(1, size * 0.1).toFixed(2)}" stroke-linecap="round"/>`;
  }
  return svgEl('Spinner', { width: size, height: size, style: { stroke: c('text/secondary') } }, raw(ticks));
}

export function divider({ vertical = false, name = 'Divider' } = {}) {
  return el('div', { name, style: vertical ? { width: d('stroke/hairline'), alignSelf: 'stretch', background: c('separator/default'), flexShrink: 0 } : { height: d('stroke/hairline'), alignSelf: 'stretch', background: c('separator/default'), flexShrink: 0 } });
}

export function formGroup({ header, rows = [], footer, width } = {}) {
  const body = col({ name: 'Group', bg: canvas('control/group'), radius: 10, clip: true, style: { border: `1px solid ${canvas('specimen/border')}` } },
    rows.flatMap((r, i) => [
      i ? divider({ name: 'Row Divider' }) : null,
      row({ name: `Row / ${r.label}`.slice(0, 50), align: 'center', justify: 'space-between', gap: d('space/lg'), style: { minHeight: 36, padding: `${d('space/xs')} ${d('space/md')}` } },
        col({ name: 'Label Block', noshrink: true }, text(r.label, { name: 'Label', font: font('body'), color: 'text/primary' }), r.help ? text(r.help, { name: 'Help', font: font('caption'), color: 'text/secondary' }) : null),
        r.control || null),
    ]));
  return col({ name: header ? `Form Group / ${header}`.slice(0, 50) : 'Form Group', gap: d('space/xs'), w: width },
    header ? text(header, { name: 'Header', font: font('subheadline'), color: 'text/secondary', style: { padding: `0 ${d('space/md')}` } }) : null,
    body,
    footer ? text(footer, { name: 'Footer', font: font('caption'), color: 'text/secondary', wrap: true, style: { padding: `0 ${d('space/md')}` } }) : null);
}

export function listRow({ selected = false, children = [], name = 'List Row', pad } = {}) {
  return row({ name, align: 'center', gap: d('space/sm'), radius: d('radius/control'), bg: selected ? canvas('selection/tint') : undefined,
    style: { padding: pad ?? `${d('space/xs')} ${d('space/md')}`, minHeight: 28 } }, children);
}

export function listSection({ header, count, rows = [] } = {}) {
  return col({ name: header ? `List Section / ${header}`.slice(0, 50) : 'List Section', gap: d('space/xxs') },
    header ? row({ name: 'Section Header', align: 'center', justify: 'space-between', style: { padding: `${d('space/xs')} ${d('space/md')}` } },
      text(header, { name: 'Header', font: font('subheadline', { weight: 'semibold' }), color: 'text/secondary' }),
      count !== undefined ? text(String(count), { name: 'Count', font: font('subheadline'), color: 'text/secondary' }) : null) : null,
    rows);
}

export function contentUnavailable({ symbol, title, description, buttons = [] } = {}) {
  return col({ name: 'Content Unavailable', align: 'center', gap: d('space/sm'), style: { maxWidth: 360 } },
    symbol ? icon(symbol, { size: 44, color: 'text/tertiary' }) : null,
    text(title, { name: 'Title', font: font('title/section'), color: 'text/primary', align: 'center' }),
    description ? text(description, { name: 'Description', font: font('body'), color: 'text/secondary', wrap: true, align: 'center' }) : null,
    buttons.length ? row({ name: 'Actions', gap: d('space/sm'), pad: [d('space/sm'), 0, 0, 0] }, buttons) : null);
}

export function tooltip(label) {
  return el('div', { name: `Tooltip / ${label}`.slice(0, 50), style: { display: 'flex', padding: `3px ${d('space/sm')}`, borderRadius: 5, background: canvas('menu/background'), backdropFilter: 'blur(30px) saturate(1.6)', border: `1px solid ${canvas('menu/stroke')}`, boxShadow: canvas('shadow/menu'), flexShrink: 0, alignSelf: 'flex-start' } },
    text(label, { name: 'Label', font: font('callout'), color: 'text/primary' }));
}
