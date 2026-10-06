# Architecture

Iter is a native macOS app (SwiftUI, Swift 6 language mode with complete concurrency checking), **deployment target macOS 26.0**: the lowest version that has the Foundation Models framework (`SystemLanguageModel`, `Tool`, `@Generable`) and `MKReverseGeocodingRequest`. Everything else used (WeatherKit `cloudCoverByAltitude` macOS 15, SwiftData, Swift Charts, MapKit for SwiftUI, Look Around) is older. No third-party code at build time or run time; XcodeGen generates `Iter.xcodeproj` from `project.yml`.

## Layout

```
project.yml              XcodeGen spec (app target, hosted test target, signing, entitlements)
App/                     macOS UI only: scenes, windows, views, commands, settings, assets, string catalog
AppTests/                hosted tests: snapshot renderer (Design/snapshots) and live service checks
Packages/IterKit/        everything that is not macOS UI, reusable by a future iOS target
Design/                  tokens.json (DTCG), TOKENS.md, SCREENS.md, COMPONENTS.md, snapshots/
Brand/                   Step (Geist 600) logo files and the First Light palette (Alpine kept in the palette files as history)
docs/                    this file, ROADMAP.md, reference/ (the approved plan and flow briefs)
scripts/                 run.sh, test.sh, tokens.sh, make-icon.sh, snapshots.sh
```

## Modules (Packages/IterKit)

| Target | Depends on | Holds |
|---|---|---|
| `IterCore` | Foundation | Value types (`Spot`, `TripPlan`, `LocalDay`, `Forecast`, `LightWindow`, `LightAssessment`, `TripSchedule`) and the service protocols (`Ephemeris`, `WeatherProviding`, `PlaceSearching`, `Geocoding`, `DriveTimeProviding`, `Scouting`). No user-facing strings. |
| `IterAstro` | Core | `Astronomy: Ephemeris`. Solar position and events (NOAA/Meeus), lunar position, phase and rise/set (Meeus, abridged). Own code, unit-tested against published values. |
| `IterLight` | Core, Astro | `LightEngine` builds the five windows for a spot and day and scores each from a forecast; confidence and range from lead time; structured contributors (the "why"). `TripScheduler` (backward schedule and feasibility), `LightFirstOrdering` (suggested order). Pure and deterministic. |
| `IterData` | Core | SwiftData models (`PlaceRecord`, `TripRecord`, `StopRecord`), `IterStore` (main-actor repository with named undo actions), curated spots (`curated-spots.json`), `TripDocument` (the `.iter` export format), sample seed trips and templates. |
| `IterServices` | Core, Light, Data | the weather providers (`AppleWeatherService` over WeatherKit, `OpenWeatherService`, `WindyService`, each a `WeatherProviding`), `WeatherRouter` (primary, then fallback), `APIKeyStore` (Keychain) and `APIKeyResolver`, `ProviderCache` and `CallBudget`, `SampleWeatherService` (Debug menu only), MapKit search, geocoding and directions (cached, throttled), `AppleIntelligenceScout` (Foundation Models with tools), `LightExplainer`. |
| `IterDesign` | Core, SwiftUI | The token registry (`TokenValues.swift`, the single source for colours, type, spacing, radii and the light ramp), the SwiftUI API (`IterColor`, `IterSpace`, `IterRadius`, `IterFont`; text tokens are `IterInk`, which is prominence-aware) and small cross-platform primitives (Light Index badge, confidence mark). |
| `IterFeatures` | all above | `@Observable @MainActor` view models for Explore, Spot, Trips, Trip builder, Scout and Saved, plus `AppEnvironment` (the service container). Platform-neutral. |
| `iter-tokens` | Design | Exports `Design/tokens.json` (DTCG) and the app's asset-catalog colour sets from the registry; imports an edited `tokens.json` back into the registry. |

The app target holds only views, scenes, menus and AppKit glue (map click handling, window restoration). An iOS target would add its own views over the same view models.

## Data flow

```
 SwiftData store ──► IterStore (main actor) ──► view models ──► SwiftUI views
                                         ▲               │
 curated-spots.json ─────────────────────┘               ▼
                          AppEnvironment services (Sendable / actors)
                 ┌───────────────┬───────────────┬────────────────┬──────────────┐
          WeatherProviding   PlaceSearching   DriveTimeProviding   Scouting     Ephemeris
           (WeatherRouter,    (MKLocalSearch,   (MKDirections,      (Foundation   (IterAstro)
            see below)         MKGeocoding)      cache, throttle)    Models+tools)
                 └──────────────► LightEngine ◄─────────────────────────────────────┘
                                      │
                               DayLight / LightWindow ──► every light view draws the same window object
```

Weather in detail (`IterServices/Weather`; the facts and limits of each provider are in [DATA-PROVIDERS.md](DATA-PROVIDERS.md)):

```
 ForecastCenter ──► WeatherRouter (actor: primary, then the fallback)
                      ├─► AppleWeatherService ──► CachedWeatherService (actor)
                      ├─► OpenWeatherService ─┐   APIKeyResolver: environment ► launch argument ► Keychain
                      └─► WindyService ───────┤   CallBudget.reserve (UTC day, cap) ── before the network
                                              ▼
                              ProviderCache (per spot ~1 km, per hour)
                              OpenWeather: disk, through the next clock hour
                              Windy: memory only, 3 hours
```

`WeatherProviderFactory` builds the stack from `WeatherSettings` and re-points a running router when Settings change. A cache hit never reaches the budget. Every attempt is reported to an observer so Settings can show a status per provider. Each provider's mapping (`OpenWeatherMapping`, `WindyMapping`) is a pure function from response bytes to `Forecast`.

* **One window object.** `LightEngine.dayLight(...)` returns `DayLight` with five `LightWindow`s. The badge, the timeline band, the arc marker, the hourly tint and the trip stop all read the same object, so they cannot disagree.
* **Honest unknowns.** A window with no forecast carries `.noForecast(reason)`, never a number. Reasons: WeatherKit not enabled, service failed, beyond the forecast horizon, in the past, not loaded, provider needs an API key, key rejected, daily call cap reached, testing key (shuffled data), and a named provider failed. A field a provider does not supply (OpenWeather has no cloud layers and caps visibility; Windy has no rain probability) is left unknown, never filled in. The score drops that factor, says so in a note (`ScoreNote`) and lowers confidence: the lead-time limits are 36 and 72 hours, 24 hours for the high level when any hour is interpolated from three-hourly steps, low for any daily-summary hour, and one step down for a window that needed cloud layers and had none.
* **The headline rule.** The headline is the score of the window for the user's intent (default: the spot's best light), always printed with its name ("Sunset · 38"). Night is its own intent and cannot lift sunrise, sunset or blue hour.
* **Attribution per provider.** Each provider's required attribution (Apple Weather: Apple's mark and legal page; OpenWeather: "Weather data © OpenWeather", linked (ODbL); Windy: "Contains data from the Windy database", linked, and the Windy logo, not shipped yet) lives in Settings ▸ Weather ("Data Sources and Attribution") and Settings ▸ About (`WeatherDataSources`), at the owner's instruction of 2026-10-06 for this test build; the providers' terms ask for it where the data is shown, so this must be revisited before release (see DATA-PROVIDERS.md). Content screens name the source quietly: lists show one source line per distinct source (`ForecastSourceLines`), including a fallback ("OpenWeather (Apple Weather unavailable)"), and a single forecast shows its source line with the fetch time. The Settings change path: `WeatherSetup` re-points the router, then `AppModel` calls `ForecastCenter.invalidateAll()` so every screen refetches; ⌘R (`retryFailed`) re-requests only the failed forecasts.
* **The Windy map is a link, not a view.** Windy's widget terms exclude weather apps and commercial sites, and the Map Forecast API trial is development-only with keys bound to web domains. So the spot page (Windy section) and Explore (toolbar button) have "Open in Windy", which opens windy.com in the browser (`WindyLink`). Windy data is never stored on disk (its terms forbid it).
* **Grounded scout.** The model can only name places returned by its tools (MapKit search, curated spots). Its structured output refers to tool-result IDs; anything else is dropped before display. The Light Index, not the model, scores the window.

## Concurrency

* Swift 6 language mode, complete checking, no `@unchecked Sendable` except where a framework type forces it (documented at the site).
* View models and `IterStore` are `@MainActor`. SwiftData `ModelContext` is used only on the main actor; the store is small (hundreds of rows).
* Services are `Sendable` structs or actors. Weather and directions caches are actors keyed by rounded coordinate (provider caches also by UTC hour); directions requests are serialised with a minimum spacing to respect MapKit throttling, and failures fall back to a labelled straight-line estimate.
* Long work (forecast fan-out for many spots, scout) runs in structured tasks owned by the view model and cancelled when the view goes away or the input changes.

## Persistence and sync readiness

SwiftData models follow CloudKit's rules so iCloud sync can be switched on later: every attribute has a default or is optional, no `@Attribute(.unique)`, every relationship is optional with an explicit inverse, enums stored as raw strings. Curated spots are not stored; a saved curated spot is a `PlaceRecord` with `curatedID` set.

## Undo

Every structural or destructive edit (delete trip, delete spot, add, remove or move a stop, rename, change dates) goes through `IterStore`, which registers a named action on the window's `UndoManager` (Edit > Undo Delete Trip). The model context's own undo is not relied on, so action names are explicit and undo groups match user actions.

## Signing and capabilities

Bundle ID `com.dwjames.iter`, team `VF945J28YU` (a Personal Team, free provisioning), automatic signing with "Apple Development certificate". App Sandbox with outgoing network and user-selected files. The WeatherKit entitlement lives in `App/Iter-WeatherKit.entitlements` and is used only when `scripts/run.sh --weatherkit` is run, because WeatherKit needs a paid Developer Program team with the capability on the App ID; see TESTING.md. API keys for OpenWeather and Windy live in the login Keychain (generic passwords, service `com.dwjames.iter.weather`, account = the provider's name). That is the file-based keychain, so it needs no keychain entitlement and does not use `kSecUseDataProtectionKeychain`. Keys are never in the repo, in UserDefaults or in logs. The sandbox's outgoing network access covers the provider calls.

## Testing and inspection

* `swift test` (package): domain, astronomy against USNO, JPL Horizons and Meeus reference values, the Light Index rules (overcast golden hour is never Good; night never lifts a daytime intent; no forecast never gives a number), the scheduler and ordering, store and undo, services with fakes, view models. `ITER_LIVE=1` adds live MapKit and WeatherKit checks, and live OpenWeather and Windy checks when a key is present (the weather mapping, cache, budget and router tests use documented-schema fixtures and fakes, not recorded responses), and `ITER_LIVE_AI=1` adds live Scout and explainer runs.
* `xcodebuild test` (hosted in the app): renderer pixel tests and the snapshot suites. `scripts/snapshots.sh` renders every screen and state offscreen to `Design/snapshots` (`AppTests/Support/Snapshot.swift` explains how and what cannot be drawn: live maps, toolbar items, traffic lights). Map views draw `MapStandIn` when `\.renderMode == .snapshot`.
* Smoke: `open -g -j build/Iter.app --args -IterSmokeTest YES -IterInMemoryStore YES` runs `SmokeHook` from app launch (no UI needed) and logs `smoke: …` lines under subsystem `com.dwjames.iter`.
* Launch switches for screenshots and checks (`AppLaunch`): `-IterSection explore|saved|scout|trips|trip`, `-IterAppearance light|dark`, `-IterSettingsTab general|weather|intelligence|about` (opens Settings on that tab) and `-IterSpot <curated spot id>` such as `mesa-arch` (opens Explore with that spot's page). A weather key can be passed for one run with `-ITER_OPENWEATHER_KEY <key>` or `-ITER_WINDY_KEY <key>`.

## Scout pipeline

Two sessions, because the on-device model's context is 4,096 tokens. (1) *Gather*: a session with tools (`FindPlacesTool` over MapKit, `CuratedSpotsTool`, `DriveTimeTool`) that registers every place it finds under a short ID. (2) *Pick*: a fresh session without tools that sees only the registered candidates and returns `@Generable ScoutAnswer` (IDs, a short reason limited to what the candidate data says, a window). `ScoutGrounding` drops any ID not in the registry and takes names and coordinates only from the registry. Parse failures are retried (greedy sampling) and tolerated when candidates already exist.

## Strings

All user-facing text is in `App/Resources/Localizable.xcstrings` (510 strings). The package produces structured values (factors, reasons, enums); the app phrases them, light vocabulary in `App/Sources/Text/LightText.swift`. Xcode's editor syncs the catalog on build; from the command line run `scripts/strings.sh` after a build.
