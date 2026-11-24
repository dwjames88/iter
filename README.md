# Iter

Iter is a road-trip planner for photographers. It helps you be in the right place when the light is right. It has four stages, in one flow:

1. **Find.** Search for photo spots by name or by a plain request ("waterfalls near Yosemite for sunrise"). With Apple Intelligence on the device, the request is understood by the model. Without it, a simple parser still finds places. Every place is checked against real map data and cites where it came from.
2. **Conditions.** For a spot and a day, Iter shows the weather and the sky and scores each shooting window (sunrise, sunset, golden hour, blue hour, night) from 0 to 100. Each number says which source it came from, how old it is, and what could not be found.
3. **Build.** Put spots into a trip, day by day. Iter orders the stops by light, works out drive times, set-up time and when to leave, and flags what does not fit.
4. **Go.** On the iPhone, trip mode follows the trip: the next stop, when to leave, the drive time, current weather and the sky now. It uses a Live Activity, the Dynamic Island, the Lock Screen and notifications.

Everything is free to run. Iter uses free public data (NOAA, MET Norway, USGS, OpenStreetMap, Wikipedia, NASA and Apple Maps) and needs no account and no key. The full list is in [docs/DATA-PROVIDERS.md](docs/DATA-PROVIDERS.md).

## Platforms

| | App | Needs |
|---|---|---|
| Mac | `Iter` (bundle id `com.dwjames.iter`) | macOS 26 or later. Find, Conditions and Build. No Go |
| iPhone and iPad | `Iter iOS` (bundle id `com.dwjames.iter.ios`) | iOS 26 or later. Find, Conditions, Build and Go. Go is for the iPhone |

Apple Intelligence is optional. It needs a device that supports it, with it turned on. Without it, Find says it is using Basic search.

Trips move between the Mac and the iPhone as `.iter` files (AirDrop from the Mac's **Send to iPhone**). There is no live sync yet. See [docs/ROADMAP.md](docs/ROADMAP.md).

## Your data and the first launch of this version

This version replaces the earlier Iter app and keeps its data. **The first time the new app opens the real store, it changes the store to schema V5, and the earlier Iter app cannot open it after that.** Iter makes a backup first. If the backup fails, the store is not opened and nothing is changed.

- **Mac.** The store is `~/Library/Application Support/Iter/Iter.store`. The backup goes in a new folder `~/Library/Application Support/Iter/Backups/pre-v5-<date and time>/`.
- **iPhone.** The store is in the app's own Application Support folder, and the backup goes in `Iter/Backups/` there. On the iPhone you can reach it by copying the app container (Xcode ▸ Devices and Simulators ▸ Download Container).
- **What is in a backup.** Copies of the raw store files, every trip as an `.iter` file the earlier app can open, and `backup.json` with the counts.
- **If the new store fails to open.** Iter keeps the original file untouched, builds a new store beside it from the backup's `.iter` files, and shows a one-time notice with the backup folder.
- **Going back.** Quit the new app and restore `Iter.store` (and its `-wal` and `-shm` files) from the backup folder, or import the `.iter` files into the earlier app.

Settings and keys: the Mac keeps its settings in the app's preferences and any keys in the Keychain. This version needs no keys.

## Build and run

You need a Mac with Xcode, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The Xcode project is generated from `project.yml` and `project-ios.yml` and is not committed. Each script below runs `xcodegen generate` for you.

**The real Mac app.** This is the one that opens your real store.

```
scripts/run.sh            # builds build/Iter.app (signed with your Apple Development certificate); does not open it
scripts/run.sh --real     # the same, then opens it: the real app on the real store, first launch migrates to V5
```

It runs as `com.dwjames.iter`. Opening it for the first time on your real library triggers the migration above. If you want to look at the app without touching your data, use the render copy.

**The render copy.** The same Mac app under another bundle id, `com.dwjames.iter.render`, signed ad hoc. It can never open the real store or the real Keychain, and it never asks for location. Use it to look at the app, take screenshots and run tests.

```
scripts/render.sh                                  # builds build/render/Iter.app
scripts/render.sh --run --wait 15 -- -IterSection trips
scripts/smoke-mac.sh                               # a hidden launch that checks the app starts
```

The render copy runs on sample data with an in-memory store. See [TESTING.md](TESTING.md) for the launch switches.

**The iPhone and iPad app.**

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/test-ios.sh   # build and test on the iOS 27.2 simulator
```

To put it on your own iPhone, follow "Install on your iPhone" in [TESTING-iOS.md](TESTING-iOS.md). It uses a free Personal Team and Xcode.

**The package.** Everything that is not a platform shell is in `Packages/Iter` and tests without Xcode projects:

```
cd Packages/Iter && swift test
```

## What is in the repository

```
Packages/Iter/         the package (16 library targets): model, sky index, planning, store, sources, discovery,
                       conditions, Go engine, UI kit, features, screens
Packages/IterUpdater/  the Mac updater and the release tool
Mac/                   the Mac app shell
iOS/                   the iPhone and iPad app shell
Widgets/               the Live Activity, Dynamic Island, Lock Screen and Home widgets
Tests/Hosted/          tests that run inside an app (Mac render copy, iOS simulator)
Design/                design tokens, glass rules, Figma map, screen renders
Brand/                 logo and palette
docs/                  documentation (below)
scripts/               build, test, render and release scripts
project.yml            Mac project spec (XcodeGen), includes project-ios.yml
project-ios.yml        iOS app, widget and iOS test targets
```

## Documentation

| | |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the app is built: targets, store and migration, sources, discovery, sky index, Go, sync |
| [docs/DATA-PROVIDERS.md](docs/DATA-PROVIDERS.md) | Every data source, who runs it, its licence, its credit text and its rate limits |
| [docs/ROADMAP.md](docs/ROADMAP.md) | What is next and why |
| [TESTING.md](TESTING.md) and [TESTING-iOS.md](TESTING-iOS.md) | How to test each layer, the launch switches, and the first-look checklist |
| [CHANGELOG.md](CHANGELOG.md) | What changed |
| [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) | Versions, releases and updates (Mac) |
| [docs/PERFORMANCE.md](docs/PERFORMANCE.md) | Performance rules and measurements |
| [Design/GLASS-RULES.md](Design/GLASS-RULES.md) | The rules for the Liquid Glass interface |
| [docs/rebuild/](docs/rebuild/) | The record of the rebuild: the audit and blueprint, and the data-source research. Not edited |

## Contributing and licence

See [CONTRIBUTING.md](CONTRIBUTING.md). The licence is in [LICENSE](LICENSE). Iter has no licensing or key check in the app.
