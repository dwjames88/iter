# Changelog

All notable changes to Iter are listed here. The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and Iter uses [Semantic Versioning](https://semver.org/): 0.x.y until the first signed release, which is 1.0.0.

## [Unreleased]

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

[Unreleased]: https://github.com/dwjames88/iter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dwjames88/iter/releases/tag/v0.1.0
