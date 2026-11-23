# Testing Iter on iPhone and iPad

**The app:** target `Iter iOS` (iPhone and iPad, iOS 26.0 or later, bundle id `com.dwjames.iter.ios`), scheme `Iter iOS`, in the same `Iter.xcodeproj` as the Mac app. The widget extension is `IterWidgets` (`com.dwjames.iter.ios.widgets`), embedded in the app. The Mac side is in [TESTING.md](TESTING.md). This page covers what differs on iOS.

Script names are the ones in `scripts/` today. If one changes, this page is wrong until it is updated.

## The one rule: never use the iOS 27.0 simulator

The iOS 27.0 beta simulator runtime crash-loops the system poster service. Use the **iOS 27.2** runtime (the one that matches your phone), or **iOS 26.5** if 27.2 also misbehaves. The default `xcodebuild` on this Mac is a beta with the iOS 27.0 SDK, so always point at the release Xcode:

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

`scripts/test-ios.sh` sets that for you, picks the runtime by name (never "newest") and refuses a device that is on 27.0.

## What is in the iOS app

- **iPhone.** One always-present system sheet over a full-screen map, with the tab bar inside it: **Find, Trips, Saved, Go**. The sheet has three heights (peek, half, full). Settings is a gear on the sheet.
- **iPad.** A split view with the sidebar Find, Trips and Saved Places, and Settings as a sheet. At compact width (Slide Over, a narrow Split View) it uses the phone layout.
- **Go.** The trip mode: next stop, leave-by, drive time, conditions and the live sky card. It posts notifications, runs a Live Activity (Lock Screen and Dynamic Island) and writes a snapshot that the widgets read.
- **Sharing.** Opens `.iter` files (v1 and v2) from AirDrop or Files and merges them. Shares a trip or the library.
- **No Sync beyond files.** There is no Bonjour or iCloud sync.
- **No updater.** iOS builds come from Xcode.

## Layers

### 1. The package

```
cd Packages/Iter && swift test
```

Same as the Mac. About 2,000 tests, with no network.

### 2. Package tests on an iOS simulator: `scripts/test-ios-package.sh`

```
scripts/test-ios-package.sh IterScreensTests
scripts/test-ios-package.sh IterScreensTests Some.XCTestCase
```

Builds one package test target for iOS and runs it on a simulator with `simctl spawn ... xctest`. It exists because `xcodebuild test` hangs before it reaches the runner on this Mac. It defaults to the device named "Iter Rebuild" on iOS 27.2 (`ITER_IOS_UDID` overrides it) and refuses 27.0. Any `ITER_*` variable is passed into the test process (for example `ITER_SNAPSHOT_RECORD=1`).

### 3. Hosted iOS tests and the whole check: `scripts/test-ios.sh`

```
scripts/test-ios.sh                          # package tests, then the app-hosted tests, on the iOS 27.2 device "Iter Rebuild"
scripts/test-ios.sh --print-device           # show the runtime, device and udid it would use, then stop
ITER_IOS_DEVICE="My Sim" scripts/test-ios.sh
ITER_IOS_UDID=<udid> scripts/test-ios.sh     # a specific simulator (still refused if it is on 27.0)
ITER_IOS_RUNTIME="iOS 26.5" scripts/test-ios.sh   # the documented fallback
ITER_IOS_SKIP_PACKAGE=1 scripts/test-ios.sh  # only the app-hosted tests
ITER_IOS_FILTER="GoPresentationTests" scripts/test-ios.sh   # an XCTest filter (Swift Testing always runs the whole bundle)
ITER_SNAPSHOT_RECORD=1 scripts/test-ios.sh   # also writes Go renders to Design/snapshots/rebuild/go/
```

It creates the device if it is missing (creating does not boot or show it), boots it without Simulator.app, builds the `Iter iOS` scheme with `build-for-testing`, and runs the `IterAppTests iOS` bundle with `simctl spawn ... xctest`. The app is never installed or launched. The bundle covers the phone and iPad shells, screens, settings, sharing, Go wiring and Go views, and the widget and Live Activity views. It never opens Simulator.app and never touches the Mac app.

### 4. Screenshots of the whole app (headless)

Create your own device on iOS 26.5 or 27.2 and boot it without a window:

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
UDID=$(xcrun simctl create "Iter Check" "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-26-5)
xcrun simctl boot $UDID; xcrun simctl bootstatus $UDID -b
xcodegen generate --quiet
xcodebuild -project Iter.xcodeproj -scheme "Iter iOS" -destination "platform=iOS Simulator,id=$UDID" \
  -derivedDataPath build/DerivedData-iOS build | grep -E "error:|BUILD"
xcrun simctl install $UDID build/DerivedData-iOS/Build/Products/Debug-iphonesimulator/Iter.app
xcrun simctl launch $UDID com.dwjames.iter.ios -IterInMemoryStore YES -IterSampleDataEnabled YES \
  -IterSeedTrip YES -IterLocation 38.57,-109.55 -IterTab find
sleep 8; xcrun simctl io $UDID screenshot find.png
xcrun simctl shutdown $UDID; xcrun simctl delete $UDID
```

Keep `-IterInMemoryStore YES` on for every screenshot. The simulator cannot be tapped from a script, so every screen has a launch switch (table below).

Notes on what a simulator shows: the "Iter Rebuild" device type is a two-display device, not a 402 by 874 point phone, so it draws the tab bar as a vertical capsule. For a faithful phone layout use an "iPhone 17 Pro" device. Liquid Glass and MapKit draw in the simulator but are still worth checking on a phone.

### 5. Go on a simulated drive

```
xcrun simctl location $UDID start --speed=20 <lat1>,<lon1> <lat2>,<lon2> ...
log stream --predicate 'subsystem == "com.dwjames.iter"'
```

Run with real Go wiring (no `-IterLocation`, no sample data), start a trip, and watch the state changes in the log. The engine itself is tested with scripted location traces and a fake clock in `IterGoTests`, with no simulator.

## Launch switches

Pass them after the bundle id with `simctl launch`, or in the scheme's Arguments. All are `-Name value` pairs, read from the process arguments.

| Switch | Effect |
|---|---|
| `-IterInMemoryStore YES` | A throwaway store. Always use it for screenshots |
| `-IterStorePath <path>` | A store at this path (never the real folder) |
| `-IterSampleDataEnabled YES` | Sample services instead of the network. Go uses fakes, so nothing prompts or posts |
| `-IterLocation lat,lon` | A fixed location. No permission is asked. Go uses fakes |
| `-IterSeedTrip YES` | Adds the sample library and trip |
| `-IterSection find\|trips\|places\|trip` | The section (with `trip`, the sample trip) |
| `-IterTab find\|trips\|saved\|go` | The tab |
| `-IterSheetDetent peek\|half\|full` | The Find sheet's height |
| `-IterOpenPlace first` | Opens the first place |
| `-IterFindQuery <text>` | Runs a Find search at launch |
| `-IterFindSelect saved` | Shows the first saved place on Find's card |
| `-IterSettings root\|sources` | Opens Settings, on a pane |
| `-IterGoSampleRun YES` | Starts the sample trip at its first stop (fakes only) |
| `-IterD6Probe YES` | Debug only. The rejected tab-bar-outside layout, kept as evidence (decision D6, see [Design/GLASS-RULES.md](Design/GLASS-RULES.md)) |

Environment variables for tests (not launch switches): `ITER_SNAPSHOT_RECORD=1` re-records snapshots, `ITER_SNAPSHOT_IOS_MODE` picks how Go snapshots are rendered, `ITER_LIVE=1` and `ITER_LIVE_AI=1` run the live Find and Conditions suite (`swift test --filter Phase4LiveTests`).

## Checking each stage by hand (simulator, sample data)

Use the launch line above with `-IterSampleDataEnabled YES -IterSeedTrip YES -IterLocation 38.57,-109.55`.

**Find.** Open on `-IterTab find -IterSheetDetent half`. Search ("-IterFindQuery waterfalls near Moab"). Results list with sources and scores. Drag the sheet between peek, half and full; the tab bar stays inside it. Select a place to see its card.

**Conditions.** Open a place with `-IterOpenPlace first`. The card shows the light windows, scores, the factors and the source line.

**Build.** `-IterTab trips`, open the sample trip. Days, stops, drive times, leave-by times, Edit for reordering, Add Stop.

**Go.** `-IterTab go -IterGoSampleRun YES`. The sample trip is at its first stop: next stop, leave-by, drive time, a conditions card and the live sky card.

**iPad.** Use an iPad simulator. The split view shows the sidebar and detail. Narrow the window and it should switch to the phone layout.

## Install on your iPhone (free team)

You need an Apple ID signed into Xcode, a Mac with Xcode, and an iPhone on iOS 26 or later. The app is signed with team `VF945J28YU` (a Personal Team), automatic signing. This is a developer install; nothing here has been run on a real phone as part of this documentation.

1. In Xcode, open **Settings ▸ Accounts** and make sure your Apple ID is signed in.
2. Connect the iPhone and unlock it. Tap **Trust** if it asks.
3. On the iPhone, turn on **Settings ▸ Privacy & Security ▸ Developer Mode**, restart when asked, and confirm.
4. Find the device: `xcrun devicectl list devices` (note its name and id).
5. In this folder run `xcodegen generate`.
6. Build for the device (the iOS 27.2 SDK):
   ```
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Iter.xcodeproj -scheme "Iter iOS" \
     -destination 'platform=iOS,name=<iPhone name>' -derivedDataPath build/DerivedData-iOS-device -allowProvisioningUpdates build
   ```
   Or open `Iter.xcodeproj`, choose the `Iter iOS` scheme and your iPhone, and press Run.
7. If you built on the command line, install it: `xcrun devicectl device install app --device <id> build/DerivedData-iOS-device/Build/Products/Debug-iphoneos/Iter.app`.
8. On the iPhone, trust the developer: **Settings ▸ General ▸ VPN & Device Management**, tap the Apple Development profile, tap **Trust**. Then open Iter.
9. Allow location when asked. During a Go run it asks once more for **Always**.

**The first launch on the phone migrates the phone's library to V5 and writes a backup first.** The backup is in the app's Application Support folder under `Iter/Backups/pre-v5-<date>/`. The earlier Iter app cannot open the library after that. Before you install, you can keep your own copy: Xcode ▸ Window ▸ Devices and Simulators ▸ select the phone ▸ select Iter ▸ the gear ▸ Download Container. (A dry run of the migration on a phone backup has not been done.)

Free-team limits:

- **How long it stays installed.** A free Personal Team normally signs for 7 days, after which the app stops opening until you build and install again. The blueprint found 365-day profiles for every app on this Mac, which suggests a different kind of team. Which one applies is not confirmed (decision D1). Check the profile expiry in **VPN & Device Management**.
- **Three apps.** A free team can have at most 3 sideloaded apps. Whether the widget extension counts is not confirmed.
- **What a free team cannot do.** No push (so the Live Activity updates only while Iter is alive), no CloudKit, no WeatherKit, no associated domains. Time-sensitive notifications are not in any profile on this Mac, so assume they do not work.
- **Apple Intelligence.** Needs a supported iPhone (15 Pro or later) with it turned on. Without it, Find still works with Basic search.

## First-look checklist (iPhone)

The Mac checklist in [TESTING.md](TESTING.md) covers first launch, Liquid Glass, maps, real sources, Apple Intelligence and sharing. These are the ones that need a real phone.

- [ ] First launch on the phone: the library opens and matches what you had, and a `Backups/pre-v5-...` folder exists in the app container.
- [ ] Liquid Glass: the Find sheet, tab bar, map controls and the Go cards draw as real glass in light and dark.
- [ ] The tab bar is inside the sheet at peek, half and full, and every tab is tappable.
- [ ] Map pins and clusters draw. Touch and hold your own pin until it lifts, drag it, and the coordinates update.
- [ ] Drag and drop: reorder stops in a trip's Edit mode. Move a place into a folder.
- [ ] Location is asked at launch (When In Use). Go asks for Always, once, with its reason, when a run starts.
- [ ] Start Go on a trip. Lock the phone and move toward the first stop. Location updates continue in the background.
- [ ] Live Activity on the Lock Screen and the Dynamic Island: the stop, leave-by and countdown are right, and old data is not labelled live.
- [ ] Notifications from the Lock Screen: leave-soon and leave-now arrive. Navigate on leave-now opens Apple Maps. On automatic arrival, Not yet undoes it.
- [ ] Do notifications break through a Focus? (Time-sensitive is expected not to work on a free team.)
- [ ] Force-quit during a run and reopen: the run is still there.
- [ ] Home widget: add it and compare it with the app.
- [ ] AirDrop: receive a trip and the library from the Mac. A second send updates the trip, not duplicates it. A trip changed on the phone and sent back updates the Mac.
- [ ] Real network sources on cellular and on Wi-Fi, including Find with Apple Intelligence on and off.
- [ ] Battery over a one-hour drive with Go running. Note the percentage.

## Known limits

1. The simulator cannot be tapped from a script, and no headless run was a drive. Go's background behaviour, Always location, the Live Activity running, notification actions and battery are only proven in tests with fakes.
2. The "Iter Rebuild" simulator is a two-display device. Layout evidence for the tab bar and sheet (decision D6) came from it and should be rechecked on a phone-sized device.
3. FoundationModels is weak-linked (`-weak_framework FoundationModels` in `project-ios.yml`). Built with the iOS 27 SDK, the `@Generable` code refers to a symbol iOS 26 does not have, and a strong link stops the app at launch on iOS 26. Find checks availability before it uses the model.
4. No updater on iOS, and no offline base map (MapKit has no way to download tiles). Pinned and active trips keep their conditions, drive times and images.
5. Old script names: `scripts/snapshots-ios.sh` still refers to the old `AppiOS` tests and looks out of date. Use `scripts/test-ios.sh` with `ITER_SNAPSHOT_RECORD=1`, or the screenshot steps above.
