# Performance

This file records how Iter is measured, what the first performance-and-correctness pass found and changed, and what was left alone. Numbers come from one machine and one set of runs (below); read them as a comparison between two builds, not as a promise for any other Mac.

## How to measure

**Use a separate copy.** `scripts/render.sh` builds a copy with its own bundle id (`com.dwjames.iter.render`), signed ad hoc, so the running app and its preferences are never touched (it also keeps off the Keychain and the real store). Debug copies are built without hardened runtime so `Iter.debug.dylib` loads. Prefer Release (`scripts/render.sh --release`) for anything you quote; Debug numbers are higher (window 620 ms against 245 to 278 ms) and only useful for relative changes. Run it hidden, for example `scripts/render.sh --release --run --wait 40 -- -IterSection trip -IterSeedTrip YES -IterPerfScript YES -IterPerfQuit YES`; it adds the in-memory and sample-data switches itself and stops only the process it launched.

**Launch switches** (`AppLaunch`; the full list is in ARCHITECTURE.md and TESTING.md). A repeatable run uses:

* `-IterInMemoryStore YES` so no on-disk store is opened, and `-IterSampleDataEnabled YES` so forecasts come from the sample service rather than the network.
* `-IterSection explore|trip` to open on a section, `-IterSeedTrip YES` to add the 4-day Canyon Country sample trip (`trip` opens it), and `-IterLocation lat,lon` to fix the location behind Near You.
* `-IterPerfScript YES` to run a fixed workload: on Explore, wait for scores, pan and zoom the map, hover pins and select five; on `trip`, `TripPerfScript` (switch days, select stops, nudge a stop, move a stop to another day, then sit idle for 10 seconds).
* `-IterPerfQuit YES` to quit when the script ends, and `-IterPerfProbe YES` to log every counter every 5 seconds.

**Reading the log.** `IterPerf` logs milestones and counters under subsystem `com.dwjames.iter`, category `perf`, with milliseconds since launch, and as signposts:

```
log stream --predicate 'subsystem == "com.dwjames.iter" AND category == "perf"'
```

`IterPerf.step` wraps one scripted interaction and reports two times. **Sync** is the mutation itself, on the main thread, until the call returns. **Settle** is the time until the main queue has turned twice after it, which includes the SwiftUI update and the MapKit and Core Animation work that follows. **Lag** comes from a main-thread monitor that probes every 5 ms and reports how late each probe ran; a long lag is a stall the user could see. The counters (recomputes, `DayLight` computations, row bodies, forecast revision bumps, drive requests) show whether work happened at all, which is what an idle check needs.

**Time Profiler.** Attach to the running copy and record the script:

```
xctrace record --template 'Time Profiler' --attach <pid> --output run.trace
```

Symbolicate with the build's dSYM and read main-thread samples only (1 ms each). Idle CPU and memory were read with `top -l 4 -s 5` on the pid, 25 seconds after launch, with the window hidden.

**Package benchmarks.** `ITER_BENCH=1 swift test` in `Packages/IterKit` runs the engine and weather-parsing benchmarks and prints microseconds per call. `TripBuilderPerfTests` and `ExplorePerfTests` pin the model counters below, so a regression in redraw or recompute counts fails a test instead of needing a profile.

## Method for the tables

Headless runs of a copy re-stamped with its own bundle id and ad-hoc signed, launched hidden, in-memory store, sample weather, fixed location, window 1280x820, on a MacBook Pro with macOS 27. "Before" is `main` plus only the instrumentation commit; "after" is the branch `perf/pass-1`. Release build unless stated. Each figure is the median of 3 interleaved runs.

## Results

### Launch (Explore, Release)

| Milestone | Before | After |
|---|---|---|
| Window appears | 278 ms | 245 ms |
| First Explore map created | 454 ms | 413 ms |
| All 31 rows scored | 896 ms | 833 ms |
| Trip map first settles (seeded trip) | 431 ms | 422 ms |

One Debug run before the change: window 620 ms, map 848 ms, all scored 1407 ms.

### Trip planner (seeded 4-day Canyon Country trip, 6 stops, 5 legs; Release)

| Interaction | Before, sync / settle | After, sync / settle |
|---|---|---|
| Switch day (n=30) | 0.6 / 87 ms | 0.6 / 75 ms |
| Select a stop (n=18) | 0.3 / 124 ms | 0.3 / 115 ms |
| Nudge a stop (n=6) | 43 / 148 ms | 21 / 111 ms |
| Move a stop to another day (n=6) | 31 / 118 ms | 28 / 125 ms |

Debug nudge sync: 72 ms before, 33 ms after.

App-code main-thread time over the whole trip script (Time Profiler, Release, about 45 s): 758 ms before, 523 ms after the model and map changes, and about 5 ms per select or day interaction after the export and inflection fixes (`StopRowView` about 36 ms over 7 selects). Before, `TripBuilderContent.body` cost 374 ms over the script: 207 ms was the toolbar building the whole `.iter` export (`IterStore.document(for:)`, 167 ms) on every body pass, and `OverviewCellView.accessibilityText` (an inflected "N stops" through `AttributedString(localized:... inflect: true)`) cost 158 ms. Both are gone from the profile.

Model counters (`TripBuilderPerfTests`): recomputes per load 6 to 2, `dayLight` computations 36 to 6, time to load all legs with fake drives 127 to 18 ms. MapKit directions requests: 5 for the trip, 2 to 3 more for a nudge to new pairs, none for moving back (the cache answers), and never a refetch of a known pair.

### Explore (Release; script: camera moves, hover, 5 selects)

| Measure | Before | After |
|---|---|---|
| Main-thread time over the script | 3.69 s | 2.95 s |
| App code within it | 297 ms | 289 ms |
| Forecast revision bumps for a 31-place fan-out | 31 | 1 |
| `row.body` evaluations across hover | re-evaluated by hover | stays at 78 |
| Camera step settle (median) | about 52 ms | about 52 ms |
| Select a place (opens the light panel), settle | about 230 ms | about 230 ms |

The largest app cost before was `EventScore.measure` (text measuring per pin per body, about 44 ms), gone with memoised widths. Hover now builds rows 0 times (pinned by a test). Camera and selection settle are MapKit and SwiftUI view-tree work; the app code inside the select is about 25 ms (`SpotModel`, `LightEngine`).

### Idle

Explore and the trip planner both use 0.0% CPU before and after. Memory: Explore 107 to 106 MB, trip 115 to 114 MB. During the trip script's 10-second idle phase every counter stays flat: no redraw, no recompute.

### Engine (`ITER_BENCH=1`, microseconds per call, Debug / Release)

| Call | Before | After |
|---|---|---|
| `nextEvent`, no forecast | 1137 / 237 | 456 / 143 |
| `nextEvent`, 8-day forecast | 856 / 240 | 495 / 145 |
| `dayLight` | 2352 / 307 | 1927 / 303 |
| Outlook, per day | 2379 / 308 | 1743 / 257 |

Forecast parsing is cheap: about 0.8 ms for the OpenWeather fixtures, 1.6 ms for Windy, about 1 ms to decode the disk cache (Debug). It runs off the main actor, which a test pins.

## What changed, and why

**Trip builder model.** One `DayLight` is computed per stop per refresh and reused while the spot, day and forecast are unchanged (clock within 60 seconds); the scheduler takes those session windows instead of solving them again. Legs already in the drive cache or an offline pack are taken synchronously (`DriveTimeProviding.cachedLeg(from:to:)`, default nil) before the first recompute, and legs arriving within 60 ms cause one recompute, not one each. The route map draws a precomputed `TripMapContent` (legs with paths, pins, day switcher) that changes only with the geometry, keeps each leg's `CLLocationCoordinate2D` values until its path changes, and requests one camera move per day switch. A transient drive error (throttling, offline) is no longer stored as a straight-line estimate; only "no route" is final.

**Trip builder view.** The `.iter` export is built only when exporting or sharing (`LazyTripDocument`, same type and file name as `TripDocument`), on Mac and iOS. The body no longer fetches the trip record; inflected counts and the overview cell's VoiceOver text are cached; the header formats its strings once.

**Explore.** Event-unit widths are memoised, rows and pins are `Equatable` and drawn with `.equatable()`, and the list no longer reads `hoveredID`. The spot panel's caches are keyed by that spot's forecast, not the global revision. Image jobs are cancelled when the last view waiting for them goes, and disk images are decoded off the main thread.

**Forecasts.** `ForecastCenter` coalesces results (a 40 ms window; the last fetch of a batch applies at once) and does not bump `revision` for an unchanged result, so one fan-out re-runs the trip builder and Explore once. A forced request joins a fetch already running. A provider that throws `CancellationError` on its own no longer leaves a place loading for good.

**Engine and store.** `nextEvent` skips the unused next-day sun, and outlook days solve each sun once. `IterStore.savedPlaces` and `pinnedTrips` filter with predicates in the store. Pinned-trip downloads encode PNGs and write the pack off the main actor (`@concurrent`).

**Instrumentation.** The `IterPerf` lag monitor, `IterPerf.step`, drive request counters, `TripPerfScript` and the Explore script's lag and step reports stay in the app so any later change can be measured the same way.

## Correctness fixes found on the way

Each has a regression test. OpenWeather daily summaries were an hour off after a clock change inside the 8-day window (one `timezone_offset` was used for every day). An OpenWeather 200 response with no hours surfaced as "MappingError" instead of "The response had no forecast data". A stale forecast saved under the current hour's file name was served as fresh for up to 2 hours (the cache now uses the forecast's own `fetchedAt`). Explore's map did not move to an Apple Maps result after the user had moved it. Stepping away from a place and back showed an empty image strip once jobs were cancellable. An interrupted first-launch move of the library could skip the offline packs and forecast cache or leave a truncated file. `LocalDay(iso: "2026-02-30")` rolled into March, and `Coordinate.cacheKey` gave two keys for one cell either side of zero. See CHANGELOG.md for the user-facing wording.

## Audited and found correct

Light windows across clock changes (Los Angeles, London, Sydney, Auckland), polar day and night (Tromsø, Longyearbyen), the spot's zone rather than the device's, and the date line; USNO almanac times for 3 dates at 5 places within 1.5 minutes (moon 3 minutes); score composition and confidence limits; the next-event rule and persistence; MapKit directions volume (one request per pair, joined, with no departure date so the pair key is right); the scheduler across zones, clock changes and polar days; schema V1 to V2 (lossless, idempotent) and the CloudKit rules; updater version comparison including build numbers, and signature checks; Ask grounding (only registry IDs, names and coordinates); the camera policy (25-mile selection, no automatic zoom-out past the cap); the Near You radius (inclusive), Popular and the no-location fallback; provider units, cache rules, call budget, key order and trimming.

## Package test counts

Before the pass: 645 tests (165 + 69 + 299 + 22 + 67 + 6 + 17 across the package targets). After: 808 tests (212 + 110 + 347 + 22 + 75 + 23 + 19), plus 86 in IterUpdater and 68 in the iOS app tests.

## Pass 2: trip builder

Same method as above (Release, re-stamped copy, in-memory store, sample weather, 1280x820, median of 3 interleaved runs, MapKit directions live). "Before" is the tree at the start of the pass, "after" is the branch. `TripPerfScript` gained a drag-reorder step (a drop before the first stop, and back), run through the same call the list's drop handler makes.

| Interaction | Before, sync / settle | After, sync / settle |
|---|---|---|
| Switch day (n=10 per run) | 0.1 / 44 ms | 0.1 / 26 ms |
| Select a stop (n=6) | 0.1 / 75 ms | 0.1 / 36 ms |
| Deselect | 0.0 / 45 ms | 0.1 / 25 ms |
| Nudge a stop down, up | 10 / 82, 8 / 71 ms | 11 / 57, 13 / 63 ms |
| Drag-reorder (drop), restore | not scripted | 15 / 78, 8 / 51 ms |
| Move to another day, back | 12 / 63, 11 / 64 ms | 8 / 50, 8 / 43 ms |

Main-thread lag while each phase ran (the sum of every probe that ran late, "blocked"): days 309 to 98 ms, selects 354 to 73 ms, nudges 71 to 73 ms, moves 90 to 46 ms. The worst single stall in each phase was 59 to 85 ms before and 32 to 57 ms after. Counters over the whole script: map body evaluations 124 to 65 (with two more interactions in the after script), camera settles 32 to 22, map camera requests that were answered with a second animated move after the first (`trip.camera.reapply`): 9 in the day phase and 4 in the select phase alone before, 0 after the first good settle. Idle: every counter stays flat for the 10 seconds in both.

Time Profiler, main thread, whole interaction part of the script: 8.3 s before, 7.9 s after, with two more interactions in the after run. About half of both is MapKit's own frame work on the main thread (`md::`, 4.1 s to 3.9 s) and a quarter Core Animation commits; SwiftUI view-graph updates fell from 1.8 s to 1.6 s. The map renders on the main thread while the camera animates, so a day switch costs about 400 ms of main-thread time however well the app code behaves; what changed is that it is paid once per switch and not once or twice.

### What was slow or glitchy, and why

1. **The camera moved twice per fit.** The map reports the camera it shows; MapKit frames a requested region inside the safe area (the card, the toolbar), so the settled region never matched the request closely enough and `MapCameraPolicy` answered with a re-request, a second animated move after nearly every day switch. After the first good settle the trip builder now keeps a missed settle as it is. A re-request before it (MapKit's default camera ahead of layout) is kept.
2. **Selecting a stop refitted the map.** A click made its day the focus day, which fitted the camera to that day and animated the map away from where the user left it, then panned to the pin as well. A selection now moves the highlight and the focus day only (`setFocusDay(_, refit: false)`) and pans only if the pin is out of view; `contentChanged()` acts only when the coordinates it would frame differ from the last ones framed.
3. **One body for everything.** `selection` and `selectedDay` were `@State` in the screen's root view, so choosing a stop re-evaluated the header, the day strip, the list (building every row's value) and the map (every polyline and pin). They now live in `TripViewState`, an `@Observable` read property by property by the list, the map and the strip, and the corner buttons, header and card are not touched by a selection.
4. **Rows and pins were not diffable.** Plan rows and map pins are now `Equatable` views drawn with `.equatable()`: a row is rebuilt only when its own value (or whether its day is the selected one) changes. The layout, days and suggestions are published only when they differ, so a recompute that changes nothing invalidates nothing (`layoutPublishCount`).
5. **Drag state invalidated the list.** `dropSpot` was `@State` on the list with `.animation(.default, value: dropSpot)`, so every row crossed during a drag re-evaluated the whole list inside an animation. It is now a `TripDropCoordinator` read only by the drop-line overlays; the indicator is an accent line with a round end across the top of the row the stop lands before, and the animation is gone.
6. **Route overlay weight.** A drive's road path has a vertex every few metres; every day switch restyles the polylines. The drawn copy is thinned with Douglas-Peucker to about 25 m (`PathSimplifier`); the full path stays in the drive leg.
7. **Not changed.** Store edits (nudge, move, drop) still save synchronously on the main actor, 8 to 15 ms (see "What is left"): moving the save off the interaction path would make an edit that the app reports as done not yet durable, and the settle after an edit is dominated by SwiftUI and MapKit work, not the save. Drag-reorder across days stays on `draggable` and `dropDestination`: `onMove` cannot move a row between day containers.

Pinned by tests (`TripBuilderPerfTests`): a selection issues no camera request, repeated `contentChanged()` for the same framing is free, an identical recompute publishes no layout, a missed settle after the first good one is not asked again, and the drawn route is thinned but keeps its ends.

## Pass 3: window resize

**Method.** `-IterResizeScript 1100,1800` steps the window's width across the range and back (176 steps of 8 pt, one about every 16 ms, `setFrame(display: true)`). Each step now records two times with `StepStats`: **sync**, until `setFrame` returns (layout and display of the window), and **total**, which adds two turns of the main queue and is what the next step waits behind. The script prints median, p90 and max for both, and the counters for the sweep (`root.body`, `panel.body`, `trip.mapBody`, `map.paneBody` and so on), to stdout and to the log (`perf resize step ...`). Release re-stamped copy, hidden, in-memory store, sample weather, 1280x820 start, median of 3 runs of the per-run median, p90 and max. "Before" is `main` with only the timing added; the trip planner row after is on the adaptive card (`PlannerCardLayout`), and the same tree without this pass measured 63 / 72 / 120 ms. The screens: trip planner (`-IterSeedTrip YES -IterSection trip`), All Trips (`-IterSeedLibrary YES -IterSection trips`), Explore (`-IterSection explore -IterLocation 37.77,-122.42`), Locations (`-IterSeedLibrary YES -IterSection locations`). The script now finds the window of a hidden (`open -j`) launch too. Round 2 brackets the sweep with the window's `willStartLiveResize` and `didEndLiveResize` notifications, as a drag on the window's edge sends them (`-IterResizeLive NO` gives the raw steps).

| Screen | Before | After, round 1 (raw `setFrame` steps) | After, round 2 (sweep as a live resize) |
|---|---|---|---|
| Trip planner | 62 / 81 / 107 ms | 38 / 44 / 71 ms | 25 / 27 / 48 ms |
| All Trips | 23 / 28 / 48 ms | 15 / 16 / 55 ms | 20 / 22 / 42 ms |
| Explore | 48 / 52 / 96 ms | 28 / 32 / 75 ms | 37 / 43 / 49 ms |
| Locations | 31 / 33 / 49 ms | 17 / 20 / 39 ms | 21 / 24 / 32 ms |

Median / p90 / max per step (total). The round 2 column was measured while other builds were running on the machine (load average above 16), and a quiet run of the same build gave 19 ms for the trip planner (21 ms p90), 16 ms for All Trips, 28 ms for Explore and 18 ms for Locations; read the round 1 and round 2 columns as the same level of performance for All Trips, Explore and Locations, and the quiet figures as the better estimate of this build. The raw `setFrame` figure for the same build (`-IterResizeLive NO`, no live-resize bracket) is 42 / 51 / 79 ms for the trip planner and, for the other three screens (where nothing is held during a live resize), 18 / 24 / 41 ms for All Trips, 33 / 36 / 50 ms for Explore and 20 / 26 / 37 ms for Locations.

**Where the time went.** Time Profiler on the main thread (symbolicated against the dSYM): app code is a few percent of every sweep; the rest is SwiftUI's `NSHostingView.layout`, the attribute graph and MapKit's own frame work. So the lever was how often app state made SwiftUI and MapKit redo that work:

1. **The window width was state in `RootView`.** `MainWindowConfigurator` wrote the raw content width to `@State` on every resize notification, only so the sidebar-collapse rule could compare it with one threshold. Every step re-evaluated the whole window (sidebar and detail). It now publishes only whether the window is narrower than the threshold (`windowIsNarrow`), so it writes state when the rule's answer changes.
2. **`FloatingPanelLayout` wrote the pane width per step** for Explore and Locations, where the card is docked and its width only depends on the window below `panelWidth + 2 x margin + detailMin` (about 800 pt). The measure is capped there, so a wide window writes nothing. This also removed one body evaluation of the map pane per step.
3. **Map panes took their size per step.** Explore pushed the size to the model for clustering and Locations kept it in state, only to know a pane had a size. Locations now keeps the first size only; Explore passes later sizes to the model once the resize has been still for 120 ms (`TrailingDebouncer`).
4. **The trip map re-framed the camera every step.** The pane size change re-applied the model's camera request (`trip.cameraRequestApplied` 174 per sweep), and the card's changing edge changed the map's safe area each step. The map now takes the new size and insets together once the resize has been still, then re-applies the framing once. The card keeps its width rules; only what the map is told lags by 120 ms.

**Pinned by tests.** `TrailingDebouncerTests` (a burst of 50 calls runs the last one once, a cancelled action never runs, spaced calls each run) and `StepStatsTests` (nearest-rank median, p90 and max). The counters in the script's output are the check for "no state per step": `root.body` and `trips.body` stay at 0 for a sweep, `map.paneBody` and `panel.body` fell as above, `trip.cameraRequestApplied` is 0.

**Round 2: the planner card holds still during a live resize.** `LiveResize` (one `@Observable` flag, written twice per drag by `MainWindowConfigurator` from the window's notifications) tells `FloatingPanelLayout` to keep the planner card's width and mode, and with them the map's safe-area insets, while the window is dragged; the newest measure is applied once at the end with a 0.25 s animation (`PlannerCardLayout`'s rules are unchanged for the settled state). The card may overlap the map more for the length of a drag. Per sweep, `panel.body` went from 174 to 2, the trip map's body from 366 to 194 and the card's list is not laid out per step. The trip planner went from 38 to about 20 to 25 ms per step; the raw `setFrame` sweep of the same build is unchanged at about 42 ms, so the gain comes from the hold and a real drag will see it, while the script without the bracket will not.

**Which screens meet 16 ms.** All Trips (about 15 to 16 ms on a quiet machine) and, within noise, Locations (17 to 18 ms) are at or just over the target; the trip planner (19 to 25 ms) and Explore (28 ms) are not. What is left in them is not app code: the sweep is dominated by `NSWindow` layout of the hosting view and by MapKit, which settles its camera about twice per step (`trip.cameraSettle` 348 for 176 steps) and writes `position` back, so the map pane's body runs once per step on both map screens (`map.paneBody` 176 in Explore). The Time Profiler shows the Explore pins' annotation closures rebuilding on each of those (about 8 % of the main thread), and the rest is SwiftUI and MapKit frame work. Removing the size and origin probes did not change the count, so it is the map's own camera write. Holding the map still during a drag (a snapshot of the map frozen under the card) would remove it but changes what the user sees, and was not done.

**Left.** An actual mouse drag was not run (the notifications are the same ones it sends). Locations evaluates `savedEvent(for:)` for every pin whenever the map body runs, and an All Trips card re-evaluates `TripNextLine` when the grid re-measures; neither is per step now.

## What is left

* **Light panel open in Explore** settles in about 230 ms, almost all SwiftUI building the panel's view tree. Cutting it needs the panel restructured; not done.
* **Store edits** (move, nudge) take undo snapshots and a synchronous SwiftData save on the main actor, about 15 to 22 ms per move. Deferring the save would change durability, so it is left as is.
* **Offline pack load at launch** reads pack JSON and images on the main actor; this only costs anything with pinned trips.
* **Transient drive errors** (throttled, offline) are retried by a backoff timer while the trip builder is on screen: 30 s after the first failing pass, then 60, 120, 240 and 300 s (`DriveRetryBackoff`), one backoff per builder. A pass that fetches everything it asked for, or any change to the trip's legs, resets it; leaving the screen cancels the timer and returning resumes it. A manual refresh before the wait is over does not ask again.
* **`ForecastCenter` coalescing window** (40 ms) is a judgement call; it is an init parameter.
* **Engine edges that are design choices:** no golden evening at Tromsø around 16 to 18 May (the sun dips but does not set); no evening blue hour at Anchorage in early June when civil dusk is after midnight; `nextEvent` is nil at Longyearbyen in midwinter.
* **Documented rules that read oddly:** a denied Keychain read shows "needs key" rather than its own error.
