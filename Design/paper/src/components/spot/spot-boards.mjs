// Component artboards for the spot page (D4): one per component, light and dark blocks, built from the same functions the screens use.
import { col, row, text, el } from '../../../tools/lib/h.mjs';
import { c, d, dv, font } from '../../../tools/lib/tokens.mjs';
import { note } from '../../../tools/lib/chrome.mjs';
import { artboardHeader, themeBlocks, section, cell, page } from '../../../tools/lib/specimens.mjs';
import { vm } from './spot-model.mjs';
import { spotCard, spotHeader, whenToGoSection, sunTimesLine, loadingLead, noScoreLead, outlookStrip, outlookCell, bestLead } from './spot-lead.mjs';
import { dayWindowsSection, windowRow, reasonsGrid, signedBar, explainBlock } from './spot-windows.mjs';
import { lightTimeline, skyArc, hourlyStrip } from './spot-charts.mjs';
import { spotFactsRow, lookAroundSection } from './spot-facts.mjs';

const W = 892; // spot page column inside its side padding
const sample = () => vm('sample');
const spec = (title, body) => col({ name: `Specimen / ${title}`.slice(0, 50), gap: d('space/sm'), style: { alignSelf: 'stretch' } },
  text(title, { name: 'Specimen Label', font: font('captionStrong'), color: 'text/secondary' }), body);
const card = (body, name) => col({ name: name || 'Card Frame', bg: 'background/control', radius: d('radius/card'), clip: true, style: { border: `${d('stroke/hairline')} solid ${c('separator/default')}`, alignSelf: 'stretch' } }, body);

function board({ id, name, type, file, job, covers, notes = [], body, width = 1000, height = 1200, blocks = 'row', blockWidth }) {
  const frameW = blockWidth ?? (blocks === 'row' ? Math.floor((width - 64 - 24) / 2) : width - 64);
  return { id, name, section: 'components', width, height, themes: ['light'], covers: [`Component/${covers}`], notes: notes.map((n) => n.title),
    render: () => page([
      artboardHeader({ title: name, type, file, job }),
      notes.length ? row({ name: 'Notes', gap: d('space/md'), align: 'flex-start', wrap: true }, notes.map((n) => note({ ...n, width: n.width ?? 280 }))) : null,
      themeBlocks(body, { direction: blocks === 'row' ? 'row' : 'column', width: frameW }),
    ], { gap: 24 }) };
}

const N = {
  chevron: { title: 'Chevron drawn open', body: 'The expanded row chevron rotates 90 degrees in the app; here it is chevron.down.' },
  signed: { title: 'Signed bars are grey', body: 'Every signed bar is text/secondary: direction is the left or right side, so colour never reads as good or bad.' },
  best: { title: 'Best tab colour', body: 'The outlook Best tag is accent/emphasis.' },
  header: { title: 'Add to Trip', body: 'Prominent in the source and in SCREENS.md; the snapshots draw it as a plain bordered button. Source followed.' },
  arc: { title: 'Arc does not zoom', body: 'Zooming narrows the timeline and hourly strip only; the sky arc keeps the whole day.' },
  hourly: { title: 'Symbols are single-colour', body: 'The app uses multicolour SF Symbols for the weather; the symbol export is one colour, drawn in text/secondary.' },
  alpha: { title: 'Hard-coded opacities', body: 'Window tints 0.2, selection 0.16, cloud 0.5, below-horizon 0.35, outlook fades 0.8 and 0.6 are literals in SpotLayout.swift (deviation 7); here they are the opacity tokens.' },
  fixture: { title: 'Fixtures', body: 'Numbers are the real engine output for Mesa Arch on Mon 12 Oct 2026 with sample weather (and Tromso, Cottonwood bend), not drawn by hand.' },
  look: { title: 'Absent in snapshots', body: 'Look Around only appears live where Apple has imagery. The preview is a system view, so it is a placeholder here.' },
};

export const artboards = [
  board({ id: 'C-spot-card', name: 'SpotCard', type: 'SpotCard', file: 'Spot/SpotLayout.swift', job: 'The card surface for the spot page lead and charts: padding space/md, background/control, radius/card, hairline.', covers: 'SpotCard', width: 1200, height: 448,
    body: () => [section('On the lead', spotCard(bestLead(sample()), { name: 'SpotCard / Lead' })), section('Empty surface', spotCard(text('Any content: lead, chart, facts', { name: 'Placeholder', font: font('callout'), color: 'text/secondary' })))], blocks: 'row' }),
  board({ id: 'C-spot-header', name: 'SpotHeader', type: 'SpotHeaderView', file: 'Spot/SpotHeaderView.swift', job: 'Who this place is and what you can do with it: name, place line, and the action row.', covers: 'SpotHeader', notes: [N.header], width: 1000, height: 1472,
    body: () => [spec('Curated, saved (Add to Trip, Saved, Open in Maps, Share)', spotHeader(vm('sample'))), spec('Apple Maps, not saved (Save)', spotHeader(vm('polar'))), spec('Added by you (Edit and Delete after a divider, no Save)', spotHeader(vm('user'))), spec('Icon-only, when the row does not fit', spotHeader(vm('user'), { iconOnly: true }))].map((x) => x), blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-when-to-go', name: 'WhenToGoSection', type: 'WhenToGoSection', file: 'Spot/WhenToGoView.swift', job: 'Leads the page with "when should I be here?": the best window, or why there is none, then the outlook.', covers: 'WhenToGoSection', notes: [N.best], width: 1000, height: 1944,
    body: () => [spec('Best window', whenToGoSection(sample())), spec('Loading', spotCard(loadingLead(vm('noforecast', { loading: true })))), spec('No score: weather off', spotCard(noScoreLead(vm('noforecast')))), spec('No score: service failed (Retry)', spotCard(noScoreLead(vm('failed'))))], blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-sun-times-line', name: 'SunTimesLine', type: 'SunTimesLine', file: 'Spot/WhenToGoView.swift', job: 'The always-exact sun times when there is no score, or the polar statement.', covers: 'SunTimesLine', width: 1400, height: 392,
    body: () => [spec('Normal day', sunTimesLine(vm('noforecast'))), spec('Polar night', sunTimesLine({ ...vm('polar'), todayKind: 'polarNight' })), spec('Midnight sun', sunTimesLine({ ...vm('polar'), todayKind: 'polarDay' }))], blocks: 'row' }),
  board({ id: 'C-outlook-strip', name: 'OutlookStrip', type: 'OutlookStrip', file: 'Spot/WhenToGoView.swift', job: 'Ten days at a glance for the chosen intent, fading with confidence.', covers: 'OutlookStrip', notes: [N.best, N.alpha], width: 1000, height: 1944,
    body: () => {
      const m = sample(), o = m.outlook;
      const cells = [['Selected + best (low conf.)', o[6], 'sel'], ['Plain (high)', o[1]], ['Medium fade 80%', { ...o[2], selected: false }], ['Low fade 60%', { ...o[6], selected: false, isBest: false }], ['Passed (ring)', o[0]], ['No window', { ...o[3], headline: null }]];
      return [spec('Sunrise, sample weather', outlookStrip(m)), spec('Weather off', outlookStrip(vm('noforecast'))), spec('Offline', outlookStrip(vm('failed'))),
        spec('Cell states', row({ name: 'Cells', gap: d('space/md'), align: 'flex-start' }, cells.map(([t, o2]) => cell(t, outlookCell(o2, { width: 80 }), { width: 96, caption: t }))))];
    }, blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-day-windows', name: 'DayWindowsSection', type: 'DayWindowsSection', file: 'Spot/DayWindowsView.swift', job: "The selected day's windows in time order, in one card.", covers: 'DayWindowsSection', notes: [N.chevron], width: 1000, height: 1816,
    body: () => [spec('Five windows, Sunrise selected', dayWindowsSection(sample())), spec('Polar night: three windows', dayWindowsSection(vm('polar'))), spec('No windows, midnight sun', dayWindowsSection({ ...sample(), windows: [], todayKind: 'polarDay' })), spec('No windows', dayWindowsSection({ ...sample(), windows: [], todayKind: 'normal' }))], blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-window-row', name: 'WindowRow', type: 'WindowRow (private)', file: 'Spot/DayWindowsView.swift', job: 'One window with its score, expandable to its reasons.', covers: 'WindowRow', notes: [N.chevron, N.signed], width: 1000, height: 2000,
    body: () => {
      const m = sample(), w = m.windows[1], fm = vm('failed'), nm = vm('noforecast');
      return [spec('Collapsed', card(windowRow(m.windows[2]))), spec('Selected', card(windowRow(w, { selected: true }))), spec('Expanded and selected', card(windowRow(w, { selected: true, expanded: true }))),
        spec('No forecast', card(windowRow(nm.windows[2]))), spec('No forecast, expanded', card(windowRow(nm.windows[2], { expanded: true }))), spec('Service failed, expanded (Retry)', card(windowRow(fm.windows[2], { expanded: true })))];
    }, blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-reasons-grid', name: 'ReasonsGrid', type: 'Reasons (private)', file: 'Spot/DayWindowsView.swift', job: 'Why the score is what it is: each factor with its value, a signed bar and a sentence, then confidence.', covers: 'ReasonsGrid', notes: [N.signed, N.fixture], width: 1000, height: 1488,
    body: () => { const m = sample(), p = vm('polar'); return [spec('Sunrise, Mon 12 Oct (sample)', card(col({ name: 'Pad', pad: d('space/md') }, reasonsGrid(m.windows[1], { sample: true })))), spec('Night, Tromso (sample)', card(col({ name: 'Pad', pad: d('space/md') }, reasonsGrid(p.windows[2], { sample: true })))), spec('No forecast', card(col({ name: 'Pad', pad: d('space/md') }, reasonsGrid(vm('noforecast').windows[2]))))]; }, blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-signed-bar', name: 'SignedBar', type: 'SignedBar (private)', file: 'Spot/DayWindowsView.swift', job: "A factor's points, right helps and left hurts; the sign is printed so colour is never the only cue.", covers: 'SignedBar', notes: [N.signed], width: 1000, height: 744,
    body: () => [spec('Scale 21 (largest factor)', col({ name: 'Bars A', gap: d('space/sm') }, [21, 10, 4, 2, 0, -4, -10, -21].map((p) => signedBar(p, 21)))), spec('Scale 10 (minimum scale)', col({ name: 'Bars B', gap: d('space/sm') }, [10, 5, 2, 0, -2, -5, -10].map((p) => signedBar(p, 10))))], blocks: 'row' }),
  board({ id: 'C-explain-block', name: 'ExplainBlock', type: 'ExplainBlock (private)', file: 'Spot/DayWindowsView.swift', job: 'A plain-language reading of the factors by Apple Intelligence. Not drawn when it is unavailable.', covers: 'ExplainBlock', width: 1200, height: 688,
    body: () => [spec('Idle', explainBlock('idle')), spec('Loading', explainBlock('loading')), spec('Done', col({ name: 'Done Wrap', w: 440 }, explainBlock('done', { textBody: 'Mid and high cloud covers 29% of the sky, which should catch colour as the sun comes up. Low cloud is only 6%, so the horizon looks open.' }))),
      spec('Failed: not available', explainBlock('failed', { failure: "Apple Intelligence isn't available right now." })), spec('Failed: ungrounded', col({ name: 'Fail Wrap', w: 440 }, explainBlock('failed', { failure: "The explanation didn't match the numbers, so it was discarded. Try again." }))),
      spec('Unavailable', text('(nothing is drawn)', { name: 'Absent', font: font('caption'), color: 'text/tertiary' }))], blocks: 'row' }),
  board({ id: 'C-light-timeline', name: 'LightTimeline', type: 'LightTimelineSection, TimelineRenderer', file: 'Spot/LightTimelineView.swift', job: 'The 24 hours of light: sky by sun altitude, five windows with scores, cloud by altitude, rain chance, and a scrubber.', covers: 'LightTimeline', notes: [N.alpha, N.fixture], width: 1000, height: 3224,
    body: () => [spec('Full day, Mon 12 Oct (Sunrise selected)', lightTimeline(sample())), spec('Sunrise ±2 h (two tiers, hourly ticks)', lightTimeline(vm('sample', { focus: 'sunrise' }))), spec('Sunset ±2 h', lightTimeline(vm('user', { focus: 'sunset' }))), spec('No forecast: sky strip only', lightTimeline(vm('noforecast')))], blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-sky-arc', name: 'SkyArc', type: 'SkyArcSection, ArcRenderer', file: 'Spot/SkyArcView.swift', job: 'Where the sun and moon are, by compass direction and height, at the shared marker time.', covers: 'SkyArc', notes: [N.arc, N.fixture], width: 1000, height: 3648,
    body: () => [spec('Default, with classic view', skyArc(sample())), spec('No classic view (facing unknown)', skyArc(vm('user'))), spec('Sun below the horizon (22:00)', skyArc(vm('sample', { markerMin: 22 * 60 }))), spec('Polar: the sun never leaves the horizon', skyArc(vm('polar')))], blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-hourly-strip', name: 'HourlyStrip', type: 'HourlyWeatherSection', file: 'Spot/HourlyWeatherView.swift', job: "The day's weather hour by hour, on the timeline's x-axis; golden and blue hours tinted.", covers: 'HourlyStrip', notes: [N.hourly, N.alpha], width: 1000, height: 1952,
    body: () => [spec('Full day (Sunrise selected, marker 07:43)', hourlyStrip(sample())), spec('Sunset selected, Cottonwood bend', hourlyStrip(vm('user'))), spec('Sunrise ±2 h (shared domain)', hourlyStrip(vm('sample', { focus: 'sunrise' }))), spec('No forecast: the section is absent', text('(nothing is drawn)', { name: 'Absent', font: font('caption'), color: 'text/tertiary' }))], blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-spot-facts-row', name: 'SpotFactsRow', type: 'SpotFactsSection', file: 'Spot/SpotFactsView.swift', job: 'The practical facts: walk-in, elevation, facing, best light, time zone; then the blurb and notes.', covers: 'SpotFactsRow', width: 1000, height: 1328,
    body: () => [spec('Curated: all five facts, blurb and notes', spotFactsRow(sample())), spec('Added by you: notes only, facing unknown', spotFactsRow(vm('user'))), spec('Apple Maps: walk-in and facing unknown, other time zone', spotFactsRow(vm('polar')))], blocks: 'column', blockWidth: 934 }),
  board({ id: 'C-look-around', name: 'LookAroundSection', type: 'LookAroundSection', file: 'Spot/SpotFactsView.swift', job: "Apple's street-level imagery where it exists.", covers: 'LookAroundSection', notes: [N.look], width: 1000, height: 968,
    body: () => [lookAroundSection({ width: W })], blocks: 'column', blockWidth: 934 }),
];
