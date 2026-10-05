// SpotCard, SpotHeader, WhenToGoSection, SunTimesLine, OutlookStrip (App/Sources/Spot/SpotLayout.swift, SpotHeaderView.swift, WhenToGoView.swift).
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, dv, font, op, canvas } from '../../../tools/lib/tokens.mjs';
import { icon } from '../../../tools/lib/icons.mjs';
import { divider, button, segmented, spinner } from '../../../tools/lib/controls.mjs';
import { lightBadge, provenanceTag, scoreChip, noForecastRing, bandFor } from '../../../tools/lib/lightindex.mjs';
export const artboards = [];
import { INTENTS, outlookCaption, outlookFade, NO_FORECAST_LONG, sentence, rangeText } from './spot-model.mjs';

/** SpotCard: the card surface (padding md, background/control, radius card, hairline). */
export function spotCard(children, { name = 'SpotCard', gap, width } = {}) {
  return col({ name, gap, pad: `calc(${d('space/md')} - ${d('stroke/hairline')})`, w: width, bg: 'background/control', radius: d('radius/card'),
    style: { border: `${d('stroke/hairline')} solid ${c('separator/default')}`, alignSelf: 'stretch' } }, children);
}

// ---- SpotHeader -----------------------------------------------------------------------------------------------
function actionButton(label, sym, o = {}) {
  const prominent = o.kind === 'prominent';
  const fg = prominent ? 'accent/onAccent' : o.destructive ? 'status/danger' : 'text/primary';
  const st = { height: d('size/control/height'), padding: `0 ${o.iconOnly ? 10 : 14}px`, borderRadius: '999px', flexShrink: 0, justifyContent: 'center' };
  if (prominent) st.background = c('accent/primary');
  else Object.assign(st, { background: canvas('control/button'), border: `1px solid ${canvas('control/button-stroke')}`, boxShadow: canvas('shadow/button') });
  return row({ name: `Button / ${label}`.slice(0, 50), align: 'center', gap: d('space/xs'), style: st },
    icon(sym, { size: 14, color: fg }),
    o.iconOnly ? null : text(label, { name: 'Label', font: font('body'), color: fg }),
    o.menu ? icon('chevron.down', { size: 9, color: fg, weight: 'bold' }) : null);
}

export function spotHeader(m, { iconOnly = false, width } = {}) {
  const s = m.spot;
  const actions = [
    actionButton('Add to Trip', 'plus.circle', { kind: 'prominent', menu: true, iconOnly }),
    !s.isUser ? actionButton(s.saved ? 'Saved' : 'Save', s.saved ? 'bookmark.fill' : 'bookmark', { iconOnly }) : null,
    actionButton('Open in Maps', 'map', { iconOnly }),
    actionButton('Share', 'square.and.arrow.up', { iconOnly }),
    s.isUser ? [divider({ vertical: true, name: 'Divider' }), actionButton('Edit', 'pencil', { iconOnly }), actionButton('Delete', 'trash', { iconOnly, destructive: true })] : null,
  ];
  return col({ name: 'SpotHeader', gap: d('space/md'), w: width },
    col({ name: 'Name and Place', gap: d('space/xs') },
      text(s.name, { name: 'Spot Name', font: font('title/spot'), color: 'text/primary' }),
      row({ name: 'Place Line', align: 'center', gap: d('space/sm') },
        s.locality ? text(s.locality, { name: 'Locality', font: font('subheadline'), color: 'text/secondary' }) : null,
        provenanceTag(s.origin),
        row({ name: 'Category', align: 'center', gap: d('space/xs') },
          icon(s.categorySymbol, { size: 12, color: 'text/secondary' }),
          text(s.category, { name: 'Category Name', font: font('subheadline'), color: 'text/secondary' })))),
    row({ name: 'Actions', align: 'center', gap: d('space/sm'), style: { height: dv('size/control/height') } }, actions));
}

// ---- SunTimesLine ---------------------------------------------------------------------------------------------
export function sunTimesLine(m) {
  if (m.todayKind === 'polarNight') return row({ name: 'SunTimesLine / Polar night', align: 'center', gap: d('space/xs') }, icon('moon.stars', { size: 14, color: 'text/secondary' }), text("The sun doesn't rise here on this day. The light is the blue hour either side of noon.", { name: 'Polar Sentence', font: font('callout'), color: 'text/secondary' }));
  if (m.todayKind === 'polarDay') return row({ name: 'SunTimesLine / Polar day', align: 'center', gap: d('space/xs') }, icon('sun.max', { size: 14, color: 'text/secondary' }), text("The sun doesn't set here on this day. No blue hour, but a long golden window while the sun is low.", { name: 'Polar Sentence', font: font('callout'), color: 'text/secondary' }));
  const item = (sym, label) => row({ name: `Sun Time / ${sym}`, align: 'center', gap: d('space/xs') }, icon(sym, { size: 14, color: 'text/primary' }), text(label, { name: 'Label', font: font('callout'), color: 'text/primary', style: { fontVariantNumeric: 'tabular-nums' } }));
  return row({ name: 'SunTimesLine', align: 'center', gap: d('space/lg') },
    m.nextSunrise ? item('sunrise', `Next sunrise ${m.nextSunrise}`) : null,
    m.nextSunset ? item('sunset', `Next sunset ${m.nextSunset}`) : null);
}

// ---- WhenToGo lead --------------------------------------------------------------------------------------------
export function bestLead(m) {
  const b = m.best, w = b.window;
  const rel = m.rel(...b.day.split('-').map(Number));
  return row({ name: 'Lead / Best window', align: 'flex-start', gap: d('space/lg') },
    lightBadge({ style: 'large', window: w.kind, score: w.score, band: w.band, confidence: w.confidence, range: rangeText(w) ? rangeText(w) : undefined, sample: false }),
    col({ name: 'Lead Text', gap: d('space/xs'), grow: true, align: 'flex-start' },
      text(`Best ${m.intentLabel.toLowerCase()} in the next 10 days`, { name: 'Caption', font: font('caption'), color: 'text/secondary' }),
      text(`${rel} · ${w.start}–${w.end}`, { name: 'Best Day and Time', font: font('headline'), color: 'text/primary', style: { fontVariantNumeric: 'tabular-nums' } }),
      text(sentence(w.contributors[0], w.kind), { name: 'Top Factor', font: font('callout'), color: 'text/primary', wrap: true }),
      text(`Updated ${w.fetchedAt}`, { name: 'Updated', font: font('footnote'), color: 'text/secondary' }),
      (b.day !== `${m.day.y}-${m.day.m}-${m.day.d}` || w.kind !== m.selected) ? button('Show this day', { size: 'small' }) : null));
}
export function noScoreLead(m, { reason } = {}) {
  const rsn = reason ?? m.unavailableReason;
  return col({ name: 'Lead / No score', gap: d('space/sm') },
    row({ name: 'No Score', align: 'flex-start', gap: d('space/md') },
      noForecastRing(dv('size/lightRing/large')),
      col({ name: 'No Score Text', gap: d('space/xs'), grow: true, align: 'flex-start' },
        text(`No scored ${m.intentLabel.toLowerCase()} window in the next 10 days.`, { name: 'Headline', font: font('headline'), color: 'text/primary', wrap: true }),
        rsn ? text(NO_FORECAST_LONG[rsn], { name: 'Reason', font: font('callout'), color: 'text/secondary', wrap: true }) : null,
        rsn === 'serviceFailed' ? button('Retry', { size: 'small', icon: 'arrow.clockwise' }) : null)),
    divider(), sunTimesLine(m));
}
export function loadingLead(m) {
  return col({ name: 'Lead / Loading', gap: d('space/sm') },
    row({ name: 'Checking', align: 'center', gap: d('space/sm') }, spinner(14), text('Checking the forecast…', { name: 'Checking', font: font('callout'), color: 'text/secondary' })),
    sunTimesLine(m));
}
export function lead(m) {
  if (m.best) return bestLead(m);
  if (m.loading) return loadingLead(m);
  return noScoreLead(m);
}

// ---- OutlookStrip ---------------------------------------------------------------------------------------------
export function outlookCell(o, { width } = {}) {
  const h = o.headline;
  const fade = outlookFade(o);
  const chip = h && h.scored ? scoreChip({ score: h.score, band: h.band || bandFor(h.score), size: 'regular' }) : noForecastRing(dv('size/badge/height'));
  const nm = `Outlook Cell / ${o.wd} ${o.dn}`;
  return col({ name: nm, align: 'center', gap: d('space/xxs'), w: width, grow: width ? false : true, noshrink: !!width,
    style: { padding: `${d('space/xs')} 0`, borderRadius: d('radius/control'), background: o.selected ? c('selection/fill') : undefined, border: `${d('stroke/regular')} solid ${o.selected ? c('accent/primary') : 'transparent'}`,
      opacity: fade === 'low' ? op('outlook-fade-low') : fade === 'medium' ? op('outlook-fade-medium') : undefined } },
  row({ name: 'Best Tab Slot', align: 'center', justify: 'center', style: { padding: `0 ${d('space/xs')}`, borderRadius: '999px', background: o.isBest ? c('accent/emphasis') : undefined } },
    text(o.isBest ? 'Best' : ' ', { name: 'Best Tab', font: font('captionStrong'), color: 'accent/onAccent' })),
  text(o.wd, { name: 'Weekday', font: font('caption'), color: 'text/secondary' }),
  text(o.dn, { name: 'Day Number', font: font('bodyEmphasis'), color: 'text/primary' }),
  chip,
  el('div', { name: 'Caption Slot', style: { minHeight: d('space/xl'), display: 'flex', justifyContent: 'center', alignItems: 'flex-start' } },
    text(outlookCaption(o), { name: 'Range or Reason', font: font('caption'), color: 'text/secondary', align: 'center', wrap: true, style: { whiteSpace: 'pre-wrap' } })));
}
export function outlookStrip(m, { width } = {}) {
  return col({ name: 'OutlookStrip', gap: d('space/sm'), w: width },
    text(`10-day outlook for ${m.intentLabel}`, { name: 'Outlook Title', font: font('subheadline'), color: 'text/secondary' }),
    row({ name: 'Outlook Cells', align: 'flex-start', gap: d('space/xs') }, m.outlook.map((o) => outlookCell(o))),
    text('Fainter days are less certain. A dashed ring means no forecast.', { name: 'Outlook Key', font: font('caption'), color: 'text/tertiary' }));
}

export function whenToGoSection(m, { width } = {}) {
  const idx = INTENTS.findIndex(([k]) => k === m.intent);
  return col({ name: 'WhenToGoSection', gap: d('space/md'), w: width },
    row({ name: 'Title Row', align: 'baseline', justify: 'space-between' },
      text('When to go', { name: 'Section Title', font: font('title/section'), color: 'text/primary' }),
      segmented(INTENTS.map(([, label]) => label), idx)),
    spotCard(lead(m), { name: 'SpotCard / Lead' }),
    outlookStrip(m));
}
