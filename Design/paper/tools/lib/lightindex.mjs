// lightindex.mjs - the shared Iter components every screen uses, exact to COMPONENTS.md and
// App/Sources/Components/{LightBadge,SampleDataLabel,WeatherAttributionView,ProvenanceTag}.swift.
//
// Data tables (from App/Sources/Text/LightText.swift and IterCore/Light.swift)
//   WINDOWS      { blueMorning|goldenMorning|goldenEvening|blueEvening|night: {name, short, symbol} }
//   BANDS        { poor|fair|good|great|epic: {name, min} }      bandFor(score) uses the IterCore thresholds (40/58/74/88)
//   CONFIDENCE   { low|medium|high: {name, short, bars} }
//   NO_FORECAST  { weatherServiceNotEnabled|serviceFailed|beyondHorizon|inThePast|notLoaded: {long, short} }, NO_FORECAST_LABEL
//   ORIGINS      ['Curated','Added by you','Apple Maps','Scout']
//
// Components (all return Html; colours/sizes come from tokens; theme from the surrounding withTheme)
//   scoreChip({score, band?, size:'compact'|'regular'|'large'='regular', lowConfidence=false})
//        NOTE: SwiftUI applies .padding(.horizontal, space/xs) OUTSIDE the min-width frame, so a regular chip is
//        28 + 2x4 = 36 wide minimum, a compact one 18 + 8 = 26 (COMPONENTS.md says 28 / 18). Source is followed.
//   noForecastRing(diameter)                     dashed 4/3 ring, 1.5 stroke, status/noForecast
//   confidenceMark('low'|'medium'|'high')        three ascending bars
//   lightBadge({style, window, score, band, confidence='high', range, reason, sample=false})
//        window: kind key above. Scored when `score` is a number; otherwise no forecast with `reason` key.
//        range: '72–100' (large only). sample: show the inline Sample data label (the `showsSource` option).
//   sampleDataLabel({style:'inline'|'banner'='inline'})
//   weatherAttribution({sample=false})           Apple Weather mark stand-in (named "Apple Weather Mark (swap)"),
//                                                "Legal attribution", "Light Index modified from forecast data"; sample -> inline label
//   provenanceTag(text)                          capsule outline tag
//   warningLine(text, {kind:'warning'|'danger', font:'caption'|'callout'})
import { row, col, text, svgEl, raw, el } from './h.mjs';
import { c, d, dv, font, op } from './tokens.mjs';
import { icon } from './icons.mjs';

export const WINDOWS = {
  blueMorning: { name: 'Morning blue hour', short: 'Blue AM', symbol: 'sun.horizon' },
  goldenMorning: { name: 'Sunrise', short: 'Sunrise', symbol: 'sunrise' },
  goldenEvening: { name: 'Sunset', short: 'Sunset', symbol: 'sunset' },
  blueEvening: { name: 'Evening blue hour', short: 'Blue PM', symbol: 'moon.haze' },
  night: { name: 'Night', short: 'Night', symbol: 'moon.stars' },
};
export const BANDS = {
  poor: { name: 'Poor', min: 0 }, fair: { name: 'Fair', min: 40 }, good: { name: 'Good', min: 58 },
  great: { name: 'Great', min: 74 }, epic: { name: 'Epic', min: 88 },
};
export const BAND_KEYS = Object.keys(BANDS);
export const bandFor = (score) => (score >= 88 ? 'epic' : score >= 74 ? 'great' : score >= 58 ? 'good' : score >= 40 ? 'fair' : 'poor');
export const CONFIDENCE = {
  low: { name: 'Low confidence', short: 'Low', bars: 1 },
  medium: { name: 'Medium confidence', short: 'Medium', bars: 2 },
  high: { name: 'High confidence', short: 'High', bars: 3 },
};
export const NO_FORECAST_LABEL = 'No forecast';
export const NO_FORECAST = {
  weatherServiceNotEnabled: { long: "Weather isn't enabled for this build of Iter, so only sun and moon times are shown.", short: 'Weather off' },
  serviceFailed: { long: "Couldn't reach Apple Weather. Sun and moon times are still exact.", short: 'Offline' },
  beyondHorizon: { long: 'Too far ahead for a forecast. Planned on sun angle and season until about ten days out.', short: 'Too far ahead' },
  inThePast: { long: 'This window has passed.', short: 'Passed' },
  notLoaded: { long: 'Forecast not loaded yet.', short: 'Loading' },
};
export const ORIGINS = ['Curated', 'Added by you', 'Apple Maps', 'Scout'];

const need = (table, key, what) => { if (!table[key]) throw new Error(`${what} "${key}" unknown; use one of ${Object.keys(table).join(', ')}`); return table[key]; };

export function scoreChip({ score, band, size = 'regular', lowConfidence = false } = {}) {
  const b = band || bandFor(score);
  need(BANDS, b, 'band');
  const fnt = { compact: 'score/badge', regular: 'score/medium', large: 'score/large' }[size];
  if (!fnt) throw new Error(`scoreChip size "${size}"`);
  const h = { compact: 'size/badge/heightCompact', regular: 'size/badge/height', large: 'size/lightRing/large' }[size];
  const w = { compact: 'size/badge/heightCompact', regular: 'size/badge/minWidth', large: 'size/lightRing/large' }[size];
  const style = {
    display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
    minWidth: size === 'large' ? d(w) : `${dv(w) + 2 * dv('space/xs')}px`, height: d(h), padding: size === 'large' ? '0' : `0 ${d('space/xs')}`,
    background: c(`light/ramp/${b}`), color: c(`light/rampText/${b}`),
    borderRadius: size === 'large' ? d('radius/card') : d('radius/badge'),
    border: `${d('stroke/hairline')} solid ${c('separator/default')}`,
    opacity: lowConfidence ? op('low-confidence') : undefined,
  };
  return el('div', { name: `ScoreChip / ${size} / ${BANDS[b].name}`.slice(0, 50), style }, text(String(score), { name: 'Score', font: font(fnt) }));
}

export function noForecastRing(diameter) {
  const sw = dv('stroke/regular');
  const r = (diameter - sw) / 2;
  return svgEl(`NoForecastRing / ${diameter}`, { width: diameter, height: diameter },
    raw(`<circle cx="${diameter / 2}" cy="${diameter / 2}" r="${r}" fill="none" style="stroke:${c('status/noForecast')};stroke-width:${d('stroke/regular')};stroke-dasharray:${d('stroke/dashLength')} ${d('stroke/dashGap')}"/>`));
}

export function confidenceMark(level) {
  const n = need(CONFIDENCE, level, 'confidence').bars;
  const H = dv('size/confidenceMark');
  return row({ name: `ConfidenceMark / ${CONFIDENCE[level].short}`, align: 'flex-end', gap: d('stroke/thin'), noshrink: true, style: { height: d('size/confidenceMark') } },
    [0, 1, 2].map((i) => el('div', { name: `Bar ${i + 1}`, style: { width: d('stroke/thick'), height: `${(H * (i + 1)) / 3}px`, borderRadius: d('stroke/thin'), background: i < n ? c('text/secondary') : c('separator/default'), flexShrink: 0 } })));
}

export function sampleDataLabel({ style = 'inline' } = {}) {
  if (style === 'inline') {
    return row({ name: 'SampleDataLabel / inline', align: 'center', gap: d('space/xs'), noshrink: true },
      icon('flask', { size: 11, color: 'status/warning' }),
      text('Sample data', { name: 'Label', font: font('captionStrong'), color: 'status/warning' }));
  }
  return row({ name: 'SampleDataLabel / banner', align: 'center', gap: d('space/sm'), bg: c('background/control'),
    style: { padding: d('space/sm'), borderRadius: d('radius/control'), border: `${d('stroke/thin')} solid ${c('status/warning')}`, alignSelf: 'stretch' } },
  icon('flask', { size: 16, color: 'status/warning' }),
  col({ name: 'Text', grow: true },
    text('Sample data', { name: 'Title', font: font('captionStrong'), color: 'text/primary' }),
    text('Scores use made-up weather. Turn off in the Debug menu.', { name: 'Body', font: font('caption'), color: 'text/secondary', wrap: true })));
}

export function weatherAttribution({ sample = false } = {}) {
  if (sample) return sampleDataLabel({ style: 'inline' });
  return row({ name: 'WeatherAttributionView', align: 'center', gap: d('space/sm'), noshrink: true },
    row({ name: 'Apple Weather Mark (swap)', align: 'center', gap: 2, style: { height: d('size/icon/small') } },
      text('', { name: 'Apple Glyph', font: font('footnote', { size: 12, lineHeight: 14 }), color: 'text/primary' }),
      text('Weather', { name: 'Weather Word', font: font('footnote', { size: 12, weight: 'semibold', lineHeight: 14 }), color: 'text/primary' })),
    text('Legal attribution', { name: 'Legal Attribution Link', font: font('caption'), color: 'accent/text' }),
    text('Light Index modified from forecast data', { name: 'Value-added Notice', font: font('caption'), color: 'text/tertiary' }));
}

export function provenanceTag(label) {
  return row({ name: `ProvenanceTag / ${label}`.slice(0, 50), align: 'center', noshrink: true,
    style: { padding: `${d('space/xxs')} ${d('space/xs')}`, borderRadius: '999px', border: `${d('stroke/hairline')} solid ${c('separator/default')}` } },
  text(label, { name: 'Label', font: font('caption'), color: 'text/secondary' }));
}

export function warningLine(message, { kind = 'warning', font: f = 'caption' } = {}) {
  const tone = kind === 'danger' ? 'status/danger' : 'status/warning';
  return row({ name: `${kind === 'danger' ? 'DangerLine' : 'WarningLine'}`, align: 'flex-start', gap: d('space/xs') },
    el('div', { name: 'Icon Slot', style: { display: 'flex', alignItems: 'center', height: f === 'callout' ? 15 : 13, flexShrink: 0 } }, icon('exclamationmark.triangle.fill', { size: 11, color: tone })),
    text(message, { name: 'Message', font: font(f), color: tone, wrap: true, grow: true }));
}

export function lightBadge({ style = 'regular', window: kind = 'goldenEvening', score, band, confidence = 'high', range, reason = 'inThePast', sample = false } = {}) {
  const w = need(WINDOWS, kind, 'window');
  const scored = typeof score === 'number';
  const nm = `LightBadge / ${style} / ${scored ? 'Scored' : 'No forecast'}`;
  if (scored) {
    const b = band || bandFor(score);
    const chip = (size) => scoreChip({ score, band: b, size, lowConfidence: confidence === 'low' });
    if (style === 'compact') {
      return row({ name: nm, align: 'center', gap: d('space/xs'), noshrink: true }, chip('compact'),
        text(w.short, { name: 'Window Name', font: font('caption'), color: 'text/secondary' }));
    }
    if (style === 'regular') {
      return row({ name: nm, align: 'center', gap: d('space/sm'), noshrink: true }, chip('regular'),
        col({ name: 'Text', align: 'flex-start' },
          text(w.name, { name: 'Window Name', font: font('subheadline'), color: 'text/primary' }),
          row({ name: 'Band Line', align: 'center', gap: d('space/xs') },
            text(BANDS[b].name, { name: 'Band', font: font('caption'), color: 'text/secondary' }),
            confidenceMark(confidence),
            sample ? sampleDataLabel() : null)));
    }
    return row({ name: nm, align: 'center', gap: d('space/md'), noshrink: true }, chip('large'),
      col({ name: 'Text', gap: d('space/xxs'), align: 'flex-start' },
        text(`${w.name} · ${score}`, { name: 'Headline', font: font('headline'), color: 'text/primary' }),
        row({ name: 'Band Line', align: 'center', gap: d('space/xs') },
          text(BANDS[b].name, { name: 'Band', font: font('subheadline'), color: 'text/secondary' }),
          range ? text('·', { name: 'Separator', font: font('subheadline'), color: 'text/secondary' }) : null,
          range ? text(`Likely ${range}`, { name: 'Range', font: font('subheadline'), color: 'text/secondary' }) : null),
        row({ name: 'Confidence Line', align: 'center', gap: d('space/xs') },
          confidenceMark(confidence),
          text(CONFIDENCE[confidence].name, { name: 'Confidence', font: font('caption'), color: 'text/secondary' }),
          sample ? sampleDataLabel() : null)));
  }
  const r = need(NO_FORECAST, reason, 'reason');
  if (style === 'compact') {
    return row({ name: nm, align: 'center', gap: d('space/xs'), noshrink: true }, noForecastRing(dv('size/badge/heightCompact')),
      text(w.short, { name: 'Window Name', font: font('caption'), color: 'text/secondary' }));
  }
  if (style === 'regular') {
    return row({ name: nm, align: 'center', gap: d('space/sm'), noshrink: true }, noForecastRing(dv('size/badge/height')),
      col({ name: 'Text', align: 'flex-start' },
        text(w.name, { name: 'Window Name', font: font('subheadline'), color: 'text/primary' }),
        text(NO_FORECAST_LABEL, { name: 'Label', font: font('caption'), color: 'text/secondary' })));
  }
  return row({ name: nm, align: 'center', gap: d('space/md') }, noForecastRing(dv('size/lightRing/large')),
    col({ name: 'Text', gap: d('space/xxs'), align: 'flex-start' },
      text(`${w.name} · ${NO_FORECAST_LABEL}`, { name: 'Headline', font: font('headline'), color: 'text/primary' }),
      text(r.long, { name: 'Reason', font: font('subheadline'), color: 'text/secondary', wrap: true, style: { maxWidth: 280 } })));
}
