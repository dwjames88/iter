# Changelog

All notable changes to Iter are listed here. The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and Iter uses [Semantic Versioning](https://semver.org/): 0.x.y until the first signed release, which is 1.0.0.

## [Unreleased]

### Added
- **All Trips redesign**: the page is a centred column with your next trip as a hero (its first spot's picture, dates, size, the next light and an Open button), then soft cards for Pinned trips, each folder and the rest. Make folders from the page's ellipsis menu, move trips with their context menu or by dragging a card onto a folder, and start from a friendlier empty state with template picture cards. iPad shows the grid, iPhone one column.
- **Licensing groundwork**: Iter can now check a licence key with Lemon Squeezy, keep it in the Keychain and work for 14 days offline. It is hidden and switched off, so nothing changes for anyone: Iter is still free, and nothing asks for a key.

### Changed
- **Trip map shows the globe and daylight**: the trip route map zooms out to the world like Explore and Locations and draws the day/night line.
- **Folders live inside All Locations**: the sidebar now lists All Trips and All Locations, then only what you pin (trips, trip folders, locations, location folders). In All Locations, folders are rows at the top with a count: open one, make a New Folder, Rename, Delete, Pin to Sidebar, drag locations onto a folder or use Move to Folder. Right-click a location to pin it. Same on iPad and iPhone.
- **Place card buttons work**: on the Mac, Back, Share and Close in the place card's header did nothing (a click in the window's title bar band became a window drag). Back is now at the leading corner (to the list, as Escape), Share and Close at the trailing corner; the position counter and previous and next buttons are gone. Add to Trip confirms what it did and can make a new trip without leaving Explore, Save flips to Saved, and the image strip switches between Look Around (live, when Apple has it) and satellite.
- **Maps show terrain and a globe, and the day/night line**: every map now draws with realistic elevation, so Satellite and Hybrid zoom out to Apple Maps' 3D globe (with its own night side and city lights). Standard stays a flat map at world scale. Zoomed out beyond about 2,000 km, a faint day/night line with two twilight bands is drawn on the map for the current time. Turn it off with **Show Daylight** in the map style menu (or View ▸ Map Style).
- **Trip planner card**: the day planner is a wider card (560 to 800 pt, growing with the window) in the middle of the map, which frames the route in the strip beside it. Share and More are round glass buttons in the card's corner and the title sits beside them, not under them. The day strip starts with All Days and marks the chosen day in the accent; each day shows Sunrise at and Sunset at on sky-coloured badges; stops carry the same numbered accent disc as their map pin; Add Stop is a standard button.
- **Trip planner speed**: picking a stop or day, dragging a stop and nudging are quicker and no longer make the map zoom twice. Choosing a stop pans the map only if its pin is out of view and never refits it.
- **Search always looks the text up first**: Return in Explore's search field now always searches your places and Apple Maps, so a long place name such as "Great Smoky Mountains National Park" finds the park instead of going to Ask Iter. When the text reads like a request ("foggy forest near Portland for sunrise", a question, or a phrase starting with "find" or "show me"), an **Ask Iter** suggestion sits above the results; choose it to ask.

### Fixed
- **Card buttons in the title bar band work**: on the Mac, the buttons in the top corner of the Explore and Locations lists (filter menu, New Folder, sort, Back) and the trip card (Share, More) did nothing, because a click there became a window drag. They now take clicks, and menus open.
- **Updates with a damaged feed entry**: one malformed entry in the update feed no longer blocks every update. Iter skips it, notes it in the log, and still offers the other releases.
- **Drive times after a dropped connection, without a refresh**: while a trip is open, a drive that MapKit throttled or that failed offline is looked up again on its own after 30 seconds, then 1, 2 and 4 minutes, and every 5 minutes after that. "No route" is still final.

### Docs
- **Glass rules**: `Design/GLASS-RULES.md` collects the Liquid Glass, geometry and component rules from the recent Mac and iOS redesign commits and the HIG in one page for anyone touching UI.

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
