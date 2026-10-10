# Changelog

All notable changes to Iter are listed here. The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and Iter uses [Semantic Versioning](https://semver.org/): 0.x.y until the first signed release, which is 1.0.0.

## [Unreleased]

<!-- These are the release notes intended for v0.3.0. -->

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
- **A cleaner sidebar**: it lists All Trips and All Locations, then only what you pin (trips, trip folders, locations, location folders). The Mac sidebar also has a search field.
- **A wider trip planner card (Mac)**: up to 800 pt in a large window, in the middle of the map, which frames the route in the strip beside it. Share and More are round glass buttons in the card's corner. The day strip starts with All Days and marks the chosen day in the accent. Each day shows Sunrise at and Sunset at on sky-coloured badges, and stops carry the same numbered disc as their map pin.
- **Swipe your trips (iPhone)**: swipe right to pin or unpin, swipe left to delete, with an Undo banner that brings a deleted trip back.
- **Licensing groundwork**: Iter can check a licence key, keep it in the Keychain and work for 14 days offline. It is hidden and switched off. Iter is still free, and nothing asks for a key.
- **Move your own spots**: drag the selected pin of a spot you added (Mac, iPhone and iPad), or choose **Adjust Location** on its place card and pan the map under a crosshair (Done saves, Cancel restores). The place card and the spot editor have **Latitude** and **Longitude** fields and a **Paste Coordinates** button that reads "lat, lon", degrees with N/S/E/W, and Apple Maps links. Each move can be undone, and the light is scored again for the new place.

### Improved
- **Search looks the text up first**: Return in Explore's search field always searches your places and Apple Maps, so a long name such as "Great Smoky Mountains National Park" finds the park. When the text reads like a request ("foggy forest near Portland for sunrise", a question, or a phrase starting with "find" or "show me"), an **Ask Iter** suggestion sits above the results; choose it to ask.
- **A faster trip planner (Mac)**: picking a stop or day, dragging a stop and nudging are quicker and no longer make the map zoom twice. Choosing a stop pans the map only if its pin is out of view.
- **Place card actions (Mac)**: Back is at the leading corner (to the list, as Escape), with Share and Close at the trailing corner. Add to Trip confirms what it did and can make a new trip without leaving Explore. Save flips to Saved. The image strip switches between Look Around (live, when Apple has it) and satellite.
- **All Trips hero**: Open is the accent action over the picture, with a little extra shading under the text. On a narrow phone it drops under the next-session line.
- **Folders are one level deep**: folders no longer nest. A subfolder from an earlier version moves to the top level, right after its parent, keeping its name, pin, trips and locations. Deleting a folder moves its trips to All Trips and its locations to All Locations.
- **The planner card fits the window (Mac)**: from 1440 pt wide it is the wide centred card; narrower, it slims so at least 40 % of the window stays map; under 1100 pt it docks to the side like Apple Maps' inspector.
- **Smoother window resizing (Mac)**: resizing the window no longer redraws the whole window or re-frames the maps at every step; each step takes about half as long, and the planner card keeps its width while you drag and settles when you let go.
- **More system controls on iPhone**: the map style button is the system glass button, and a trip stop's session and day menus are standard bordered buttons.

### Fixed
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
- **One event unit** for every score: a band-coloured rounded rectangle with a heavy score and the symbol over the time.
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
