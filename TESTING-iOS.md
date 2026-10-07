# Testing Iter on iPhone and iPad (first cut)

**The app:** target `Iter iOS` (iPhone and iPad, iOS 26.0 or later, bundle id `com.dwjames.iter.ios`), scheme `Iter iOS`, in the same `Iter.xcodeproj` as the Mac app. `scripts/test-ios.sh` builds it and runs its tests on a Simulator. The Mac build and its tour are in [TESTING.md](TESTING.md); this file covers only what differs on iOS.

## What is in this build

- **iPhone:** a tab bar with Explore, Trips, Locations and Settings, and a separate round search button (a search tab) that holds Apple Maps and Ask suggestions.
- **Explore:** a full-bleed map with a bottom sheet that sits above the tab bar and has three heights (peek, half, full). The header has a very large title, round buttons and a row of chips. Selecting a pin or a row puts the light panel in the sheet. **Show full page** (or opening a spot from anywhere) pushes the spot page.
- **Trips:** a list with filter chips, New Trip, import, and swipe and context actions; the builder has days, stops, drive times, a route map, reordering through **Edit**, and Share.
- **Locations:** your spots and folders. **Settings:** Weather, Apple Intelligence, Location, General, This build, Updates, What the scores mean (the colour and score legend) and About.
- **iPad (regular width):** a split view with the sidebar Trips, Locations and Find, like the Mac. Settings opens as a sheet. At compact width (Slide Over, narrow Split View) the iPad uses the phone layout.
- Everything below the screens is shared with the Mac: all IterKit modules, the asset catalog, the String Catalog and most views in `App/Sources`. See "Platforms" in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

**Not in this build:** Now mode, the "Tonight" Live Activity, widgets and CarPlay (see "Next on iOS" in [docs/ROADMAP.md](docs/ROADMAP.md)), iCloud sync (a trip made on the Mac does not appear on the iPhone yet), an in-app updater, and offline base map tiles (MapKit has no way to download them). Pinned trips keep forecasts, drive times and images, as on the Mac.

## Forecasts: the key

WeatherKit needs a paid Apple Developer Program team, and this build is signed with a free Personal Team. So on iOS the first-run forecast source is **OpenWeather** (the registered default for `iter.weather.primary`). Without a key, screens show "needs a key" instead of scores. Getting a key is the same as on the Mac (see "Turning on forecasts without WeatherKit" in [TESTING.md](TESTING.md)).

Three ways to give Iter the key:

1. **Settings.** Settings ▸ Weather, paste the key, Save. It goes in the Keychain and survives relaunch (checked on the Simulator).
2. **A launch argument for one run:** `-ITER_OPENWEATHER_KEY <key>`. It overrides the Keychain and is not saved.
3. **Save it from the argument (Debug builds only):** add `-IterSaveOpenWeatherKeyFromArgument YES` once; the key from the argument goes into the Keychain through the same path as the Save button, and later launches need no argument.

The key is never printed or logged by the app. Do not paste it into scripts or notes you keep.

## Build and run on the Simulator (headless)

Nothing here opens Simulator.app. Pick a device with `xcrun simctl list devices available` and use its UDID.

```
cd <this folder>
xcodegen generate --quiet
xcodebuild -project Iter.xcodeproj -scheme "Iter iOS" -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath build/DerivedData-iOS build 2>&1 | grep -E "error:|BUILD"
xcrun simctl boot <UDID> 2>/dev/null; xcrun simctl bootstatus <UDID> -b
xcrun simctl install <UDID> build/DerivedData-iOS/Build/Products/Debug-iphonesimulator/Iter.app
xcrun simctl terminate <UDID> com.dwjames.iter.ios 2>/dev/null
xcrun simctl launch <UDID> com.dwjames.iter.ios -IterInMemoryStore YES -IterSeedLibrary YES -IterSeedTrip YES \
  -IterAppearance dark -ITER_OPENWEATHER_KEY <key>
sleep 8; xcrun simctl io <UDID> screenshot shot.png
xcrun simctl location <UDID> set 38.5733,-109.5498     # Moab, so "near you" has something to show
```

`-IterInMemoryStore YES` runs on a throwaway store, so it never touches the Simulator's real data. Drop it to test persistence. Taps cannot be scripted on the Simulator, so every screen below has a launch switch (table further down).

**Tests:** `scripts/test-ios.sh` runs the IterKit package tests, then the 37 Swift Testing tests of `IterAppTests iOS` on an iPhone 17 Pro Simulator, headless. Use `ITER_IOS_DEVICE="iPad Pro 11-inch (M5)"` or `ITER_IOS_UDID=<udid>` to pick another. Do not run the Mac scheme's tests while the Mac app is open; `test-ios.sh` never touches it.

## Install on your iPhone (free team)

You need an Apple ID signed into Xcode, a Mac with Xcode, and an iPhone on iOS 26 or later. The app is signed with team `VF945J28YU` (a Personal Team), automatic signing.

1. In Xcode, open **Settings ▸ Accounts** and make sure your Apple ID is signed in.
2. Connect the iPhone with a cable and unlock it. Tap **Trust** if it asks about the computer.
3. On the iPhone, turn on **Settings ▸ Privacy & Security ▸ Developer Mode**, then restart when asked and confirm.
4. Find the device: `xcrun devicectl list devices` (note its name and id).
5. In this folder run `xcodegen generate`.
6. Build for the device:
   ```
   xcodebuild -project Iter.xcodeproj -scheme "Iter iOS" -destination 'platform=iOS,name=<iPhone name>' \
     -derivedDataPath build/DerivedData-iOS-device -allowProvisioningUpdates build
   ```
   Or open `Iter.xcodeproj`, choose the `Iter iOS` scheme and your iPhone, and press Run; that also installs it.
7. If you built on the command line, install it: `xcrun devicectl device install app --device <id> build/DerivedData-iOS-device/Build/Products/Debug-iphoneos/Iter.app`.
8. On the iPhone, trust the developer: **Settings ▸ General ▸ VPN & Device Management**, tap the Apple Development profile, tap **Trust**. Then open Iter.
9. Open **Settings ▸ Weather** in Iter and paste your OpenWeather key.

Free-team limits: the app stops opening after 7 days (build and install again), a free team can have at most 3 apps installed this way, WeatherKit is unavailable (hence OpenWeather), and the app needs iOS 26 or later. Ask Iter needs Apple Intelligence: an iPhone 15 Pro or later (or a supported iPad) with Apple Intelligence turned on. Without it, search still works and Ask says why it is off.

## A guided tour

Launch with the seed switches (`-IterInMemoryStore YES -IterSeedLibrary YES -IterSeedTrip YES`) and a key. If you are on a real iPhone you can do all of this by hand.

### iPhone

1. **Explore.** The map fills the screen and the sheet rests at its middle height (half). Drag the sheet's header up to full and down to peek; it should stop at each of the three heights and the tab bar should stay visible and tappable at all of them. (Simulator: `-IterSheet peek|half|full`.)
2. **Chips.** The row under the title filters the list (for example by when and by kind). Pick one and the list and the pins change together.
3. **A pin.** Tap a pin or a row. The sheet shows the light panel: small caps overline, big title, a status band in the colour of the next window, large times, fact chips, two cards, Good to know and an action pill. The round button at the top closes it and returns to the list where you left it. A round map button in Explore's control stack (and at the corner of the Locations and trip route maps) chooses Standard, Satellite or Hybrid for every map, and the choice is remembered. Selecting a place also moves the map to about 25 miles around it (it only pans when you are already zoomed in closer), and closing the panel leaves the map where it is. (Simulator: `-IterSelectRow mesa-arch`.)
4. **Search and Ask.** Tap the round search button. Typing shows two suggestions, Apple Maps and Ask Iter, the likelier first. Try "Skógafoss", then "waterfalls near here for sunrise". (Simulator: `-IterSection search -IterQuery "text"`, `-IterSearch "Skógafoss"`, `-IterAsk "…"`, `-IterScoutStub results`.)
5. **Spot page.** From the panel choose the full page: when to go, the five windows, the light timeline, the sun and moon arc, hourly weather, sun and weather facts. Back returns to Explore. (Simulator: `-IterSpot mesa-arch`.)
6. **Trips.** The list shows trips with filter chips (All, Pinned, folders). Swipe a trip or press and hold it for its menu; New Trip opens the new-trip sheet; the import button opens the file picker for `.iter` files. (Simulator: `-IterSection trips`, `-IterNewTrip YES`, `-IterTripsFilter pinned`.)
7. **Builder.** Open a trip. Move between days; each stop shows its schedule ("Leave 4:10, set up by 5:52, Sunrise 6:12") and drive times between stops. Tap **Edit**: handles appear; drag stops to reorder and delete with the red control. The route map collapses to a bar. **Add stop** opens the add sheet. (Simulator: `-IterSection trip -IterTripDay 2 -IterEditStops YES -IterRouteCollapsed YES -IterAddStop YES`; `-IterSeedTrip conflict` reverses day 2 to show a conflict.)
8. **Share and import.** In the builder, the share button offers the trip as an `.iter` file. Send it to yourself (AirDrop, Files), open the file and Iter should import it as a new trip; a garbled file shows "Couldn't open this trip".
9. **Locations.** Folders and spots; open a folder, swipe or hold a spot for actions. (Simulator: `-IterSection locations -IterLocationFolder <name>`.)
10. **Settings.** The grouped form: Weather (source, keys, caps, status), Apple Intelligence (status and what to do when it is off), Location (permission state), General (temperature, set-up time), This build (version), Updates (a note: updates will come through TestFlight; nothing to check in the app) and About. (Simulator: `-IterSection settings -IterSettingsTab weather|intelligence|about`.)
11. **Light and dark.** Switch with the system setting or `-IterAppearance light|dark`; check that every screen is readable in both.

### iPad

1. Launch on an iPad Simulator or iPad. The sidebar lists All Trips (with pinned trips and folders under Trips), Locations and Explore (under Find). Selecting a row fills the detail area.
2. **Find** shows the map with the list beside it. Selecting a place opens its panel; open the full page from there.
3. **Builder:** open a trip from the sidebar. Reordering, Edit, Share and Add stop work as on the iPhone.
4. **Settings** is a sheet over the split view. Make the window narrow (Slide Over or a narrow Split View): the layout should switch to the iPhone tabs.

## Launch switches

Pass them after the bundle id with `simctl launch`, or in the scheme's Arguments for a device. All except the key ones read `UserDefaults`, so `-Name value` pairs work.

| Switch | Effect |
|---|---|
| `-IterInMemoryStore YES` | Throwaway store; required for the seed and stub switches below. |
| `-IterSeedLibrary YES` | A pinned trip, trip folders (one nested), location folders and saved spots. |
| `-IterSeedTrip YES` or `conflict` | The sample trip; `conflict` also reverses day 2. |
| `-IterSection explore\|trips\|trip\|locations\|settings\|search` | Opens that tab. `trip` is the first pinned trip, else the most recent. `settings` shows Settings; `search` shows the search tab. |
| `-IterSpot <id>` | Pushes that curated spot's page, for example `mesa-arch`. |
| `-IterSelectRow <id>` | Explore selects that row and shows its panel. |
| `-IterSheet peek\|half\|full` | The Explore sheet's starting height (phone). |
| `-IterSearch <text>` | Runs that Apple Maps search at launch. |
| `-IterQuery <text>` | Fills the search field without running it, so the suggestions show. |
| `-IterSearchPreview YES` | Shows the search screen inside the Explore tab (debug aid). |
| `-IterAsk <text>` | Puts that request to Ask at launch. |
| `-IterScoutStub unavailable\|results` | A stand-in for Apple Intelligence: reports it off, or answers with three curated spots. Only with `-IterInMemoryStore YES`. |
| `-IterAddSpot "lat,lon,Name"` | Adds your own spot at launch (in-memory only). |
| `-IterTripDay <n>` | The builder opens on day n (1-based). |
| `-IterEditStops YES` | The builder opens in Edit mode. |
| `-IterRouteCollapsed YES` | The builder's route map starts collapsed. |
| `-IterAddStop YES` | The builder opens the Add stop sheet. |
| `-IterNewTrip YES` | The Trips list opens the New Trip sheet. |
| `-IterTripsFilter pinned\|<folder name>` | The Trips list opens with that chip selected. |
| `-IterLocationFolder <name>` | Opens that location folder. |
| `-IterSettingsTab weather\|intelligence\|about\|general` | Opens that Settings page (`general` stays on the list). |
| `-IterAppearance light\|dark` | Forces the appearance. |
| `-IterPanelScrolled YES` | The place panel opens scrolled to its lower half. |
| `-ITER_OPENWEATHER_KEY <key>` | OpenWeather key for this run (also `-ITER_WINDY_KEY`). |
| `-IterSaveOpenWeatherKeyFromArgument YES` | Debug builds: saves that key to the Keychain. |
| `-IterSmokeTest YES` | Walks the main view models once and logs `smoke:` lines. |

The Mac-only switches (`-IterWindowSize`, `-IterExpandFolders`) do nothing on iOS.

### What was seen on the Simulator (2026-10-06, Xcode 27 beta, iOS 26.5 and 27.0 runtimes)

- **Launch on iOS 26.5:** the first build stopped at launch (dyld: `Generable.promptRepresentation` missing from iOS 26.5's FoundationModels, because the app is built with the iOS 27 SDK). FoundationModels is now weak-linked and the app launches on 26.5 and 27.0.
- **OpenWeather, live:** with the key as a launch argument and from the Keychain, every list, pin, panel, trip stop and the outlook scored from OpenWeather (for example Mesa Arch sunrise 66 "Good", the Canyon Country stops 66, 71, 68, 73). The daily call count rose with each run (Settings showed 28, then 29).
- **Keychain:** a key saved through the Settings save path survived a relaunch without the argument ("Saved in Keychain", status Working).
- **MapKit:** the Explore and Locations maps, clusters and pins, Apple Maps search suggestions, drive times and route lines on the trip map, reverse-geocoded localities, and satellite images in the image strip (Look Around where Apple has it) all loaded.
- **Apple Intelligence:** the iOS 26.5 Simulator reports Apple Intelligence as ready, but a real Ask fails inside the model (`promptTemplateNotFound` from the on-device model host), so Ask shows its honest "Ask Iter couldn't finish" state with Search Apple Maps Instead. On the iOS 27.0 Simulator the same Ask ("sunrise spots within 2 hours of Moab") returned four grounded places (Mesa Arch, Monument Valley, Dead Horse Point, Factory Butte) with notes. On a real iPhone, Ask needs an Apple Intelligence iPhone with it turned on; otherwise the screen says why.
- **Location:** with the location permission granted and the Simulator at Moab, Explore shows "Near You · Within 300 mi" first.


## Not tested by hand

The Simulator cannot be tapped from a script, so these were built and compiled but not exercised: dragging the Explore sheet between heights, swipe actions, reorder drags in Edit, context menus, the share sheet and importing a `.iter` file, the file picker, and any drag and drop. They need a person at a device. The iPad layout and the device install were checked as far as the Simulator and the build allow; the install steps above were not run on a real iPhone for this file.

## Known issues and limits

1. **Apple Intelligence on the Simulator.** Ask depends on the device's model. What the screens say is described under the Simulator results above; use `-IterScoutStub results` to see the Ask layout without it.
2. **Look Around.** Place images show Look Around snapshots where Apple has imagery and a satellite image otherwise, as on the Mac.
3. **No offline base map.** A pinned trip is ready offline except for the map tiles.
4. **No updater.** Settings ▸ Updates is a note only. The version is shared with the Mac (`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`). TestFlight or the App Store would deliver updates later; `IterUpdater` is Mac-only.
5. **iOS 26 and FoundationModels.** The app is weak-linked to FoundationModels (`-weak_framework FoundationModels` in `project-ios.yml`). Built with the iOS 27 SDK, the `@Generable` code referred to a symbol iOS 26.5 does not have, and a strong link stopped the app at launch. Ask checks availability before it uses the model.
6. **Free team.** The app expires after 7 days, and WeatherKit is not available (OpenWeather is the default instead).
7. **No sync.** Trips and spots made on the Mac are not on the iPhone (iCloud is Milestone 3).
