# Iter

A native road-trip planner (Mac, iPhone and iPad) for photographers. *Be in the right place when the light is right.*

`scripts/run.sh` builds and opens the app (`build/Iter.app`), and `scripts/test.sh` runs every test.
The iPhone and iPad app builds from the same project (scheme `Iter iOS`); `scripts/test-ios.sh` builds it and runs its tests on a Simulator, and [TESTING-iOS.md](TESTING-iOS.md) covers running it on a Simulator and on your iPhone.
Start with [TESTING.md](TESTING.md) for the Mac app. It covers what is in this build, a guided tour, the Debug menu, and how to switch on real weather.

- SwiftUI, MapKit, WeatherKit, Apple Intelligence (Foundation Models), SwiftData, Swift Charts. No third-party code.
- macOS 26 or later; iOS 26 or later for the iPhone and iPad app. Swift 6 with complete concurrency checking. Tests use Swift Testing.
- The Xcode project is generated from `project.yml` by XcodeGen (`brew install xcodegen`).

| Where | What |
|---|---|
| `docs/ARCHITECTURE.md`, `docs/ROADMAP.md` | How it is built; what milestone 1 contains and what comes next |
| `docs/DATA-PROVIDERS.md` | Weather sources (Apple Weather, OpenWeather, Windy): what each gives the Light Index, limits, licences, attribution, caching |
| `docs/reference/` | The approved improvement plan and the prototype's flow briefs |
| `Design/` | Design tokens (`tokens.json`, DTCG), `TOKENS.md`, `SCREENS.md`, `COMPONENTS.md`, `snapshots/` |
| `Brand/` | The Step logo (Geist 600) and the First Light palette (`palettes/` also keeps the Alpine study as history) |
| `Packages/IterKit/` | Everything that is not Mac UI: domain, light engine, astronomy, data, services, view models |
| `App/` | The macOS app's scenes, menus and settings, plus the views, assets and String Catalog that the iOS app compiles too |
| `AppiOS/`, `AppiOSTests/` | The iPhone and iPad app: shell, Explore, Trips, Locations, Settings, Info.plist (target in `project-ios.yml`) and its tests |
| `docs/DISTRIBUTION.md`, `CHANGELOG.md` | Versions, cutting a release, the signed update feed and keys, Gatekeeper; what changed in each version |
| `scripts/` | `run.sh`, `test.sh`, `test-ios.sh`, `snapshots.sh`, `tokens.sh` (design tokens round trip), `make-icon.sh`, `strings.sh`, `release.sh`, `bump.sh`, `version.sh`, `updater-e2e.sh` |
