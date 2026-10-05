# Paper build log

Record of placing the Iter design onto the Paper canvas (route B in [BUILD-PLAN.md](BUILD-PLAN.md)).

## Where it stopped

**Stopped on 2026-10-05 at Paper's weekly limit.** The `write_html` for fragment 22 of F01 Colour was refused with:

> Weekly MCP limit reached. It resets in 4 days. Upgrade to Paper Pro to continue. You can upgrade in Paper or visit https://paper.design/pricing. If you just upgraded and still see this, try closing and reopening Paper.

So the account is on Paper's **free plan** (100 MCP calls a week; Pro is unlimited for this purpose), and the allowance comes back **about 2026-10-09**. The call was not retried. `finish_working_on_nodes` (a release, not a write) still went through afterwards, so no artboard is left marked as being worked on.

On the canvas: **F02 Type scale** (complete, reviewed) and **F01 Colour** (partial: fragments 1-21 of 88, the header, notes, column headers and the Accent, Focus, Selection, Route and part of the Map groups). Everything else is not started. The rest of the build is about 5,900 calls: roughly 60 free weeks, or one sitting on Pro. See "How to resume" below.

## How to resume

**By agent (route B), after the reset or on Pro.** Open Paper with the Iter file. Give each worker `tools/paper-driver.mjs` and the brief (the worker brief used here is reproduced in the "Worker loop" section below). Order:
1. F01 Colour: `node tools/paper-driver.mjs next foundations/F01-colour.html`. It will first ask for a flush (queued clone overrides plus a text fix for every hex label placed so far), then fragment 22 (a clone into the Map group), and so on to 88.
2. Then F03 Spacing & radii, F07 Light Index language, and every following stage in the order of the table below (`start` / `init` / `next` / `record` / `flush` / `reviewed`). Dark twins use `dup` / `dup-record`.
3. On the free plan, 100 calls a week buys about one foundation sheet or two or three component sheets; F01 needs about 80 more calls on its own.

**By hand (route A, no agent calls).** `node tools/paste-bundle.mjs` has been run with the corrected sources: open `preview.html`, click **Copy for Paper** beside an artboard and paste it onto its page, in the order of the table below (or import the numbered files in `paste/<page>/`). Tokens are already in the file and bind, so use the normal files, not the literal ones. Skip F02 (done) and either finish F01 by agent or delete the partial F01 artboard and paste the whole one. Paper calls are then needed only for reviews.

## File

- Paper file: **Iter** (new file in the Field Frames team, Projects folder). Nothing else in the team was opened or changed.
- Pages, in order of creation: Foundations, Components, Screens (Light), Screens (Dark), Flows. (Paper lists them newest first in its API; reorder by dragging in the page list if wanted.)
- Tokens: all 277 entries of `tokens.paper.json` created (180 colours, 40 spacing, 4 radius, 11 container, 2 families, 15 sizes, 2 weights, 15 line heights, 8 opacities).

## Paper calls used

| Who | Calls | Notes |
|---|---|---|
| Lead (setup, tests, probes, reviews, fixes) | 43 | guide, file, open ×2, 5 page calls, 3 token batches, 1 token fix, list files, 2 failed font lookups ("Open a Paper file to use this tool"), F02 start, 18 calls on a temporary probe artboard (deleted), F02 border correction and review, final finish_working_on_nodes |
| Worker: F02 Type scale | 39 | 15 fragment writes after my 3, flush, 4 screenshots, 5 style checks and fixes, finish |
| Worker: F01 Colour | 27 | create, 21 writes, 1 refused write (the limit), 3 flush calls, 1 screenshot, 1 text fix |
| **Total** | **109** | 1 refused by the limit, 2 refused as "Open a Paper file"; Paper's own count evidently reached 100 at about this point |

Plan or usage: checked after the first 80 calls; no response revealed the plan, a quota or usage until the refusal above (responses carry only the file id, file name and a token hash).

## Artboards

Status: not started / in progress (next fragment) / placed, not reviewed / reviewed. Generated from `build-state/` by `node tools/log-table.mjs`; every artboard, in build order.

<!-- BEGIN ARTBOARDS -->
Reviewed 1, placed 0, in progress 1, not started 247 (of 249).

| Stage | Artboard | Page | Status | Review notes |
|---|---|---|---|---|
| 1 | F01 Colour | Foundations | in progress (next fragment 22 of 88) |  |
| 1 | F02 Type scale | Foundations | reviewed | Matches the reference in layout, spacing, sizes and colours; nothing clipped. Hairlines restored at 0.5px. The place-name sample shows the default sans because Paper cannot see New York here (decision 7); digits proportional. |
| 1 | F03 Spacing & radii | Foundations | not started |  |
| 1 | F07 Light Index language | Foundations | not started |  |
| 2 | LightBadge · Compact, Regular | Components | not started |  |
| 2 | LightBadge · Large, No forecast | Components | not started |  |
| 2 | ScoreChip | Components | not started |  |
| 2 | NoForecastRing | Components | not started |  |
| 2 | ConfidenceMark | Components | not started |  |
| 2 | SampleDataLabel | Components | not started |  |
| 2 | WeatherAttributionView | Components | not started |  |
| 2 | ProvenanceTag | Components | not started |  |
| 2 | Warning lines | Components | not started |  |
| 3 | Shell · Default · Light · 1280 | Screens (Light) | not started |  |
| 3 | All Trips · List · Light · 1280 | Screens (Light) | not started |  |
| 3 | Trip builder · Default · Light · 1280 | Screens (Light) | not started |  |
| 3 | Explore · Default · Light · 1280 | Screens (Light) | not started |  |
| 3 | Explore · Selected with place card · Light · 1280 | Screens (Light) | not started |  |
| 3 | Spot page · Sample (scored) · Light · 1280 | Screens (Light) | not started |  |
| 3 | Saved · List · Light · 1280 | Screens (Light) | not started |  |
| 3 | Scout · Results · Light · 1280 | Screens (Light) | not started |  |
| 4 | Shell · Default · Dark · 1280 | Screens (Dark) | not started |  |
| 4 | All Trips · List · Dark · 1280 | Screens (Dark) | not started |  |
| 4 | Trip builder · Default · Dark · 1280 | Screens (Dark) | not started |  |
| 4 | Explore · Default · Dark · 1280 | Screens (Dark) | not started |  |
| 4 | Explore · Selected with place card · Dark · 1280 | Screens (Dark) | not started |  |
| 4 | Spot page · Sample (scored) · Dark · 1280 | Screens (Dark) | not started |  |
| 4 | Saved · List · Dark · 1280 | Screens (Dark) | not started |  |
| 4 | Scout · Results · Dark · 1280 | Screens (Dark) | not started |  |
| 5 | AddToTripMenu | Components | not started |  |
| 5 | MapStandIn | Components | not started |  |
| 5 | SpotEditorSheet | Components | not started |  |
| 5 | SpotCard | Components | not started |  |
| 5 | TripContextMenu | Components | not started |  |
| 5 | TripCard | Components | not started |  |
| 5 | TemplateRow | Components | not started |  |
| 5 | TripHeader | Components | not started |  |
| 5 | TripPlanList | Components | not started |  |
| 5 | DayHeader | Components | not started |  |
| 5 | StopRow | Components | not started |  |
| 5 | StopNumberBadge | Components | not started |  |
| 5 | ConnectorRow | Components | not started |  |
| 5 | SuggestionBanner | Components | not started |  |
| 5 | TripRouteMap | Components | not started |  |
| 5 | AddStopPopover | Components | not started |  |
| 5 | ExploreListPanel | Components | not started |  |
| 5 | ExploreRow | Components | not started |  |
| 5 | ExploreMapPane | Components | not started |  |
| 5 | ExplorePinView | Components | not started |  |
| 5 | ExplorePlaceCard | Components | not started |  |
| 5 | AddSpotBanner | Components | not started |  |
| 5 | SpotHeader | Components | not started |  |
| 5 | WhenToGoSection | Components | not started |  |
| 5 | SunTimesLine | Components | not started |  |
| 5 | OutlookStrip | Components | not started |  |
| 5 | DayWindowsSection | Components | not started |  |
| 5 | WindowRow | Components | not started |  |
| 5 | ReasonsGrid | Components | not started |  |
| 5 | SignedBar | Components | not started |  |
| 5 | ExplainBlock | Components | not started |  |
| 5 | LightTimeline | Components | not started |  |
| 5 | SkyArc | Components | not started |  |
| 5 | HourlyStrip | Components | not started |  |
| 5 | SpotFactsRow | Components | not started |  |
| 5 | LookAroundSection | Components | not started |  |
| 5 | SavedRow | Components | not started |  |
| 5 | ScoutResultRow | Components | not started |  |
| 5 | ScoutProgress | Components | not started |  |
| 5 | System components | Components | not started |  |
| 6 | Shell · No sample banner · Light · 1280 | Screens (Light) | not started |  |
| 6 | All Trips · Empty · Light · 1280 | Screens (Light) | not started |  |
| 6 | All Trips · All sessions passed · Light · 1280 | Screens (Light) | not started |  |
| 6 | All Trips · Import error · Light · 1280 | Screens (Light) | not started |  |
| 6 | New Trip sheet · Template chosen · Light · 1280 | Screens (Light) | not started |  |
| 6 | New Trip sheet · Empty trip · Light · 1280 | Screens (Light) | not started |  |
| 6 | Change Dates · Stops would move · Light · 1280 | Screens (Light) | not started |  |
| 6 | Trip builder · Add Stop popover · Light · 1280 | Screens (Light) | not started |  |
| 6 | Trip builder · No forecast · Light · 1280 | Screens (Light) | not started |  |
| 6 | Trip builder · Conflict · Light · 1280 | Screens (Light) | not started |  |
| 6 | Trip builder · Missing trip · Light · 1280 | Screens (Light) | not started |  |
| 6 | Trip builder · A stop row · Light · 1280 | Screens (Light) | not started |  |
| 6 | Trip builder · Dragging a stop · Light · 1280 | Screens (Light) | not started |  |
| 6 | Trip builder · Fetching drives · Light · 1280 | Screens (Light) | not started |  |
| 6 | Trip builder · Estimated drive · Light · 1280 | Screens (Light) | not started |  |
| 6 | Trip builder · Window missing · Light · 1280 | Screens (Light) | not started |  |
| 6 | Explore · No forecast · Light · 1280 | Screens (Light) | not started |  |
| 6 | Explore · Filtered empty · Light · 1280 | Screens (Light) | not started |  |
| 6 | Explore · Add Spot mode · Light · 1280 | Screens (Light) | not started |  |
| 6 | Explore · Apple Maps results · Light · 1280 | Screens (Light) | not started |  |
| 6 | Explore · Search found nothing · Light · 1280 | Screens (Light) | not started |  |
| 6 | Explore · Search failed · Light · 1280 | Screens (Light) | not started |  |
| 6 | Explore · Polar day, no window · Light · 1280 | Screens (Light) | not started |  |
| 6 | Explore · Scored place card · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot page · Window expanded · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot page · No forecast · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot page · Failed · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot page · Polar · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot page · User spot · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot page · Loading forecast · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot page · Explanation states · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot page · Zoomed timeline · Light · 1280 | Screens (Light) | not started |  |
| 6 | Saved · Empty · Light · 1280 | Screens (Light) | not started |  |
| 6 | Saved · No forecast · Light · 1280 | Screens (Light) | not started |  |
| 6 | Saved · Filter empty · Light · 1280 | Screens (Light) | not started |  |
| 6 | Saved · Delete confirmation · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot editor · Create · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot editor · Edit · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot editor · Lookup failed · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot editor · Looking up · Light · 1280 | Screens (Light) | not started |  |
| 6 | Spot editor · Validation errors · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · Idle · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · Running · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · Results, no forecast · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · Apple Intelligence off · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · Unavailable, device · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · Unavailable, downloading · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · No results · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · Guardrail · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · Other failures · Light · 1280 | Screens (Light) | not started |  |
| 6 | Scout · Checking the forecast · Light · 1280 | Screens (Light) | not started |  |
| 6 | Settings · General · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · Weather, not enabled · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · Weather, working · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · Weather, checking · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · Weather, failed · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · Intelligence, unavailable · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · Intelligence, device · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · Intelligence, downloading · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · Intelligence, off · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · Intelligence, ready · Light · 552 | Screens (Light) | not started |  |
| 6 | Settings · About · Light · 552 | Screens (Light) | not started |  |
| 7 | Shell · No sample banner · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | All Trips · Empty · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | All Trips · All sessions passed · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | All Trips · Import error · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | New Trip sheet · Template chosen · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | New Trip sheet · Empty trip · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Change Dates · Stops would move · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Trip builder · Add Stop popover · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Trip builder · No forecast · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Trip builder · Conflict · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Trip builder · Missing trip · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Trip builder · A stop row · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Trip builder · Dragging a stop · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Trip builder · Fetching drives · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Trip builder · Estimated drive · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Trip builder · Window missing · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Explore · No forecast · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Explore · Filtered empty · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Explore · Add Spot mode · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Explore · Apple Maps results · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Explore · Search found nothing · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Explore · Search failed · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Explore · Polar day, no window · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Explore · Scored place card · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot page · Window expanded · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot page · No forecast · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot page · Failed · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot page · Polar · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot page · User spot · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot page · Loading forecast · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot page · Explanation states · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot page · Zoomed timeline · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Saved · Empty · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Saved · No forecast · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Saved · Filter empty · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Saved · Delete confirmation · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot editor · Create · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot editor · Edit · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot editor · Lookup failed · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot editor · Looking up · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Spot editor · Validation errors · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · Idle · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · Running · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · Results, no forecast · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · Apple Intelligence off · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · Unavailable, device · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · Unavailable, downloading · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · No results · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · Guardrail · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · Other failures · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Scout · Checking the forecast · Dark · 1280 | Screens (Dark) | not started |  |
| 7 | Settings · General · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · Weather, not enabled · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · Weather, working · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · Weather, checking · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · Weather, failed · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · Intelligence, unavailable · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · Intelligence, device · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · Intelligence, downloading · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · Intelligence, off · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · Intelligence, ready · Dark · 552 | Screens (Dark) | not started |  |
| 7 | Settings · About · Dark · 552 | Screens (Dark) | not started |  |
| 8 | Shell · Default · Light · 960 | Screens (Light) | not started |  |
| 8 | Shell · No sample banner · Light · 960 | Screens (Light) | not started |  |
| 8 | Trip builder · Default · Light · 960 | Screens (Light) | not started |  |
| 8 | Trip builder · No forecast · Light · 960 | Screens (Light) | not started |  |
| 8 | Trip builder · Conflict · Light · 960 | Screens (Light) | not started |  |
| 8 | Explore · Default · Light · 960 | Screens (Light) | not started |  |
| 8 | Spot page · Sample (scored) · Light · 960 | Screens (Light) | not started |  |
| 8 | Shell · Default · Dark · 960 | Screens (Dark) | not started |  |
| 8 | Shell · No sample banner · Dark · 960 | Screens (Dark) | not started |  |
| 8 | Trip builder · Default · Dark · 960 | Screens (Dark) | not started |  |
| 8 | Trip builder · No forecast · Dark · 960 | Screens (Dark) | not started |  |
| 8 | Trip builder · Conflict · Dark · 960 | Screens (Dark) | not started |  |
| 8 | Explore · Default · Dark · 960 | Screens (Dark) | not started |  |
| 8 | Spot page · Sample (scored) · Dark · 960 | Screens (Dark) | not started |  |
| 9 | Trip builder menus | Components | not started |  |
| 9 | Share sheet | Components | not started |  |
| 9 | File importer and exporter | Components | not started |  |
| 9 | Alerts and dialogs | Components | not started |  |
| 9 | Window title bar and toolbars | Components | not started |  |
| 9 | Explore · Spot context menu · Light · 1280 | Screens (Light) | not started |  |
| 9 | Explore · Filters menu · Light · 1280 | Screens (Light) | not started |  |
| 9 | Explore · Sort menu · Light · 1280 | Screens (Light) | not started |  |
| 9 | Saved · Sort and filter menu · Light · 1280 | Screens (Light) | not started |  |
| 9 | Explore · Spot context menu · Dark · 1280 | Screens (Dark) | not started |  |
| 9 | Explore · Filters menu · Dark · 1280 | Screens (Dark) | not started |  |
| 9 | Explore · Sort menu · Dark · 1280 | Screens (Dark) | not started |  |
| 9 | Saved · Sort and filter menu · Dark · 1280 | Screens (Dark) | not started |  |
| 10 | Flows · Overview | Flows | not started |  |
| 10 | Flow · Plan a trip | Flows | not started |  |
| 10 | Flow · Explore and save | Flows | not started |  |
| 10 | Flow · Read a spot | Flows | not started |  |
| 10 | Flow · Scout | Flows | not started |  |
| 11 | Shell · Default · Notes | Screens (Light) | not started |  |
| 11 | All Trips · List · Notes | Screens (Light) | not started |  |
| 11 | All Trips · Import error · Notes | Screens (Light) | not started |  |
| 11 | New Trip sheet · Template chosen · Notes | Screens (Light) | not started |  |
| 11 | Change Dates · Stops would move · Notes | Screens (Light) | not started |  |
| 11 | Trip builder · Default · Notes | Screens (Light) | not started |  |
| 11 | Explore · Default · Notes | Screens (Light) | not started |  |
| 11 | Explore · Selected with place card · Notes | Screens (Light) | not started |  |
| 11 | Explore · Apple Maps results · Notes | Screens (Light) | not started |  |
| 11 | Explore · Polar day, no window · Notes | Screens (Light) | not started |  |
| 11 | Explore · Scored place card · Notes | Screens (Light) | not started |  |
| 11 | Saved · Empty · Notes | Screens (Light) | not started |  |
| 11 | Saved · Filter empty · Notes | Screens (Light) | not started |  |
| 11 | Saved · Delete confirmation · Notes | Screens (Light) | not started |  |
| 11 | Spot editor · Edit · Notes | Screens (Light) | not started |  |
| 11 | Spot editor · Validation errors · Notes | Screens (Light) | not started |  |
| 11 | Scout · Results · Notes | Screens (Light) | not started |  |
| 11 | Scout · Other failures · Notes | Screens (Light) | not started |  |
| 11 | Settings · General · Notes | Screens (Light) | not started |  |
| 11 | Settings · Weather, not enabled · Notes | Screens (Light) | not started |  |
| 11 | Settings · Weather, failed · Notes | Screens (Light) | not started |  |
| 12 | F04 Elevation & materials | Foundations | not started |  |
| 12 | F05 Iconography | Foundations | not started |  |
| 12 | F06 Logo & app icon | Foundations | not started |  |
<!-- END ARTBOARDS -->

## Decisions

1. **Token names.** `tokens.paper.json` was generated without the leading `--` on each name, which Paper's `create_tokens` refuses (its schema requires `^--`). Fixed in `tools/gen-tokens.mjs` (names now carry `--`; font weights and opacities are sent as numbers, as Paper documents) and regenerated. `tokens.css` is unchanged.
2. **Selection tint tokens.** Paper stored the two `color-mix(...)` token values (`--color-canvas-selection-tint`, `--color-dark-canvas-selection-tint`) as an opaque dark grey, `rgb(41 41 41)`. Set them to their resolved values instead: accent at 16 % (`rgba(217, 67, 26, 0.16)` light, `rgba(255, 138, 92, 0.16)` dark). Token aliases with plain `var(--x)` (menu highlight) stored correctly.
3. **Font lookup.** `get_font_family_info` failed twice with "Open a Paper file to use this tool" although the Iter file was open (it seems to need the file to be the foreground tab, which needs the app's UI). Fonts were checked on the canvas instead: the first artboard renders SF Pro (computed `font-family: var(--font-sans)`, screenshot shows SF Pro). New York is checked on the type-scale sample row.
4. **Token variables bind.** On the first artboard, computed styles keep `var(--color-…)`, `var(--spacing-…)`, `var(--text-…)` and `var(--font-weight-…)` as live references, and the screenshot shows the token colours. So the token build is used, not the literal build.
5. **Canvas positions.** `create_artboard` ignores `left`/`top`; the driver queues the position from `artboards/layout.json` and applies it with the first batched `update_styles`.
6. **Driver.** Added `tools/paper-driver.mjs`, which tells each worker the next call and records every node ID Paper returns, resolving parents, clone sources and override targets from real IDs. Its state is the machine record in `build-state/`.
7. **New York cannot be shown yet.** A probe artboard (since deleted) showed Paper renders only web-safe and Google fonts on this Mac: Times and Georgia work; New York (every optical size), Avenir Next, Menlo and SF Pro Rounded all fall back to the default sans. Paper's default sans here is the system font, so SF Pro text looks right. Paper evidently has no access to the Mac's local fonts in this session (the font lookup tool also refused to run). Font families were left as the token variables (`--font-serif` is `"New York", …`), so New York appears by itself once Paper can see local fonts. Tabular digits (`font-variant-numeric`) are also not applied; digits are proportional.
8. **Paper wraps some text.** A text-only element with a fixed width becomes a Frame with a Text child inside, and the Text sits at the start, so centred or right-aligned single-line text in a fixed-width cell drifted left (660 elements). A single-line centred text without a width hugs its content and sits at the start of a column (98 elements). Fixed in the generator (`tools/lib/paperfix.mjs`): the first kind gets flex justification, the second `align-self`. Both are invisible in a browser.
9. **Paper drops var() border widths.** `border: var(--spacing-stroke-hairline) solid …` lost the whole border, and `var()` inside SVG `stroke-width` / `stroke-dasharray` was ignored. The generator now writes those widths and dash lengths as their literal token values (0.5px hairlines etc.); colours stay token variables. F02 had been placed before the fix; its 45 hairlines were corrected on the canvas to the literal 0.5px values.
10. **SVGs and absolute layers.** Paper makes a layer for each shape inside an inline SVG, and lists absolutely positioned layers after their siblings. The driver accounts for both.
11. **App and docs changes applied to the sources (commit e1fae6a and the build commits).** After the app-fix lead's commits: logo and app-icon loaders use the plain First Light names in `Brand/logo/` and fail loudly instead of falling back to other artwork (F06 shows the shipped `app-icon.svg`); `cloud.slash` replaced by the real `thermometer.medium.slash` vector (LightTimeline board, Explore list panel, Spot and Explore no-forecast/failed/loading screens, F05) and its stand-in notes removed everywhere; the delete-spot dialog reads `Delete “<name>”?`, "It is also removed from N trip stops. You can undo this with Edit > Undo." and "Delete Spot"; the Explore and Scout list column is 520 at 1280 and 360 at 960, and the open-choice note and its companion artboard (Explore default · Notes) are gone, so there are now 249 artboards; notes that contradicted the corrected docs were reworded (chip widths, Best tag and in-day pins on accent/emphasis, neutral SignedBars, bookmark on the place card, date formats, no provenance tag on Apple Maps rows, sun arc not zooming). F07's sample SignedBars were coloured; they are now neutral (`text/secondary`) as the docs say. None of these artboards had been placed.
12. **Hex labels.** The sources write hex values as `&#35;D9431A` (so the colour lint does not mistake a label for a colour). The fragment builder passed that through as `&amp;#35;`, so Paper showed the entity literally on F01. Fixed in `tools/lib/dom.mjs` (numeric entities decoded) and `tools/lib/paperfix.mjs`; the F01 worker corrected six labels on the canvas, and every other placed hex label on F01 is queued for correction in its next flush.

## Differences between the canvas and the prepared sources

- Everywhere: serif text (New York) shows in the default sans, and digits are proportional (decision 7). This fixes itself once Paper can use the Mac's local fonts; nothing in the file needs editing.
- F02 Type scale: as above; otherwise matches.
- F01 Colour (partial): the Route and Map clone rows and the second Selection clone still show the text and colours of the row they were cloned from, and some hex labels show `&#35;` instead of `#`, until the queued flush runs on resume. The second Selection clone is also not yet renamed to its group name.

## Worker loop (for resuming by agent)

Per artboard: `node tools/paper-driver.mjs start <file>` → `create_artboard` with the printed args → `init <file> <id>`; then repeat `next <file>`: for a write, call `write_html` with the printed target and the HTML between the markers verbatim, then `record <file> <seq>` with every createdNodes entry as `id=name` lines on stdin; for a flush, `flush <file>`, make the printed calls, `flushed <file>`; at review, screenshot, compare with `tools/render.sh` output, targeted fixes only, `finish_working_on_nodes`, `reviewed <file> "<verdict>"`. Dark twins: `dup <file>` → `duplicate_nodes` → save `descendantIdMap` to a JSON file → `dup-record <file> <newId> <json>` → flush → review. Stop on any limit or quota message. `node tools/log-table.mjs` refreshes the tables in this log.

## Machine section: artboard → node ID (for resuming; not for reading)

File id `01M46EFK4QR1BT4YSNYVKWC5XM`. Page ids: Foundations `p-1-0`, Components `p-2-0`, Screens (Light) `p-3-0`, Screens (Dark) `p-4-0`, Flows `p-5-0`. Full node maps per artboard are in `build-state/*.json`.

<!-- BEGIN IDS -->
| Artboard | Node id | Source |
|---|---|---|
| F01 Colour | 7N-0 | foundations/F01-colour.html |
| F02 Type scale | 1-0 | foundations/F02-type-scale.html |
<!-- END IDS -->
