# Architecture

How Iter is built, as it stands on this branch. The plan it was built from is [docs/rebuild/BLUEPRINT.md](rebuild/BLUEPRINT.md), which is kept as the record and is not edited. Where the build differs from the plan, this page says so.

Iter is one flow on two platforms:

1. **Find.** Search and AI discovery of photo spots.
2. **Conditions.** Weather and sky for each spot.
3. **Build.** A trip builder.
4. **Go.** An iPhone trip mode with ETA, leave-by times, current weather, a short forecast and a live sky index.

It is Swift 6 with complete concurrency checking and `ExistentialAny`, SwiftUI, SwiftData, MapKit and on-device Foundation Models. There is no third-party code. XcodeGen makes the Xcode project and is a developer tool only.

## Layout

```
Packages/Iter/         the package: everything that is not a platform shell (16 library targets, one tool)
Packages/IterUpdater/  the Mac updater and the iter-release tool (Mac only)
Mac/                   Mac app shell: scenes, windows, commands, sidebar, Settings, updater screens
iOS/                   iPhone and iPad shell: tabs, iPad split view, Go tab, sharing, Settings
Widgets/               iOS widget extension: Live Activity, Dynamic Island, Lock Screen and Home widgets
Tests/Hosted/{Mac,iOS} tests that must run inside an app (snapshots of whole windows, shell and wiring)
Design/                tokens.json (source of truth), GLASS-RULES.md, FIGMA-MAP.md, snapshots
Brand/                 logo files and palette
docs/                  these documents; docs/rebuild/ is the record of the rebuild
scripts/               build, test, render and release scripts
project.yml            XcodeGen spec for the Mac app and its tests (includes project-ios.yml)
project-ios.yml        XcodeGen spec for the iOS app, the widget extension and the iOS tests
```

There are no shared-folder exclude lists. Every view used by both apps lives in `IterUI` or `IterScreens` in the package. The app folders hold only platform shells. `Legacy/` (the old package) and the old `App/` and `AppiOS/` folders are being deleted in the cut-over.

## The package: 16 targets

Verified against `Packages/Iter/Package.swift`. "Depends on" lists direct dependencies only.

| Target | Depends on | What it holds |
|---|---|---|
| `IterModel` | nothing | Pure value types: coordinates, regions, local days, places, trips, stops, legs, light windows. Provenance (`SourceID`, `SourceTier`, `Provenance`, `Sourced<T>`, `DataState<T>`, `NoDataReason`). Weather fields (all optional). Discovery candidates and citations. The coordinate parser. Foundation only |
| `IterAstro` | Model | Sun, moon and galactic-centre positions and events. Pure |
| `IterSky` | Model, Astro | Light-window geometry, the Forecast Sky Index, the Live Sky Index, terrain horizon effects, confidence and staleness. Pure |
| `IterPlan` | Model, Sky, Astro | The scheduler (backward schedule, dwell, start points, issues, light-first order), the live schedule, offline ETA, alarm plan, conditions alert rule, day layout and builder rows. Pure |
| `IterStore` | Model | SwiftData: frozen schemas V1 to V4, V5, the migration plan, store locations, backup before migration, recovery, repositories with named undo, the `.iter` v1 and v2 files and the merge planner, the curated catalogue |
| `IterSources` | Model | Provider protocols, the source registry and catalogue, the cache, HTTP with per-host spacing, the rate limiter, the Keychain key vault, attribution text. No concrete network adapters |
| `IterSourcesLive` | Model, Sources | The concrete adapters (MapKit and the feeds) each with a pure `Mapping`, plus own decoders: GRIB2 simple packing, Terrarium PNG, the World Magnetic Model, MGRS |
| `IterAI` | Model | Foundation Models behind a fakeable `LanguageModeling` protocol. Weak-linked in one place |
| `IterDiscovery` | Model, Sources, AI | The Find pipeline |
| `IterConditions` | Model, Sources, Sky, Astro | The conditions service (an actor), the composite forecast, observations, nowcast, sky inputs, offline packs |
| `IterGo` | Model, Plan, Conditions, Sources, Sky, GoActivity | The trip-mode engine: run state machine, live location, ETA refresh, conditions loop, notification planner, snapshot writer |
| `IterGoActivity` | Model | The Live Activity attributes and content, and `GoSnapshot`, the value the widget reads from the App Group. Small on purpose |
| `IterSync` | Model, Store | **A placeholder.** See "Sync" below |
| `IterUI` | Model | Design tokens (generated from `tokens.json`), colours, fonts, the score ramp, the Figma components, glass controls, text phrasing. SwiftUI |
| `IterFeatures` | Model, Astro, Sky, Plan, Store, Sources, SourcesLive, AI, Discovery, Conditions, Go, Sync | One `@MainActor @Observable` model per stage (`FindModel`, `ConditionsModel`, `BuildModel`, `GoModel`), plus `LibraryModel`, `SettingsModel`, preferences, launch options and the composition root (`AppContainer`). Does not depend on `IterUI` |
| `IterScreens` | Features, UI | Shared SwiftUI screens and sections for both apps: Find, Conditions, Build, Go, Library, maps, the iPhone compositions |
| `iter-tokens` (tool) | UI | Exports and imports `Design/tokens.json` and the asset-catalogue colours |

Each library has a test target of the same name with `Tests` added.

### Dependency graph

```
IterModel ─┬─ IterAstro ── IterSky ── IterPlan
           ├─ IterStore ── IterSync (placeholder)
           ├─ IterSources ── IterSourcesLive
           │      ├── IterDiscovery  (also needs IterAI)
           │      └── IterConditions (also needs IterSky, IterAstro)
           ├─ IterAI
           ├─ IterGoActivity
           ├─ IterGo (needs Plan, Conditions, Sources, Sky, GoActivity)
           └─ IterUI
IterFeatures ◄── everything above except IterUI and IterGoActivity
IterScreens  ◄── IterFeatures, IterUI
```

Rules the structure enforces:

- Pure targets (Model, Astro, Sky, Plan) do no I/O and never read the clock. A clock is passed in.
- Concrete network adapters live only in `IterSourcesLive` and are built only in `AppContainer+Live.swift`.
- View models never touch `ModelContext`. Only `IterStore` does.
- The widget extension reads the App Group snapshot only. It never opens the store.

## App shells

| Shell | Target and bundle id | What it holds |
|---|---|---|
| Mac | `Iter`, `com.dwjames.iter` | `Mac/Sources`: app and window shell, sidebar (Find, Trips, Saved Places), detail routing, menu commands, Settings (General, Search, Sources & Credits, Keys, Updates), the Send to iPhone commands, the recovery notice, and the updater screens over `IterUpdater`. Not sandboxed. Entitlements: network client, user-selected files, location |
| iPhone and iPad | `Iter iOS`, `com.dwjames.iter.ios` | `iOS/Sources`: the phone shell (one always-present system sheet over the map with the tab bar inside it: Find, Trips, Saved, Go; decision D6 in Design/GLASS-RULES.md), the iPad split view, the Go tab and its controller, sharing and import, Settings. Entitlement: App Group `group.com.dwjames.iter` |
| Widget extension | `IterWidgets`, `com.dwjames.iter.ios.widgets` | `Widgets/Sources`: the Live Activity, Dynamic Island, Lock Screen and Home widgets. Their views are plain SwiftUI values-in views, and the same files are compiled into the iOS app so the hosted tests can render them. App Group entitlement |
| Render copy | the Mac app built as `com.dwjames.iter.render` | The same Mac app, ad hoc signed, that tests and renders use. It can never touch the real store or Keychain. See "Concurrency and safety" |

There is no Mac widget, no share extension and no CarPlay target. Go is iPhone only. The bundle ids of both real apps are the ones the old app used, so the stores and Keychain items keep matching.

## The store and migration

SwiftData holds the library: places, trips, stops, folders, trip runs, stop visits, deletion tombstones and sync-peer records. Forecasts, observations and other fetched data are not in SwiftData. They are cache files.

**Schemas.** V1 to V4 are the old app's schemas, copied unchanged into `IterStore/Schema/Legacy/` and frozen. V5 is the rebuild's. The live models keep the class names `PlaceRecord`, `TripRecord`, `StopRecord` and `FolderRecord`, so SwiftData sees one store evolving, not a delete and an insert. The migration plan has four lightweight stages, V1 to V2 to V3 to V4 to V5. V5 only adds optional or defaulted fields and new models, which keeps it in the kind of migration SwiftData has already done for this store three times.

**What V5 adds.** Place provenance (sources, citations, verification state, discovered date, a cached horizon profile); stop dwell, fixed arrival and kind (light, lodging, waypoint); the trip's start place; and the models `TripRunRecord`, `StopVisitRecord`, `DeletionRecord` and `SyncPeerRecord`.

**Where the files are.**

| | Store | Backups |
|---|---|---|
| Mac | `~/Library/Application Support/Iter/Iter.store` (the one-time copy out of the old sandbox container runs first, if the store is missing) | `~/Library/Application Support/Iter/Backups/` |
| iPhone | `default.store` in the app's own Application Support folder (an explicit URL, so a later SwiftData change cannot move it). No App Group | `Iter/Backups/` under the app's Application Support folder |

Offline packs for pinned trips go beside the store in `OfflinePacks/`. The source cache goes in `Caches/Iter/Sources`, and only for the real store.

**Opening the store (`StoreOpener`).** In order:

1. If a recovery manifest (`store-manifest.json`) names an existing store, open that one. It is never recovered twice.
2. If there is no store file, make a fresh V5 store. No backup.
3. Read the store's schema version from its metadata, on a scratch copy, without opening it with SwiftData. If it is already V5, open it. No backup.
4. If it is older, make the backup first (below). If the backup fails, remove the partial backup, report the error and do not open the store. The real store is untouched.
5. Open the real store with the full V1 to V5 plan. If that throws, make a new empty V5 store under a different name (`Iter-recovered-<date>.store`), import the backup's `.iter` files into it, write the manifest, and show a one-time notice with the backup folder. The original file is never deleted, moved or overwritten.
6. After every successful open, the idempotent folder flattening runs.

**The backup.** `Backups/pre-v5-<yyyy-MM-dd-HHmmss>/` holds: the raw store files (`Iter.store`, `-wal`, `-shm`, the external-data folder), copied through temporary names and size-checked; every trip as an `.iter` v1 file, read from a scratch copy through the frozen V4 classes; and `backup.json` with the counts. A `.migration-pending` marker file is in the folder while it is being written and removed last, so a folder that still has it is incomplete.

**After the first V5 open the old app cannot open the store.** This is by design and is why the backup exists. The `.iter` v1 files in the backup open in the old app.

## Sources layer

`IterSources` defines what a provider is, and `IterSourcesLive` supplies the adapters. The registry (`SourceRegistry`) picks providers for a kind of data at a place: enabled, covering the point, keyed if it needs a key, best tier first, then by rank within the tier. It can also say why a source was dropped (outside coverage, needs a key, switched off).

- `SourceCatalogue` is the one table of every source: tier, coverage, rate policy, cache lifetime, licence, default on or off. [DATA-PROVIDERS.md](DATA-PROVIDERS.md) lists it all.
- `SourceHTTP` sends requests with the app-name-and-version User-Agent, per-host spacing and concurrency, an optional per-minute cap, retries with backoff and jitter, conditional requests (`ETag`, `If-Modified-Since`) and MET Norway's `Expires` rule.
- `SourceCache` keeps values in memory and on disk with a time-to-live and stale-while-revalidate, and does not write to disk what a licence forbids keeping.
- `KeyVault` keeps optional keys in the Keychain.
- Every result is a `Sourced<T>` with provenance, or a `DataState` that says fresh, stale with an age, or none with a reason.

## Discovery pipeline (Find)

`IterDiscovery`'s `DiscoveryEngine` turns a typed search into a ranked, cited list of places and streams events as it goes:

1. **Query plan.** With Apple Intelligence available, the model reads the text into a plan (what, where, when). Without it, or if it fails, a deterministic parser (`BasicQueryParser`) takes over, so a search always works. The app says when it fell back to "Basic search".
2. **Area.** The area is resolved to a real place and, where one exists, its real outline from OpenStreetMap (parks, protected areas).
3. **Fan-out.** Every provider that applies runs at once as structured tasks: Apple Maps search and points of interest, Overpass features, USGS names, Wikipedia, Wikivoyage, Commons photos. A source that fails or is off becomes a status chip. It never fails the search.
4. **Extraction.** The model may pull place names out of the text evidence. It never supplies a coordinate.
5. **Verification.** Every candidate gets its coordinate from a geocoder or a gazetteer and must fall inside the area. Anything else is dropped. This is the grounding rule: no result has a model-made coordinate, and the tests assert it.
6. **Merge, rank, explain, cite.** Candidates from different sources are merged by name and distance, ranked (popular, unique or mixed, with a small boost for kinds you save, if "Learn From My Library" is on), and given a short explanation and citation links.

Cancelling the search cancels every provider and model call. Reddit and Google appear in the chips as unavailable, with the reason.

## The sky index

Both indexes score a shooting window from 0 to 100 with the same scorer, so the two numbers can be compared. Each factor is used only when its input is present. A missing input is dropped and the screen says so. Every added curve beyond the old ones is a first guess pending calibration against real shoots.

- **Forecast Sky Index** (`ForecastSkyIndex`). A baseline of 60 plus signed factor points, an overcast ceiling on daytime windows, then a clamp to 0 to 100. Factors: cloud colour and low-cloud block (golden, blue hour) or total cloud (night); precipitation; visibility; moon (night); aerosol or smoke; terrain (the fraction of the window lost behind the skyline); humidity and wind; the Milky Way core being up in the dark; and, only if supplied, Bortle class and seeing. Aurora and fog are flags, not points. No source supplies Bortle or seeing yet, so those two are always dropped.
- **Live Sky Index** (`LiveSkyIndex`). The sky now and for the next few hours, from the latest observation (METAR, NWS), the nowcast (HRRR first hours) and the forecast, blended by weight with the station's distance and age. States: blended, forecast only, observation only, no data. It reports a trend (rising, steady, falling).
- **Freshness.** A forecast older than three hours is stale and is shown with its age, never as current.
- **Terrain.** A 72-azimuth horizon profile per place is computed on the device from Terrarium tiles and cached on the place. It shortens golden-hour windows that the sun reaches late or loses early.

## Conditions

`ConditionsService` (an actor) builds a `SkyReport` per place and day: a composite forecast with per-field provenance (HRRR then GFS then MET Norway for gaps), observations, nowcast and sky inputs, with one job per (place, day) that can have many subscribers and a generation guard. `ConditionsStore` is the `@MainActor @Observable` face of it. Pinned and active trips are saved as offline packs so a trip still shows its last conditions with no signal, labelled with their age.

## The Go engine

`IterGo` runs a trip on the phone. Everything platform-specific (location, notifications, Live Activity, background refresh, power) is behind a protocol, so the whole engine runs on macOS in tests with a scripted location trace and a fake clock.

- **State.** A run is armed, active, paused or finished and is saved (`TripRunRecord`, `StopVisitRecord`), so it survives a relaunch. Each stop is pending, en route, arrived, done or skipped. Leave-by and arrival times are frozen when you set off, so notifications stay stable.
- **One step.** Every event (a tick, a location fix, an action, a foreground, a background refresh) goes through the same step: recompute the live schedule, feed the state machine, set the location mode, ask for an ETA only if due, start the conditions loop if due, build the snapshot, plan and sync notifications, publish the snapshot, update the Live Activity, save, and ask for the next background refresh.
- **Location.** Off when nothing is running; region monitoring while waiting; continuous updates with backup regions while driving; back down at arrival. Choosing the mode is a pure function of the phase.
- **ETA.** At most one request in flight. A held ETA counts only while fresh and near where it was asked, and is rescaled as you move. Otherwise the planned leg along its route line stands in, labelled as an estimate. A deviation of over 1 km while driving forces a new request.
- **Notifications.** Leave soon (15 minutes before), leave now, late, missed, stay check, conditions changed (plus or minus 15 points or a band change, at most one per stop per hour) and arrival. Leave now and late offer Navigate (opens Apple Maps). Automatic arrival offers "Not yet", which undoes it for two minutes.
- **Live Activity and widgets.** The engine writes a `GoSnapshot` JSON into the App Group and updates the Live Activity locally. There is no push, because the free team has no push entitlement. Old or offline data is never labelled live.
- **Background.** Location in the background (`UIBackgroundModes: location, fetch`) and a best-effort refresh task `com.dwjames.iter.go.refresh`. iOS decides when background tasks run.
- **Deep links.** `iter://go` and `iter://go/navigate?stop=<id>`.

## Sync

What exists:

- **`.iter` v1** is the old single-trip format. It is readable for ever and can still be written ("Export for older Iter").
- **`.iter` v2** holds one trip or the whole library: trips, places, folders, pins, sort order, saved places, provenance, `updatedAt` on every record and deletion tombstones. Trips refer to places by id.
- **Merge** (`LibraryMerge`, in `IterStore`) merges by id. A newer `updatedAt` wins per record, an unknown id is inserted, and tombstones apply deletions. "Import as copy" stays an explicit choice.
- **Send to iPhone and Send Library to iPhone** (Mac menu) write a v2 file and open the share sheet with AirDrop. The iPhone imports it with the same merge, so the trip updates in place and does not duplicate. The reverse works the same way.

What does not exist: **Bonjour peer sync (blueprint phase 10b) is not built.** `IterSync` contains only a placeholder type and a smoke test. There is no `NWListener` or `NWBrowser` code, and neither Info.plist has the local-network or Bonjour keys. The merge logic that the blueprint put in `IterSync` is in `IterStore`. There is no iCloud sync (the free signing team has no CloudKit). See [ROADMAP.md](ROADMAP.md).

## Concurrency and safety

- Swift 6 complete checking and `ExistentialAny` on every target.
- Pure targets are `Sendable` value types. Services are actors or `Sendable` structs. View models are `@MainActor @Observable` with `@ObservationIgnored` internals.
- Store writes stay on the main actor. Saves are coalesced to the next run-loop turn.
- Every fan-out is a structured task owned by a model, cancelled when its view or input goes away, and written under a generation guard so a late result cannot overwrite a newer one.
- Performance rules (per-property observable state, `Equatable` rows, debounced map size, precomputed map content, no export built in a view body) are in [PERFORMANCE.md](PERFORMANCE.md).
- **The real app and everything else.** `StorePlacement` decides what a launch may open. Only the real bundle id (`com.dwjames.iter` on the Mac, `com.dwjames.iter.ios` on iPhone), outside a test host, can open the real store. Every other process gets an in-memory store or an explicit scratch path, and a scratch path inside the real store's folder is refused. Keys, preferences and location follow the same rule: the real Keychain and defaults only for the real process, and a render or test never prompts for location or notifications. This is structural, not a convention.
- **Sample data.** `-IterSampleDataEnabled YES` swaps every network service for built-in sample services. Settings and the credits say when sample data is on.

## Design

`Design/tokens.json` is the source of truth for colours, type, spacing and the score ramp. `scripts/tokens.sh` generates `IterUI/Tokens/TokenValues.swift` from it. UI follows [Design/GLASS-RULES.md](../Design/GLASS-RULES.md): system Liquid Glass components only. [Design/FIGMA-MAP.md](../Design/FIGMA-MAP.md) maps Figma components to code.

## Distribution

The Mac app is a direct download that updates itself through `IterUpdater` ([DISTRIBUTION.md](DISTRIBUTION.md)). The iPhone app is installed from Xcode onto the owner's phones with a free Personal Team ([TESTING-iOS.md](../TESTING-iOS.md)). Licensing was dropped in the rebuild (decision D11).
