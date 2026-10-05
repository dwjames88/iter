// SpotFactsRow, LookAroundSection (App/Sources/Spot/SpotFactsView.swift) and the whole spot page column.
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, dv, font, canvas } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { spotCard, spotHeader, whenToGoSection } from './spot-lead.mjs';
import { dayWindowsSection } from './spot-windows.mjs';
import { lightTimeline, skyArc, hourlyStrip } from './spot-charts.mjs';
import { elevationText, BEST_AT } from './spot-model.mjs';
import { degrees } from './spot-model.mjs';

export const artboards = [];

export function spotFactsRow(m, { width } = {}) {
  const s = m.spot;
  const inner = (width ?? 892) - 2 * dv('space/md') - 2;
  const perRow = Math.max(1, Math.floor((inner + dv('space/sm')) / (150 + dv('space/sm'))));
  const itemW = Math.floor((inner - (perRow - 1) * dv('space/sm')) / perRow);
  const fact = (sym, label, known = true) => row({ name: `Fact / ${label}`.slice(0, 50), align: 'flex-start', gap: d('space/xs'), w: itemW, noshrink: true },
    el('div', { name: 'Icon Slot', style: { width: 16, height: 15, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 } }, icon(sym, { size: 14, color: 'text/secondary' })),
    text(label, { name: 'Fact Text', font: font('callout'), color: known ? 'text/primary' : 'text/secondary', wrap: true, grow: true }));
  const facts = [
    fact('figure.walk', s.walk != null ? `${s.walk} min walk-in` : 'Walk-in unknown', s.walk != null),
    s.elevM != null ? fact('mountain.2', elevationText(m)) : null,
    fact('safari', s.facing != null ? `Faces ${degrees(s.facing)}` : 'Facing unknown', s.facing != null),
    BEST_AT(m) ? fact('sun.horizon', BEST_AT(m)) : null,
    s.zoneNote ? fact('clock', s.zoneNote) : null,
  ];
  return col({ name: 'SpotFactsRow', gap: d('space/md'), w: width },
    text('Good to know', { name: 'Section Title', font: font('title/section'), color: 'text/primary' }),
    spotCard(col({ name: 'Facts Body', gap: d('space/md') },
      row({ name: 'Facts Grid', wrap: true, gap: d('space/sm'), align: 'flex-start' }, facts),
      s.blurb ? text(s.blurb, { name: 'Blurb', font: font('body'), color: 'text/primary', wrap: true }) : null,
      s.notes ? col({ name: 'Notes', gap: d('space/xs') }, text('Notes', { name: 'Notes Title', font: font('captionStrong'), color: 'text/secondary' }), text(s.notes, { name: 'Notes Text', font: font('callout'), color: 'text/primary', wrap: true })) : null), { name: 'SpotCard / Facts' }));
}
const f1 = (n) => Math.round(n * 10) / 10;

/** Look Around: only live, only when Apple has imagery. The preview is a system view, drawn as a placeholder. */
export function lookAroundSection({ width } = {}) {
  return col({ name: 'LookAroundSection', gap: d('space/md'), w: width },
    text('Look Around', { name: 'Section Title', font: font('title/section'), color: 'text/primary' }),
    el('div', { name: 'Look Around Preview (swap)', style: { height: dv('chart/arcHeight') + dv('chart/timelineHeight'), borderRadius: d('radius/card'), background: canvas('map/ground'), border: `${d('stroke/hairline')} solid ${c('separator/default')}`, display: 'flex', alignItems: 'flex-end', padding: d('space/sm'), alignSelf: 'stretch' } },
      text('Apple Look Around preview — system view, swap for an image', { name: 'Caption', font: font('caption'), color: canvas('map/label') })));
}

/** The scrolling column of the whole spot page. */
export function spotColumn(m, { width = 940, expanded, explain, explainText, failure, lookAround = false } = {}) {
  const inner = width - 2 * dv('space/xl');
  return col({ name: 'Spot Page Content', w: width, gap: d('space/xl'), pad: d('space/xl'), noshrink: true },
    spotHeader(m, { iconOnly: inner < 560 }),
    whenToGoSection(m),
    dayWindowsSection(m, { expanded, explain, explainText, failure }),
    lightTimeline(m, { width: inner }),
    skyArc(m, { width: inner }),
    hourlyStrip(m, { width: inner }),
    spotFactsRow(m, { width: inner }),
    lookAround ? lookAroundSection({ width: inner }) : null);
}
