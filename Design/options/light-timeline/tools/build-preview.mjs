// build-preview.mjs: writes ../preview.html with every render embedded as a WebP data URI.
// Usage: node Design/options/light-timeline/tools/build-preview.mjs
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.dirname(HERE);
const SCRATCH = '/tmp/iter-scratch/timeline-options';
const RENDERS = `${SCRATCH}/renders`;
const TMP = `${SCRATCH}/preview`;
fs.mkdirSync(TMP, { recursive: true });
const manifest = JSON.parse(fs.readFileSync(path.join(ROOT, 'artboards/manifest.json'), 'utf8'));
const meta = Object.fromEntries(manifest.map(a => [a.id, a]));

function uri(id) {
  const png = `${RENDERS}/${id}.png`;
  let src = png;
  if (meta[id].width > 2000) {
    src = `${TMP}/${id}-s.png`;
    execFileSync('sips', ['--resampleWidth', '2000', png, '--out', src], { stdio: 'ignore' });
  }
  const out = `${TMP}/${id}.webp`;
  execFileSync('/opt/homebrew/bin/cwebp', ['-q', '82', '-m', '6', src, '-o', out], { stdio: 'ignore' });
  return 'data:image/webp;base64,' + fs.readFileSync(out).toString('base64');
}

const cap = (id, label) => {
  const m = meta[id];
  const ap = m.appearance === 'dark' ? 'Dark' : 'Light';
  return `${id} · ${m.width}×${m.height} · ${label || ap}`;
};
const fig = (id, text, wide) => {
  const m = meta[id];
  return `<figure class="fig"><div class="frame"><img class="${wide ? 'wide' : ''}" src="${uri(id)}" width="${m.width}" height="${m.height}" alt="${id}" loading="lazy"></div><figcaption>${text || cap(id)}</figcaption></figure>`;
};
const grid = (ids) => `<div class="pair">${ids.map(i => fig(i)).join('')}</div>`;
const ul = (a) => `<ul>${a.map(x => `<li>${x}</li>`).join('')}</ul>`;

const css = `
:root{--bg:#fff8f0;--surface:#fffdf9;--text:#1e0f0a;--text2:#6b5a51;--text3:#a6958b;--line:#e6d6c8;--accent:#d9431a;--accent-text:#b5360f;--accent-soft:#fdeee6;--on-accent:#fff;color-scheme:light}
@media (prefers-color-scheme: dark){:root:not([data-theme="light"]){--bg:#150C0A;--surface:#1F1512;--text:#FFF4E8;--text2:#BBA99D;--text3:#7A685E;--line:#3A2C26;--accent:#FF8A5C;--accent-text:#FF8A5C;--accent-soft:#2c1a14;--on-accent:#150C0A;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#150C0A;--surface:#1F1512;--text:#FFF4E8;--text2:#BBA99D;--text3:#7A685E;--line:#3A2C26;--accent:#FF8A5C;--accent-text:#FF8A5C;--accent-soft:#2c1a14;--on-accent:#150C0A;color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;-webkit-font-smoothing:antialiased}
.page{max-width:1200px;margin:0 auto;padding:32px 16px 80px}
.top{display:flex;justify-content:space-between;align-items:center;gap:12px;color:var(--text2);font-size:13px}
button.theme{font:inherit;font-size:13px;color:var(--text);background:var(--surface);border:1px solid var(--line);border-radius:999px;padding:5px 12px;cursor:pointer}
h1{font-size:clamp(28px,5vw,40px);line-height:1.12;letter-spacing:-.02em;margin:18px 0 12px;font-weight:700}
h2{font-size:clamp(22px,3.4vw,28px);line-height:1.2;letter-spacing:-.015em;margin:56px 0 10px;padding-top:28px;border-top:1px solid var(--line)}
h3{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--text2);margin:22px 0 6px}
p{margin:0 0 12px;max-width:72ch}
blockquote{margin:16px 0;padding:4px 0 4px 16px;border-left:3px solid var(--accent);color:var(--text);font-size:18px;line-height:1.45;max-width:72ch}
.muted{color:var(--text2)}
ul{margin:0 0 12px;padding-left:20px;max-width:80ch}li{margin:3px 0}
.cols{display:grid;grid-template-columns:minmax(0,1fr);gap:0 40px}
@media(min-width:800px){.cols{grid-template-columns:minmax(0,1fr) minmax(0,1fr)}}
.scroll{overflow-x:auto;border:1px solid var(--line);border-radius:12px;background:var(--surface);margin:18px 0}
table{border-collapse:collapse;width:100%;min-width:640px;font-size:14px}
th,td{text-align:left;vertical-align:top;padding:10px 14px;border-bottom:1px solid var(--line)}
tr:last-child td{border-bottom:0}th{font-size:12px;text-transform:uppercase;letter-spacing:.05em;color:var(--text2);font-weight:600}
td:first-child{font-weight:600;white-space:nowrap}
.rec{border:1px solid var(--accent);background:var(--accent-soft);border-radius:12px;padding:16px 18px;margin:22px 0}
.rec strong.t{display:block;color:var(--accent-text);font-size:18px;margin-bottom:6px}
.rec ul{margin-bottom:0}
.note{font-size:14px;color:var(--text2);margin-top:14px}
.fig{margin:20px 0 0;min-width:0}
.frame{overflow-x:auto;border:1px solid var(--line);border-radius:12px;background:var(--surface)}
.frame img{display:block;width:100%;height:auto;min-width:720px}
.frame img.wide{min-width:960px}
figcaption{font-size:13px;color:var(--text2);margin-top:8px;font-variant-numeric:tabular-nums}
.pair{display:grid;grid-template-columns:minmax(0,1fr);gap:0 20px}
@media(min-width:1000px){.pair{grid-template-columns:minmax(0,1fr) minmax(0,1fr)}}
.tag{display:inline-block;font-size:12px;font-weight:600;color:var(--on-accent);background:var(--accent);border-radius:999px;padding:2px 10px;vertical-align:middle;margin-left:8px}
`;

const html = `<title>Iter Light Timeline Options</title>
<style>${css}</style>
<div class="page">
<div class="top"><span>Iter · Explore · place card</span><button class="theme" id="tt" type="button">Toggle theme</button></div>
<h1>Light through the day — layout options</h1>
<blockquote>i think this needs to be a bigger section. show me options with it as a full height bar on the left, and on the right replacing the places list.</blockquote>
<p class="muted">Each option is drawn in the real Explore window at 1280×820 and 960×652, in light and dark. Data: Bixby Bridge, Tue Oct 6 2026, OpenWeather updated 11:50, marker being dragged at 18:26. Windows: Sunset 76 (18:09–18:43), Blue PM 78, Night 79; Blue AM and Sunrise have passed.</p>
<div class="scroll"><table>
<thead><tr><th>Option</th><th>pt per hour</th><th>Sky band</th><th>What it costs</th></tr></thead>
<tbody>
<tr><td>Today</td><td>~10.5</td><td>56 pt × ~252 pt, 80 pt cloud plot</td><td>Inside the 360 pt place card</td></tr>
<tr><td>A — Bar on the left</td><td>~25</td><td>48 pt wide, full-height bar</td><td>Map 680 → 492 (428 at 960); list drops to 340; card 320; cloud chart a 24 pt sliver</td></tr>
<tr><td>B — Replaces the list</td><td>~13.7 full day, ~82 zoomed (Sunset ±2 h)</td><td>56 → 88 pt; plot 80 → 112 pt, 328 pt wide</td><td>List hidden while the panel is open; map untouched</td></tr>
<tr><td>C — Strip over the map</td><td>~26</td><td>64 pt, 632 pt across</td><td>Covers 276 of 768 pt of map height (36%); light info split between strip and card</td></tr>
</tbody></table></div>
<div class="rec"><strong class="t">Recommendation: B</strong>
${ul([
  '<b>Best fit with the click.</b> Choosing a place is already the moment you want its light; B gives it the whole column: timeline, window rows and what is coming up in one readable stack.',
  '<b>Lowest cost.</b> Nothing taken from the map, and the smallest structural change: one column switching between two views, reusing the horizontal renderer.',
  '<b>Easy to undo.</b> Esc and the up/down arrows make it cheap to leave and to compare places.',
  '<b>A</b> is the most striking and the only one that keeps the timeline up while browsing the list, but it takes 188 pt of map and its vertical weather band is too slim to read. <b>C</b> has the best time resolution but covers a third of the map and splits light across two places.',
  'If time resolution matters most, take C’s every-hour axis into B’s zoomed views.'])}
</div>
<p class="note">The event unit (symbol + score + time) follows the shared component the design lead is finalising.</p>

<h2>Today — for comparison</h2>
<p>The module is a 56 pt sky band about 252 pt wide inside the 360 pt place card: about 10.5 pt per hour, with an 80 pt cloud plot beneath.</p>
${fig('00-today-light')}${fig('00-today-dark')}

<h2>Option A — Full-height bar on the left</h2>
<p>The timeline becomes its own column between the sidebar and the places list, with time running top to bottom: a 48 pt sky bar the full height of the window, a slim cloud and rain band beside it, and the day's windows to the right as event units with brackets for each span. The day runs about 600 pt tall, so 24 hours get about 25 pt per hour, 2.4 times today. In Set mode the four hours around sunset fill the whole height.</p>
<div class="cols"><div><h3>Interaction</h3>${ul([
  'Hover or drag on the bar moves a horizontal marker with a time pill; on release it turns dashed and stays, and the readout returns to the selected window.',
  'Click a window to select it in the column, on the pin and in the card.',
  'Up/Down move the list; Left/Right or [ ] step windows; D, R, S switch range; Esc ends a scrub.',
  'Nothing selected: the column shows the area’s sky with sunrise and sunset, no scores (A-1280-empty-light).',
  'VoiceOver: one adjustable bar in 10-minute steps; each window its own element.'])}</div>
<div><h3>What changes in the app</h3>${ul([
  'A third column in the Explore split, with a width constant and collapse rule (sidebar collapses first, then the map; below ~400 pt of map the card becomes a sheet).',
  'A vertical renderer for <code>LightTimelineSection</code> sharing window and marker logic with the horizontal one.',
  '<code>ExplorePlaceCard</code> drops its timeline and shrinks to 320 (296 at 960).',
  'Selection and marker state move up to the Explore model.'])}</div></div>
${fig('A-1280-light')}${fig('A-1280-dark')}${fig('A-960-light')}${fig('A-960-dark')}${fig('A-1280-sunset-light', cap('A-1280-sunset-light', 'Light, Set range'))}${fig('A-1280-empty-light', cap('A-1280-empty-light', 'Light, nothing selected'))}

<h2>Option B — Light panel replaces the places list <span class="tag">Recommended</span></h2>
<p>Selecting a place turns the list column into that place's Light panel: a header with ‹ Places and "3 of 16" arrows, the spot name and next event, the full segmented control and readout, the grown timeline, "Today" window rows led by the event unit, and "Coming up". The map stays exactly where it was. The sky band grows 56 → 88 pt, the plot 80 → 112 pt and 252 → 328 pt wide (about 13.7 pt per hour, or about 82 pt per hour in Sunset ±2 h). It is the biggest gain in height and the smallest in time resolution.</p>
<div class="cols"><div><h3>Interaction</h3>${ul([
  'Enter by clicking a row or pin, or Return on a row; back via ‹ Places, Esc or Explore in the sidebar, at the same scroll position.',
  'Up/Down (and header arrows) step to the previous or next place without leaving the panel.',
  'Hover or drag scrubs the timeline with a time pill; click a bracket or window row to select it everywhere.',
  'Nothing selected: the column is the list.',
  'VoiceOver: "Back to places", "Place 3 of 16", one adjustable timeline.'])}</div>
<div><h3>What changes in the app</h3>${ul([
  'The list column becomes a two-state container: list or new <code>LightPanel</code>, driven by the selected place.',
  '<code>LightTimelineSection</code> gets a "wide" size: labels inside the plot, taller band and plot, axis pill.',
  '<code>DayWindowsSection</code> and "Coming up" move from the card into the panel; the card keeps name, images and Good to know.',
  'Column keeps 340 pt minimum; below 350 pt the drag hint is dropped; the panel scrolls (cut at "Coming up" at 820, "Today" at 652).'])}</div></div>
${fig('B-pair-light', 'B-pair-light · 2600×880 · List state and Light state side by side · Light', true)}${fig('B-pair-dark', 'B-pair-dark · 2600×880 · List state and Light state side by side · Dark', true)}
${fig('B-1280-light-light', cap('B-1280-light-light', 'Light state · Light'))}${fig('B-1280-light-dark', cap('B-1280-light-dark', 'Light state · Dark'))}${fig('B-960-light-light', cap('B-960-light-light', 'Light state · Light'))}${fig('B-960-light-dark', cap('B-960-light-dark', 'Light state · Dark'))}${fig('B-1280-sunset-light', cap('B-1280-sunset-light', 'Light state, Sunset ±2 h · Light'))}${fig('B-1280-list-dark', cap('B-1280-list-dark', 'List state · Dark'))}

<h2>Option C — Light strip across the top of the map</h2>
<p>With a place selected, a glass strip docks across the full map width, inset 12 pt like the place card: a header row (spot and event unit, readout, range control, collapse chevron), window event units above a 64 pt sky band with every hour labelled, and a 72 pt cloud plot with the legend inside. 632 pt across gives about 26 pt per hour, 2.5 times today. It covers 276 of the map's 768 pt at 1280 (36%), and 268 of 600 pt at 960; collapsed it folds to a 44 pt ribbon and returns about 220 pt.</p>
<div class="cols"><div><h3>Interaction</h3>${ul([
  'Hover or drag scrubs with a time pill in the axis row; click a window to select it.',
  'Esc deselects the place and removes the strip; ⌥⌘L or the chevron collapses and expands it.',
  'Up/Down move the list and the strip follows; Left/Right step windows.',
  'Nothing selected: no strip. VoiceOver: one adjustable element.'])}</div>
<div><h3>What changes in the app</h3>${ul([
  'A new overlay in <code>ExploreMapPane</code> with a top content inset so the camera keeps the pin clear.',
  'A wide variant of <code>LightTimelineSection</code> with event-unit bracket labels, inline legend and collapsed mode.',
  '<code>ExplorePlaceCard</code> drops its timeline, shrinks to 320 and shares the remaining height (opens scrolled at 960); windows and "Coming up" stay in the card.',
  'The strip is always map width minus 24 pt; at 960 hour labels go to every two hours.'])}</div></div>
${fig('C-1280-light')}${fig('C-1280-dark')}${fig('C-960-light')}${fig('C-960-dark')}${fig('C-1280-collapsed-light', cap('C-1280-collapsed-light', 'Light, strip collapsed'))}
</div>
<script>
(function(){var r=document.documentElement,b=document.getElementById('tt');
b.addEventListener('click',function(){var d=r.dataset.theme?r.dataset.theme==='dark':matchMedia('(prefers-color-scheme: dark)').matches;r.dataset.theme=d?'light':'dark'})})();
</script>
`;
const out = path.join(ROOT, 'preview.html');
fs.writeFileSync(out, html);
console.log(out, (Buffer.byteLength(html) / 1048576).toFixed(2) + ' MB');
