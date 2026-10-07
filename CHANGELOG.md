# Changelog

All notable changes to Iter are listed here. The format follows [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and Iter uses [Semantic Versioning](https://semver.org/): 0.x.y until the first signed release, which is 1.0.0.

## [Unreleased]

### Added
- Versions. Iter has a version number and a build number, shown in the About window, Settings ▸ About and Settings ▸ Updates (Debug builds also show the git commit).
- **Iter ▸ Check for Updates…** looks for a newer version, shows what changed, and downloads and installs it for you.
- **Settings ▸ Updates**: automatic daily checks (on or off), the current version, the last check, and a button to check now.
- A signed update feed. Every update is signed with an Ed25519 key, and Iter checks the file's size, SHA-256 and signature before it installs anything.
- Selecting a place in Explore opens its light panel in the list column (header, images, light timeline, Today and Coming up, When to go, sun and moon, hour by hour, Save, Add to Trip, **Show Full Page**); **‹ Places** or Esc goes back.
- Ask in Explore's search field: the answers appear in an **Ask Iter** section at the top of the list.
- Trips and locations can go in folders (one level of nesting).
- A pinned trip is downloaded for offline use, with a status badge.
- **Debug ▸ Show Layout Grid** overlays the 8 pt grid and lane guides on lists and cards.

### Changed
- Search is one field: type, and the top of the list offers **Apple Maps** and **Ask Iter**, the likelier first; Return runs the first.
- Iter now runs outside the App Sandbox, so it can replace itself when you update it. A sandboxed app cannot swap its own bundle or clear the download quarantine flag. Hardened Runtime stays on. Your data moves once, on first launch, from `~/Library/Containers/com.dwjames.iter` to `~/Library/Application Support/Iter`; the old container is left in place as a backup.
- Every score is one event unit: the window's symbol, the score and the start time in one capsule coloured by the score band, in Explore, on map pins, the place panel, the spot page, Locations, Ask, trip stops and the Add Stop popover.
- The sidebar is grouped as **Trips**, **Locations** and **Find**; Saved is now Locations.
- The trip builder is built around days: an overview strip of day cells, one box per day with a timeline, and no more CPU loop.
- The map is faster: scores are worked out off the main thread, pins are cached, and spots that overlap merge into numbered circles you click to zoom.
- Sheets and Settings use standard system controls: grouped forms, section footers, default and cancel buttons.

### Removed
- The Scout screen. Its answers now live in Explore.
- The floating place card over the map (replaced by the light panel), the sparkles Ask button, Ask mode and **Go ▸ Ask Iter…** (⌘4).

[Unreleased]: https://github.com/dwjames88/iter/commits/main
