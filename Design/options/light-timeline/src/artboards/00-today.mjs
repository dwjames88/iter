// 00-today: the CURRENT app. Explore 1280x820, Bixby Bridge selected, the place card scrolled to "Light through the day".
// Plus 00-shell-960: the shell at 960x652 (sidebar collapsed, list 340) as a check.
import { el, col, text } from '../../../../paper/tools/lib/h.mjs';
import { c, d, font } from '../../../../paper/tools/lib/tokens.mjs';
import { exploreWindow, placeCard } from '../shell.mjs';
import { lightTimelineModule } from '../timeline-h.mjs';

const todayWindow = () => {
  const card = placeCard({ height: 500, scrollY: 200, sections: [lightTimelineModule({ width: 336, readoutValues: '18:26 · 25% cloud · 0% rain' }),
    col({ name: 'Sun and moon (stub)', gap: 12 }, text('Sun and moon', { name: 'Title', font: font('title/section', { size: 15, lineHeight: 20 }), color: 'text/primary' }),
      el('div', { name: 'Card stub', style: { height: 120, borderRadius: d('radius/card'), background: c('background/control'), border: `0.5px solid ${c('separator/default')}` } }))] });
  return exploreWindow({ width: 1280, height: 820, overlay: el('div', { name: 'Card Position', style: { position: 'absolute', right: 12, bottom: 12, display: 'flex' } }, card) });
};
export const artboards = [
  { id: '00-today-light', width: 1280, height: 820, appearance: 'light', html: todayWindow },
  { id: '00-today-dark', width: 1280, height: 820, appearance: 'dark', html: todayWindow },
  { id: '00-shell-960-light', width: 960, height: 652, appearance: 'light', html: () => exploreWindow({ width: 960, height: 652 }) },
];
