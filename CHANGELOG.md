# Changelog

All notable changes to Iter are listed here. The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and Iter uses [Semantic Versioning](https://semver.org/): 0.x.y until the first signed release, which is 1.0.0.

## [Unreleased]

<!-- The rebuild. Written for the owner. Older Unreleased notes (for the planned v0.3.0, never shipped) follow below, under their own heading. -->

Iter has been rebuilt from the ground up. It keeps your trips, places and folders, but almost everything under them is new. This is the plain list of what changed.

### Read this first: your data
- **The first launch of the new app on your real library changes the store to a new format (schema V5). The earlier Iter app cannot open it afterwards.**
- Iter makes a backup before it touches anything. On the Mac it is `~/Library/Application Support/Iter/Backups/pre-v5-<date and time>/`, with the raw store files, every trip as an `.iter` file the earlier app can open, and `backup.json`. If the backup cannot be made, the store is not opened and nothing is changed.
- If the new store fails to open, Iter leaves your original file alone, builds a new store beside it from the backup's `.iter` files, and tells you where the backup is.
- The iPhone does the same in its own app folder. The iPhone's bundle id is unchanged, so its library carries over.
- Migration was tested on fixture stores made by the old app's own code (schemas V1 to V4, including folders, pins, transfer timings and drive notes). It has not been tried on a copy of the iPhone store.

### New
- **One flow, Find, Conditions, Build, Go, on Mac and iPhone.** The Mac sidebar is Find, Trips and Saved Places ("Locations" is now "Saved Places"). The iPhone has Find, Trips, Saved and Go tabs. Go is iPhone only.
- **Go, a trip mode for the iPhone.** Starts a run on a trip, and follows it: next stop, leave-by time, drive time with a live ETA, current weather, a short forecast and the sky now. It runs in the background on location, shows a Live Activity (Lock Screen and Dynamic Island) and a Home widget, and sends notifications: leave soon, leave now, late, stay check, conditions changed and arrival. Navigate opens Apple Maps. Arrival is automatic, with a two-minute "Not yet" undo. A run survives a relaunch. Old or offline data is never shown as live. There is no push, because a free developer team cannot use it, so the Live Activity updates only while Iter is running.
- **Find reads requests.** With Apple Intelligence, a request such as "waterfalls near Yosemite for sunrise" is turned into a plan. Without it, a simple parser does the job and Find says "Basic search". The model never supplies a coordinate: every result gets its coordinate from a map source and must lie inside the area. Results show the sources that found them and links to them. A source that is down or off is named, not hidden.
- **Real data sources, all free and keyless.** NOAA HRRR and GFS forecasts (decoded on the device), MET Norway, aviation weather reports (METAR and TAF, including military airfields), NWS alerts and observations, NOAA space weather and smoke, USGS names, OpenStreetMap, Wikipedia, Wikivoyage, Wikimedia Commons, Terrain Tiles, and Apple Maps. Each number carries its source, age and licence. Settings ▸ Sources & Credits lists them all with the credit text. See [docs/DATA-PROVIDERS.md](docs/DATA-PROVIDERS.md).
- **On-device military-origin references.** World Magnetic Model 2025 (declination) and MGRS grid references, computed on the device.
- **A new Sky Index.** The Forecast Sky Index now uses precipitation, visibility, moon, smoke and aerosol, terrain (the real horizon, computed per place), humidity, wind and the Milky Way core, as well as cloud. A missing input is dropped and the screen says so. The score runs from 0 to 100 (it was 5 to 100). The Live Sky Index blends the latest observation, the nowcast and the forecast for the sky now and the next few hours, and shows a trend. A forecast older than three hours is marked stale. The new factors are first guesses that still need calibrating.
- **Better planning.** Stops can have a dwell time (shoot until), a fixed arrival, and a kind (light, lodging, waypoint). A trip has a start place, so the first stop gets a leave-by time. Leave-by and drive times use live routes, with an offline estimate when there is no signal.
- **Pinned and active trips keep their conditions offline**, labelled with their age.
- **`.iter` version 2.** Holds a trip or the whole library, with folders, pins, saved places, provenance, and deletion records. Importing merges by id: the newer edit wins, and a second import updates a trip instead of duplicating it. **Send to iPhone** and **Send Library to iPhone** (Mac, with AirDrop) use it. **Export for older Iter** writes version 1. Version 1 files stay readable.
- **Recovery and backup**, as above.
- **Location at launch.** Iter asks for your location as soon as it opens, and nothing is gated on the answer.
- **Liquid Glass throughout**, using the system components, laid out for both platforms from one shared set of screens.

### Changed
- **Ask Iter is gone as a separate screen.** Its job is Find.
- **Data sources.** The forecast now comes from NOAA and MET Norway, not OpenWeather or WeatherKit.
- **The app is built in a package.** 16 targets with strict concurrency, no third-party code, and no shared-folder exclude lists. The old `App/`, `AppiOS/` and `IterKit` folders are removed.
- **Bundle ids are unchanged** (`com.dwjames.iter` on the Mac, `com.dwjames.iter.ios` on iPhone), so your data and Keychain items still match. Tests and renders run as `com.dwjames.iter.render` and can never open the real store.

### Removed, or not carried over
- **OpenWeather, Windy and WeatherKit.** No source needs a key now. Settings ▸ Keys says so. The old OpenWeather, Windy and Google keys stay in your Keychain where they were, and nothing reads them. The Windy layer and the "Open in Windy" links are gone.
- **The licensing module.** Dropped. Iter has no licence check.
- **Reddit and Google search.** Not available. Reddit needs your own API credentials, and Google is closing its search product to new users. Find lists both as "unavailable" with the reason.
- **Light pollution and seeing.** There is no source. The sky index leaves Bortle and seeing out and says so.
- **Satellite and radar maps.** The NASA, EUMETSAT and IEM imagery adapters exist but no map layer uses them yet. EUMETSAT and IEM radar are off until their licences are read.

### Known gaps
- **Bonjour sync is not built.** Only file sharing (AirDrop and Files) with merge. There is no iCloud sync.
- **Not checked by a person yet:** Liquid Glass, map pins on the Mac, drag and drop, menus and keyboard shortcuts, the Live Activity and Dynamic Island, background location during Go, notification actions from the Lock Screen, real network sources, Apple Intelligence on a device, and the first launch on the real store. The list is in [TESTING.md](TESTING.md).
- **Calibration.** The new score factors have not been compared with real shoots.
- **Free team.** Time-sensitive notifications are unlikely to work, and how long a sideloaded build stays installed is not confirmed ([docs/ROADMAP.md](docs/ROADMAP.md)).
- **Offline base maps** are not possible with MapKit.

## Older Unreleased notes (for the planned v0.3.0, never shipped)

<!-- These were the release notes intended for v0.3.0 on the old app. The rebuild replaces that code, so some items may no longer be true. Kept for the record and to be pruned by the owner. -->

### New
- **Search Here**: pan the Explore map and a Search Here button (also Edit ▸ Search Here, ⌘⇧F) lists the places in view in a new In View section, first from Apple Maps, then joined by Ask's suggestions (each confirmed on the map before it shows) and by web discovery as they arrive. It never moves the map. Each row names the sources that list it and, where known, the elevation.
- **Web discovery**: places also come from OpenStreetMap, Wikipedia, Wikivoyage, Reddit and, optionally, Google with your own key. The on-device model only copies names out of Reddit and Google text; every place is checked to be real and inside the area, and a source that is down is named instead of failing the search.
- **Feature searches**: typing "peaks in Glacier National Park", "waterfalls of Yosemite" or "lakes near Banff" lists every peak, lake, waterfall, arch, viewpoint and so on inside the area's real boundary, with elevation. Words like "near here" or "at sunset" are not mistaken for the area.
- **Settings ▸ Search**: What I Like to Shoot (added to Ask and discovery prompts on your device), Learn From My Library (a short summary of what you save and plan, kept on the device), Popular, Unique or Mixed ordering, a result cap, which sources to use, and the optional Google key (kept in your Keychain).
- **Edit any saved or own location**: Edit is on the place card, the spot page, Locations rows (context menu, swipe on iPhone) and pinned sidebar rows, and Command-E edits the location you are looking at. Change the name, place, notes, folder, pin and, for your own and Apple Maps spots, the coordinates, category, best light, walk-in and tags. A saved catalogue spot keeps its position, category and light fixed (the sheet says why) but its name, place and notes are yours. One undo step: Undo Edit Location.
- **A Liquid Glass redesign, laid out like Apple Maps**: on the Mac, map actions sit on the map, the search field is Maps' own, cards have glass corners and sizes match Maps. On iPhone, the map fills the screen under one floating sheet with the tab bar at its foot, and Explore uses standard system controls, filter chips included.
- **A globe with daylight**: every map shows realistic terrain, and Satellite and Hybrid zoom out to Apple Maps' 3D globe with its night side and city lights. Hybrid is now the default style (Standard cannot show the globe), and anyone who chose a style keeps it. Zoomed far out, a faint day and night line with twilight bands is drawn for the current time. Turn it off with **Show Daylight** in the map style menu (Mac: View ▸ Map Style). The trip route map reaches the globe and daylight too.
- **A new All Trips page**: your next trip is a hero with its first spot's picture, dates, size, the next light and an Open button. Below it, soft cards for Pinned trips, each folder and the rest. Move trips with the context menu or by dragging a card onto a folder. An empty page offers template picture cards. iPad shows a grid, iPhone one column.
- **Folders inside All Locations**: folders are rows at the top with a count. Open one, make a New Folder, Rename, Delete, Pin to Sidebar, drag locations onto a folder or use Move to Folder. Right-click a location to pin it. Works on Mac, iPad and iPhone.
- **A cleaner sidebar**: Find, Locations and Trips, each with accent symbols. All Locations and All Trips open to show only what you pin (trips, trip folders, locations, location folders), and remember whether they are open. The Mac sidebar is 280 pt wide on paper, with a glass search field at the top and, at the foot, an info button (what the scores mean) and a + menu (New Trip, New Location) in place of the toolbar +. Built from the Figma sidebar.
- **A redesigned Trip Builder**: on the Mac a trip is three columns: the sidebar, the route map filling the middle under the toolbar, and the Trip Builder in the system inspector on the right (480 to 680 pt, 560 by default; Trip Builder in the toolbar or ⌥⌘0 hides and shows it). It has a header card (name, Share and More, dates, size, driving), a day selector, and a card per day with sunrise and sunset, stop cards (set-up time, numbered badge, light-window menu, walk-in and set-up, note, score chip), blue-car drives between stops, a card for each overnight drive between days with Find hotels and a Morning or Evening Before picker ("Drive to the next area the [Morning] before the shoot."; Evening Before leaves when the last session ends and moves the overnight and the driving total to the day before), a note field on every drive and transfer card (a drive note stays with the stop the drive arrives at, so it moves with that stop if you reorder), and Add Stop at the foot of each day. Down and up arrows select the next and previous stop in the Mac list. The floating planner card is gone. iPhone and iPad use the same components in the trip sheet. Built from the Figma Trip Builder Module, with these deliberate differences: the panel is 560 pt wide, not 639, to leave map room in a 1280 pt window; the light-window picker is the system menu button, not the white bordered combo; times and durations use the locale formatters ("2 hr, 19 min"); day cards have no drop shadow (List rows cannot share one) while the header and selector cards do; stop numbers count across the trip and match the map pins, instead of restarting each day; the header card is a solid content card, not glass; Find hotels uses the warning colour as drawn; and the selection is a 1.5 pt accent stroke. The panel has no solid background: it takes the system inspector's material, and the trip sheet on iPhone and iPad shows the sheet's. The toolbar button sits at the trailing edge. Older trips and `.iter` files open unchanged (store schema 4; files import as Morning with no drive notes). This also fixes a crash that closed the Mac app within seconds of opening a trip with sample weather on (the sidebar's Sample Data banner changed height with its width and the window's constraints never settled).
- **Swipe your trips (iPhone)**: swipe right to pin or unpin, swipe left to delete, with an Undo banner that brings a deleted trip back.
- **Licensing groundwork**: Iter can check a licence key, keep it in the Keychain and work for 14 days offline. It is hidden and switched off. Iter is still free, and nothing asks for a key.
- **Move your own spots**: drag any pin of a spot you added on the Explore and Locations maps, folders included (Mac, iPhone and iPad), or choose **Adjust Location** on its place card and pan the map under a crosshair (Done saves, Cancel restores). Your own spots never merge into a numbered cluster, so they can always be picked up. The place card and the spot editor have **Latitude** and **Longitude** fields and a **Paste Coordinates** button that reads "lat, lon", degrees with N/S/E/W, and Apple Maps links. Each move can be undone, and the light is scored again for the new place.

### Improved
- **Location without asking twice**: Iter asks for your location as soon as it opens, so Near You is there without pressing Use My Location, which is gone. On iPhone it asks once more to allow Always, so it doesn't ask each time you open it. If location is off in System Settings, the Explore banner still opens it for you.
- **Search looks the text up first**: Return in Explore's search field always searches your places and Apple Maps, so a long name such as "Great Smoky Mountains National Park" finds the park. When the text reads like a request ("foggy forest near Portland for sunrise", a question, or a phrase starting with "find" or "show me"), an **Ask Iter** suggestion sits above the results; choose it to ask.
- **A faster trip planner (Mac)**: picking a stop or day, dragging a stop and nudging are quicker and no longer make the map zoom twice. Choosing a stop pans the map only if its pin is out of view.
- **Place card actions (Mac)**: Back is at the leading corner (to the list, as Escape), with Share and Close at the trailing corner. Add to Trip confirms what it did and can make a new trip without leaving Explore. Save flips to Saved. The image strip switches between Look Around (live, when Apple has it) and satellite.
- **All Trips hero**: Open is the accent action over the picture, with a little extra shading under the text. On a narrow phone it drops under the next-session line.
- **Folders are one level deep**: folders no longer nest. A subfolder from an earlier version moves to the top level, right after its parent, keeping its name, pin, trips and locations. Deleting a folder moves its trips to All Trips and its locations to All Locations.
- **Smoother window resizing (Mac)**: resizing the window no longer redraws the whole window or re-frames the maps at every step; each step takes about half as long, and the trip panel keeps its width while you drag and settles when you let go.
- **More system controls on iPhone**: the map style button is the system glass button, and a trip stop's session and day menus are standard bordered buttons.

### Fixed
- **Move your own pin on the map**: on the Mac, drag any of your own pins straight away, selected or not (the press selects it); a click on your selected pin keeps it selected and never moves the map; the pointer shows an open hand over it and a closed hand while dragging, and the pin lifts while held. On iPhone and iPad, touch and hold your pin, then drag it. The drop re-scores the place and is one Undo Move Spot. Your own spots on Explore are no longer swallowed by a cluster, and the Locations maps (All Locations and folders) have the same drag. Adjust Location's Done and Cancel now take clicks on the Mac (the place card was covering them). A one-time tip on your spot's card says how to move it, and Edit Location has the same small pin map as Add Spot.
- **Buttons in the top corner (Mac)**: the filter menu, New Folder, sort and Back buttons on the Explore and Locations lists, and Share and More on the trip card, did nothing because a click there became a window drag. They take clicks now, and menus open.
- **Place card buttons (Mac)**: Back, Share and Close in the place card's header work again.
- **Updates with a damaged feed entry**: one malformed entry no longer blocks every update. Iter skips it and still offers the other releases.
- **Drive times after a dropped connection**: while a trip is open, a drive that was throttled or failed offline is looked up again on its own, after 30 seconds, then 1, 2 and 4 minutes, then every 5 minutes. "No route" is still final.
- **Dropped pins land where you click (Mac)**: Add Spot placed the spot to one side of the click, by hundreds of metres to kilometres depending on zoom, because the click was read in the map's padded area under the card and toolbar. It now lands exactly where you click. Selecting a pin no longer makes it jump, and your selected spot shows a dot at its exact point.
- **Place card buttons stay in the card (Mac)**: after you opened a place, Back, Share and Close could be left floating over the map beside the card. They now sit inside the card above the title; the card fades in instead of sliding.
- **Place card labels fit (Mac)**: with four actions on the card, Open in Maps no longer cuts off.

## [0.2.0] - 2026-10-07

### Fixed
- **Search results on the map**: after you have moved the map, searching Apple Maps for a place now brings the result into view instead of leaving it off screen.
- **Drive times after a dropped connection**: if MapKit was throttled or you were offline when a trip loaded, the drive stays an estimate only until the next refresh, then is looked up again; before, the straight-line guess stuck until you reopened the trip.
- **Forecasts after a clock change**: OpenWeather daily forecasts no longer come out an hour off for days after a daylight-saving change within the next 8 days.
- **A clear message for an empty forecast**: when OpenWeather answers with no forecast data, Settings says "The response had no forecast data" rather than an internal error name.
- **Stale forecasts**: a forecast saved on disk long ago is no longer shown as fresh for up to 2 hours.
- **Places stuck loading**: a place whose forecast fetch was cancelled by the provider can be asked for again instead of staying on its spinner. Pressing retry during a fetch joins it.
- **Image strip after stepping back**: going to another place and straight back no longer leaves the image strip empty.
- **Moving your library on first launch**: if Iter was quit or crashed partway through moving its data out of the old sandbox container, the next launch finishes the move, offline packs and forecast cache included, and no half-written file is left behind.
- **Impossible dates**: a date that does not exist, such as 30 February, is rejected instead of becoming 2 March.

### Changed
- **A faster trip planner and map**: switching days, selecting and moving stops do less work, the route map redraws only when the route changes, and drive times that are already known appear at once.
- **Fewer redraws in Explore**: hovering the map or list no longer rebuilds rows, and a batch of forecasts arriving updates the screen once instead of once per place.
- **Pinned-trip downloads no longer stall the window** while images are saved.
- **Sharing a trip builds the file only when you share it**, not each time the trip redraws.

## [0.1.0] - 2026-10-07

First pre-release, for friends to try.

### Added
- **Explore**: places near you with a light score for the next sunrise or sunset, on a list and a map. Scores cover sunrise, sunset, golden hour and blue hour.
- **Light panel**: click a place for a timeline of the day's light, cloud and rain, the day's windows, a compass rose with a time scrubber, and hour-by-hour weather.
- **Good to know**: the best sunrise or sunset in the days the forecast covers sits at the top of the spot page, under the image strip, with the practical facts.
- **Trips by day**: start from a template or a blank trip, add stops, and see each day as a timeline with drive times and the light at each stop. Iter warns when a drive does not fit and offers to reorder by light. Everything can be undone.
- **Locations and folders**: save places, add your own spots on the map, and keep trips and locations in folders.
- **Offline trips**: pin a trip to keep its forecasts, drives and images for when you have no signal.
- **Ask Iter**: describe the light and place you want, and Iter finds real places that fit (needs Apple Intelligence on an Apple silicon Mac).
- **Forecasts from OpenWeather** with your own free key (Windy works too, with a paid Professional key).
- **A welcome guide** that sets up your location, your weather key and Ask, and can be reopened from Help.
- **Automatic updates**: Iter checks daily, shows what changed, and installs signed updates itself (**Iter ▸ Check for Updates…**).

### Changed
- **A compass rose** replaces the sun and moon arc, at the foot of Light through the day, with a time scrubber shared with the timeline. Marks carry their labels, and the spot's classic view is labelled just outside the rim ("View 263° W").
- **New window symbols**: sunrise, sunset, morning blue hour (sun in haze), evening blue hour (moon in haze) and night each have their own symbol everywhere.
- **One score chip** for every score: a band-coloured rounded rectangle with the window's symbol over its time on the left and a semibold score on the right, built to the Figma Score component. Large (48 pt), small (38 pt) and compact (26 pt) sizes plus the map pin; every chip of a size is the same width at any score, unscored included. The colour ramp is unchanged; light mode uses dark ink up to 99 and white at 100, dark mode uses white on every chip as designed (under 4.5:1 contrast from a score of about 65 up, a design decision).
- **Selecting a spot zooms the map to a 25-mile radius** (it only pans if you are already closer).
- **Coming up is gone**; the 8 or 10-day outlook opens each day in place to show its light windows.
- **Map style**: Standard, Satellite or Hybrid on Explore, Locations and trip maps, remembered, Standard by default.
- **Tab controls** are full-width segmented controls with equal segments; on iPhone, Explore's sort (Near you, Best light, Popular) is one, above the filter chips.
- **No band words or confidence bars.** The colour carries the rating (VoiceOver still speaks it). Click the **i** at the bottom of the sidebar, or open Settings on iPhone, for **What the scores mean**, with each colour's score range.

### Known issues
- This build is not notarised by Apple, so macOS blocks it the first time you open it. Use System Settings ▸ Privacy & Security ▸ Open Anyway (see the README).
- No sync between Mac and iPhone yet, and the iPhone app is not part of this release.
- No Apple Weather yet, so scores use OpenWeather's total cloud forecast.

[Unreleased]: https://github.com/dwjames88/iter/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/dwjames88/iter/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/dwjames88/iter/releases/tag/v0.1.0
