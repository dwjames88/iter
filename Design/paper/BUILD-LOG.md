# Paper build log

Live record of placing the Iter design onto the Paper canvas (route B in [BUILD-PLAN.md](BUILD-PLAN.md)). Updated as the build runs.

## File

- Paper file: **Iter** (new file in the Field Frames team, Projects folder). Nothing else in the team was opened or changed.
- Pages, in order of creation: Foundations, Components, Screens (Light), Screens (Dark), Flows. (Paper lists them newest first in its API; reorder by dragging in the page list if wanted.)
- Tokens: all 277 entries of `tokens.paper.json` created (180 colours, 40 spacing, 4 radius, 11 container, 2 families, 15 sizes, 2 weights, 15 line heights, 8 opacities).

## Paper calls used

| Who | Calls | Notes |
|---|---|---|
| Lead (setup, tests, reviews) | 21 | guide, file, open ×2, 5 page calls, 3 token batches, 1 token fix, list files, 2 failed font lookups, first artboard tests |
| Workers | 0 | |
| **Total** | **21** | |

Plan or usage: nothing seen yet (checked in every response header so far: they carry only the file id, name and a token hash).

## Artboards

Status: not started / in progress (next fragment) / placed / reviewed.

| Stage | Artboard | Page | Status | Review notes |
|---|---|---|---|---|
| 1 | F02 Type scale | Foundations | in progress (fragment 2 of 18) | |
| 1 | F01 Colour | Foundations | not started | |
| 1 | F03 Spacing & radii | Foundations | not started | |
| 1 | F07 Light Index language | Foundations | not started | |

(Later stages are added as they start. Every remaining artboard is "not started"; the full ordered list is in `artboards/plan-tables.md`.)

## Decisions

1. **Token names.** `tokens.paper.json` was generated without the leading `--` on each name, which Paper's `create_tokens` refuses (its schema requires `^--`). Fixed in `tools/gen-tokens.mjs` (names now carry `--`; font weights and opacities are sent as numbers, as Paper documents) and regenerated. `tokens.css` is unchanged.
2. **Selection tint tokens.** Paper stored the two `color-mix(...)` token values (`--color-canvas-selection-tint`, `--color-dark-canvas-selection-tint`) as an opaque dark grey, `rgb(41 41 41)`. Set them to their resolved values instead: accent at 16 % (`rgba(217, 67, 26, 0.16)` light, `rgba(255, 138, 92, 0.16)` dark). Token aliases with plain `var(--x)` (menu highlight) stored correctly.
3. **Font lookup.** `get_font_family_info` failed twice with "Open a Paper file to use this tool" although the Iter file was open (it seems to need the file to be the foreground tab, which needs the app's UI). Fonts were checked on the canvas instead: the first artboard renders SF Pro (computed `font-family: var(--font-sans)`, screenshot shows SF Pro). New York is checked on the type-scale sample row.
4. **Token variables bind.** On the first artboard, computed styles keep `var(--color-…)`, `var(--spacing-…)`, `var(--text-…)` and `var(--font-weight-…)` as live references, and the screenshot shows the token colours. So the token build is used, not the literal build.
5. **Canvas positions.** `create_artboard` ignores `left`/`top`; the driver queues the position from `artboards/layout.json` and applies it with the first batched `update_styles`.
6. **Driver.** Added `tools/paper-driver.mjs`, which tells each worker the next call and records every node ID Paper returns, resolving parents, clone sources and override targets from real IDs. Its state is the machine record in `build-state/`.

## Differences between the canvas and the prepared sources

(none yet)

## Machine section: artboard → node ID (for resuming; not for reading)

File id `01M46EFK4QR1BT4YSNYVKWC5XM`. Page ids: Foundations `p-1-0`, Components `p-2-0`, Screens (Light) `p-3-0`, Screens (Dark) `p-4-0`, Flows `p-5-0`. Full node maps per artboard are in `build-state/*.json`.

| Artboard | Node id |
|---|---|
| F02 Type scale | 1-0 |
