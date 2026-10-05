// DayWindowsSection, WindowRow, ReasonsGrid, SignedBar, ExplainBlock (App/Sources/Spot/DayWindowsView.swift).
import { col, row, text, el, spacer } from '../../../tools/lib/h.mjs';
import { c, d, dv, font } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { divider, button, spinner } from '../../../tools/lib/controls.mjs';
import { lightBadge, confidenceMark, sampleDataLabel } from '../../../tools/lib/lightindex.mjs';
import { FACTOR_TITLE, factorValue, sentence, signed, CONFIDENCE_NAME, CONFIDENCE_EXPLAINED, leadNote, rangeText, NO_FORECAST_LONG } from './spot-model.mjs';

export const artboards = [];

/** SignedBar: centre line, bar right = helps, left = hurts; the sign is printed too. Source colour: text/secondary for every effect. */
export function signedBar(points, scale) {
  const half = dv('size/lightRing/large') / 2 + dv('space/xs'); // 36
  const len = half * Math.min(1, Math.abs(points) / scale);
  const barW = points === 0 ? 0 : Math.max(len, dv('stroke/thick'));
  const track = half * 2;
  const centre = track / 2;
  const left = points >= 0 ? centre : centre - barW;
  return row({ name: `SignedBar / ${signed(points)}`, align: 'center', gap: d('space/xs'), noshrink: true },
    el('div', { name: 'Track', style: { position: 'relative', width: track, height: d('size/icon/small'), flexShrink: 0 } },
      el('div', { name: 'Centre Line', style: { position: 'absolute', left: centre - dv('stroke/thin') / 2, top: 0, width: d('stroke/thin'), height: '100%', background: c('separator/default') } }),
      barW ? el('div', { name: 'Bar', style: { position: 'absolute', left, top: (dv('size/icon/small') - dv('space/sm')) / 2, width: barW, height: d('space/sm'), borderRadius: d('stroke/thin'), background: c('text/secondary') } }) : null),
    text(signed(points), { name: 'Points', font: font('timeSmall'), color: 'text/secondary', w: dv('size/badge/minWidth'), style: { flexShrink: 0 } }));
}

/** ExplainBlock states: idle | loading | done | failed | unavailable (nothing). */
export function explainBlock(state = 'idle', { failure = "Apple Intelligence isn't available right now.", textBody } = {}) {
  const btn = (label) => button(label, { size: 'small', icon: 'apple.intelligence' });
  if (state === 'unavailable') return null;
  if (state === 'idle') return col({ name: 'ExplainBlock / Idle', gap: d('space/sm'), align: 'flex-start' }, btn('Explain'));
  if (state === 'loading') return col({ name: 'ExplainBlock / Loading', gap: d('space/sm') }, row({ name: 'Writing', align: 'center', gap: d('space/sm') }, spinner(14), text('Writing an explanation…', { name: 'Writing', font: font('callout'), color: 'text/secondary' }), button('Cancel', { size: 'small' })));
  if (state === 'done') return col({ name: 'ExplainBlock / Done', gap: d('space/sm'), align: 'flex-start' },
    text(textBody, { name: 'Explanation', font: font('callout'), color: 'text/primary', wrap: true }),
    row({ name: 'Attribution', align: 'center', gap: d('space/sm') },
      row({ name: 'Written by', align: 'center', gap: d('space/xs') }, icon('apple.intelligence', { size: 11, color: 'text/secondary' }), text('Written by Apple Intelligence from the factors listed above.', { name: 'Attribution', font: font('caption'), color: 'text/secondary' })),
      btn('Explain again')));
  return col({ name: 'ExplainBlock / Failed', gap: d('space/sm'), align: 'flex-start' }, text(failure, { name: 'Failure', font: font('callout'), color: 'text/secondary', wrap: true }), btn('Explain'));
}

const COLS = { name: 128, value: 44 };
/** ReasonsGrid for a scored window (w) or the no-forecast sentence. */
export function reasonsGrid(w, { sample = true, explain = 'idle', explainText, failure } = {}) {
  if (!w.scored) {
    return col({ name: 'ReasonsGrid / No forecast', gap: d('space/sm'), align: 'flex-start' },
      text(NO_FORECAST_LONG[w.reason], { name: 'Reason', font: font('callout'), color: 'text/secondary', wrap: true }),
      w.reason === 'serviceFailed' ? button('Retry', { size: 'small', icon: 'arrow.clockwise' }) : null);
  }
  const scale = Math.max(10, ...w.contributors.map((x) => Math.abs(x.points)));
  const range = rangeText(w);
  return col({ name: 'ReasonsGrid', gap: d('space/sm'), align: 'flex-start' },
    text('Why this score', { name: 'Title', font: font('captionStrong'), color: 'text/secondary' }),
    col({ name: 'Factors', gap: d('space/sm') }, w.contributors.map((x) =>
      row({ name: `Factor / ${FACTOR_TITLE[x.factor]}`, align: 'baseline', gap: d('space/md') },
        text(FACTOR_TITLE[x.factor], { name: 'Factor Name', font: font('bodyEmphasis'), color: 'text/primary', w: COLS.name, style: { flexShrink: 0 } }),
        text(factorValue(x), { name: 'Value', font: font('time'), color: 'text/secondary', align: 'right', w: COLS.value, style: { flexShrink: 0 } }),
        row({ name: 'Bar Slot', align: 'center', style: { alignSelf: 'center', flexShrink: 0 } }, signedBar(x.points, scale)),
        text(sentence(x, w.kind), { name: 'Sentence', font: font('callout'), color: 'text/primary', wrap: true })))),
    col({ name: 'Confidence', gap: d('space/xs') },
      row({ name: 'Confidence Line', align: 'center', gap: d('space/sm') },
        confidenceMark(w.confidence),
        text(CONFIDENCE_NAME[w.confidence], { name: 'Confidence', font: font('subheadline'), color: 'text/primary' }),
        range ? [text('·', { name: 'Dot', font: font('subheadline'), color: 'text/secondary' }), text(`Likely ${range}`, { name: 'Range', font: font('subheadline'), color: 'text/primary' })] : null,
        text('·', { name: 'Dot', font: font('subheadline'), color: 'text/secondary' }),
        text(`Updated ${w.fetchedAt}`, { name: 'Updated', font: font('subheadline'), color: 'text/secondary' }),
        sample ? sampleDataLabel({ style: 'inline' }) : null),
      text(`${CONFIDENCE_EXPLAINED[w.confidence]} ${leadNote(w.leadHours)}`, { name: 'Footnote', font: font('footnote'), color: 'text/secondary', wrap: true })),
    explainBlock(explain, { textBody: explainText, failure }));
}

/** WindowRow: collapsed or expanded; selected rows are filled with selection/fill. */
export function windowRow(w, { selected = false, expanded = false, sample = true, explain = 'idle', explainText, failure, last } = {}) {
  const badge = lightBadge({ style: 'regular', window: w.kind, score: w.scored ? w.score : undefined, band: w.band, confidence: w.confidence, reason: w.reason, sample: false });
  return col({ name: `WindowRow / ${w.kind}`, style: { background: selected ? c('selection/fill') : undefined } },
    row({ name: 'Row', align: 'center', gap: d('space/sm'), style: { padding: `${d('space/sm')} ${d('space/md')}` } },
      el('div', { name: 'Chevron Slot', style: { width: d('size/icon/small'), display: 'flex', justifyContent: 'center', flexShrink: 0 } }, icon(expanded ? 'chevron.down' : 'chevron.right', { size: 10, color: 'text/secondary', weight: 'semibold' })),
      badge, spacer(),
      text(`${w.start}–${w.end}`, { name: 'Time Range', font: font('time'), color: 'text/primary' })),
    expanded ? el('div', { name: 'Reasons Indent', style: { display: 'flex', flexDirection: 'column', padding: `0 ${d('space/md')} ${d('space/md')} calc(${d('space/md')} + ${d('size/icon/small')} + ${d('space/sm')})` } }, reasonsGrid(w, { sample, explain, explainText, failure })) : null);
}

/** DayWindowsSection. opts.expanded: kinds; opts.explain/explainText for the selected expanded row. */
export function dayWindowsSection(m, { width, expanded = m.expanded, explain, explainText, failure } = {}) {
  const dayLabel = m.day.rel === m.day.long ? m.day.long : `${m.day.rel} · ${m.day.long}`;
  const rows = m.windows;
  const polarSentence = m.todayKind === 'polarDay' ? "The sun doesn't set here on this day. No blue hour, but a long golden window while the sun is low." : null;
  return col({ name: 'DayWindowsSection', gap: d('space/md'), w: width },
    row({ name: 'Title Row', align: 'baseline', gap: d('space/sm') },
      text('Light windows', { name: 'Section Title', font: font('title/section'), color: 'text/primary' }),
      text(dayLabel, { name: 'Day Label', font: font('subheadline'), color: 'text/secondary' }),
      spacer(), m.day.isToday ? null : button('Today', { size: 'small' })),
    rows.length === 0
      ? row({ name: 'No Windows', align: 'center', gap: d('space/xs') }, icon(polarSentence ? 'sun.max' : 'moon.stars', { size: 14, color: 'text/secondary' }), text(polarSentence || 'No golden hour, blue hour or night window today.', { name: 'Sentence', font: font('callout'), color: 'text/secondary' }))
      : col({ name: 'Windows Card', bg: 'background/control', radius: d('radius/card'), clip: true, style: { border: `${d('stroke/hairline')} solid ${c('separator/default')}` } },
        rows.flatMap((w, i) => [i ? divider({ name: 'Row Divider' }) : null,
          windowRow(w, { selected: m.selected === w.kind, expanded: expanded.includes(w.kind), sample: m.sample, explain: m.selected === w.kind ? explain : 'idle', explainText, failure })])));
}
