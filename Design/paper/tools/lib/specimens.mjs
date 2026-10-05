// specimens.mjs - layout furniture for component/foundation artboards (labelled specimen grids, light + dark blocks).
//   artboardHeader({title, type, file, job, width})   title (component name), "Swift type · file" line, one-line job
//   themeBlocks(fn, {direction:'row'|'column'=row, gap=24, width})   renders fn(theme) once under withTheme('light') and once
//        under withTheme('dark'), each inside a labelled block filled with background/window of that theme.
//        fn returns Html (a section or an array of sections).
//   section(title, ...children, {gap})   labelled group inside a block (children are rows/grids)
//   gridRow(label, cells, {labelWidth=88, gap=24})   row with a row header and specimen cells
//   cell(name, body, {width, caption})   one named specimen frame (optional caption under it)
//   colHeaders(labels, {labelWidth=88, widths, gap=24})  header row for a grid
//   page(children, {pad=32})             artboard body column with the standard padding
import { col, row, text, el } from './h.mjs';
import { c, d, canvas, font, withTheme } from './tokens.mjs';

export function artboardHeader({ title, type, file, job } = {}) {
  return col({ name: 'Artboard Header', gap: d('space/xs') },
    text(title, { name: 'Artboard Title', font: font('title/section', { size: 22, lineHeight: 28, weight: 'semibold' }), color: canvas('label/title') }),
    type ? text(`${type}${file ? ' · ' + file : ''}`, { name: 'Type and File', font: font('callout'), color: canvas('label/body') }) : null,
    job ? text(job, { name: 'Job', font: font('body'), color: canvas('label/title'), wrap: true, style: { maxWidth: 900 } }) : null);
}

export function themeBlocks(fn, { direction = 'row', gap = 24, width } = {}) {
  const block = (theme) => withTheme(theme, () =>
    col({ name: `${theme === 'dark' ? 'Dark' : 'Light'} Appearance`, gap: d('space/xl'), pad: 20, radius: 16, bg: c('background/window'), noshrink: true,
      style: { border: `1px solid ${canvas('specimen/border')}`, width } },
    text(theme === 'dark' ? 'DARK' : 'LIGHT', { name: 'Appearance Label', font: font('captionStrong'), color: 'text/secondary', style: { letterSpacing: '0.08em' } }),
    fn(theme)));
  return row({ name: 'Appearances', gap, align: 'flex-start', style: direction === 'column' ? { flexDirection: 'column' } : {} }, block('light'), block('dark'));
}

export function section(title, ...children) {
  let opts = {};
  const last = children[children.length - 1];
  if (last && last.constructor === Object) opts = children.pop();
  return col({ name: `Section / ${title}`.slice(0, 50), gap: opts.gap ?? d('space/md') },
    text(title, { name: 'Section Title', font: font('headline'), color: 'text/primary' }), children);
}

export function colHeaders(labels, { labelWidth = 88, widths = [], gap = 24 } = {}) {
  return row({ name: 'Column Headers', gap, align: 'flex-end' },
    el('div', { name: 'Corner', style: { width: labelWidth, flexShrink: 0 } }),
    labels.map((l, i) => text(l, { name: `Column / ${l}`.slice(0, 50), font: font('captionStrong'), color: 'text/secondary', w: widths[i], style: { flexShrink: 0 } })));
}

export function cell(name, body, { width, caption } = {}) {
  return col({ name: `Specimen / ${name}`.slice(0, 50), gap: d('space/xs'), align: 'flex-start', style: { width, flexShrink: 0 } }, body,
    caption ? text(caption, { name: 'Caption', font: font('caption'), color: 'text/secondary', wrap: true }) : null);
}

export function gridRow(label, cells, { labelWidth = 88, gap = 24, align = 'center' } = {}) {
  return row({ name: `Row / ${label}`.slice(0, 50), gap, align },
    text(label, { name: 'Row Header', font: font('caption'), color: 'text/secondary', w: labelWidth, style: { flexShrink: 0 } }), cells);
}

export function page(children, { pad = 32, gap = 24 } = {}) {
  return col({ name: 'Page', gap, pad, grow: 'auto', style: { minHeight: 0 } }, children);
}
