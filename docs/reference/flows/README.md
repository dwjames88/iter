# Iter user flows

These briefs describe how a person moves through the current Iter prototype build (still named "Vantage" in the code). They cover what is actually built, including stubs and places where the UI implies more than the code does. Each brief ends with a separate **Tweak points** section for things to change.

The Markdown files are the editable source. `iter-user-flows.html` is a reading view of the same content, with every flowchart rendered. It is generated from these files, so edit the Markdown and ask for the page to be rebuilt.

Source references use `path:line` relative to the project root and were checked against the build on 2026-10-04.

| File | Flow | Summary |
|---|---|---|
| [00-app-map.md](00-app-map.md) | App map | Every route and overlay, global navigation, the master flowchart, a screen inventory, where data lives, and app-wide tweak points. Start here; it also has the diagram legend. |
| [01-first-visit-landing.md](01-first-visit-landing.md) | First visit: landing page | The marketing page at `/`, its live "Tonight's light" cards and about ten ways into the app. The hero search is discarded on arrival. |
| [02-explore-browse-map.md](02-explore-browse-map.md) | Explore: browse the map | Map plus list at `/explore`: search, filters, date, "Search this area", bottom sheet and floating card on mobile, split view on desktop. |
| [03-ai-discover.md](03-ai-discover.md) | AI scout (discover mode) | Asking for spots in plain language, the paced loading steps, results as cards and gold pins, saving them or adding them to a trip, and the Worker and browser fallback behind it. |
| [04-add-custom-spot.md](04-add-custom-spot.md) | Add your own spot | Pick mode or long-press on the map, the add-spot form, and where the new spot then shows up. Custom spots cannot be edited or deleted. |
| [05-spot-detail.md](05-spot-detail.md) | Spot detail | `/spot/:id`: 7-day date strip, light timeline, Light Index, sun and moon, hourly weather, nearby spots, save, share, directions and the Add to trip modal. |
| [06-trips-list-and-create.md](06-trips-list-and-create.md) | Trips list and create | `/trips`, the New trip form, one-tap templates, trips created implicitly from Explore, and deleting a trip. |
| [07-trip-builder.md](07-trip-builder.md) | Trip builder | `/trip/:id`: title, dates and days, adding and reordering stops, light sessions, notes, drive times and warnings, the map. |
| [08-invite-and-sync.md](08-invite-and-sync.md) | Invite and sync | The Invite modal, the share link and QR code, adding people by name, and how the trip is mirrored to Cloudflare KV and pulled back. |
| [09-join-shared-trip.md](09-join-shared-trip.md) | Join a shared trip | The recipient opening `/join/CODE`: preview card, name, join, and the not-found and unreachable states. |
| [10-saved-and-returning.md](10-saved-and-returning.md) | Saved and returning users | The two kinds of "saved" spot, what persists in the browser, the anonymous name-only identity, and what a returning visitor sees. |
| [11-system-and-edge-states.md](11-system-and-edge-states.md) | System and edge states | Loading, not found, offline and failure behaviour across the app in one table, plus the internal `/styleguide` route. |
| [iter-user-flows.html](iter-user-flows.html) | Reading view | All of the above on one page with a table of contents and rendered flowcharts. |
