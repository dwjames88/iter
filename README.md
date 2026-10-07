# Iter

A native Mac road-trip planner for photographers. *Be in the right place when the light is right.*

`scripts/run.sh` builds and opens the app (`build/Iter.app`), and `scripts/test.sh` runs every test.
Start with [TESTING.md](TESTING.md). It covers what is in this build, a guided tour, the Debug menu, and how to switch on real weather.

- SwiftUI, MapKit, WeatherKit, Apple Intelligence (Foundation Models), SwiftData, Swift Charts. No third-party code.
- macOS 26 or later. Swift 6 with complete concurrency checking. Tests use Swift Testing.
- The Xcode project is generated from `project.yml` by XcodeGen (`brew install xcodegen`).

| Where | What |
|---|---|
| `docs/ARCHITECTURE.md`, `docs/ROADMAP.md` | How it is built; what milestone 1 contains and what comes next |
| `docs/DATA-PROVIDERS.md` | Weather sources (Apple Weather, OpenWeather, Windy): what each gives the Light Index, limits, licences, attribution, caching |
| `docs/reference/` | The approved improvement plan and the prototype's flow briefs |
| `Design/` | Design tokens (`tokens.json`, DTCG), `TOKENS.md`, `SCREENS.md`, `COMPONENTS.md`, `snapshots/` |
| `Brand/` | The Step logo (Geist 600) and the First Light palette (`palettes/` also keeps the Alpine study as history) |
| `Packages/IterKit/` | Everything that is not Mac UI: domain, light engine, astronomy, data, services, view models |
| `App/` | The macOS app: views, menus, settings, assets, the String Catalog |
| `docs/DISTRIBUTION.md`, `CHANGELOG.md` | Versions, cutting a release, the signed update feed and keys, Gatekeeper; what changed in each version |
| `scripts/` | `run.sh`, `test.sh`, `snapshots.sh`, `tokens.sh` (design tokens round trip), `make-icon.sh`, `strings.sh`, `release.sh`, `bump.sh`, `version.sh`, `updater-e2e.sh` |
