// 10-option-a: Option A - "Light through the day" as a full-height column between the sidebar and the list.
import { el, row, col, text } from '../../../../paper/tools/lib/h.mjs';
import { c, d, font } from '../../../../paper/tools/lib/tokens.mjs';
import { exploreWindow, defaultList, defaultMap, placeCard, pinSelected, mapPin } from '../shell.mjs';
import { windowsToday } from '../data.mjs';
import { lightColumn } from '../option-a/column.mjs';

const wins = windowsToday.map((w) => ({ ...w, selected: w.kind === 'goldenEvening' }));
const kv = (k, v, last) => row({ name: `Fact / ${k}`, align: 'center', justify: 'space-between', style: { height: 32, padding: '0 12px', borderBottom: last ? undefined : `0.5px solid ${c('separator/default')}` } },
  text(k, { name: 'Key', font: font('body'), color: 'text/secondary' }), text(v, { name: 'Value', font: font('body'), color: 'text/primary' }));
const goodToKnow = () => col({ name: 'Good to know', gap: 12 }, text('Good to know', { name: 'Title', font: font('title/section', { size: 15, lineHeight: 20 }), color: 'text/primary' }),
  col({ name: 'Facts Card', style: { background: c('background/control'), borderRadius: d('radius/card'), border: `0.5px solid ${c('separator/default')}` } },
    kv('Faces', '170° S'), kv('Walk-in', '5 min'), kv('Best at', 'Sunset'), kv('Parking', 'Pullout, north side', true)));

function board({ W, H, mode = 'day', empty = false, scrubbing = true, scrim = 'band', cardW = 320, cardH = 420 }) {
  return () => {
    const colW = W >= 1280 ? 208 : 192, lw = 340, side = W >= 1280 ? 240 : 0;
    const mapW = W - side - colW - lw, mapH = H - 52;
    const column = lightColumn({ width: colW, height: mapH, mode, empty, scrubbing, scrim, windows: empty ? [] : wins, marker: scrubbing ? undefined : 18 * 60 + 9, readoutValues: '25% cloud · 0% rain' });
    const cardTop = mapH - 12 - cardH;
    const pin = empty ? null : mapPin(mapW * 0.36, cardTop - 30, pinSelected({ score: 76, time: '18:09' }), { bottom: true });
    const card = empty ? null : el('div', { name: 'Card Position', style: { position: 'absolute', right: 12, bottom: 12, display: 'flex' } },
      placeCard({ width: cardW, height: cardH, sections: [goodToKnow()] }));
    return exploreWindow({ width: W, height: H, listWidth: lw, extraColumn: { width: colW, html: column }, list: defaultList({ selected: empty ? null : 'Bixby Bridge' }),
      map: defaultMap({ width: mapW, height: mapH, selectedName: null, children: [pin] }), overlay: card });
  };
}
const mk = (id, W, H, appearance, opts) => ({ id, width: W, height: H, appearance, html: board({ W, H, ...opts }) });
export const artboards = [
  mk('A-1280-light', 1280, 820, 'light'), mk('A-1280-dark', 1280, 820, 'dark'),
  mk('A-960-light', 960, 652, 'light', { cardW: 296, cardH: 400 }), mk('A-960-dark', 960, 652, 'dark', { cardW: 296, cardH: 400 }),
  mk('A-1280-sunset-light', 1280, 820, 'light', { mode: 'set', scrubbing: false }),
  mk('A-1280-empty-light', 1280, 820, 'light', { empty: true }),
];
