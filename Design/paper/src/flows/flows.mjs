// Flow artboards: four journeys plus an overview (app map). Cards hold real screen thumbnails (assets/thumbs, made by tools/thumbs.sh).
import { col, row, text, el, svgEl, spacer } from '../../tools/lib/h.mjs';
import { c, d, canvas, font } from '../../tools/lib/tokens.mjs';
import { asset } from '../../tools/lib/assets.mjs';
import { artboardHeader } from '../../tools/lib/specimens.mjs';

const CARD_W = 344, SLOT = 48, PITCH = CARD_W + SLOT, CARD_H = 316, V = 40, PAD = 32;
const stroke = () => `fill:none;stroke:${canvas('flow/arrow')};stroke-width:2;stroke-linecap:round;stroke-linejoin:round`;
const head = (x, y) => `<path d="M${x - 7} ${y - 6} L${x} ${y} L${x - 7} ${y + 6}" style="${stroke()}"/>`;

function arrow(from, to, w = SLOT, label) {
  return svgEl(`Arrow / ${from} → ${to}`.slice(0, 50), { width: w, height: 16 },
    `<path d="M4 8 H${w - 3}" style="${stroke()}"/>${head(w - 3, 8)}`);
}
const arrowSlot = (from, to) => col({ name: 'Arrow Slot', w: SLOT, pad: [12 + 103 - 8, 0, 0, 0], noshrink: true }, arrow(from, to));

function card(n, s) {
  return col({ name: `Step ${n} / ${s.label}`.slice(0, 50), w: CARD_W, h: CARD_H, pad: 12, gap: 8, radius: d('radius/card'), noshrink: true, bg: canvas('specimen/background'), style: { border: `1px solid ${canvas('specimen/border')}` } },
    row({ name: 'Thumb Frame', clip: true, radius: 6, noshrink: true, style: { border: `1px solid ${canvas('specimen/border')}`, width: 322, height: 207 } },
      asset(`thumbs/${s.id}.png`, { name: `Thumb / ${s.label}`, width: 320, height: 205 })),
    row({ name: 'Step Title', gap: 8, align: 'center' },
      row({ name: 'Step Number', w: 22, h: 22, radius: 11, align: 'center', justify: 'center', noshrink: true, style: { border: `1.5px solid ${canvas('flow/arrow')}` } },
        text(String(n), { name: 'Number', font: font('captionStrong'), color: 'text/primary' })),
      text(s.label, { name: 'Screen Name', font: font('headline'), color: 'text/primary' })),
    text(s.caption, { name: 'Caption', font: font('caption'), color: 'text/secondary', wrap: true }));
}

// steps: [{id,label,caption}], rendered as a row with arrows; `offset` columns of empty space on the left.
function stepsRow(name, steps, startNo, offset = 0, afterIn = []) {
  const kids = [];
  steps.forEach((s, i) => {
    if (i > 0) kids.push(arrowSlot(steps[i - 1].label, s.label));
    kids.push(card(startNo + i, s));
  });
  return kids;
}

// One branch row: cards start one column right of the parent; an elbow (absolute SVG) runs from the parent card's bottom centre
// down through the branch rows above it and into the first branch card's left edge.
function branchRow({ label, fromCol, steps, startNo }) {
  return row({ name: `Branch / ${label}`.slice(0, 50), align: 'flex-start' },
    el('div', { name: 'Offset', style: { width: PITCH * (fromCol + 1), flexShrink: 0 } }),
    col({ name: 'Branch Cards', pad: [0, 0, 0, 0], noshrink: true },
      row({ name: 'Branch Label', h: V, align: 'center', noshrink: true }, text(label, { name: 'Branch Label', font: font('captionStrong'), color: 'text/secondary' })),
      row({ name: 'Cards', align: 'flex-start' }, stepsRow('Branch', steps, startNo))));
}
function elbow(from, to, fromCol, k) {
  const w = PITCH - CARD_W / 2, h = k * (V + CARD_H) + V + CARD_H / 2;
  return svgEl(`Arrow / ${from} → ${to}`.slice(0, 50), { width: w, height: h, style: { position: 'absolute', left: `${PITCH * fromCol + CARD_W / 2 - 1}px`, top: '0' } },
    `<path d="M1 0 V${h - 0.5} H${w - 3}" style="${stroke()}"/>${head(w - 3, h - 0.5)}`);
}

function flowBoard({ title, job, main, branches = [] }) {
  const cols = Math.max(main.length, ...branches.map((b) => b.fromCol + 1 + b.steps.length));
  const W = PAD * 2 + cols * CARD_W + (cols - 1) * SLOT;
  let no = main.length + 1;
  const numbered = branches.map((b) => { const o = { ...b, startNo: no }; no += b.steps.length; return o; });
  // deepest parent first so no vertical connector crosses a branch card
  const order = [...numbered].sort((a, b) => b.fromCol - a.fromCol);
  return {
    width: W,
    render: () => col({ name: 'Page', pad: PAD, gap: 28, grow: 'auto', style: { minHeight: 0 } },
      artboardHeader({ title, job }),
      col({ name: 'Journey', gap: 0 },
        row({ name: 'Main Journey', align: 'flex-start' }, stepsRow('Main', main, 1)),
        order.length ? col({ name: 'Branches', gap: 0, style: { position: 'relative', paddingLeft: `0px` } },
          order.map((b, k) => elbow(main[b.fromCol].label, b.steps[0].label, b.fromCol, k)),
          order.map((b) => branchRow(b))) : null)),
  };
}

const defs = [
  { id: 'F-flow-plan-trip', name: 'Flow · Plan a trip', title: 'Plan a trip',
    job: 'Start from an empty All Trips, create a trip from a template, add a stop, resolve a light-order conflict with the suggestion banner, then move the dates.',
    main: [
      { id: 'S-trips-empty', label: 'All Trips · Empty', caption: 'Click New Trip (⌘N), or a template row, to open the New Trip sheet.' },
      { id: 'S-new-trip-template', label: 'New Trip sheet · Template', caption: 'Check the name, start date and length, then click Create. The trip opens in the sidebar.' },
      { id: 'S-trip-builder-default', label: 'Trip builder · Default', caption: 'Click the Add Stop row under a day to open the Add Stop popover.' },
      { id: 'S-trip-builder-add-stop', label: 'Trip builder · Add Stop', caption: 'Search and pick a spot; it joins the end of the day. Stops that clash show a conflict.' },
      { id: 'S-trip-builder-conflict', label: 'Trip builder · Conflict', caption: 'Click Apply on the suggestion to reorder by light, or click the header date button.' },
      { id: 'S-change-dates', label: 'Change Dates · Stops move', caption: 'Pick the new dates and confirm. Moved stops are listed first, and Edit > Undo reverses it.' }] },
  { id: 'F-flow-explore-save', name: 'Flow · Explore and save', title: 'Explore and save',
    job: 'Find a spot on the Explore map, open its place card and spot page, and save it. The side branch adds your own spot with Add Spot mode and ends up in the same Saved list.',
    main: [
      { id: 'S-explore-default', label: 'Explore · Default', caption: 'Click a pin or a row to select it.' },
      { id: 'S-explore-selected', label: 'Explore · Selected', caption: 'Double-click the row, or press Return, to open the spot page.' },
      { id: 'S-spot-sample', label: 'Spot page · Sample', caption: 'Click Save in the header to keep the spot.' },
      { id: 'S-saved-list', label: 'Saved · List', caption: 'Double-click a row to reopen its spot page.' }],
    branches: [{ label: 'Side branch: add your own spot', fromCol: 0, steps: [
      { id: 'S-explore-add-spot', label: 'Explore · Add Spot mode', caption: 'File > Add Spot on Map (⇧⌘N), then click the map to drop a pin.' },
      { id: 'S-editor-create', label: 'Spot editor · Create', caption: 'Fill in the name and details, then click Save.' },
      { id: 'S-saved-list', label: 'Saved · List', caption: 'Your spot lives in Saved too, tagged Added by you.' }] }] },
  { id: 'F-flow-scout', name: 'Flow · Scout', title: 'Scout',
    job: 'Describe a trip in plain words and let Scout find places. Pick a result to open its spot page. If Scout is unavailable or finds nothing, Search Places in Explore is the way out.',
    main: [
      { id: 'S-scout-idle', label: 'Scout · Idle', caption: 'Type a request and press Return or Find Places, or click an example.' },
      { id: 'S-scout-running', label: 'Scout · Running', caption: 'Four stages run. Cancel, or Esc, stops the request.' },
      { id: 'S-scout-results', label: 'Scout · Results', caption: 'Select a row; Open, or a double-click, pushes its spot page.' },
      { id: 'S-spot-sample', label: 'Spot page · Sample', caption: 'Save, or Add to Trip, from the header.' }],
    branches: [
      { label: 'Side branch: Scout unavailable', fromCol: 0, steps: [
        { id: 'S-scout-unavailable-device', label: 'Scout · Unavailable', caption: 'Apple Intelligence is missing. Click Search Places in Explore.' },
        { id: 'S-explore-search-results', label: 'Explore · Apple Maps', caption: 'Search by name or place; results come from Apple Maps.' }] },
      { label: 'Side branch: no results', fromCol: 1, steps: [
        { id: 'S-scout-no-results', label: 'Scout · No results', caption: 'Rephrase, or click Search Places in Explore.' },
        { id: 'S-explore-search-results', label: 'Explore · Apple Maps', caption: 'Search by name or place; results come from Apple Maps.' }] }] },
  { id: 'F-flow-read-spot', name: 'Flow · Read a spot', title: 'Read a spot',
    job: 'The spot page explains a score from the top down: the lead card, the windows, then the reasons. When a forecast is missing, failed, or the sun never sets, the page says so instead of guessing.',
    main: [
      { id: 'S-spot-sample', label: 'Spot page · Sample', caption: 'Click a window row to expand its reasons.' },
      { id: 'S-spot-window-expanded', label: 'Spot page · Window expanded', caption: 'Change the intent, or click another outlook day, to compare.' },
      { id: 'S-spot-no-forecast', label: 'Spot page · No forecast', caption: 'Weather is off: scores become dashed rings.' },
      { id: 'S-spot-failed', label: 'Spot page · Failed', caption: 'Click Retry (⌥⌘R) when the forecast failed to load.' },
      { id: 'S-spot-polar', label: 'Spot page · Polar', caption: 'In polar day or night there is no window to score.' }] },
];

const FIT = { 'F-flow-plan-trip': 472, 'F-flow-explore-save': 832, 'F-flow-scout': 1184, 'F-flow-read-spot': 472 };
const boards = defs.map((x) => ({ x, b: flowBoard(x) }));

// Overview: app map.
const box = (name, sub, o = {}) => col({ name: `Node / ${name}`.slice(0, 50), w: 200, pad: [10, 12], gap: 2, radius: d('radius/card'), noshrink: true, bg: canvas('specimen/background'),
  style: { border: `${o.strong ? 2 : 1}px solid ${o.strong ? canvas('flow/arrow') : canvas('specimen/border')}` } },
  text(name, { name: 'Node Name', font: font('headline'), color: 'text/primary' }),
  sub ? text(sub, { name: 'Node Kind', font: font('caption'), color: 'text/secondary', wrap: true }) : null);
const hop = (from, to, label) => col({ name: 'Hop', w: 96, align: 'center', gap: 2, noshrink: true },
  text(label || '', { name: 'Hop Label', font: font('caption'), color: 'text/tertiary', align: 'center', wrap: true, style: { minHeight: 14 } }), arrow(from, to, 72));
const chain = (nodes) => {
  const kids = [];
  nodes.forEach((n, i) => { if (i) kids.push(hop(nodes[i - 1][0], n[0], n[3])); kids.push(box(n[0], n[1], { strong: n[2] })); });
  return row({ name: `Map Row / ${nodes[0][0]}`.slice(0, 50), align: 'center' }, kids);
};
const MAP = [
  ['Sidebar: All Trips', [['All Trips', 'Detail root · ⌘1, opens here', true], ['New Trip sheet', 'Sheet', false, 'New Trip, template'], ['Trip builder', 'Sidebar entry per trip', false, 'Create']]],
  ['Sidebar: trip', [['Trip: Canyon Country', 'Detail root (Trip builder)', true], ['Add Stop', 'Popover', false, 'Add Stop row'], ['Set-up time', 'Popover', false, '20 min set-up']]],
  ['Trip dates', [['Trip builder', 'Detail root', true], ['Change Dates sheet', 'Sheet', false, 'Date line'], ['Spot page', 'Pushed on the stack', false, 'Stop name']]],
  ['Sidebar: Explore', [['Explore', 'Detail root · ⌘2, ⌘F', true], ['Place card', 'Floating panel', false, 'Select pin or row'], ['Spot page', 'Pushed on the stack', false, 'Open, Return']]],
  ['Add Spot', [['Explore', 'Add Spot mode · ⇧⌘N', true], ['Spot editor sheet', 'Sheet', false, 'Click the map'], ['Saved', 'Detail root', false, 'Save']]],
  ['Sidebar: Saved', [['Saved', 'Detail root · ⌘3', true], ['Spot page', 'Pushed on the stack', false, 'Open'], ['Spot editor sheet', 'Sheet', false, 'Edit…']]],
  ['Sidebar: Scout', [['Scout', 'Detail root · ⌘4', true], ['Spot page', 'Pushed on the stack', false, 'Open'], ['Explore', 'Search Places in Explore', false, 'Unavailable, no results']]],
  ['Settings', [['Settings', 'Separate window, four tabs', true], ['General, Weather, …', 'App menu > Settings… (⌘,)', false, '']]],
];
const overviewH = () => col({ name: 'Page', pad: PAD, gap: 24, grow: 'auto', style: { minHeight: 0 } },
  artboardHeader({ title: 'App map', job: 'Where every surface is reached from. Left to right: a sidebar section (a detail root), then what it opens. Each section keeps its own navigation stack, so switching sections keeps your place.' }),
  col({ name: 'Map', gap: 16 }, MAP.map(([, nodes]) => chain(nodes))));

export const artboards = [
  { id: 'F-flows-overview', name: 'Flows · Overview', section: 'flows', width: 960, height: 704, themes: ['light'], covers: [], render: overviewH },
  ...boards.map(({ x, b }) => ({ id: x.id, name: x.name, section: 'flows', width: b.width, height: FIT[x.id], themes: ['light'], covers: [], render: b.render })),
];
