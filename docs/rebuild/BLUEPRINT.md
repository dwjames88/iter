# Iter rebuild: audit and blueprint

Written 2026-11-22 on branch `rebuild` (identical to `main` at `bf0d7dfe`). This document is what the build leads follow. The data-source facts are in `docs/rebuild/SOURCES.md` (a separate track). Where this document needs a source decision, it leaves a named slot, marked **[SOURCES]**, and does not guess.

Each claim is marked with how it was established:
- **(V)** verified in code, in a file on this Mac, or by running tests.
- **(I)** inferred from the code or from platform knowledge, and not tested here.

---

## 0. The product in one paragraph

Iter is one flow on two platforms:
- **Find:** search and AI discovery of photo spots.
- **Conditions:** weather and sky for each spot.
- **Build:** a trip builder.
- **Go:** the iPhone trip mode, with ETA, leave-by times, current weather, a short forecast and a real-time sky index.

It must be free to run. Data comes from free feeds with no key by default, military-origin first, then government, then other open data. A user may add their own keys, which are stored in the Keychain. The constraints are:
- Swift 6 and SwiftUI, with zero third-party dependencies. XcodeGen is a dev tool only.
- MapKit for maps, on-device Foundation Models for AI, and SwiftData for storage.
- No WeatherKit and no CloudKit, because the signing team is a free Personal Team (see §11 for a finding that questions this).
- The owner's existing trips, places and folders must survive.

---

## 1. Audit: inventory and verdicts

Sizes are in Swift lines. The test counts come from running `swift test --filter` per target on 2026-11-22. All of them passed **(V)**.

| Module | Size | Tests | What it does | Verdict |
|---|---|---|---|---|
| **IterCore** | 2.4k / 19 files | 64 | Value types (`Spot`, `TripPlan`, `TripStopPlan`, `DriveLeg`, `StopSchedule`, `Forecast`, `LightWindow`, `LocalDay`, `TimeSpan`, `Coordinate`), the service protocols, and the discovery value types and merge. It also holds `IterPerf`, `RenderCopy` and `TrailingDebouncer`. | **Port with changes.** The value types, `LocalDay`, `Geo`, `CoordinateParser`, `DiscoveryMerge`, `FeatureKind` and `DiscoveryNames` are proven and pure. `IterPerf`, `RenderCopy` and the debouncer are app plumbing and move out. The Scout protocols are replaced. `DiscoveredPlace` is not `Codable` (V). |
| **IterAstro** | 0.5k / 5 | 26 | Meeus sun and moon positions, rise and set, twilight, phase, refraction, and day/night polygons. Tested against USNO and Meeus examples, including the polar and DST cases. | **Keep as is.** Add a galactic-centre (Milky Way core) altitude and azimuth function (§8). ΔT is a fixed 69 s, which is fine. |
| **IterLight** | 0.7k / 3 | 115 | `LightEngine`: five windows per day, honest unknowns, confidence from lead time, and persistence beyond the horizon. `WindowScorer`: 60 plus signed factor points, clamped to 5..100. `TripScheduler`: a backward schedule (setUpBy, arriveBy, leaveBy) and light-first ordering. | **Port with changes.** The window geometry and the scorer structure carry over. The scorer gains inputs (aerosol, humidity and fog, wind, terrain horizon, light pollution) and a staleness term. The scheduler becomes Plan v2, with a live origin, progress and `now` (§9, §10). |
| **IterData** | 2.2k / 13 | 103 | SwiftData models V1 to V4, frozen schemas, lightweight migrations, `IterStore` (a 1,000-line main-actor repository with snapshot undo), the `.iter` v1 document, 45 curated spots, templates and the Mac store location. | **Port with changes.** Carry the frozen V1 to V4 schemas and the four `@Model` class names **byte for byte**, because the owner's store depends on them (§5). Split `IterStore` by concern. Add V5. |
| **IterServices** | 5.0k / 39 | 272 | Weather: WeatherKit, OpenWeather and Windy, all keyed or paid; a router; caches; a call budget. Discovery: Overpass, Wikipedia, Wikivoyage, Reddit, Google CSE, an FM extractor, a validator and an engine. Scout: FM tool-calling "Ask". MapKit search, geocode, directions and imagery; one-shot location. | **Rewrite the weather and location parts. Port the discovery architecture and the Scout grounding pattern.** The weather layer has no keyless real provider (V). Location is one-shot, kilometre accuracy, with no streaming (V, `UserLocationService.swift:54,101-111`). The directions cache has no TTL and sets no `departureDate` (V, `MapKitDriveTimes.swift:125-142`). |
| **IterFeatures** | 7.4k / 42 | 512 | `@MainActor @Observable` view models: Explore (979 lines plus 3 extensions), Spot, TripBuilder (803 lines), ForecastCenter, Scout, Library and offline packs, MapCameraPolicy, and `AppModel` (the service locator). | **Rewrite the models around the four stages.** Port the pure helpers: `TripDayLayout`, `TripBuilderRows`, `DriveRetryBackoff`, `PathSimplifier`, `PinClusterer`, `SearchIntent`, `SearchSuggestions`, `TasteSummary`, `SkyRose`, `MapCameraPolicy` and the coalescing pattern of `ForecastCenter`. `TripBuilderModel` and `ExploreModel` are god objects coupled through `AppModel`. |
| **IterDesign** | 1.3k / 9 | 26 | The token registry (`TokenValues.swift`), `IterColor` and `IterFont`, the score ramp (`IterRamp`: five sRGB stops from white to `#D9431A`, precomputed into 101 colours), `GlassGeometry` constants and the token codec. It has no glass code of its own. | **Port with changes.** Settle one source of truth: `tokens.json`, with `TokenValues.swift` generated from it. Today `TOKENS.md` and the generated file's header contradict each other (V). Keep the ramp. |
| **IterLicensing** | 0.9k / 10 | 59 | Lemon Squeezy licence keys. Enforcement is off (`ITER_LICENSING_ENFORCED=NO`), and the pane is hidden. | **Drop.** The app is free and nothing is gated. |
| **IterTokensTool** | 53 | none of its own | `iter-tokens` exports and imports `tokens.json` and the asset-catalogue colours. | **Keep** as the token pipeline tool. |
| **IterUpdater** (package) | 1.0k sources + 1.1k tests | 91 | An in-house Sparkle equivalent: JSON appcast, SHA-256 and Ed25519 checks, atomic `replaceItemAt`, relaunch. Includes the release tool. | **Keep as is**, Mac only. It does not interact with the rebuild. |
| **App/Sources** (Mac + shared views) | 18.8k / 141 | 129 hosted | Shell, sidebar, Explore, Trips, Spot, Locations, Settings, Updates, Onboarding, Text, and the Figma components. | **Rewrite the screens. Port the components.** Port `Components/{Score,Sidebar,TripBuilder}`, `Text/*` and `Updates/*`. Rewrite Shell, Sidebar, Explore (it becomes Find), Onboarding and Spot (it becomes Conditions). Drop `Saved/` (no callers, V) and the debug scripts in the shipping target. |
| **AppiOS/Sources** | 4.5k / 27 | ~120 markers | Phone and iPad shells, Explore with a custom bottom sheet, the Trips builder, Locations, Settings. | **Rewrite the shell. Port the screen patterns.** There is no trip mode, no notifications, no ActivityKit, no WidgetKit and no background location anywhere (V, by grep). |

### What is tangled, slow or dead

**Tangled.**
- **The iOS build compiles all of `App/Sources` minus an exclude list** (`project-ios.yml:15-40`). A new Mac-only file compiles for iOS silently. The list also references a file that no longer exists, `ExplorePlaceCard` (V).
- **`AppModel` is a service locator** that `ExploreModel`, `SpotModel` and `ScoutModel` all take whole (V).
- **There are two separate AI pipelines.** The Discovery extractor and the Scout tools have different place types (`DiscoveredPlace` against `PlaceResult`, `ScoutSuggestion` and `Spot`) and are joined only in IterFeatures.
- **API keys are resolved three different ways.** Weather uses env, then launch argument, then Keychain. Discovery uses Keychain only. Windy has a separate "key type" setting.
- **Reactivity is by polling.** Views call `refreshIfChanged()` when `store.revision` changes.

**Slow (from PERFORMANCE.md and the code).**
- A day switch in the trip view costs about 400 ms on the main thread, inside MapKit and Core Animation.
- Explore resize takes about 28 ms per step against a 16 ms target.
- Store saves are synchronous on the main actor, at 8 to 15 ms each.
- `MKDirections` calls are serialised at 200 ms spacing.
- `suggestOrdering` reschedules the whole trip once per day.

**Dead or test-only code in production.**
- `Saved/` (80 lines).
- `TripOverviewCell` and `overviewCells`, which only tests use.
- `FolderRecord.parent` and `children`, which are always nil.
- `SampleWeatherService`, a fixture that is wired into the provider factory.
- `InMemory*KeyStore` test helpers that are public.
- About 1,400 lines of launch switches and perf, smoke and seed scripts inside the Mac shell.

**A live bug.**
- `DiscoveryHTTP.timeout` is 10 s (`DiscoveryHTTP.swift:178`), but the Overpass query asks the server for 20 to 25 s (`OverpassProvider.swift:29,137`). A slow Overpass answer is therefore cut off by the client (V).

**A rule conflict.**
- `GLASS-RULES.md` says the iPhone uses "one floating system sheet … no hand-built sheet".
- `ARCHITECTURE.md` explains that the Explore sheet is custom, because the system sheet covered the iOS 26 tab bar.
- This is listed as owner decision D6.

### What carries over, and where it does not fit

| Carry over | Why it fits | Where it does not |
|---|---|---|
| IterAstro, whole | Pure, tested and accurate | — |
| `WindowScorer` and `LightEngine` window geometry | Honest unknowns, confidence and polar handling | No staleness against `now`; inputs too narrow; a 5..100 clamp hides very bad windows |
| `TripScheduler.schedule` | A correct backward chain, transfer timing, issues | It chains only stop to stop. It has no live origin, no visited state and no `now`. The first stop has `leaveBy = nil` (V). |
| Frozen schemas V1 to V4, the `@Model` classes, `StoreLocation` | They are the only route to the owner's data | — |
| `.iter` v1 decoder | Old files must keep opening | It always duplicates on import (V, `IterStore.swift:430`). Folders and pins are not exported. |
| `DiscoveryMerge` and the extraction filter | Grounded and tested | Name trust ranks Reddit last; the new ranking is in §7 |
| Scout grounding ("the model only cites registry IDs") | The right safety model | It is tied to MapKit-only tools and a 4k context |
| `RegionProposer` | — | **Not carried.** It asks the model for coordinates (V, `RegionProposer.swift:20-23`), which breaks the grounding rule. |
| `ForecastCenter` coalescing and `lastGood` | Good observable cache behaviour | It is bound to `WeatherRouter` and a primary/fallback pair, not per-field sourcing |
| Figma components | Built to the owner's Figma frames and take plain values | `SidebarSearchField` and `SidebarBottomBar` are Mac only. The cards draw custom fills, which is acceptable because they are in the content layer. |
| IterUpdater | Works and has 91 tests | Only relevant while the Mac app is distributed directly |

---

## 2. Flow gaps: the four stages against today's code

### Find
- **AI discovery quality.** Text evidence comes only from Reddit and Google.
  - Reddit uses unauthenticated `www.reddit.com/*.json` with no OAuth. A 403 or 429 is reported as "Rate limited", and Reddit is then skipped for that search (V, `TextSources.swift:4-65`). In practice it fails often (documented in DATA-PROVIDERS.md).
  - Google Custom Search needs the user's key and engine id. It returns snippets, not places (V).
  - So the default text evidence is empty, and the on-device extractor has nothing to read. Structured sources (Overpass, Wikipedia, Wikivoyage) do run, all in English only (V).
- **No photo-evidence signal.** Nothing tells a famous viewpoint from an obscure one. For example, there is no count of geotagged photos.
- **No query understanding.** `SearchIntent.classify` is a keyword list, and `FeatureAreaQuery` is a regex-style parser. The on-device model is used only to extract names and to pick from candidates.
- **Ranking is too simple.** It is popular, unique or mixed, by mentions and Wikipedia presence. Light suitability (facing against the sun's azimuth), drive time and the user's own library do not enter it.
- **Coordinates from the model.** `RegionProposer` lets the model offer coordinates.

### Conditions
- **No keyless real forecast.** Without WeatherKit and without a user key, only `SampleWeatherService` (synthetic data) runs (V). iOS defaults to OpenWeather, which needs a key (V, `IterIOSApp.swift:23`).
- **No observations, nowcast, satellite cloud, aerosol or smoke, AQI, light-pollution or terrain feeds** (V, by grep).
- **The Light Index ignores** humidity and dewpoint, wind, aerosols and smoke, cloud base, terrain horizon and light pollution (V, `WindowScorer.swift:55-132`).
  - Confidence comes only from lead time measured from the fetch time.
  - An old cached forecast scores as fresh (V).
- **Selection is not per region.** It is a user-chosen primary and fallback (V, `WeatherProviderFactory.swift:5-30`).
- **Attribution is shown only in Settings.** That was the owner's instruction of 2026-10-06. DATA-PROVIDERS.md says it must be revisited before release, because provider terms ask for attribution where the data appears.

### Build
- **Works:** days and stops, MapKit legs, the backward schedule, transfer timing, drive notes, light-first ordering suggestions, and the Mac three-column layout with the builder in `.inspector` (V).
- **Missing:**
  - No dwell or "shoot until" time. A stop occupies its light window, and nothing else.
  - No per-stop leave time for the first stop of a day from a lodging or start point.
  - No traffic-aware departure time.
  - Duplicate-on-import only.
  - No Mac to iPhone transfer other than sharing a file.

### Go
- **Nothing exists** (V): no `CLLocationUpdate`, `CLBackgroundActivitySession`, `CLMonitor`, `UNUserNotificationCenter`, `ActivityKit`, `WidgetKit`, `BGTaskScheduler` or `UIBackgroundModes`. iOS has no entitlements file at all.
- **The location request is one-shot**, with kilometre accuracy.

---

## 3. Target architecture

### Repository layout

```
Packages/Iter/                 NEW package, the only one the apps link (besides IterUpdater)
Packages/IterUpdater/          unchanged (Mac only)
Legacy/IterKit/                the old package, moved in Phase 0, never built by project.yml, deleted in Phase 11
Mac/                           Mac app shell only (scenes, commands, AppKit glue, updater UI)
iOS/                           iOS app shell only (scenes, tab and split shells, App Intents)
Widgets/                       iOS widget extension: Live Activity + Lock Screen + Home widgets
Tests/Hosted/{Mac,iOS}/        hosted snapshot and integration tests
Design/, Brand/, docs/         as today; tokens.json is the source of truth
project.yml, project-ios.yml   XcodeGen; no exclude lists: shared UI lives in the package
```

**No more shared-folder exclude lists.** Every view used by both apps lives in `IterUI` or `IterScreens` in the package, with `#if os` only for small differences. The app folders hold only platform shells.

### Package targets and what each owns

| Target | Depends on | Owns |
|---|---|---|
| `IterModel` | Foundation | Value types: `Coordinate`, `GeoRegion`, `GeoPolygon`, `LocalDay`, `TimeSpan`, `Place`, `Trip`, `Stop`, `Leg`, `Route`, `LightWindowKind`. Provenance: `SourceID`, `SourceTier`, `Provenance`, `Sourced<T>`, `DataState<T>`, `NoDataReason`. Weather: `HourlyConditions` with every field optional, `Observation`, `NowcastStep`, `SkyInputs`. Discovery: `PlaceCandidate`, `Citation`, `FeatureKind`. Also `CoordinateParser`. No protocols with I/O. |
| `IterAstro` | IterModel | Carried as is, plus `GalacticCentre`. |
| `IterSky` | IterModel, IterAstro | Window geometry (from `LightEngine`). The Forecast Sky Index (from `WindowScorer`, extended). The Live Sky Index. Confidence and staleness. Pure. |
| `IterPlan` | IterModel, IterSky | `Scheduler` v2 (pure): the backward schedule, dwell, start points, issues, light-first ordering, and the live schedule from `(plan, progress, now, origin, legs)`. Also `TripDayLayout`, the builder rows, `PathSimplifier` and the leave-by alarm plan. Pure. |
| `IterStore` | IterModel | SwiftData: frozen V1 to V4 (copied verbatim), V5, the migration plan, the store-location logic, a backup before migration, and repositories (trips, places, folders, runs, deletions) with named undo. `.iter` v1 read; `.iter` v2 read and write and merge. Curated spots. |
| `IterSources` | IterModel | Provider **protocols** (§6), `SourceRegistry` (per-region and per-tier selection), `SourceCache` (disk and memory, TTL, stale-while-revalidate, licence-aware), `SourceHTTP` (honest User-Agent, per-host spacing, ETag, per-source timeout), `KeyVault` (Keychain), `RateLimiter`, and attribution text. No concrete network adapters. |
| `IterSourcesLive` | IterSources | Concrete adapters. The MapKit ones (search, geocode, `MKDirections` route and ETA, Look Around imagery) are ported. The feed adapters come from the confirmed list in **[SOURCES]**. Each adapter is one file plus a pure `Mapping` with fixture tests. Also any minimal own decoders for formats the confirmed sources need (§6.6). |
| `IterAI` | IterModel | A thin wrapper over Foundation Models behind `LanguageModeling` (availability, `@Generable` calls with retry), so every AI use is fakeable and weak-linked in one place. |
| `IterDiscovery` | IterModel, IterSources, IterAI | The pipeline in §7: query plan, area, fan-out, extraction, verification, merge, rank, citations. |
| `IterConditions` | IterModel, IterSources, IterSky, IterAstro | `ConditionsService`, an actor: a composite forecast with per-field provenance, observations, nowcast and sky inputs, giving a `SkyReport` per place and day. `ConditionsStore`, `@MainActor @Observable`, replaces `ForecastCenter`. Offline packs for pinned and active trips. |
| `IterGo` | IterModel, IterPlan, IterConditions, IterSources | The trip-mode engine: the `TripRun` state machine, `LiveLocation` (a protocol over CoreLocation), the ETA refresher, the notification planner, `GoSnapshot` (what the widget and Live Activity show) and the App Group writer. Platform types are behind protocols, so it is testable on macOS with scripted traces. |
| `IterGoActivity` | IterModel | iOS only (`#if canImport(ActivityKit)`): `ActivityAttributes` and `ContentState`, shared by the app and the widget extension. Tiny on purpose. |
| `IterSync` | IterModel, IterStore | `.iter` v2 merge and Bonjour peer sync (§12). |
| `IterUI` | IterModel, SwiftUI | Tokens (generated), `IterColor`, `IterFont`, the ramp, and the Figma components (`ScoreChip`, the sidebar rows, the Trip Builder parts). It also holds shared controls that follow GLASS-RULES (`GlassCircleButtonStyle`, `PlaceActionStyle`, `MapControlStack`) and `Text/*` phrasing. |
| `IterFeatures` | everything above except IterUI | `@Observable @MainActor` view models, one per stage: `FindModel`, `ConditionsModel`, `BuildModel`, `GoModel`. Also `LibraryModel` and `SettingsModel`, plus `AppContainer`, the composition root of protocol-typed services with no service locator passed into models. |
| `IterScreens` | IterFeatures, IterUI | Shared SwiftUI screens and sections used by both apps (Find list and results, Conditions sections, Builder day list, Go cards). Platform shells compose them. |
| `iter-tokens` | IterUI | The token tool, as today. |

### Dependency graph

```
IterModel ─┬─ IterAstro ── IterSky ── IterPlan ─────────────┐
           ├─ IterStore ── IterSync                         │
           ├─ IterSources ── IterSourcesLive                │
           │      ├── IterDiscovery ◄── IterAI              │
           │      └── IterConditions ◄── IterSky            │
           ├─ IterGoActivity                                │
           └─ IterGo ◄── IterPlan, IterConditions ◄─────────┘
IterFeatures ◄── all of the above (not IterUI)
IterUI ◄── IterModel          IterScreens ◄── IterFeatures, IterUI
Mac app ◄── IterScreens, IterUpdater     iOS app ◄── IterScreens, IterGoActivity
Widgets extension ◄── IterModel, IterUI, IterGoActivity  (reads the App Group snapshot only, never the store)
```

**Rules.**
- Pure targets (Model, Astro, Sky, Plan) have no I/O and no `Date.now`. A clock is passed in.
- Concrete adapters live only in `IterSourcesLive` and are wired only in `AppContainer.live()`.
- View models never touch `ModelContext`.

### Targets in XcodeGen

| Target | Bundle id | Notes |
|---|---|---|
| `Iter` (macOS 26) | `com.dwjames.iter` | **Unchanged**, so the store and Keychain items keep matching. |
| `Iter iOS` (iOS 26) | `com.dwjames.iter.ios` | **Unchanged.** Changing it would orphan the phone's store. |
| `IterWidgets` (iOS app extension) | `com.dwjames.iter.ios.widgets` | Holds the Live Activity, Lock Screen and Home widgets. App Group `group.com.dwjames.iter`. |
| Test targets | — | Hosted test bundles as today. The Mac ones run only as the render copy `com.dwjames.iter.render`. |

**Not planned:** a Mac widget (low value), a Share extension (later, optional) and CarPlay (no fitting category; the Live Activity reaches the CarPlay Dashboard by itself (I)).

---

## 4. Concurrency and state rules (unchanged in spirit, enforced in structure)

- **Swift 6 complete checking** and `ExistentialAny`.
- **Pure targets are `Sendable` value types.** Services are actors or `Sendable` structs. View models are `@MainActor @Observable` with `@ObservationIgnored` internals.
- **Store writes stay on the main actor**, because the store is small. Saves are coalesced on the next run-loop turn to remove the 8 to 15 ms synchronous save per edit.
- **Every fan-out is a structured task** owned by a model, cancelled when its view or input goes away, and written under a generation guard (a pattern ported from Search Here).
- **Keep the lessons from PERFORMANCE.md:**
  - Per-property observable state.
  - `Equatable` rows.
  - Map size debounced.
  - Map content precomputed.
  - No export built in a view body.

---

## 5. Data model and migration

### 5.1 Today (V)

The store is SwiftData `IterSchemaV4`. There are four models. All attributes have defaults or are optional, there are no unique attributes, every relationship is optional with an inverse, and enums are stored as raw strings (CloudKit-shaped).

- **`FolderRecord`:** `id`, `name`, `kindRaw` (trips or locations), `sortOrder`, `createdAt`, `updatedAt`, `isPinned`, `pinnedAt`, plus `parent` and `children`, which are deprecated and always nil.
  - `trips`: nullify.
  - `places`: nullify.
- **`PlaceRecord`:** `id`, `curatedID`, `originRaw` (curated, user, appleMaps or scout), `externalID`, `name`, `locality`, `latitude`, `longitude`, `timeZoneIdentifier`, `categoryRaw`, `bestLightRaw` (CSV), `facing`, `blurb`, `notes`, `walkInMinutes`, `elevationMeters`, `popularity`, `tagsRaw` (CSV), `isSaved`, `createdAt`, `updatedAt`, `folder`, `sortOrder`, `isPinned`, `pinnedAt`.
  - `stops`: nullify.
- **`TripRecord`:** `id`, `name`, `startDayISO`, `dayCount`, `notes`, `createdAt`, `updatedAt`, `folder`, `sortOrder`, `isPinned`, `pinnedAt`, `transferTimingsRaw` (for example `"1:eveningBefore"`).
  - `stops`: cascade.
- **`StopRecord`:** `id`, `dayIndex`, `sortOrder`, `sessionRaw`, `setUpBufferMinutes` (20), `note`, `driveNote`, `trip`, `place`.
- **Migration plan:** `IterMigrationPlan` runs V1 to V2 to V3 to V4, all lightweight (`Schema.swift:14-21`).
- **Per-open fixup:** `flattenFolders`, idempotent, runs on every open.

**Store files.**
- **Mac:** `~/Library/Application Support/Iter/Iter.store`, set by `StoreLocation.directStoreURL()`. A one-time copy from the old sandbox container runs first (`StoreBootstrap.swift:11-27`).
- **iOS:** SwiftData's default `default.store` in the app's own Application Support (`IterSchema.makeContainer(inMemory: false)` with no URL, `IterIOSApp.swift:26-31`). There is no App Group.

**The `.iter` format.**
- One trip as pretty-printed JSON with sorted keys and ISO-8601 dates: `{formatVersion: 1, exportedAt, trip: TripPlan}`.
- Every stop embeds its full `Spot`.
- The UTType is `com.dwjames.iter.trip`, conforming to `public.json`.
- Any `formatVersion != 1` is rejected.
- Missing `driveNote` and `transferTimings` are tolerated.
- Import always creates a new trip with new IDs. Places are upserted by curated slug, then UUID, then `externalID`.
- Not exported: folders, pins, the saved flag, sort order and `externalID`.

**Cached data.** Forecasts are not in SwiftData. They are files: the OpenWeather disk cache and the offline packs `Application Support/Iter/OfflinePacks/<trip>.json`.

### 5.2 V5: what the rebuild adds

V5 is a **lightweight** stage from V4. It only adds new models and defaulted or optional attributes, and keeps the CloudKit-shaped rules. That keeps the migration in the class SwiftData has already handled three times for this store.

**New attributes on existing models**

| Model | Attribute | Type and default | Why |
|---|---|---|---|
| `PlaceRecord` | `sourcesRaw` | `String = ""` (CSV of `SourceID`) | Place provenance: which sources found or confirmed it |
| | `citationsJSON` | `String = ""` (JSON `[Citation]`: source, url, title, retrievedAt, licence) | Citation links shown on the place |
| | `verificationRaw` | `String = ""` (`confirmed`, `singleSource` or `userPlaced`) | Honest discovery state |
| | `discoveredAt` | `Date?` | — |
| | `horizonJSON` | `String = ""` (a cached terrain horizon profile, 72 azimuths) | Terrain-aware sun and moon visibility. Small, per place, and it rarely changes. |
| `StopRecord` | `dwellMinutes` | `Int = 0` (0 means "until the window ends") | Shoot-until and leave times |
| | `fixedArrivalISO` | `String = ""` (optional user-fixed arrival, for example for a non-light stop) | Stops not driven by light (lodging, a meal) |
| | `kindRaw` | `String = "light"` (`light`, `lodging` or `waypoint`) | Lodging and start points get leave-by times too |
| `TripRecord` | `startPlaceID` | `UUID?` | Where day 1 starts, for a first-stop leave-by |
| | `timeZonePolicyRaw` | `String = "spot"` | Reserved. The current behaviour is the spot's zone. |
| `FolderRecord` | (none) | — | `parent` and `children` stay, because removing them needs a non-lightweight stage for no gain |

**New models**

| Model | Fields | Purpose |
|---|---|---|
| `TripRunRecord` | `id`, `tripID: UUID`, `stateRaw` (`armed`, `active`, `paused` or `finished`), `startedAt: Date?`, `endedAt: Date?`, `currentStopID: UUID?`, `updatedAt` | Trip mode. One per run. It survives relaunch. |
| `StopVisitRecord` | `id`, `runID`, `stopID`, `statusRaw` (`pending`, `enRoute`, `arrived`, `done` or `skipped`), `departedForAt: Date?`, `arrivedAt: Date?`, `leftAt: Date?`, `plannedLeaveBy: Date?`, `plannedArrival: Date?`, `updatedAt` | Progress, plus the leave and arrival times frozen at the moment of departure, so notifications and the Live Activity are stable. |
| `DeletionRecord` | `id`, `entityRaw`, `entityID: UUID`, `deletedAt` | Tombstones for sync merge (§12). Pruned after 90 days. |
| `SyncPeerRecord` | `id`, `peerName`, `lastSyncAt`, `lastSentToken`, `pairingKeyRef` (Keychain account) | Bonjour sync state. |

**Kept out of SwiftData on purpose.**
- **Forecasts, observations, nowcasts and sky inputs** go in `SourceCache`. These are files keyed by source, kind, geohash and time bucket, under `Caches/Iter/Sources`, with pinned-trip and active-trip packs under `Application Support/Iter/Packs`.
  - Reasons: high churn, per device, licence-dependent (some feeds may not be stored), and no migration burden.
  - Each datum carries `Provenance`: source, model, issuedAt, fetchedAt, validity, station distance, URL and licence.
- **Live state the widget needs** is a JSON `GoSnapshot` in the App Group. The extension never opens the store.

### 5.3 Migration path (non-negotiable steps)

1. **Freeze, don't rewrite.**
   - Copy `SchemaV1.swift`, `SchemaV2.swift`, `SchemaV3.swift` and the V4 `Models.swift` into `IterStore/Legacy/`, unchanged except for the module name.
   - The live V5 models keep the **class names** `PlaceRecord`, `TripRecord`, `StopRecord` and `FolderRecord`. SwiftData's entity names come from them (I). Renaming would read as delete and insert.
   - `IterSchemaV5.versionIdentifier = 5.0.0`.
   - `IterMigrationPlan.stages` gains `.lightweight(V4 → V5)`.
2. **Same file, same place.**
   - Mac: keep `StoreLocation.directStoreURL()` and the sandbox-container copy. The copy is cheap, and a second Mac might still need it.
   - iOS: open the **explicit** URL of today's default store (`applicationSupportDirectory/default.store`), so a later SwiftData default change cannot move it.
   - Do not move the store into the App Group.
3. **Back up before the first V5 open.**
   - Copy `Iter.store`, `-wal` and `-shm` (iOS: `default.store*`) to `Application Support/Iter/Backups/pre-v5-<date>/`, through a temporary name, before the container opens.
   - Also export every trip as an `.iter` **v1** file into the same folder, using the carried v1 encoder before the new store code touches anything. A failure in either step aborts the open and keeps the old data untouched. The old code's `.migration-pending` pattern is reused.
4. **Prove it on fixtures, then on a copy.**
   - Phase 1 ships migration tests that open fixture stores written **by the old package**: V1, V2, V3, and a realistic V4 with folders, pins, transfer timings and drive notes. Generate them once in Phase 0 from `Legacy/IterKit` and commit them as test resources.
   - Phase 11 does a dry run on a **copy** of the owner's real Mac store, copied to the scratchpad and never opened in place. It compares counts and every trip's `TripPlan` before and after.
5. **Import as a fallback.** If the container fails to open after the backup, the app opens an empty V5 store **at a different file name**, imports the backup's `.iter` files, and shows a one-time notice with the backup folder. The original file is never deleted or overwritten.
6. **`.iter` files.**
   - **v1 stays readable for ever.**
   - **v2** adds `formatVersion: 2`, a `library` form (many trips plus folders, pins, sort order and saved places), the place provenance fields, `updatedAt` on every record, and tombstones.
   - Import **merges by id**. A newer `updatedAt` wins per record, and an unknown id is inserted. "Import as copy" is kept as an explicit choice.
   - The app writes v2, and **Export for older Iter** writes v1.
7. **Keys.**
   - `KeyVault` reads the old Keychain items once: service `com.dwjames.iter.weather`, accounts `openWeather` and `windy`; service `com.dwjames.iter.discovery`, accounts `googleAPIKey` and `googleEngineID`.
   - It rewrites them under `com.dwjames.iter.keys`, account = `SourceID`, and leaves the old items in place.

---

## 6. Provider layer

### 6.1 Core types (`IterModel`)

```swift
public struct SourceID: Hashable, Codable, Sendable, RawRepresentable { public let rawValue: String }   // "apple.mapkit", ids from [SOURCES]
public enum SourceTier: Int, Codable, Sendable, Comparable { case military, government, openData, userKey, device }
public enum DataKind: String, Codable, Sendable { case places, gazetteer, textEvidence, photoEvidence, geocode,
    forecast, observation, nowcast, aerosol, smoke, airQuality, satelliteCloud, lightPollution, aurora,
    astronomy, elevation, horizon, routing, eta, imagery }

public struct Provenance: Codable, Sendable, Hashable {
    public var source: SourceID
    public var model: String?          // e.g. the NWP model / run id
    public var issuedAt: Date?         // model run or observation time
    public var fetchedAt: Date
    public var validFor: TimeSpan?
    public var distanceKm: Double?     // station / grid-point distance from the place
    public var url: URL?               // human link for citation
    public var licence: LicenceTag      // attribution text key, mayStore flag
}
public struct Sourced<Value: Sendable>: Sendable { public var value: Value; public var provenance: Provenance }

public enum NoDataReason: Codable, Sendable, Hashable {
    case outsideCoverage, needsKey(SourceID), offline(lastGood: Date?), rateLimited(retryAfter: Date?),
         sourceError(SourceID, String), notProvidedBySource, appleIntelligenceUnavailable
}
public enum DataState<Value: Sendable>: Sendable {
    case fresh(Sourced<Value>)
    case stale(Sourced<Value>, age: Duration)     // shown with its age, never as fresh
    case none([NoDataReason])                     // shown as a named gap, never a number
}
```

**Hourly fields are all optional.** Examples: `cloudTotal`, `cloudLow`, `cloudMid`, `cloudHigh`, `cloudBaseM`, `precipChance`, `precipMm`, `visibilityKm`, `tempC`, `dewpointC`, `rhPercent`, `windMs`, `gustMs`, `windDirDeg`, `aod550`, `smokeUgm3`, `pm25`. Each field of a *composite* forecast carries its own `SourceID`, so the UI can say "Cloud layers: <source>; Smoke: <source>".

### 6.2 Protocols (`IterSources`)

```swift
public protocol SourceDescribing: Sendable { var descriptor: SourceDescriptor { get } }
public struct SourceDescriptor: Sendable {
    public var id: SourceID; public var name: String; public var operatorName: String
    public var tier: SourceTier; public var kinds: Set<DataKind>
    public var coverage: Coverage                 // .global, .polygons([GeoPolygon]), .countries([String])
    public var key: KeyRequirement                // .none, .optional(SourceID), .required(SourceID)
    public var spacing: Duration; public var timeout: Duration; public var cacheTTL: Duration
    public var licence: LicenceTag; public var termsURL: URL?
}

public protocol PlaceSearchProvider: SourceDescribing {            // free text near a region (MapKit)
    func search(_ text: String, near: GeoRegion) async throws -> [PlaceCandidate] }
public protocol GazetteerProvider: SourceDescribing {               // structured features in an area
    func candidates(in area: DiscoveryArea, features: Set<FeatureKind>, limit: Int) async throws -> [PlaceCandidate] }
public protocol TextEvidenceProvider: SourceDescribing {            // documents for the extractor
    func documents(for plan: QueryPlan, in area: DiscoveryArea) async throws -> [EvidenceDocument] }
public protocol PhotoEvidenceProvider: SourceDescribing {           // geotagged photo density near a point
    func evidence(near: Coordinate, radiusM: Double) async throws -> PhotoEvidence }
public protocol Geocoder: SourceDescribing {
    func geocode(_ text: String, near: GeoRegion?) async throws -> [GeocodeResult]
    func reverse(_ c: Coordinate) async throws -> GeocodeResult
    func boundary(of name: String, near: Coordinate?) async throws -> GeoPolygon? }

public protocol ForecastProvider: SourceDescribing {
    func forecast(at c: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries> }
public protocol ObservationProvider: SourceDescribing {
    func latest(near c: Coordinate, within km: Double, maxAge: Duration) async throws -> [Sourced<Observation>] }
public protocol NowcastProvider: SourceDescribing {                 // 0–6 h
    func nowcast(at c: Coordinate) async throws -> Sourced<[NowcastStep]> }
public protocol SkyInputProvider: SourceDescribing {                // aerosol, smoke, AQI, sat cloud, light pollution, aurora
    func inputs(at c: Coordinate, span: TimeSpan) async throws -> Sourced<SkyInputs> }
public protocol TerrainProvider: SourceDescribing {
    func elevation(at c: Coordinate) async throws -> Sourced<Double>
    func horizon(at c: Coordinate, azimuthStep: Double) async throws -> Sourced<HorizonProfile> }
public protocol RoutingProvider: SourceDescribing {                 // MapKit
    func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route
    func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA }   // MKDirections.calculateETA
```

Astronomy is not a provider: IterAstro computes it locally. Where the sources lead confirms an authoritative feed (USNO is being probed), it is used **only as a test oracle**, not at run time (I, decision D10).

### 6.3 Selection: `SourceRegistry`

`SourceRegistry.candidates(kind:, at:) -> [any Provider]` does the following:
1. It filters by coverage containing the coordinate, by whether the user has enabled the source, and by the key being present when one is required.
2. It sorts by **tier** (military, then government, then open data, then user key), then by a per-kind quality rank given in the registry table, which **[SOURCES]** fills in.

The registry table is one Swift file of `SourceDescriptor`s. It is reviewed against SOURCES.md and is the only place priorities live.

**Composite fetch.** `ConditionsService` asks the candidates in order, **field by field**. For example, cloud layers come from the first source that has them, and aerosol from the first that has it. It stops once every field the Sky Index uses is filled, or the candidates run out. A US-only source simply drops out of the list for a non-US coordinate. That is the global fallback, and it needs no special case.

**Per-field honesty.** A field nobody supplies stays `nil`. The scorer drops it and says so, and the UI names the gap.

### 6.4 Caching and offline

- **`SourceCache` is an actor.** It keeps memory (LRU) and a disk JSON cache keyed by `(source, kind, geohash at the source's grid resolution, time bucket)`.
- **Freshness.** Results are stale after the descriptor's `cacheTTL`. A stale result is returned at once as `.stale` while one refetch runs (stale-while-revalidate). An identical request already in flight is joined.
- **Licence.** A source whose licence says `mayStore = false` is kept in memory only, as Windy is today.
- **Packs.** A pinned or active trip gets a pack in `Application Support/Iter/Packs/<trip>/`. It holds the composite forecasts for every stop, observations, the horizon profiles, the legs with route lines, and the images. A pack is refreshed hourly while the app runs. During Go it is refreshed by the Go engine (§10.6).
- **Offline.** Every screen reads `DataState`. Offline shows the last good value with its age ("Forecast from 06:29, offline"). It never shows a blank where a stale value exists, and never shows a number where nothing exists.
- **MapKit tiles** still cannot be cached offline (V, documented). Go shows the route line over whatever tiles MapKit has, and the hand-off to Apple Maps covers navigation.

### 6.5 HTTP and keys

- **`SourceHTTP`** is ported from `DiscoveryHTTP` and:
  - sends an honest generic User-Agent (`Iter/<version> (+project URL)`) with no personal details;
  - applies the per-host spacing and concurrency from the descriptor;
  - uses ETag and `If-Modified-Since`;
  - uses a **per-source timeout taken from the descriptor**, which fixes the 10 s against 20 s Overpass bug;
  - maps errors to `NoDataReason`.
- **`KeyVault`** stores keys in the Keychain under `com.dwjames.iter.keys`. A key never goes into UserDefaults, logs or the repo. Render copies and tests use an in-memory vault.

### 6.6 Formats with zero dependencies

- **Prefer JSON, CSV or GeoJSON endpoints.** If a confirmed military or government feed only offers **GRIB2**, write a minimal own decoder: section parsing, template 3.0 lat/lon grids, template 5.0 simple packing, and point extraction. It goes in `IterSourcesLive/Formats` with fixtures.
- **Do not take on JPEG2000-packed GRIB2 (template 5.40).** Choose another product or endpoint instead. The sources lead is probing GRIB2 templates (`scripts/probes/weather/grib2_templates.py`), and its result decides this. **[SOURCES]**
- **METAR and TAF text** (if confirmed) gets a small pure parser for cloud layers, visibility and weather.

---

## 7. Discovery pipeline (Find)

The pipeline runs entirely on the device. Only the search words and the area go to the sources, never the user's library.

1. **Query understanding.**
   - `IterAI` asks Foundation Models for a `@Generable QueryPlan`:
     - `areaText` (or `nearMe`, or `mapArea`)
     - `features: [FeatureKind]`
     - `windows: [LightWindowKind]`
     - `dateHint`
     - `maxDriveMinutes`
     - `keywords: [String]` (at most 6)
     - `exclude: [String]`
   - The model never outputs coordinates. The `QueryPlan` type has no coordinate field.
   - **Without Apple Intelligence**, the deterministic parser builds the same `QueryPlan`. It is ported from `SearchIntent`, `FeatureAreaQuery` and the synonym tables. Results are labelled "Basic search".
2. **Area.**
   - `Geocoder.geocode` plus `boundary` give the real outline where OSM or the gazetteer has one, otherwise a box sized by the place's type. `nearMe` uses the current location, and `mapArea` uses the visible region.
   - Drive-time constraints become a radius first, then a later filter by real ETA on the top results.
3. **Fan-out.** All enabled providers run concurrently, each under its own timeout and spacing. A failing source becomes a status and never fails the run.
   - Structured gazetteers: `GazetteerProvider`s. MapKit POI and the ported Overpass, Wikipedia and Wikivoyage are known. Military and government gazetteers (for example NGA GNS for names outside the US, and USGS GNIS) and Wikidata are **[SOURCES]**.
   - Text evidence: `TextEvidenceProvider`s. Wikivoyage and Wikipedia extracts are known. Reddit is **[SOURCES]**: only if a keyless endpoint is confirmed to work (see D2). Google CSE is only with the user's own key.
   - Photo evidence: `PhotoEvidenceProvider`, for example the density of Wikimedia Commons geotagged photos (**[SOURCES]**, probed as `wikimedia.sh`).
4. **Extraction (text only).**
   - The ported `FoundationModelsDiscoveryExtractor` runs in chunks within the 4k context. Each document is capped and the evidence is prioritised by relevance.
   - The ported `DiscoveryExtractionFilter` keeps the rule that a name must occur literally in the text.
   - The model returns names and the id of the document each came from. That id becomes the citation.
5. **Verification.** Every candidate must end with a coordinate that did not come from the model.
   - **Name-only candidates** are geocoded (MapKit, then the gazetteers) inside the area, with a normalised-name match.
   - **Structured candidates** keep their own coordinate if the area contains it.
   - **Status:**
     - `confirmed`: two or more independent sources, or one structured source with a stable id (OSM, Wikidata, NGA).
     - `singleSource`: shown, labelled.
     - Otherwise the candidate is dropped.
   - The RegionProposer path is removed.
6. **Merge.** The ported `DiscoveryMerge` (name within 1.5 km, or any name within 60 m) unions sources, links and mentions. Coordinate trust goes to the most precise structured source.
7. **Rank.** A deterministic score with visible parts:
   - Feature match to `QueryPlan.features`.
   - Evidence: photo density, mentions, wiki presence, confirmation count.
   - Light suit: the stated `facing` against the sun's azimuth in the intended window from IterAstro, plus a horizon check when a horizon profile exists.
   - Reachability: straight-line distance first, then real ETA for the top 20.
   - Novelty against the library, from the ported `TasteSummary`.

   Presets: Popular, Hidden and Balanced. The model does not rank.
8. **Explain and cite.**
   - Each result gets a one-line "why" from the model, built only from that place's stored facts. Numbers are checked against the facts, ported from `LightExplainer`'s number-grounding check.
   - Without AI, a template sentence is used.
   - The citations (source, title, URL, retrieved date, licence) show on the result and travel into `PlaceRecord.citationsJSON` on save.
9. **Conditions on demand.** Results get their Sky Index lazily, rows in view first, through `ConditionsService`.

**UI states.** Each source shows a status chip: "OpenStreetMap: 14", "Reddit: rate limited", "Google: add a key". Apple Intelligence off shows "Basic search: AI unavailable (reason)" and still returns structured results.

---

## 8. Sky Index

There are two scores, both 0..100, drawn with the same white-to-orange ramp and `ScoreChip`. Each card shows one score.

### 8.1 Forecast Sky Index (per window)

- **Windows:** blue morning, golden morning, golden evening, blue evening, and night. The geometry is the ported `LightEngine`, including the polar cases.
- **Score:** baseline plus signed factors, with an overcast ceiling. This is the `WindowScorer` structure.
- **Clamp:** keep 0..100 instead of 5..100. A floor of 5 hid how bad a window was, and the clamp is now explained in "Why".

| Factor | Windows | Input slots | Status |
|---|---|---|---|
| Cloud colour (mid and high) against low-cloud block | golden, blue | `cloudLow`, `cloudMid`, `cloudHigh` (or `cloudTotal` with a lower ceiling) | exists |
| Precipitation | all | `precipChance` or `precipMm` | exists |
| Visibility and haze | all | `visibilityKm` | exists |
| **Aerosol and smoke** | golden, blue, night | `aod550`, `smokeUgm3` (**[SOURCES]**: NRL NAAPS, HMS smoke, Open-Meteo AQ and FIRMS are being probed) | new. Light smoke raises sunset colour, heavy smoke blocks it. The curve is pending calibration. |
| **Fog and mist risk** | blue morning, golden morning | dewpoint spread `tempC - dewpointC`, `rhPercent`, `windMs` | new. Shown as an opportunity flag, not only a penalty. |
| **Wind** | blue, night | `windMs`, `gustMs` | new. A note for long exposures and reflections, light weight. |
| **Terrain horizon** | golden, blue | `HorizonProfile` from `TerrainProvider` (**[SOURCES]**: USGS 3DEP, EPQS, PVGIS horizon and Open-Elevation are probed) | new. If the sun sets behind terrain before the astronomical event, the window's effective end moves and the UI says so. |
| Moon | night | IterAstro altitude and illumination | exists |
| **Light pollution** | night | Bortle or sky brightness (**[SOURCES]**: `lpmap-query.sh`) | new |
| **Milky Way core** | night | IterAstro galactic-centre altitude (new function) | new. Informational, plus a small bonus when the core is up and the moon is down. |
| **Aurora** | night, high latitudes | Kp forecast and OVATION (**[SOURCES]**: SWPC is probed) | new. A flag, not a score term, until calibrated. |

**Confidence** is a 3-level value as today, with an added cause list:
- **Lead time:** 36 h and 72 h thresholds, as today.
- **Missing inputs:** one step down per missing *primary* input for that window.
- **Source spread:** when two or more forecast sources supply cloud, a disagreement above a threshold drops one step and shows the range.
- **Staleness against now** (new): a forecast older than its TTL drops one step and shows its age.
- **Persistence beyond the horizon:** always low, as today.

### 8.2 Live Sky Index (Go and "Now")

- **Recompute:** every 10 minutes while Go is active and the app is running, and on every observation or nowcast update.
- **Inputs, blended by recency:**
  - The nearest observation (cloud layers and visibility from a station; **[SOURCES]**: METAR including military stations through the probed feeds), weighted by distance and age.
  - Satellite cloud fraction at the point (**[SOURCES]**).
  - The 0 to 6 h nowcast (**[SOURCES]**).
  - The current forecast hour as the base.
  - The sun's altitude now, from IterAstro.
  - Smoke and aerosol now.
- **Weighting:** observation and satellite weight falls from 0.7 (age 0) to 0 (age 90 min, or 50 km). The rest comes from nowcast, then forecast.
- **Output:** `LiveSkyIndex { score, trend (rising, steady or falling over the next 60 min from the nowcast), inputsUsed: [Provenance], age, confidence }`.

**Display rule (both indexes).** The chip shows the score, a confidence mark and, beside it, the **data age** ("Obs 12 min · nowcast 5 min"). When age passes its limit, the chip turns to the stale style and says "as of 06:29". With no inputs at all it shows "No live data" and falls back to the forecast score, clearly labelled.

**Slots left open for SOURCES.md:** the exact observation feed(s) per region, the satellite cloud product, the nowcast source, the aerosol and smoke product, light pollution, aurora, terrain DEM and horizon, and the global fallbacks for each.

---

## 9. Trip builder (Mac and iOS)

### Carries over (V: built to Figma, plain-value inputs, already used by both apps)

These move into `IterUI`:
- `TripHeaderCard`, `TripMetaRow`, `DaySelector`, `DayCardHeader` and `SunTimesRow`
- `DayCard` and `DayCardBackground`
- `StopCard`, which is generic over its picker, score, note and editor slots
- `LightWindowPicker`, `NotePlaceholder`, `TimeLabelColumn`, `NumberBadge` and `DriveBadge`
- `DriveSegmentRow`, `OvernightNote`, `AddStopButton`, `FindHotelsButton`
- `ScoreChip`
- `BuilderType`, `BuilderMetrics` and `BuilderCardBackground`

`SidebarRow`, `SidebarDisclosureRow` and `SidebarSectionHeader` move to `IterUI`. `SidebarSearchField` and `SidebarBottomBar` stay in the Mac shell.

**Figma check (2026-11-22, one `get_metadata` call on page 5:2, V).** The Components page still holds the same three top-level nodes:
- a screenshot, 5:3
- **Sidebar** 11:1768, a 280×943 symbol
- **Trip Builder Module** 11:1873, 639×943

The module holds Title (11:2746), the day selector (25:4074), day cards (16:3329, 42:4291) with stop cards (21:3363) and their Score instances, a drive or overnight row (44:170, 44:283) and the Add row (21:3570). No new component has been added since the 2026-10-25 build that implemented the drive rows. No Figma node ids are recorded in code (V), so Phase 5 adds a `Design/FIGMA-MAP.md` table from component to node.

### Changes

- **Layout, Mac:** sidebar on the left, then map with waypoints in the middle, then the Trip Builder on the right in the system `.inspector`. This is the same as today and the owner's rule.
- **Layout, iPhone:** the builder is a pushed screen with the map in a collapsible header. On iPad it uses the split view and the inspector, as on the Mac.
- **Stop card additions.**
  - Stop kind (light, lodging or waypoint).
  - A dwell or "shoot until" control.
  - The stop's **leave-by** time, shown on the drive row into the next stop. It is already drawn by `DriveSegmentRow` but is now computed for the first stop of a day too, from the day's start place or lodging.
  - A citation link for discovered places.
  - The Conditions sparkline: the score per window across the trip days, which are the existing outlook chips.
- **Traffic-aware legs.** Plan legs are requested with `departing:` set to the planned leave time when it is within MapKit's horizon. Otherwise the request uses the typical estimate, labelled.
- **"Start trip"** (iOS) appears in the header when the trip's first day is today or tomorrow. It arms Go.
- **"Send to iPhone"** (Mac) is in the header's More menu (§12).

**Tests.** The day layout, rows and scheduler stay package-tested. The components keep snapshot tests in both appearances.

---

## 10. iOS Trip Mode (Go)

### 10.1 State machine (`IterGo.TripRun`, pure, persisted as `TripRunRecord` and `StopVisitRecord`)

```
idle ──Start trip──► armed(beforeDeparture)
armed ──leave-by reached or "Leave now" or motion away from start──► driving(to: stop)
driving ──geofence enter (r = 150–300 m by stop kind) or "I'm here"──► atStop(stop)
atStop ──window ends + dwell, or "Done here"──► betweenStops(next)   (if next leave-by is later: waiting/overnight)
betweenStops ──leave-by reached or "Leave now"──► driving(to: next)
any ──"Skip stop"──► marks skipped, recomputes, continues
last stop done or "End trip" ──► finished (summary: what was shot, scores at the time)
```

- Every transition writes the visit record.
- Automatic transitions from a geofence or a time come with a "Not yet" undo for 2 minutes in the UI.

### 10.2 Live ETA and leave-by

- **ETA** is `RoutingProvider.eta(from: here, to: nextStop, departing: now)`, which is `MKDirections.calculateETA` and lighter than a full route (I). The route line comes from the plan's leg or a fresh `route` call when the user deviates by more than 1 km.
- **ETA refresh triggers:**
  - every 3 minutes while driving;
  - after a significant location change (2 km or more);
  - when the app comes to the foreground;
  - and never more than one request in flight.
- **Leave-by** = `arriveBy - liveETA - safety margin`, from `IterPlan.liveSchedule(plan, progress, now, origin: here, legs)`. Here `arriveBy` is the window start minus set-up buffer minus walk-in. The safety margin is 5 minutes plus 10 % of the ETA.
- **Late or early.** If you are running late, the card says "Leave now: arrive 6 min after set-up" and offers the next-best window or stop from `IterPlan`. If you are early, it shows a countdown.
- **Hand-off to Apple Maps.** "Navigate" calls `MKMapItem.openMaps(with: [destination], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])`. Iter does not do turn-by-turn. It keeps running in the background to update the ETA and the Live Activity.

### 10.3 Conditions at the next stop

- **Current weather:** the nearest observation, with its station distance and age. Without one, the current forecast hour, labelled.
- **Short-range forecast:** a 6-hour strip (nowcast, then forecast) for the next stop, showing the window's hours highlighted.
- **Real-time sky index:** the Live Sky Index (§8.2) for the next stop's window, beside the forecast index, with its trend.

### 10.4 Notifications (local only)

| Notification | When | Content |
|---|---|---|
| Leave soon | at leave-by − 15 min (D9) | "Leave by 17:42 for Mesa Arch: 48 min drive, sunset 18:31" |
| Leave now | at leave-by | Includes a **Navigate** action, which opens Apple Maps |
| Conditions changed | the Live or Forecast index for the next window moves by ±15 or more, or changes band (D9) | "Sunset at Mesa Arch now 72 (was 45): high cloud moving in" |
| Window starting | at set-up time when at the stop | Optional |

- **Rescheduling.** Requests use stable identifiers per stop and kind, so a new ETA *replaces* the pending request.
- **Interruption level.** `.active`. Time-sensitive needs an entitlement that no profile on this Mac carries (V). Phase 9 tries enabling it once. If Xcode cannot provision it on this team, the app stays on `.active` and the doc says so.

### 10.5 Live Activity, Dynamic Island and Lock Screen

- **`IterGoActivity`** holds `GoActivityAttributes(tripName)` and the `ContentState`:
  - `phase`
  - `nextStopName`
  - `leaveBy: Date?`
  - `eta: Date?`
  - `windowStart` and `windowKind`
  - `liveScore`, `forecastScore` and `trend`
  - `dataAge`
- **Countdowns** use `Text(timerInterval:)` and relative dates, so they tick with no updates.
- **Updates.** **Local updates only**, from the app process (no push, see §11). The app is kept running in the background by the location session while a run is active, so it can call `activity.update(...)` on each ETA or index change, throttled to at most one update a minute.
- **`staleDate`** is set to the next expected refresh plus 15 minutes. The widget views show a stale style after it.
- **Dynamic Island:**
  - compact: the leave-by or ETA countdown, plus the score chip;
  - minimal: the score;
  - expanded: next stop, ETA, window, and live and forecast scores.
- **Lock Screen and StandBy** use the same views. A Lock Screen accessory widget (`accessoryRectangular`) shows the next leave-by from the App Group `GoSnapshot`, with a timeline entry at each leave-by.
- **Start and end.** The activity starts at `armed` (if within 8 h of the first leave-by) or at Start trip, and ends at `finished` with a final state, dismissed after 1 h.

### 10.6 Background and location strategy, and battery

| Phase | Location API | Accuracy | Cost (I) |
|---|---|---|---|
| armed, more than 2 h before leave-by | none. A local notification plus a `BGAppRefreshTask` request to refresh conditions (best effort, iOS decides) | — | ~0 |
| armed, 2 h or less | `CLMonitor` circular condition on the start (exit) + significant-change | low | very low |
| driving | `CLBackgroundActivitySession` + `CLLocationUpdate.liveUpdates(.automotiveNavigation)` | best for navigation, but we only *read* every update and act on the triggers in §10.2 | the main cost. Comparable to a navigation app minus the screen. Ends at arrival. |
| atStop | stop live updates. Keep `CLMonitor` on the stop (exit = left) + significant-change | low | very low |
| betweenStops, waiting | as armed | — | ~0 |
| finished | everything stopped | — | 0 |

- **Required keys.**
  - `UIBackgroundModes`: `location`, `fetch` and `processing`.
  - `BGTaskSchedulerPermittedIdentifiers`.
  - `NSSupportsLiveActivities` and `NSSupportsLiveActivitiesFrequentUpdates` (I: frequent updates matter mainly for push. Harmless).
  - The existing When-In-Use and Always strings.
- **Permission.** Location is asked at launch (the owner's rule, as today). Always is asked only when a trip starts, with a sentence saying why: arrival detection while the phone is locked. Go works on When-In-Use alone while a background activity session is running (I).
- **Conditions refresh during Go:**
  - next stop: every 15 min (observation and nowcast) and every 60 min (forecast), while running in the background thanks to the location session;
  - the whole pack: every 3 h.
- **Low Power Mode or below 20 % battery:** the ETA interval goes to 10 minutes, conditions refresh to 30 minutes, and the Live Activity updates at most every 5 minutes. The card says so.

### 10.7 Offline on the road

- **Before departure.** Starting a trip builds the trip's pack (§6.4): composite forecasts, horizon profiles, legs with lines, images.
- **Offline ETA.** Without network, ETA = the remaining planned leg time scaled by the progress along the stored route line (pure, in `IterPlan`), labelled "offline estimate".
- **Offline conditions.** The last good values with their ages. The Live Index falls back to the forecast score, labelled "No live data".
- **Notifications** are local, so they keep firing.
- **Apple Maps hand-off** still works. Maps has its own offline maps (I).

### 10.8 What Go looks like

- **The Go tab** is the first tab while a run is active, and a banner otherwise. It shows:
  - a large card: next stop, leave-by or ETA countdown, the window and the two scores;
  - a 6-hour strip;
  - Navigate, I'm Here, Skip and Done Here;
  - the trip's remaining stops below.
- **Visual system.** System glass for controls only, and the First Light palette (GLASS-RULES). A dim night variant comes later as a token mode (ROADMAP M2).

---

## 11. Free Personal Team: what works (team `VF945J28YU`)

**Evidence.** 11 Xcode-managed iOS profiles on this Mac were decoded (V). Every one carries only these entitlements:
- `application-identifier`
- `team-identifier`
- `get-task-allow`
- `keychain-access-groups`
- in 5 of them, `com.apple.security.application-groups` (ClearClock app and widget, WoodFam app and widgets, Field Frames)
- in one, HealthKit

None carries `aps-environment`, WeatherKit, iCloud, time-sensitive notifications or associated domains.

| Capability | Verdict | Basis |
|---|---|---|
| App Groups (app ↔ widget or Live Activity extension) | **Works** | V: profiles carry it. ClearClock (app and widget, same team) runs on the owner's phone. |
| WidgetKit extension, Lock Screen widgets | **Works** | V (ClearClock) |
| Live Activities and Dynamic Island, updated locally by the app | **Works** | I: no entitlement, only `NSSupportsLiveActivities`. Not yet seen running on this team. Phase 9 proves it on the 27.2 simulator first. |
| Live Activity updates by push, remote push in general | **Does not work** | V: no `aps-environment` in any profile. WoodFam's project marks push as a paid-team item. |
| Background location, fetch, processing modes; `BGTaskScheduler` | **Works** | I: Info.plist keys only. iOS decides when background tasks run. |
| `CLMonitor` geofences, `CLBackgroundActivitySession` | **Works** | I: no entitlement |
| Local notifications | **Works** | I |
| Time-sensitive notifications | **Uncertain, assume no** | V: not in any profile. Phase 9 tries it once. |
| CloudKit or an iCloud container | **Does not work** | V: absent. WoodFam comments it out as paid. |
| User-picked iCloud Drive files (document picker) | **Works** | I: no entitlement. `.fileImporter` already works for `.iter`. |
| Bonjour and local network (`NWBrowser`, `NWListener`) | **Works** | I: plist keys `NSLocalNetworkUsageDescription` and `NSBonjourServices`, plus a runtime prompt |
| Multicast entitlement | **Does not work** | I: not needed for Bonjour |
| MapKit, `MKDirections`, Look Around | **Works** | V: in use today |
| WeatherKit | **Does not work** | V: absent from every profile |
| Foundation Models | **Works** (device-dependent) | V: in use. Weak-linked on iOS. |
| Keychain (default group) | **Works** | V |
| Profile lifetime | **365 days in every profile on this Mac** | V: `TimeToLive = 365`. For example, Iter iOS was created 2026-10-07 and expires 2027-10-07. **This contradicts** TESTING-iOS.md's "stops opening after 7 days", and a free Personal Team normally gets 7-day profiles (I). See D1. |
| Number of apps | Free teams are limited to 3 installed sideloaded apps (I). Whether the widget extension counts separately is uncertain. | I |

**What does not work, in plain words.**
- Trip mode cannot be pushed to. The Live Activity and the conditions-changed alert only update while Iter itself is alive, through the background location session during a drive, or a best-effort background refresh otherwise.
- The phone cannot get updates from a server while Iter is suspended and no trip is driving.
- There is no iCloud sync.
- There is no WeatherKit.

---

## 12. Sharing a trip between Mac and iPhone (no CloudKit)

**Phase 10a: send a file (works on day one).**
- The Mac's **Send to iPhone** writes an `.iter` v2 file and offers the share sheet with AirDrop first.
- The iPhone opens it, and `IterSync` **merges by id** (a newer `updatedAt` wins per record; tombstones apply deletes), so the same trip updates in place instead of duplicating.
- **Send Library** sends every trip and saved place with folders.
- The reverse direction works the same way.

**Phase 10b: local-network sync.**
- **Discovery and pairing.** The Mac advertises `_iter-sync._tcp` with `NWListener`, and the iPhone browses with `NWBrowser`. Pairing is a 6-digit code shown on the Mac. It derives a pre-shared key stored in each device's Keychain, used for TLS-PSK on `NWProtocolTLS` (I).
- **Exchange.** The two sides swap change sets since each peer's last token: records with `updatedAt` newer than the token, plus tombstones. The merge rule is the same as 10a.
- **When it runs.** At iPhone launch and foreground, and from **Sync Now**, when both are on the same network.
- **Requirements.** No server and no entitlement. It needs `NSLocalNetworkUsageDescription` and `NSBonjourServices` on iOS. On the unsandboxed Mac it needs nothing extra (I).

**Not chosen.**
- **An iCloud Drive folder of JSON** (user-picked, with a security-scoped bookmark) is feasible with no entitlement (I). It is fragile, though: file coordination conflicts and an eventually consistent upload while the phone is on the road. It is kept as a fallback idea.
- **A hosted sync server** is not chosen. It is not free, and it adds an account.

---

## 13. Build phases

Each phase has one Opus lead and Sonnet workers. Every phase ends **green**: `swift test` passes for the package, the Mac and iOS apps build with `xcodebuild` (iOS against the iOS 27.2 simulator runtime, never 27.0), and there is a headless check named in the phase.

The workers in a phase own disjoint paths, listed per phase. Nobody edits `project.yml` except the phase lead.

| # | Phase | Depends on | Workers and their file ownership | Ends with (headless check) |
|---|---|---|---|---|
| **0** | **Scaffold and safety** | — | W1: move `Packages/IterKit` to `Legacy/IterKit`, and create the `Packages/Iter` skeleton with all targets empty plus test targets. W2: a fixture generator (a small executable in `Legacy/`) that writes V1, V2, V3 and V4 stores and `.iter` v1 files with the **old** code into `Packages/Iter/Tests/IterStoreTests/Fixtures/`. W3: new `project.yml` and `project-ios.yml` with app shells that show "Rebuild" and the widget target stub; pin `scripts/test-ios.sh` to the 27.2 runtime by name (today it takes the newest, `tail -1`, V). | Both apps build. `swift test` passes on empty targets. The fixture stores are committed. |
| **1** | **Model and Store** | 0 | W1: `IterModel` (port the IterCore value types, add provenance and `DataState`). W2: `IterStore` (frozen V1 to V4, V5, migration plan, backup-before-open, store location, repositories with undo). W3: `.iter` v1 reader, v2 reader and writer and merge, plus `KeyVault` migration (in `IterStore` and `IterSources/KeyVault` only). | Migration tests open every fixture V1 to V4 store and the realistic V4 store, and assert equal `TripPlan`s. The v1 file round-trip passes. Backup-then-open is tested, including an injected failure. |
| **2** | **Sources layer** | 1 | W1: `IterSources` (protocols, registry, cache, HTTP, rate limiter). W2: MapKit adapters in `IterSourcesLive/Apple/`. W3 and W4: feed adapters for the confirmed **[SOURCES]** list, one directory per operator in `IterSourcesLive/<operator>/`, each with a pure `Mapping` and fixtures recorded by the sources lead. W5: any format decoders (`IterSourcesLive/Formats/`). | Fixture tests for every adapter. Registry selection tests for a US point, a non-US point and an ocean point. A live smoke run gated by `ITER_LIVE=1`, run only by the lead. |
| **3** | **Sky and Plan** | 1 (parallel with 2) | W1: `IterAstro` carried plus the galactic centre. W2: `IterSky` (ported windows and scorer, new factors behind optional inputs, Live Index, confidence and staleness). W3: `IterPlan` (scheduler v2, dwell and lodging and start place, live schedule, offline ETA, alarm plan, ported layout and rows). | The ported tests pass: the existing 26 astro and 115 light tests, adapted. New tests: missing input means dropped plus a note; the stale rule; first-stop leave-by; a live schedule across a scripted day. |
| **4** | **Conditions and Discovery** | 2, 3 | W1: `IterConditions` (composite fetch, `ConditionsStore`, packs). W2: `IterAI` (FM wrapper, fakes). W3: `IterDiscovery` (QueryPlan with the deterministic fallback, fan-out, extraction, verification, merge, rank, citations). | Discovery runs end to end over fixture providers and a fake model. It proves that no result has a model-supplied coordinate. Conditions yields per-field provenance and the right `DataState` offline. |
| **5** | **UI kit** | 1 (parallel with 2 to 4) | W1: `IterUI` tokens (`tokens.json` as the source, generated Swift, the ramp) and the `iter-tokens` port. W2: port the Figma components and `Text/*` into `IterUI`, and write `Design/FIGMA-MAP.md`. | Snapshot renders of every component, light and dark, Mac offscreen and iOS simulator. A pixel check of the ramp endpoints. |
| **6** | **Features and Mac app** | 4, 5 | W1: `FindModel` and `ConditionsModel`. W2: `BuildModel` and `LibraryModel`. W3: the Mac shell (`Mac/`: scenes, sidebar, commands, Settings with Sources and Keys, the updater UI carried over). W4: `IterScreens` Find and Conditions screens. W5: `IterScreens` Build screens. | Mac snapshot suite of every screen and state through the render copy, plus a smoke launch hidden with `-IterInMemoryStore`. Then the real-store open is tested on a **copy** of a fixture library. |
| **7** | **iOS app** (without Go) | 6 (models and screens) | W1: the iOS shell (`iOS/`: tabs, iPad split, location at launch with stub for tests). W2: the iPhone Find, Conditions and Build composition. | iOS snapshot suite on the 27.2 simulator through `xcodebuild test`, and background `simctl io screenshot` of a booted headless simulator. |
| **8** | **Go engine** | 3, 4 (parallel with 6 and 7) | W1: `IterGo` state machine and persistence. W2: `LiveLocation` adapter, ETA refresher and battery policy. W3: notification planner and the App Group `GoSnapshot` writer. W4: `IterGoActivity`. | Simulation tests on macOS: a scripted location trace with a fake clock drives a whole trip through every state. Notification requests are asserted, and so are ETA requests, at most one in flight. |
| **9** | **iOS Trip Mode UI and extension** | 7, 8 | W1: Go tab and screens in `iOS/Go/` and `IterScreens/Go/`. W2: the `Widgets/` extension (Live Activity, Island, Lock Screen accessory). W3: Info.plist and entitlements (App Group) and the one-time time-sensitive try. | On the 27.2 simulator: Live Activity views rendered by snapshot. A headless run with `simctl location <udid> start` along a route checks state changes in logs. Notification scheduling is checked through the test host. |
| **10** | **Sync** | 1, 6, 7 | W1: `.iter` v2 Send to iPhone and Send Library with merge (10a). W2: Bonjour pairing and sync in `IterSync` (10b). | Merge tests (concurrent edits, tombstones). A loopback `NWListener` and `NWBrowser` test on macOS. |
| **11** | **Cut-over** | all | Lead plus one worker: a dry run on a **copy** of the owner's real Mac store and of an iPhone backup if the owner provides one, data-equality report, delete `Legacy/`, docs (ARCHITECTURE, DATA-PROVIDERS from SOURCES.md, TESTING, ROADMAP). | A signed-off equality report, all suites green, release notes. |

**Parallel tracks after Phase 1.**
- Phase 2 and Phase 3 run together.
- Phase 5 runs together with phases 2 to 4.
- Phase 8 runs together with phases 6 and 7.
- Phase 10a can start once Phase 7 lands.

The critical path is 0 → 1 → 2 → 4 → 6 → 7 → 9 → 11.

---

## 14. Test and verification strategy

All verification is headless. Every subagent brief must say: never drive the pointer or keyboard, never activate windows, never capture the live screen, never boot the iOS 27.0 runtime, never touch `/Users/designbyjdw/Developer/Active/Iter` or its running app.

| Layer | How |
|---|---|
| Pure modules (Model, Astro, Sky, Plan) | Swift Testing in the package. Reference values (USNO and Meeus, as today). An injected clock. Property tests for monotonic leave-by and ETA effects. |
| Store | Fixture stores from the old code (Phase 0). On-disk migration tests at a temporary URL. A backup and failure-injection test. A v1 and v2 file corpus. |
| Sources | Recorded fixtures per adapter (recorded by the sources lead), pure `Mapping` tests, a registry selection table, cache TTL and stale-while-revalidate tests on a fake clock. Live tests only with `ITER_LIVE=1`, run by leads, never in worker loops. |
| AI | A `LanguageModeling` fake for every path. `ITER_LIVE_AI=1` for real runs on device-capable hardware. The grounding invariant (no coordinate from the model) asserted on every discovery test. |
| Go | Scripted location traces with timestamps, and a fake ETA provider with traffic changes, run on macOS in `swift test`. Then on the 27.2 simulator with `xcrun simctl location <udid> start --speed=… <waypoints>` in the background, reading the app's `os_log` through `log stream --predicate 'subsystem == "com.dwjames.iter"'`. |
| UI | The Mac offscreen snapshot harness (ported `AppTests/Support/Snapshot.swift`: offscreen window at −30000, `CALayer.render`, render copy only). iOS `UIHostingController` in an offscreen window through `xcodebuild test` on the 27.2 simulator. Widget and Live Activity views rendered the same way. `simctl io <udid> screenshot` of a headless booted simulator for whole-app checks. Today snapshots are written for human review, not diffed (I). Phase 5 adds a tolerance diff for the components, so they gate regressions. |
| Location in tests and render copies | `-IterLocation lat,lon` gives a fixed provider. Render copies and tests never prompt (ported `FixedLocationProvider` and `InertLocationProvider`). |

---

## 15. Owner decisions (each with the default the build uses until told otherwise)

| # | Decision | Default |
|---|---|---|
| D1 | **Is the team really free?** Every profile on this Mac has a 365-day lifetime, which is unusual for a free Personal Team. If the Apple ID has a paid membership, WeatherKit, push (remote Live Activity updates), CloudKit sync and time-sensitive alerts all become available. | **Design for free.** Keep provider protocols so WeatherKit could be one more `ForecastProvider` later. Ask the owner to check developer.apple.com ▸ Membership. |
| D2 | **Reddit.** Unauthenticated JSON fails often. Options: the endpoint SOURCES.md confirms, the user's own Reddit app credentials (OAuth, free), or off. | Use the SOURCES.md-confirmed keyless endpoint if any, otherwise **off**. An optional user OAuth comes later. |
| D3 | **Google.** | Optional user key, off by default (as today). |
| D4 | **Sidebar sections on the Mac.** | Find, Trips (pinned, folders), Saved Places (folders). "Locations" is renamed Saved Places. Conditions opens from any place, and Go is iPhone only. |
| D5 | **Attribution placement.** Owner instruction 2026-10-06 put it in Settings only, while provider terms ask for it where the data is shown. | A quiet source line with the data (as today) **and** the full credits in Settings. Re-check against each SOURCES.md licence. |
| D6 | **iPhone Find sheet.** GLASS-RULES says use the system sheet. Today it is custom because the system sheet covered the tab bar on iOS 26. | Try the system sheet on 27.2 in Phase 7. Keep the custom one only if it still covers the tab bar, and record the result in GLASS-RULES. |
| D7 | **Sync.** | 10a (AirDrop file with merge) first, then 10b (Bonjour). No iCloud Drive folder. |
| D8 | **Distribution.** | Mac: direct download with IterUpdater (as today). iPhone: Xcode install on the owner's phones. |
| D9 | **Alert thresholds.** | Leave-soon at −15 min plus leave-now. Conditions alert on ±15 points or a band change, at most one per stop per hour. |
| D10 | **Run-time astronomy source.** | Own IterAstro at run time. A military or government feed (USNO) is used as a test oracle only. |
| D11 | **Licensing module.** | Drop it. |
| D12 | **Auto-advance in Go.** | Automatic by geofence and time, with a 2-minute "Not yet" undo. |
| D13 | **Units and time format.** | Follow the device locale. Times in each stop's own time zone (as today). |
| D14 | **Score clamp.** | 0..100 instead of 5..100 (§8.1). |

---

## 16. Verified against inferred (for the record)

**Verified (V):**
- **Code and docs.** Every size, test count and module behaviour in §1. The schema, store locations and `.iter` behaviour in §5.1. No trip-mode APIs anywhere. No keyless forecast provider. No `departureDate` on directions. One-shot kilometre-accuracy location. The Overpass timeout mismatch. `RegionProposer` asking for coordinates. `test-ios.sh` picking the newest runtime.
- **Signing.** The profile entitlements and the 365-day lifetime.
- **Figma.** The Components page contents (one `get_metadata` call).

**Inferred (I):**
- SwiftData entity names derive from the class names. Phase 1's cross-module fixture test proves or disproves this before any real store is touched.
- Live Activities update locally on a free team.
- Background, `CLMonitor` and BG task behaviour.
- `calculateETA` cost.
- TLS-PSK on `NWProtocolTLS`.
- The 3-app limit and whether extensions count.
- Battery figures.
- Apple Maps offline behaviour.
