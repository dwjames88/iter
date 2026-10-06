# Roadmap

Plan references are to `docs/reference/plan/` (P = phase item, numbers = sections).

## Milestone 1 · A place to start testing (this build)

A coherent Mac app you can use end to end. Anything not listed here is absent from the UI, not present and dead.

**Shell (6.1-A, trip-first).** Sidebar: Trips (each trip listed, New Trip), then Explore, Saved, Scout. Toolbar, menu commands with shortcuts, Settings window, Debug menu, window state restoration, light and dark appearance.

**Light Index (2.3-C, 6.4-A with B one click away).** Intent picker (Sunrise, Sunset, Blue hour, Night), default from the spot's best light. Every score names its window ("Sunset · 38"), shows confidence and, for days 4 and later, a range. Reasons by factor one click away; a plain-language explanation from Apple Intelligence when available. "No forecast" with the specific reason; never a placeholder score. Single-hue light ramp with band words.

**Explore (6.2-B on Mac).** Map with a list panel, one selection driving pin, row and card. Curated spots plus Apple Maps search results. Date control, intent, filters (category, best light, source), sort (light, name, distance, popularity). Click the map in Add Spot mode to drop a pin, name it (reverse geocoded), save it.

**Spot page (P3.3).** Leads with when to go: the best window for the intent over the next days, then a 10-day outlook (fading with confidence), the five windows with scores and reasons, the light timeline (labelled bands, cloud layers, rain), the sun and moon arc with a time scrubber, hourly weather with the provider's attribution, a Windy section with Open in Windy, Look Around where available, Add to Trip (day picker shows the light per day), Open in Maps, Save.

**Trips (6.3-A, P3.5, P4.1, P4.2).** List, create (blank or from a template), rename, change dates, duplicate, delete with undo. Builder: days and stops, one session per stop, drag to reorder within and across days, MapKit drive times, connectors that state feasibility, a backward schedule on every stop ("Leave 4:10 · set up by 5:52 · Sunrise 6:12"), warnings when a drive does not fit, a route map, and a light-first ordering suggestion you accept or ignore.

**Scout (P3.7).** Apple Intelligence via Foundation Models with tool calling over MapKit and the curated set; results land as map objects with provenance and drive time, scored by the Light Index; progress and cancel; specific unavailable states; ordinary search works without it.

**Saved and your own spots (P3.9).** One idea of saved: a single list with an "Added by you" tag; edit and delete your own spots with undo.

**Getting a trip out (P4.7, partly).** Share or export a trip as an `.iter` file (ShareLink and File > Export); open or import one back. Open any stop in Apple Maps.

**Weather providers.** OpenWeather and Windy beside Apple Weather, chosen in Settings ▸ Weather with an optional fallback. Keys in the Keychain, per-provider caches and daily call caps, honest unknowns when a provider lacks a field, and "Open in Windy" on the spot page and in Explore. See `docs/DATA-PROVIDERS.md`.

**Testing aids.** Debug menu: Sample Data mode (off by default, labelled on every screen), Seed Sample Trip, Reset All Data. Snapshot renderer for every screen and state.

**Not in milestone 1, deliberately:** Night mode (designed with the palette work, below), spot photos (the Wikipedia source is gone; the Explore place card's image strip shows Look Around where Apple has it, 4 of 45 curated spots, and a satellite image otherwise; user photos will be one more source in that strip), a per-day timeline strip (6.3-B), "How did it go?" check-ins, calendar and GPX export.

## Milestone 2 · Foundation and field

* Night mode (red, dim) as a token mode (P2.4–P2.6). The palette decision is made: First Light throughout.
* Now mode (E1): opens to the next three hours during a trip.
* Weather swap (B3) inside 72 hours, once the confidence model has been tested.
* Calendar export of sessions and GPX; along-the-drive spots (P4.6).
* "How did it go?" check-in to calibrate the Light Index.

## Before any release (weather providers)

* Ship the Windy logo asset (unscaled, clickable to windy.com) beside "Contains data from the Windy database", and use a Windy Professional key (Testing data is shuffled and development-only).
* Record real fixtures for OpenWeather and Windy with `ITER_LIVE=1` and replace the documented-schema ones.
* Confirm whether OpenWeather's free allowance needs a payment card.
* Consider One Call 4.0, which OpenWeather now recommends for new integrations.
* An in-app Windy map only with a Map Forecast Professional licence that permits a native app. Until then the map opens windy.com.

## Milestone 3 · Everywhere

* iCloud sync of trips and spots (SwiftData + CloudKit), then shared trips with CloudKit sharing and the no-account guest link (P3.6, P5.5).
* Offline trip packs (C2), never paywalled: area, legs, windows, last forecast with its age.
* The iOS app over the same IterKit, with the "Tonight" Live Activity (C1).
* Widgets (C7).

## Milestone 4 · Business

* The fair paywall (E5): one tier, price before trial, never locks a built trip.
* Value-added data notice and a public method page for the Light Index.
