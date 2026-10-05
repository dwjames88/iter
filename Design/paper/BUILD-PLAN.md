# Putting the Iter design onto the Paper canvas

This is the order to place everything, how to arrange and name it, what each step costs in Paper calls, and what to check after each stage. It is written for the next step, an agent with Paper's tools connected, and for you if you place artboards by hand. What Paper accepts, and how it was confirmed, is in [PAPER-NOTES.md](PAPER-NOTES.md). Every file is listed in [INDEX.md](INDEX.md). You can review the whole set first in [preview.html](preview.html).

## What there is

| Page | Artboards | Of which | Calls by the agent route (with clone and duplicate savings) |
|---|---|---|---|
| Foundations | 7 | colour, type, spacing and radii, elevation, icons, logo and app icon, Light Index | 428 |
| Components | 54 | 47 component sheets (light and dark side by side), the system components board, 6 menu and dialog boards | 1,879 |
| Screens (Light) | 103 | 81 screen states + 22 note companions | 3,147 |
| Screens (Dark) | 81 | dark twins of every screen state | 483 |
| Flows | 5 | overview and four journeys | 58 |
| **Total** | **250** | 228 artboards + 22 note companions | **≈ 6,000** (10,067 without savings) |

Every screen state in `Design/SCREENS.md` and every component in `Design/COMPONENTS.md` has an artboard (129 of 129, checked by `tools/check.mjs --strict`).

## Two routes, and which to use

**The quota decides the route.** Paper's free plan allows 100 MCP tool calls a week; Pro allows 1,000,000 ([pricing](https://paper.design/pricing)). Paper's agent guide requires small writes: about one visual group, roughly 15 lines of HTML, per `write_html` call. Under that rule the whole file is about 6,000 calls. On the free plan that is about 60 weeks; on Pro, an afternoon.

| Route | How | Calls | Fits |
|---|---|---|---|
| **A. Import by hand, agent for tokens and checks** | You import each artboard file into Paper (Paper documents "Import a local file" and HTML paste as editable layers). The agent only creates the pages and the tokens, then reviews with screenshots. | about 12 to set up, plus whatever you spend on reviews | Free plan. Recommended if you are not on Pro. |
| **B. Agent builds everything** | The agent follows the stages below, writing each artboard from its fragment manifest. | ≈ 6,000 | Pro. One month of Pro covers it. |

The two routes produce the same layers, because the import files and the fragment manifests come from the same build. Route A is quicker in your hands but untested: whether an imported `var(--token)` binds to a Paper token of the same name is unconfirmed. If it does not, import the literal files instead (see below). Route B follows Paper's own guidance, so its result is the most predictable.

### Route A step by step (free plan)

1. Agent, 12 calls: `get_guide`, `get_basic_info`, `get_font_family_info` for SF Pro and New York, `create_page` ×5 (names below), `create_tokens` ×3 with [`tokens.paper.json`](tokens.paper.json) (277 tokens, in Paper's required order).
2. You: first run `node tools/paste-bundle.mjs` once (from `Design/paper/`). It writes the import files and the data behind the preview's copy buttons; they are generated, not committed, because together they are about 50 MB. Then, in `preview.html`, click **Copy for Paper** beside an artboard and paste it onto the right page with ⌘V. Alternatively, import the matching file from `paste/<page>/` (one root element per file, numbered in build order). Work in the stage order below.
3. If colours come in blank, tokens did not bind. Use **Copy literal**, or the `paste-literal/` files, which have every value resolved.
4. Agent, as quota allows: `get_screenshot` per section to review, and `finish_working_on_nodes` at the end of each session.

Flow thumbnails are images. Paper's paste rules say pasted images need a public URL, so if a thumbnail does not come through, drag the PNG from `assets/thumbs/` onto its frame. The frame's layer name says which one.

### Route B step by step (agent, Pro)

For each artboard, in stage order:

1. `create_artboard` on its page with the name, size and position from `artboards/layout.json` (left and top place it on the canvas).
2. `write_html` each fragment from `<file>.fragments.json` in sequence, into the parent named by its `parentPath`. Fragments marked `clone` are one `write_html` holding `<x-paper-clone node-id="…">` (the source node is the one created by `sourceSeq`), followed by `set_text_content` and `update_styles` for the listed overrides, batched.
3. A dark screen is `duplicate_nodes` of its light twin, then batched `update_styles` swapping `--color-` for `--color-dark-` on the nodes listed under `duplicateOf.changes`.
4. `get_screenshot` once per top-level section of the artboard, compared with the local render (`tools/render.sh`).
5. `finish_working_on_nodes` at the end of every session.

## Pages, names and arrangement

Five pages, in this order: **Foundations**, **Components**, **Screens (Light)**, **Screens (Dark)**, **Flows**.

- **Artboard names** are the build names: `F01 Colour`, `LightBadge · Compact, Regular`, `Trip builder · Conflict and suggestion · Light · 1280`, `Explore · Default · Dark · 960`. Every layer inside has a `layer-name` (window, toolbar, sidebar, sections, rows, icons named `Icon / <SF Symbol name>`, maps named `Map placeholder (swap)`, notes named `Note / <title>`).
- **Positions** are in `artboards/layout.json` (from `tools/layout.mjs`). Each page is laid out in rows by section, in the product's order: for screens, one row per `SCREENS.md` section (Shell, All Trips, New Trip sheet, Trip builder, Explore, Spot page, Saved, Spot editor, Scout, Settings, menus and dialogs). Within a row, states run in the order of the States table, 1280 before 960. There is 200 px between artboards and 400 px between rows, with a row label above each row. A screen's **note companion** (`… · Notes`, 320 wide) sits 40 px to its right. Dark screens sit in the same positions on the dark page, so the two pages can be compared by switching.
- **Components** are rows by `COMPONENTS.md` group (Light Index, Honesty, Shared, Shell, Trips, Explore, Spot page, Saved and Scout, System, then the menu boards).

## Build order, with calls (route B)

Generated by `tools/plan.mjs`; the full per-artboard list is in [`artboards/plan-tables.md`](artboards/plan-tables.md). Most valuable first: the system, then the screens you will finish first, then everything else.

| # | Stage | Artboards | Calls | Cumulative | Check after it |
|---|---|---|---|---|---|
| 0 | Setup: guide, basic info, fonts, five pages, tokens | 0 | 12 | 13 | `get_tokens` lists 277 tokens; light and dark colour sets both present; SF Pro and New York found |
| 1 | Foundations: colour, type, Light Index, spacing | 4 | 244 | 257 | Swatches show colour (tokens bound); type samples are SF Pro and New York, not a fallback serif; digits are tabular |
| 2 | Core components: LightBadge (2 sheets), ScoreChip, NoForecastRing, ConfidenceMark, SampleDataLabel, WeatherAttribution, ProvenanceTag, Warning lines | 9 | 214 | 471 | Dashed rings are dashed; the low-confidence column is faded; nothing clipped |
| 3 | Key light screens: Shell, All Trips list, Trip builder, Explore default and selected, Spot page (sample), Saved list, Scout results | 8 | 393 | 864 | Each matches its render in `preview.html`; layers read as Window / Toolbar / Sidebar / Detail; flex containers behave like auto layout when resized |
| 4 | Their dark twins | 8 | 48 | 912 | Every colour switched to the dark set (search the layers for `--color-` without `dark`) |
| 5 | Remaining domain components | 40 | 1,530 | 2,442 | As stage 2 |
| 6 | Remaining light screens | 62 | 2,124 | 4,566 | As stage 3 |
| 7 | Remaining dark twins | 62 | 371 | 4,937 | As stage 4 |
| 8 | 960 × 640 variants, light and dark | 14 | 335 | 5,272 | Truncation where the app truncates ("25 min wal…"), and the Explore toolbar overflow |
| 9 | Menus, popovers, dialogs, system boards | 13 | 428 | 5,700 | Menus are absolutely positioned over their window; shadows present |
| 10 | Flows | 5 | 58 | 5,758 | Thumbnails present (else drag the PNGs in); arrows join the right cards |
| 11 | Note companions | 22 | 66 | 5,824 | Each sits beside its screen |
| 12 | F04 elevation, F05 icons, F06 logo and app icon | 3 | 184 | 6,008 | Icons are vectors you can recolour; the logo dot is coral |

Each session also costs its own fixed overhead: about 4 calls to start (`get_guide`, `get_basic_info`, two font lookups) and 1 to finish.

### What a budget gets you (route B)

| Budget | What lands |
|---|---|
| **100 calls** (one free week) | Setup and two foundations (type scale and spacing). The colour page alone is 101 calls. Use route A instead. |
| **500 calls** | Setup, the four core foundations, all nine core component sheets, and the first two key screens (Shell, All Trips list). |
| **2,000 calls** | Stages 0 to 4 (system, core components, the eight key screens in light and dark) and 30 of the 40 remaining component sheets (all Trips, Explore and most Spot page components). |
| **≈ 6,000 calls** | Everything. |

For comparison only: writing each artboard in one `write_html` call, against Paper's guidance, would be about 763 calls in total.

### Recommended for the free plan

Week 1: route A setup (12 calls), then import stages 1 to 4 by hand and review them with about 40 screenshot calls. Keep 40 calls back for fixes. Later weeks: import the rest by hand, in stage order, and spend the calls only on reviews. Nothing in this plan needs the agent to write artboards if you import them.

## Before anything goes in: regenerate

The First Light retheme (commits `755b4da` and `5a5706f`) has landed, and everything here was built against it. If `Design/tokens.json` changes again, regenerate before placing anything:

```sh
cd Design/paper
node tools/gen-tokens.mjs          # tokens.css, tokens.paper.json, tools/token-map.json
node tools/build.mjs               # all artboards, manifest, fragments (add --literal for artboards-literal/)
node tools/check.mjs --strict      # coverage, literal colours, banned CSS, layer names, overflow, sizes
node tools/calls.mjs && node tools/layout.mjs && node tools/plan.mjs
tools/thumbs.sh                    # flow thumbnails
node tools/paste-bundle.mjs        # paste/ and paste-literal/
node tools/build-preview.mjs && node tools/build-index.mjs
```

A renamed token makes `build.mjs` stop with the name and a suggestion, so nothing goes in with a stale colour.

## Known limits

- **Maps** are a neutral placeholder layer named `Map placeholder (swap)`; pins, routes, cards and banners on top are real layers. Swap the placeholder for a map image.
- **Blur**: materials (place card, popovers, menus, sheets, glass) use `backdrop-filter`, which Paper may not support. They are 92 to 96% opaque, so they read correctly without it.
- **Shadows** are inline CSS (Paper has no shadow token type).
- **Files over 200 KB** (F01, F05, the Explore list and map panels, HourlyStrip) are a problem only for route A pastes. If Paper refuses one, import it in two halves (the light and dark blocks are separate top-level children). Route B writes them in fragments anyway.
