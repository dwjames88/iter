# Testing Iter (Mac)

How to test each layer, how to look at the Mac app without touching your data, and the checklist for what only a person can check. The iPhone and iPad side is in [TESTING-iOS.md](TESTING-iOS.md).

Script names below are the ones in `scripts/` today. If a script is renamed or removed, this page is wrong until it is updated.

## The two Mac apps

| | Real app | Render copy |
|---|---|---|
| Bundle id | `com.dwjames.iter` | `com.dwjames.iter.render` |
| Signing | Your Apple Development certificate, hardened runtime | Ad hoc, no team, no hardened runtime |
| Store | Your real library, `~/Library/Application Support/Iter/Iter.store` | In memory, or a scratch file you name. Refused inside the real folder |
| Keychain and preferences | The real ones | Throwaway. Never touches the real ones |
| Location | Asks at launch | Never asks. A fixed place, or none |
| Built by | `scripts/run.sh` (builds only; `--real` also opens it, which is the real app on the real store) | `scripts/render.sh`, `scripts/test-mac.sh`, `scripts/smoke-mac.sh` |

This split is enforced in code (`StorePlacement`), not by habit. A test or render run cannot open the real store even if given its path. Everything in the "headless" sections below uses the render copy.

**First launch of the real app on your real library** migrates the store to V5 and writes a backup first. See the first-look checklist, and the README.

## Layers

### One command for everything: `scripts/test.sh`

```
scripts/test.sh                  # package, IterUpdater, hosted Mac tests, iOS tests, in that order
scripts/test.sh --no-ios --no-mac   # skip stages: --no-package --no-updater --no-mac --no-ios
```

Every stage runs even if an earlier one fails, and the exit code is non-zero if any stage failed. Set `ITER_SCRATCH` to move the SwiftPM scratch folder. Everything it runs is headless and uses the render copy and the iOS 27.2 simulator.

### 1. The package: `swift test`

```
cd Packages/Iter
swift test                         # everything: about 2,000 tests across 16 targets
swift test --filter IterStoreTests # one target
swift test --filter IterUITests --parallel
```

Swift Testing. Pure targets (Model, Astro, Sky, Plan) test with an injected clock. The store tests open fixture stores written by the old app's code (V1, V2, V3 and a realistic V4 with folders, pins, transfer timings and drive notes) and check that every trip comes out the same, then test the backup, including an injected failure, and recovery. The sources tests run every adapter over recorded fixtures with no network. Discovery, conditions, Go and sync run on fakes: a fake model, a fake clock and a scripted location trace.

Two sets are off unless you ask:

- `ITER_LIVE=1 swift test --filter Phase4LiveTests` runs Find and Conditions against the real services. This uses the network and the real feeds, so run it by hand and sparingly. Add `ITER_LIVE_AI=1` to use Apple Intelligence on a capable Mac. `ITER_LIVE_AI=1` also enables the Foundation Models test in `IterAITests`.
- `ITER_BENCH=1 swift test --filter EngineBenchmark` times the sky engine (add `-c release` for the real numbers).

Snapshot tests in the package (`IterUITests`, `IterScreensTests`) draw offscreen. A reference PNG is recorded the first time a test runs. After that the render is compared with a small tolerance and a mismatch is reported with the folder holding the actual, reference and diff images. `ITER_SNAPSHOT_RECORD=1` re-records. References are written under `Design/snapshots/rebuild/`.

Design tokens: `scripts/tokens.sh check` exits 0 if the generated `TokenValues.swift` matches `Design/tokens.json`.

### 2. Hosted Mac tests: `scripts/test-mac.sh`

```
scripts/test-mac.sh                       # build the render copy and run all hosted Mac tests
scripts/test-mac.sh --only ShellTests     # one test class
scripts/test-mac.sh --no-build            # reuse the last build
scripts/test-mac.sh --timeout 600
```

It runs `xcodebuild build-for-testing` and then `test-without-building` on the `Iter` scheme. The scheme's test action uses the `Test` configuration, which is the render copy. The test host launches with `-IterInMemoryStore YES -IterLocation 38.39,-109.87`. The script refuses to run if the built bundle id is not the render id, kills only the processes it started, and prints a pass and fail tally. It also needs XcodeGen. The host app never takes focus under test.

These tests cover the Mac shell (windows, commands, routing, Settings, the recovery notice) and whole-window snapshots. They write PNGs to `Design/snapshots/rebuild/mac/<name>-<light|dark>.png`.

What offscreen snapshots can and cannot show: layout, text, colour and states are faithful. **System Liquid Glass, MapKit maps, web views and Metal layers do not draw** (glass comes out as a faint flat fill, maps are blank). Do not judge glass or maps from a snapshot. Those are on the first-look checklist.

### 3. Smoke launch: `scripts/smoke-mac.sh`

```
scripts/smoke-mac.sh                                                   # build, launch hidden, report
scripts/smoke-mac.sh --no-build --timeout 60
scripts/smoke-mac.sh -- -IterSeedTrip YES -IterSection trip -IterSmokeQuitAfter 8
```

It builds the render copy, launches it hidden (`open -g -j -n`, so it never comes to the front), waits for a line starting `smoke: ready` (with the trip, stop and route counts), and stops only its own process. The app's output goes to `build/smoke-mac.log`.

### 4. Renders and screenshots: `scripts/render.sh`

```
scripts/render.sh                                         # build build/render/Iter.app
scripts/render.sh --run --wait 15 -- -IterSection trips
```

`--run` launches the render copy hidden with sample data, an in-memory store and a fixed location (San Francisco) unless you pass your own. For window images use the hosted tests (`scripts/test-mac.sh`). As with snapshots, glass and maps do not draw in a hidden window.

### 5. Updater: `scripts/updater-e2e.sh`

An end-to-end check of the Mac updater, local and invisible: a local web server, two fixture apps, a throwaway key, and a second round with the wrong key that must install nothing.

### 6. iPhone and iPad

See [TESTING-iOS.md](TESTING-iOS.md). `scripts/test-ios.sh` also runs `swift test` for the package.

## Launch switches

Switches are `-Name value` pairs, parsed from the process arguments by `LaunchOptions` (they do not read saved preferences, so a stale preference cannot turn a real launch into a test launch).

### Shared by Mac and iPhone (`LaunchOptions`)

| Switch | Effect |
|---|---|
| `-IterInMemoryStore YES` | Opens an in-memory store. No file is read or written. Also honoured, as a safety, by the real app |
| `-IterStorePath <path>` | Opens a store at this path. Render copies and tests only. The real app ignores it, and any path inside the real store's folder is refused |
| `-IterSampleDataEnabled YES` | Find, Conditions and routing come from built-in sample services, not the network. Settings says sample data is on |
| `-IterLocation lat,lon` | A fixed location. No permission is ever asked |
| `-IterSection find\|trips\|places\|trip` | The section to open on |
| `-IterSeedTrip YES` | Adds the sample library. With `-IterSection trip` it opens the sample trip. Never applies to the real store |
| `-IterMapCamera lat,lon,span` | Find map: starts centred there, `span` degrees of latitude tall (zoomed out shows the night side). Only with `-IterInMemoryStore YES` |
| `-IterMapTime <ISO 8601>` | Find map: draws the night side for that instant. Only with `-IterInMemoryStore YES` |

### Mac only

| Switch | Effect |
|---|---|
| `-IterSmokeQuitAfter N` | Once the first window has loaded, print `smoke: ready ...` and quit after N seconds |

The Debug menu (Debug builds only, which include the render copy) has Seed Sample Trip, Reset All Data and Show Layout Grid. Its data actions refuse the real store.

### iPhone only (`IOSLaunchSwitches` and Go)

| Switch | Effect |
|---|---|
| `-IterTab find\|trips\|saved\|go` | The tab to open on |
| `-IterSheetDetent peek\|half\|full` | The Find sheet's starting height |
| `-IterOpenPlace first` | Opens the first place on the Find card |
| `-IterFindQuery <text>` | Runs a Find search at launch |
| `-IterFindSelect saved` | Shows the first saved place on Find's card |
| `-IterSettings root\|sources` | Opens Settings, on a pane |
| `-IterFirstRun YES\|NO` | Forces the one-time first-run guide on or off (it otherwise shows once) |
| `-IterFindQuick today\|tomorrow\|nearyou` | Runs a Today, Tomorrow or Near You quick choice on Find (iPhone and iPad only) |
| `-IterGoSampleRun YES` | Starts the sample trip at its first stop. Only with fake wiring (a fixed location or sample data) |
| `-IterD6Probe YES` | Debug builds only. The rejected "tab bar outside the sheet" layout, kept as evidence for decision D6 |

## Checking each stage by hand (render copy, sample data)

Start a hidden render copy with `scripts/render.sh --run`, or build it and open it yourself. These steps use the render copy with sample data, so they exercise screens and logic, not the real feeds.

**Find.**
1. Type a place name. Results should list with a source line each, and a score chip for the next light window.
2. Type a request such as "waterfalls near here for sunrise". Chips under the list show each source with its count or its reason ("Reddit: needs your own Reddit API access"). Without Apple Intelligence, the list says it used Basic search.
3. Pick a result. The card shows the light times, the score, the sources and links to the citations. Save it, and it appears in Saved Places.

**Conditions.**
1. Open a place. The sections show the hourly table, the sky factors with plus and minus points, the confidence, and a source line.
2. Look for the honest states: a factor with no data says so (Bortle and seeing always say "no source"), and an old forecast shows its age.
3. Refresh (Conditions ▸ Refresh, Command-R).

**Build.**
1. New Trip (Command-N), name it, set dates, add the sample spots with Add to Trip.
2. Each stop shows arrive, set-up and leave-by times in its own time zone, drive times between stops, and an issue flag when something does not fit.
3. Reorder stops, change the transfer timing between days (Morning or Evening Before), edit a drive note, Undo each (Command-Z, the menu names the action).
4. Export the trip, import it again (a copy), and check it matches.

**Go (iPhone only).** Go starts from the legs Build planned (kept in `<tripID>.legs` beside the offline pack) and works offline. With sample data it says so: Sample drive times, Sample Sky Index, "Sample" on the widget and Live Activity, and Trip Builder shows "Sample data, no offline pack". The Go map frames you, the next stop and today's stops, merges close pins into one badge, shows your own blue dot and has a recentre button.  In the simulator, start it with `-IterTab go -IterGoSampleRun YES`. The Go tab shows the next stop, leave-by, the drive time, conditions and the live sky card. Real Go behaviour (background location, notifications, Live Activity) is on the first-look checklist.

## First-look checklist

Nothing below could be checked by a headless run. Look at each one yourself, on a real Mac and a real iPhone, the first time you run the new app. Mark each as you go.

**First launch and your data**
- [ ] Before the first launch, copy `~/Library/Application Support/Iter/` somewhere safe yourself. This is your own extra backup on top of Iter's.
- [ ] Open the real Mac app. It opens your library. The trips, stops, places and folders match what you had (compare a couple of trips with the old app's screenshots or notes).
- [ ] A folder `~/Library/Application Support/Iter/Backups/pre-v5-<date>/` exists. It contains the store files, one `.iter` file per trip, and `backup.json`. The counts in `backup.json` match your library.
- [ ] Quit and reopen. It opens at once and makes no second backup folder.
- [ ] If a "your library was recovered" notice ever shows, it names the backup folder. Note what it says.
- [ ] Open one `.iter` file from the backup folder in the old app (if it is still installed), to confirm the way back works.
- [ ] Same on the iPhone: the first launch opens your library, and a backup folder exists in the app's container.

**Liquid Glass and look**
- [ ] The Mac sidebar, toolbar, place card, map controls and sheets draw as real glass (not flat fills), in light and dark.
- [ ] On the iPhone, the Find sheet sits over the map with the tab bar inside it, and the tab bar stays tappable at peek, half and full. (Evidence so far came from a non-phone simulator, so check on a real phone.)
- [ ] Text is readable over glass on a bright map and a dark map.

**Maps**
- [ ] Map pins draw on the Mac Find and Saved Places maps, with the score chips. Clusters form and open when you zoom in.
- [ ] The one-time "Move This Spot" tip shows on your own spot and does not come back after you close it.
- [ ] Your own pins never merge into a cluster, and you can drag one. The coordinates update. Undo moves it back.
- [ ] Map style (Standard, Satellite, Hybrid) changes on every map. Show Daylight draws the night side when zoomed out.
- [ ] Look Around shows on a place card where Apple has it.

**Drag and drop**
- [ ] Mac: drag a stop to reorder within a day and to another day. A drop line shows where it lands.
- [ ] Mac: drag a place into a folder in Saved Places. Drag a trip into a trip folder.
- [ ] Mac: open an `.iter` file by double-clicking it (or File ▸ Import Trip) and check it imports.
- [ ] iPhone: reorder stops in Edit mode.

**Menus and keyboard (Mac)**
- [ ] File: New Trip (Command-N), New Folder (Option-Command-N), Add Spot on Map (Shift-Command-N), Import Trip (Command-O), Export Library, Send Library to iPhone.
- [ ] Edit: Edit Place (Command-E), Find Spots (Command-F), Search Here (Shift-Command-F), Undo names the last action.
- [ ] View: Trip Builder panel (Option-Command-0).
- [ ] Go menu: Find (Command-1), Trips (Command-2), Saved Places (Command-3).
- [ ] Conditions: Refresh (Command-R). Trip: Change Dates (Shift-Command-D), Export (Shift-Command-E), Send to iPhone (Shift-Command-I).
- [ ] Learn From My Library (Settings ▸ Search, on by default) changes the order of results a little toward the kinds you save, and nothing else. Turn it off and the order returns.
- [ ] Settings: General, Search, Sources & Credits, Keys, Updates. Turning EUMETSAT or IEM on needs a relaunch of Conditions to apply, as the pane says.

**Real network sources** (the headless runs used recordings)
- [ ] Find returns real places for a US place and a non-US place. The source chips show OpenStreetMap, Wikipedia and Apple Maps with counts.
- [ ] Conditions shows a real forecast for a US place (HRRR then GFS) and a non-US place (GFS or MET Norway). Look at the source line.
- [ ] An observation from a nearby station shows its name and distance. Near a military airfield it is labelled military-origin.
- [ ] Turn Wi-Fi off. The last conditions still show, with their age, and nothing says "live".
- [ ] Settings ▸ Sources & Credits lists every source with its credit text.

**Apple Intelligence on the device**
- [ ] On a Mac or iPhone with Apple Intelligence on, a request such as "waterfalls near Yosemite" is understood and the chip says Apple Intelligence. Every result has a coordinate from a map source.
- [ ] With it off, Find says Basic search and still finds places.

**Go and the iPhone (needs a real phone)**
- [ ] Always location is asked once, with the plain explanation. Declining it leaves Go working in the foreground with a clear note.
- [ ] Start a trip. Lock the phone and drive (or walk) toward the first stop. Location keeps updating in the background (the blue pill or arrow shows).
- [ ] The Live Activity shows on the Lock Screen and the Dynamic Island, with the stop, leave-by and a countdown. Old data is never shown as live.
- [ ] Leave-soon and leave-now notifications arrive. From the Lock Screen, tap Navigate on leave-now: it opens Apple Maps. On automatic arrival, tap Not yet: it undoes the arrival.
- [ ] Time-sensitive delivery: the blueprint assumed a free team cannot use it. Note whether notifications break through a Focus.
- [ ] Kill the app during a run and reopen it. The run is still there.
- [ ] Battery: note the drain over a one-hour drive. The figures in the code are estimates.
- [ ] Widgets: add the Go widget to the Home Screen and check it matches the app.

**Sharing**
- [ ] Mac Send to iPhone (Shift-Command-I) offers AirDrop. The iPhone opens the file and the trip updates in place (a second send does not duplicate it).
- [ ] Send Library to iPhone brings over trips, places and folders.
- [ ] Export for older Iter makes a file the old app opens.

**Updates (Mac)**
- [ ] Check for Updates finds nothing when current, and a signed update installs. See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md).

## Known limits of the headless checks

- Offscreen renders cannot draw glass or maps.
- No headless run clicked, dragged, typed or pressed a key. Drag and drop, menus and keyboard are by hand.
- No headless run asked for location or notification permission, or ran in the background on a phone.
- The Live Activity and Dynamic Island were rendered as views, not seen running.
- The recorded fixtures show what the feeds looked like on the day they were recorded. Feeds change.
- The battery numbers in `LocationPolicy` are estimates.
