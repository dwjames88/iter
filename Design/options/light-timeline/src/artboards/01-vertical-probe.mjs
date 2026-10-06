// 01-vertical-probe: skeleton check only (timeline-v on a plain card, light and dark). Builders replace this with real options.
import { col, text, row } from '../../../../paper/tools/lib/h.mjs';
import { c } from '../../../../paper/tools/lib/tokens.mjs';
import { timelineV } from '../timeline-v.mjs';
const board = () => row({ name: 'Probe', grow: true, bg: 'background/window', pad: 24, gap: 24 },
  col({ name: 'Card', pad: 12, bg: 'background/control', radius: 12, style: { border: `0.5px solid ${c('separator/default')}`, alignSelf: 'flex-start' } }, timelineV({ height: 520 }).html),
  col({ name: 'Card narrow', pad: 12, bg: 'background/control', radius: 12, style: { border: `0.5px solid ${c('separator/default')}`, alignSelf: 'flex-start' } }, timelineV({ height: 520, barWidth: 24, chartWidth: 90, labelsWidth: 80, domain: { lo: 960, hi: 1200 }, tickEvery: 1 }).html));
export const artboards = ['light', 'dark'].map((a) => ({ id: `01-vertical-probe-${a}`, width: 760, height: 620, appearance: a, html: board }));
