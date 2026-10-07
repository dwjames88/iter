# Iter screens and states

Hand-off for rebuilding Iter's design in a design tool. Companion files: [COMPONENTS.md](COMPONENTS.md) (every component), [TOKENS.md](TOKENS.md) and `tokens.json` (every colour, size and type style). Everything here is read from the SwiftUI code in `App/Sources/` and the snapshot tests in `AppTests/`.

Iter is a native macOS 26 app. Its promise: **"Be in the right place when the light is right."** It plans photography trips around the Light Index, a 0 to 100 score for one named light window (Sunrise, Sunset, the blue hours, Night) at one place.

## How to read this

- **Tokens** are written as `space/md`, `light/ramp/good`, `type/headline`. Look them up in TOKENS.md. Where the code uses a system control or system colour, the text says so.
- **Hierarchy.** Every screen follows [HIERARCHY.md](HIERARCHY.md): five type levels (Display, Title, Headline, Body, Secondary), module titles in `type/moduleTitle`, one strong fact per module, an 8 pt grid with 16 pt insets and fixed lanes. Metadata is `type/secondary` in `text/secondary`. The event unit is one capsule in one continuous band-coloured fill, with the window's symbol, the number and the time in the band's text colour ([EventScore](COMPONENTS.md#eventscore-the-event-unit)); screens name its variant.
- **Components** link to COMPONENTS.md anchors. A component that is only a system control is listed under "System components" there.
- **Snapshot paths** are relative to `Design/`. They are written compactly: `snapshots/trips-list-{light,dark}-{1280x820,960x640}.png` means four files. Sizes: `1280x820` (the default window), `960x640` (a small window), `1280x2600` (the spot page, tall, to show all of it). PNGs are 2x pixels (2560x1640).
- **What the snapshots are.** Every screen except the shell is rendered alone in a navigation stack, with no sidebar and no toolbar contents. Only `shell-default` shows sidebar plus detail. Explore and Locations are the exception: they split their own width, so they are rendered beside a blank 240 pt strip that stands in for the sidebar, which gives them the detail width a real window has. The sidebar has its own render (`sidebar-library`). New snapshot names (`explore-ask-*`, `locations-*`, `sidebar-library`) come from `scripts/snapshots.sh`; the older `saved-*` and `scout-*` files in `snapshots/` are from before the restructure and are no longer produced. The date in every snapshot is fixed: **Tue, Oct 6, 2026, 10:00 in Denver**. Times follow the Mac's clock, which is 24-hour in these renders ("17:25", not "5:25 PM"). Sample weather is on in every "sample" render, so those screens carry the Sample data label.
- **What the snapshots cannot show** is listed in [Not in the snapshots](#not-in-the-snapshots). Read it before trusting a blank area.
- "Light mode" and "dark mode" are the system appearances. The sidebar, toolbar, Settings and sheets keep system colours; what the app draws itself uses First Light paper and ink (see "Where First Light stops" in TOKENS.md).

## Contents

1. [Navigation map](#navigation-map)
2. [Menu bar and keyboard shortcuts](#menu-bar-and-keyboard-shortcuts)
3. [Shell: sidebar and detail](#shell-sidebar-and-detail)
4. [All Trips](#all-trips)
5. [New Trip sheet (and Change Dates sheet)](#new-trip-sheet-and-change-dates-sheet)
6. [Trip builder](#trip-builder)
7. [Explore](#explore)
8. [Spot page](#spot-page)
9. [Locations](#locations)
10. [Spot editor sheet](#spot-editor-sheet)
11. [Settings](#settings)
12. [Menus, popovers, dialogs not in the snapshots](#menus-popovers-and-dialogs)
13. [Not in the snapshots](#not-in-the-snapshots)
14. [Cross-screen conventions](#cross-screen-conventions)

---

## Navigation map

| Surface | Kind | Reached from |
|---|---|---|
| Sidebar: All Trips | Detail root | Sidebar, Go > Trips (⌘1), the app opens here |
| Sidebar: one entry per trip (pinned, in a folder or unfiled) | Detail root (Trip builder) | Sidebar, a trip card, a template, New Trip (after Create), Debug > Seed Sample Trip |
| Sidebar: Explore | Detail root | Sidebar, Go > Explore (⌘2), Find Spots (⌘F), Add Spot on Map (⇧⌘N), New Location in the sidebar's New menu, Locations empty-state buttons |
| Sidebar: All Locations | Detail root | Sidebar, Go > Locations (⌘3) |
| Sidebar: one entry per location folder | Detail root (Locations, filtered) | Sidebar |
| Ask (a section inside Explore) | Part of the Explore list | The **Ask Iter** suggestion under the search field (Return when it is first, or a click). There is no toggle and no menu item. |
| Spot page | Pushed onto the current section's navigation stack | Explore (Open, double-click, Return, including Ask rows), Locations (Open, double-click), Trip builder (stop name, context menu). Each section keeps its own stack, so switching sections keeps your place. |
| New Trip sheet | Sheet | New Trip (menu, toolbar, empty-state button, template row) |
| Change Dates sheet | Sheet | Trip builder: date line in the header, or Trip Actions menu |
| Spot editor sheet | Sheet | Explore (after a click in Add Spot mode), Spot page Edit (your own spots), Locations context menu Edit… |
| Add Stop popover | Popover | Trip builder: "Add Stop" row under each day |
| Set-up time popover | Popover | Trip builder: the "20 min set-up" link on a stop |
| Settings | Separate window, four tabs | App menu > Settings… (⌘,) |
| Place card | Floating panel over the Explore map | Selecting a pin or row |

A new section's detail replaces the previous one. Trips are listed first in the sidebar because the plan makes the trip the home of the app. The main window restores its last sidebar selection on launch (falls back to All Trips if that trip or folder is gone). Folder rows in the Trips group only open and close; they are not destinations.

---

## Menu bar and keyboard shortcuts

From `App/Sources/Shell/AppCommands.swift`, plus screen-level shortcuts. None of the menus render in snapshots.

| Menu | Item | Shortcut | Notes |
|---|---|---|---|
| File (replaces "New") | New Trip | ⌘N | Switches to All Trips (unless already in a trip) and opens the New Trip sheet. |
| File | New Folder | ⌥⌘N | Makes a folder in Trips, or in Locations when a Locations screen is open, and puts its sidebar row into rename. |
| File | Add Spot on Map | ⇧⌘N | Switches to Explore and turns on Add Spot mode. |
| File | Import Trip… | ⌘O | Opens a file picker for `.iter` (or .json) files; imports as a new trip. |
| Edit (after text editing) | Find Spots | ⌘F | Switches to Explore and focuses the search field. |
| Go | Trips | ⌘1 | |
| Go | Explore | ⌘2 | |
| Go | Locations | ⌘3 | |
| Light | Refresh Forecasts | ⌘R | Re-requests only the forecasts that failed (no key, rejected key, cap reached, offline). Forecasts that loaded are kept. Changing anything in Settings > Weather is different: it drops every forecast and every screen refetches. |
| Debug | Use Sample Weather (toggle) | none | Off by default. When on, scores use made-up weather and "Sample data" is labelled. |
| Debug | Seed Sample Trip | none | Adds the Canyon Country trip starting tomorrow and opens it. |
| Debug | Reset All Data… | none | Destructive. System alert "Delete all trips and spots? This can't be undone." Buttons Delete Everything, Cancel. |
| Edit | Undo / Redo | ⌘Z / ⇧⌘Z | Names the action ("Undo Move Stop"). Every move, removal, rename, date change, duplicate, delete, save, spot edit, folder change and pin is undoable. |
| Iter | Settings… | ⌘, | Opens the Settings window. |

Screen-level shortcuts:

| Where | Shortcut | Action |
|---|---|---|
| Explore | Esc | Leaves Add Spot mode (Cancel on the banner) |
| Explore list | Click | Selects the row; its light panel replaces the list after the double-click interval |
| Explore list | Up, Down | Move the selection and open the panel at once |
| Explore list | Return | Opens the light panel for the selected row |
| Explore list | Double-click | Opens the spot page |
| Explore light panel | Up, Down | Step to the previous or next place in list order; the pin follows |
| Explore light panel | Esc, **‹ Places** | Back to the list at the same scroll position, the row still selected (Esc is left to Add Spot mode while it is on) |
| Explore | ⌘F | Focuses the search field, in the list and in the panel |
| Spot page | ⌘D | Save / unsave (not offered on your own spots) |
| Spot page | ⌘E | Edit (your own spots only) |
| Trip builder | ⇧⌘D | Change Dates… (Trip Actions menu) |
| Trip builder | ⇧⌘E | Export… (Trip Actions menu) |
| Trip builder, Locations | Delete | Remove the selected stop; in Locations, delete your own spot or unsave a saved one |
| Sheets (New Trip, Change Dates, Spot editor) | Return / Esc | The default button (Create, Change Dates, Add Spot or Save: `.defaultAction`) / Cancel (`.cancelAction`) |
| Sidebar rename field | Return / Esc | Save the name / leave it unchanged |
| Explore search field | Return | Runs the first suggestion: Ask Iter when the text reads like a request and Apple Intelligence can run it, else Apple Maps |

---

## Shell: sidebar and detail

**Purpose.** The frame for the whole app: choose a trip or a way to find places, see it in the detail column.

**Placement.** The main window (`WindowGroup`). Default size 1280x820, minimum 761x600 (`layout/windowMinWidth`, `layout/windowMinHeight`; 761 is `layout/listColumnMin` 340 + `layout/detailMin` 420 + a 1 pt divider). `NavigationSplitView` with a sidebar column (sidebar minimum 240 pt, ideal 240, maximum 320: `layout/sidebarMin`, `Ideal`, `Max`) and a detail column. The sidebar collapses on its own when the window is narrower than 1001 pt (sidebar ideal plus window minimum), and returns when there is room, unless you collapsed it yourself.

**Regions.**

| Region | Contents |
|---|---|
| Sidebar, Trips | Section header **Trips**. Rows, in order: **All Trips** (`map`); pinned trips; trip folders; unfiled trips. A trip row is the icon `point.topleft.down.to.point.bottomright.curvepath`, the name and, at the trailing edge, for a pinned trip a small `pin.fill` (tooltip "Pinned: kept ready offline") and an [OfflineStatusBadge](COMPONENTS.md#offlinestatusbadge) in its row style. A pinned trip shows only in this pinned group, never inside its folder. A folder is a disclosure row (`folder`, name) that opens to its subfolders, then its trips; clicking it or its arrow opens and closes it, and which folders are open is remembered. Folders nest one level. |
| Sidebar, Locations | Section header **Locations**. Rows: **All Locations** (`mappin.and.ellipse`), then one row per location folder (`folder`, name), selectable; a folder with subfolders is a disclosure row, its subfolders selectable inside it. |
| Sidebar, Find | Section header **Find**. Row: **Explore** (`binoculars`). |
| Sidebar, bottom | Only when Sample data mode is on: a [SampleDataLabel](COMPONENTS.md#sampledatalabel) in banner style, padded `space/sm`, pinned to the bottom edge. |
| Sidebar toolbar | One menu button, `plus`, labelled "New", tooltip "New Trip, Folder or Location". Items: **New Trip** (⌘N), **New Folder** (⌥⌘N; made in the section the current selection belongs to, trips by default) and **New Location** (opens Explore in Add Spot mode). |
| Detail | A navigation stack holding the selected section. Window title is the section's title ("All Trips", "Explore", ...). |

**Components.** [SampleDataLabel](COMPONENTS.md#sampledatalabel) (banner), system sidebar List, [SidebarTripRow](COMPONENTS.md#sidebar-rows) and the folder rows, [OfflineStatusBadge](COMPONENTS.md#offlinestatusbadge), [TripContextMenu](COMPONENTS.md#tripcontextmenu), [FolderContextMenu](COMPONENTS.md#foldercontextmenu).

**Actions.** Click a row to select. Trip rows: right-click for Open, Pin Trip or Unpin Trip, Move to Folder ▸, New Folder with Selection, Rename, Duplicate, Share…, Delete Trip. Folder rows: right-click for New Folder Inside (top-level folders only), Rename, Delete Folder (its contents move up a level). Rename edits the name in the row: Return saves, Esc cancels, an empty name is ignored. Drag a trip onto a folder to file it, onto another trip to put it before that trip in its container, onto a pinned trip to pin it, or onto All Trips to unfile it; drag a location from the Locations list onto a location folder; drag a folder onto a top-level folder to nest it. Every one of these is undoable. The sidebar selection is the accent-tinted system pill (a neutral grey pill in the snapshots, because the offscreen window is inactive).

**States.**

| State | Trigger | What changes | Snapshots |
|---|---|---|---|
| Default (sample data on) | App open, All Trips selected, one trip (Canyon Country) | Sidebar as above, Sample data banner at the bottom, detail shows the All Trips list with one trip card. | `snapshots/shell-default-{light,dark}-{1280x820,960x640}.png` |
| No sample banner | Sample data off | Banner absent; nothing else changes. | not rendered |
| Trip renamed or created | Store changes | Sidebar rows follow the store. | not rendered |
| Library | A pinned trip, a trip folder with a subfolder, unfiled trips, no sample banner | The sidebar alone at 240 pt wide, 560 pt high: pinned trip (pin and status glyph), folders with their trips, Locations, Find. | `snapshots/sidebar-library-{light,dark}-1280x820.png` |

Note for the redesign: in the snapshots the toolbar and the sidebar-toggle render as blank rounded squares, and the traffic lights are absent (see [Not in the snapshots](#not-in-the-snapshots)). The window title "All Trips" appears top-left of the detail.

---

## All Trips

**Purpose.** The home of the app: your trips, or one clear way to start one.

**Placement.** Sidebar > All Trips. Window title "All Trips".

**Regions (list state).** Scrolling grid on `background/window`, content margin `space/xl`. Adaptive columns, 300 to 360 pt wide (`layout/listMin` to `layout/listIdeal`), gap `space/lg`. Toolbar: New Trip (`plus`) when at least one trip exists.

**Regions (empty state).** Centred column, page margin `space/xxl`, items spaced `space/xl`:

1. Headline "Plan trips around the light" in `type/title/spot`, centred.
2. Sentence "Pick your spots and days. Iter works out when to leave so you are set up before the light arrives." in `type/callout`, `text/secondary`.
3. Primary button **New Trip** (prominent, large, minimum width 128 pt).
4. Caption "Or start from a template" (`type/captionStrong`, `text/secondary`).
5. Three [TemplateRow](COMPONENTS.md#templaterow)s (max width 520 pt): Canyon Country (4 days, 6 stops), Eastern Sierra (3 days, 6 stops), Yosemite (2 days, 3 stops), each with its first three spot names.

**Components.** [TripCard](COMPONENTS.md#tripcard), [TemplateRow](COMPONENTS.md#templaterow), [TripContextMenu](COMPONENTS.md#tripcontextmenu).

**Actions.** Click a card to open the trip. Right-click a card: Open, Duplicate, Share…, Delete Trip. New Trip button or ⌘N opens the [New Trip sheet](#new-trip-sheet-and-change-dates-sheet). Click a template row to open the sheet with that template chosen. ⌘O imports a trip file.

**States.**

| State | Trigger | What changes | Snapshots |
|---|---|---|---|
| Empty | No trips | Headline, New Trip, three template rows. | `snapshots/trips-empty-{light,dark}-{1280x820,960x640}.png` |
| List | One or more trips | Card grid. Three cards are rendered: a trip with no stops ("No stops yet. Open the trip to add the first." with an accent `plus.circle`), and two with a Next line: one secondary line, "Next: Horseshoe Bend", then the window's symbol (a blue-hour window in `light/blueHour`) and "Sunset from 17:25, Wed", all `type/secondary` in `text/secondary`. | `snapshots/trips-list-{light,dark}-{1280x820,960x640}.png` |
| Card, all sessions passed | Every stop's session is in the past | Footer reads "All sessions have passed" with a `checkmark.circle`. | not rendered |
| Import error | A bad `.iter` file | System alert "Couldn't Import Trip" with a reason, button OK. | not rendered |

---

## New Trip sheet (and Change Dates sheet)

**Purpose.** Name a trip, choose its start date and length, optionally start from a template.

**Placement.** Sheet over All Trips or a trip. The sheet is **sized to its content** (no fixed height), with a 20 pt margin all round (`space/sheet`); it is a grouped form of system controls only (see [Controls](COMPONENTS.md#controls)). `.tint(nil)` at the sheet root keeps the app's coral tint off the neutral buttons and pickers. The snapshot renders the sheet in a larger frame, so take its size from the content, not the picture.

**Regions, top to bottom.**

1. Title "New Trip" (`type/title/section`).
2. Grouped form, two sections: **Name** (text field, placeholder is the template name or "New Trip") and **Start from** (menu picker: "Empty trip", divider, each template as "Name · 4 days, 6 stops"); then **Starts** (compact date picker, shown in UTC so the date does not shift) and **Days** (menu picker; the items read "1 day", "2 days", "3 days", inflected, up to the maximum).
3. When a template is chosen: the Days picker is disabled and the section footer says "The template sets the number of days. You can add, move and remove stops afterwards." (system footer text).
4. Buttons, trailing: system **Cancel** (Esc) and **Create** (the default button, Return).

**Actions.** Create makes the trip, selects it in the sidebar and closes the sheet. Default start date is tomorrow. Default length 3 days (the template's length when one is chosen).

**Change Dates sheet** (same sizing, margin and controls). Title "Change Dates". Fields: **Starts** (compact date picker), **Days** (menu picker, "3 days"), **Ends** (read-only text, "Fri, Oct 9, 2026"). When shortening the trip would push stops off the end, a violet warning line with `exclamationmark.triangle.fill`: "N stops will move to Day D, the new last day. You can undo this." Buttons system Cancel and **Change Dates** (default). Not rendered in the snapshots.

**Components.** System grouped Form, compact DatePicker, menu Picker, system buttons; [WarningLine](COMPONENTS.md#warning-lines) (Change Dates).

**States.**

| State | Trigger | What changes | Snapshots |
|---|---|---|---|
| New Trip, template chosen | Open from the Canyon Country template row | Name placeholder "Canyon Country", Days "4 days" (disabled), "Start from" shows the template, explanatory footer shown. | `snapshots/trip-new-sheet-{light,dark}-{1280x820,960x640}.png` |
| New Trip, empty | New Trip button or ⌘N | Days "3 days" and enabled, "Start from" is "Empty trip", no footer. | not rendered |
| Change Dates, stops would move | Shortening the trip below the last used day | Violet warning line appears. | not rendered |

The snapshot draws the sheet on a regular-material panel with 12 pt corners, centred in the frame, with empty space around it. In the app the sheet is sized to its content.

---

## Trip builder

**Purpose.** Lay out days and stops so you are set up before the light arrives. The list is the plan; the map is the sanity check.

**Placement.** Sidebar > a trip. A navigation stack root (a spot page can be pushed on top).

**Regions, left to right.** A horizontal split view (draggable divider): left column minimum 340 pt (`layout/listColumnMin`), ideal 520 pt; right map minimum 420 pt (`layout/detailMin`).

**Route map camera.** The route map fits the whole trip when the builder first opens, never wider than a 40 degree span. Once you move the map, the camera is yours: it is saved for that trip and restored on relaunch, and changing stops refits only while you have not touched it. Selecting a stop pans to it with the zoom kept.

Left column, top to bottom:

| Region | Contents |
|---|---|
| [TripHeader](COMPONENTS.md#tripheader) | Trip name as an in-place text field (`type/title/spot`; click to rename, Return or leaving the field commits). Beneath it, a line in `type/subheadline`, `text/secondary`: a borderless date-range button with a `calendar` icon, then "4 days · 6 stops", then "376 mi · 8 hr, 39 min driving" (suffix "(estimated)" when any drive is a straight-line estimate). The driving total is hidden under one minute. Padding `space/lg`. For a pinned trip, one more line under the dates: the [OfflineStatusBadge](COMPONENTS.md#offlinestatusbadge) in header style (glyph and words, for example "Ready offline"; hover for the note that the base map is not stored offline). Nothing is drawn for a trip that is not pinned. |
| Divider | |
| [WeatherStatusBanner](COMPONENTS.md#weatherstatusbanner) | Only when weather is missing. |
| [TripOverviewStrip](COMPONENTS.md#tripoverviewstrip) | One equal-width cell per day (only on trips of more than one day): "Day 2", "Thu 8", "2 stops", the best window as one compact event unit ([EventScore](COMPONENTS.md#eventscore-the-event-unit): symbol, score and start time in one capsule) or "No stops", a warning mark when the day has a conflict. The selected day's cell has an accent fill and stroke. More days than fit scroll horizontally. A divider closes it. |
| [Plan list](COMPONENTS.md#tripplanlist) | A list on `background/window`. Each day is one bounded container (see below); between containers an [OvernightBoundary](COMPONENTS.md#overnightboundary). |
| Footer | [ForecastSourceLines](COMPONENTS.md#forecastsourcelines) as the last row, only when at least one stop has a score. No attribution; that is in Settings. |

Each day container (`background/content`, `radius/card` corners, hairline stroke; accent stroke when the day is selected), top to bottom:

1. [DayHeader](COMPONENTS.md#dayheader): "Day 2" (`type/title/section`) with "Thursday, October 8", the light bookends (sunrise and sunset symbols with their times), and "2 stops · 5 hr, 27 min driving" or "No stops yet".
2. [SuggestionBanner](COMPONENTS.md#suggestionbanner), only when the stops are out of light order.
3. A conflict line ("2 conflicts on this day"), only when the day has conflicts.
4. The timeline. A time gutter on the left (leave time beside a drive, set-up time beside a stop), a rail with numbered stop nodes joined by a line, and the content on the right. The drive from the previous day's last stop is the first item of the day ("From Horseshoe Bend"). Between two stops a [DriveRow](COMPONENTS.md#driverow) sits on the rail. Each stop is a [StopRow](COMPONENTS.md#stoprow).
5. An **Add Stop** row (accent text, `plus` icon), aligned with the stop content.

Right column: [TripRouteMap](COMPONENTS.md#triproutemap) (with the user's location dot when permitted), full height. A day switcher floats at its top edge: "‹ Day 2 · Thu, Oct 8 ›" with previous and next buttons, and a menu with All Days.

Day selection has one source of truth. The strip, the map switcher, the list's accent stroke and the map's highlighted day all read it. Choosing a day in the strip or the switcher scrolls the list to that day and frames it on the map; selecting a stop (list or pin) selects its day. With no day selected (All Days) the strip shows no highlight and the map shows every day at full strength; with a day selected, the other days' pins and routes are dimmed.

Toolbar: a spinner while drive times are fetched ("Fetching drive times"), **Share** (`square.and.arrow.up`, shares the trip as an `.iter` file), and **Trip Actions** (`ellipsis.circle`) with Change Dates… (⇧⌘D), Export… (⇧⌘E), Duplicate, divider, Delete Trip (destructive). The window title is removed because the trip name is the header. There is no day picker in the toolbar.

Launch switches for captures: `-IterSeedTrip conflict` seeds the sample trip with day 2 reversed (a conflict and a Reorder-by-light suggestion); `-IterTripDay <n>` opens the builder with day n (1-based) selected.

**Components.** [TripHeader](COMPONENTS.md#tripheader), [TripOverviewStrip](COMPONENTS.md#tripoverviewstrip), [DayHeader](COMPONENTS.md#dayheader), [StopRow](COMPONENTS.md#stoprow), [StopNumberBadge](COMPONENTS.md#stopnumberbadge), [DriveRow](COMPONENTS.md#driverow), [OvernightBoundary](COMPONENTS.md#overnightboundary), [SuggestionBanner](COMPONENTS.md#suggestionbanner), [EventScore](COMPONENTS.md#eventscore-the-event-unit) (regular on stops, compact in the overview strip), [BandConfidence](COMPONENTS.md#bandconfidence), [WindowSymbol](COMPONENTS.md#windowsymbol), [WeatherStatusBanner](COMPONENTS.md#weatherstatusbanner), [WarningLine](COMPONENTS.md#warning-lines), [TripRouteMap](COMPONENTS.md#triproutemap), [AddStopPopover](COMPONENTS.md#addstoppopover), [ForecastSourceLines](COMPONENTS.md#forecastsourcelines), [MapStandIn](COMPONENTS.md#mapstandin) (snapshots only).

**Actions.**

- Rename the trip in place. Change dates (header date button).
- Click a stop to select it (selection is shared with the map pin and selects the stop's day; the map frames that day, or recentres on the stop keeping zoom when the day is already framed). Click the stop's name to open its spot page for that day.
- Change a stop's **session** with the menu on the row; the closed menu reads "Sunset · 17:25–18:00" (the score is in the event unit above it); each item in the open menu has the window's symbol and reads "Sunset · 17:25–18:00 · 7" (window, time range, score for that day; no score when there is no forecast). A stop shows its own session on its assigned day.
- Edit the **set-up time** by clicking "20 min set-up" (popover with a stepper 0 to 120 in steps of 5).
- Type a **note** under the stop (saved a second after you stop typing, and on leaving the field).
- **Reorder:** drag a stop onto another stop or a drive row (goes before the stop), onto a day header or the Add Stop row (goes to the end of that day). A 2 pt accent line shows the drop spot. Keyboard and VoiceOver: stop context menu Move Up, Move Down, Move to Day ▸.
- **Remove:** Delete key, or context menu Remove from Trip.
- Stop context menu: Open Spot Page, Open in Maps, Move Up, Move Down, Move to Day ▸ (only on multi-day trips), Remove from Trip.
- Suggestion banner: **Apply** reorders that day by light order; **Dismiss** hides it. Iter never reorders by itself.
- Add Stop opens the [AddStopPopover](COMPONENTS.md#addstoppopover).
- Click a day cell in the strip, or use the map's day switcher, to select a day. Click a day header to select it too.

**States.**

| State | Trigger | What changes | Snapshots |
|---|---|---|---|
| Default, sample weather | Seeded Canyon Country (6 stops over 4 days), day 2 selected, sample data on | Strip with four cells (each with the day's best window as a compact event unit), Day 2 highlighted; Day 1 container, overnight boundary "Overnight · near Page, AZ", Day 2 container with its accent stroke starting with the drive in from Horseshoe Bend. On each stop's title line, the session as a regular event unit (the window's symbol, the score and the start time in one capsule, banded by colour) and its band word with confidence bars: Day 1, Horseshoe Bend, a pale sand chip (hairline) holding the sunset symbol and "7", the time "17:25" after it, then "Poor". Drives are coral (`route/active`). Map shows Day 2's route and pins at full strength, the others dimmed, and the switcher "Day 2 · Thu, Oct 8". | `snapshots/trip-builder-{light,dark}-{1280x820,960x640}.png` |
| Weather offline | Weather not enabled (the fixture), no day selected | The weather banner above the strip: "Apple Weather isn't enabled for this build. Choose another source in Settings." with a **Settings…** button. No cell is highlighted, the map shows every day and the switcher reads "All Days". Every stop shows its window's symbol alone where the event unit's head would be, with its start time; no stop says "No forecast". The session menu items carry no score. | `snapshots/trip-builder-weather-offline-{light,dark}-{1280x820,960x640}.png` |
| Conflict and suggestion | Sample trip with day 2 reversed (`-IterSeedTrip conflict`), day 2 selected | Day 2's strip cell has a violet warning mark. Its container shows the suggestion banner "Reorder by light: fixes 2 conflicts" with Dismiss and Apply, then "2 conflicts on this day". Violet rails and "Drive doesn't fit: …" lines on drives that cannot be made; a violet "Out of order" line on the stop. | `snapshots/trip-builder-conflict-{light,dark}-{1280x820,960x640}.png` |
| Missing trip | The trip was deleted or its creation undone | Empty-state: map icon, "Trip Not Found", "This trip was deleted or its creation was undone.", prominent button **Back to All Trips**. | `snapshots/trip-builder-missing-{light,dark}-{1280x820,960x640}.png` |
| A stop row (detail) | Component study | Four stops in a 560 pt column as timeline rows, showing: the first stop with its set-up time in the gutter and no drive, drives with their leave times, "Park 06:50 · 10 min walk-in", walk-in unknown, an out-of-order line, an overnight boundary, the drive in at the top of day 2, infeasible drives, and a blue-hour window ("Evening blue hour"). | `snapshots/trip-stoprow-{light,dark}-{1280x820,960x640}.png` |
| Dragging | A stop is dragged over a drop target | A 2 pt accent capsule appears at the top of the target. | not rendered |
| Fetching drives | Drive times being fetched | Toolbar spinner; drive rows for new legs fill in as MapKit answers. | not rendered |
| Estimated drive | MapKit has no road route | Connector adds "· estimated" (tooltip "Drive time estimated"), and the header total gets "(estimated)". | not rendered |
| Window missing | The sun does not produce the chosen window that day | Stop line "No Sunset window on this day at this place" (violet, with icon); session menu shows "Sunset · no window this day". | not rendered |

---

## Explore

**Purpose.** Find the next good light across 45 curated spots, your own spots, and Apple Maps results, each scored for its own coordinate. A row is only light: the spot's next sunrise or sunset. One selection drives the pin, the row and the light panel that replaces the list.

**Placement.** Sidebar > Explore. Window title "Explore".

**Regions, left to right.** A horizontal split view: list column (min 340, ideal 360, max 520 pt) beside a full-height map (min 420 pt). The split view ignores the ideal width: it shares the detail width equally and clamps the list to 340 to 520, so beside the 240 pt sidebar the list is 520 pt in a 1280 pt window. Below 1001 pt the sidebar collapses, and at the 761 pt window minimum the list is 340 and the map 420 with the sidebar closed.

The list column has two states. The **list** (below) is the default. When a place is selected and opened, the **light panel** ([ExploreLightPanel](COMPONENTS.md#explorelightpanel), described after the list) takes the column's place; the map and its pins do not change, and nothing floats over the map.

List column, top to bottom ([ExploreListPanel](COMPONENTS.md#explorelistpanel)):

1. **Header** (padding `space/md` by `space/sm`): "45 places" in `type/secondary`, `text/secondary` at the leading edge; at the trailing edge a small spinner while forecasts load, then one borderless menu button (tinted with the app accent in the app; it renders in ink in the snapshots) with `line.3.horizontal.decrease.circle` (filled, with a count, when filters are on). Its menu: inline picker **Near You Radius** (100, 200, 300, 500 mi; default 300), inline picker **Sort By** (Best Light, Name, Distance, Popularity; Distance by default when Iter knows where you are), submenus **Category** (10 categories), **Known For** (Sunrise, Sunset, Blue hour, Night sky, Midday, Overcast) and **Source** (Curated, Your Spots, Apple Maps), divider, Clear Filters (disabled when no filter is on). There is no light choice and no date: a row always shows the next sunrise or sunset. Under the count, a Sample data label when sample weather is on, and the search status slot. Below the header's divider, in order, whichever apply: the [WeatherStatusBanner](COMPONENTS.md#weatherstatusbanner) (no key, offline or a provider error; see the Weather offline state) and the [ExploreLocationBanner](COMPONENTS.md#explorelocationbanner) (only while there is no location).
2. Hairline divider.
3. **Search suggestions** (only while the field has text and no search or Ask for that text is running or shown): at the top of the list, above any Ask section and above the empty state, two labelled groups, each a header in `type/moduleTitle` over one button row. See [Search suggestions](#search-suggestions) below.
4. **List** (inset style) in sections with a header (`type/moduleTitle`, `text/secondary`; 24 above, 8 below) and a count, made of [ExploreRow](COMPONENTS.md#explorerow)s, sorted by the chosen sort. Or an empty state. **With a location:** "Near You · Within 300 mi" (your own and curated spots inside the radius), "Popular" (curated spots with popularity 80 or more outside the radius, most popular first), "More Places" (everything else; collapsed until you open it, and open while a search narrows the list), then "Apple Maps" results in their own section. **Without a location:** one "Spots" section under the location banner, then "Apple Maps". Each row is 48 pt at least (`grid/row/double`) and has two parts on one first baseline. Left, the label lane: the spot name (`type/headline`, wraps to two lines rather than truncating) over one `type/secondary` line: locality, then the distance after it when a location is known ("Big Sur, CA · 101 mi"), then "Added by you" on your own spots. Right, one measured lane: the regular **event unit** (one capsule, 24 pt, one band-coloured fill: the window's symbol, the score and the start time). Units are one width and stack down the whole list. While a spot's forecast is in flight a small spinner sits beside the symbol; with no score the head is neutral with the symbol alone and the time still shows. Rows are fetched in list order as they appear, and "More Places" when opened. Clicking a row selects it and opens its panel (see Actions).
5. Hairline divider.
6. **Footer:** [ForecastSourceLines](COMPONENTS.md#forecastsourcelines): a quiet source line per distinct source behind the scored rows (without a time, for example "Windy · GFS"; a fallback reads "OpenWeather (Apple Weather unavailable)"). Attribution is not shown here; it is in Settings ▸ Weather and About. With no forecast loaded, the footer is empty.

**Light panel** ([ExploreLightPanel](COMPONENTS.md#explorelightpanel)). The column is 340 to 520 pt wide, and the panel fills it, on `background/content`. Top to bottom:

1. **Header** (padding `space/sm` vertical, `grid/inset` horizontal), then a divider: **‹ Places** at the leading edge (`chevron.left`, accent, tooltip "Back to places (Esc)"), then "3 of 16" (`type/secondary`, `text/secondary`, digits monospaced), then up and down steppers (`chevron.up`, `chevron.down`; each disabled at the end of the list).
2. The weather banner, when weather is missing.
3. **Place:** name (`type/title/spot`, up to two lines); on its baseline at the trailing edge the next event as a large event unit (44 pt, start time), with "Tomorrow" before it when it is tomorrow's. Under both, locality · distance (only with a location) · [ProvenanceTag](COMPONENTS.md#provenancetag) in `type/secondary`, `text/secondary`.
4. **Image strip** ([SpotImageStrip](COMPONENTS.md#spotimagestrip), `size/imageStripHeight`, 200 pt), running to both column edges.
5. **Light through the day** ([LightTimeline](COMPONENTS.md#lighttimeline) at panel density): a segmented range control at the full width under the title, a readout line, the sky band (88 pt) and the cloud and rain plot (112 pt) at the column's width with no label gutter (the 0, 50 and 100 percent labels sit inside the plot), the hour axis with a time pill at the marker, and the legend. Hover or drag reads any time. From 350 pt wide the legend line ends in "Drag to read any time" (on the readout line when the legend has no room). The timeline grows with the column.
6. **Today** (the windows still ahead, with the date at the title's trailing edge) and **Coming up** (tomorrow's windows, with its date): [DayWindowsSection](COMPONENTS.md#daywindowssection) at panel density, each a filled card of [WindowRow](COMPONENTS.md#windowrow)s. A row from the other day opens that day on the timeline. When nothing is left today the Today card says so ("No light windows are left today." or the polar-day or polar-night line).
7. **When to go**, **Sun and moon**, **Hour by hour** and **Good to know**: the spot page's sections at panel density (see below).
8. **Actions:** **Save** / **Saved** (hidden for your own spots) and [AddToTripMenu](COMPONENTS.md#addtotripmenu); then the source line ([ForecastSourceLine](COMPONENTS.md#forecastsourceline)) and a link-style **Show Full Page** that opens the spot page for the chosen day.

The panel scrolls under its header. Windy and Look Around are on the full page only.

Map: [ExploreMapPane](COMPONENTS.md#exploremappane), showing the user's location (system blue dot and button; a simulated dot with `-IterLocation`; nothing without permission) and framing it with Near You in the first fit, with [ExplorePinView](COMPONENTS.md#explorepinview)s, and the [AddSpotBanner](COMPONENTS.md#addspotbanner) docked top in Add Spot mode. Nothing else floats over the map. The selected pin is the only mark of the selection on the map. Map controls: zoom stepper, compass, scale. Map style: standard, flat, no points of interest.

**Map camera.** Iter fits the map to your Near You set (every listed spot when there is none), and an automatic fit never shows more than 40 degrees, so the map opens on a region, not the world. If the set is wider, the densest cluster is fitted and the rest stays reachable by zooming out. Once you pan or zoom, the camera is yours: content changes (a new day, filter, search or radius) do not refit it, and it is saved for Explore and restored on relaunch. Selecting a spot pans to it without zooming out. The faint dotted lines you may see at world zoom are MapKit's own latitude lines (Arctic Circle, tropics, equator), not Iter's.

Toolbar (all primary-action placement), left to right. The window toolbar draws the system toolbar background across the whole window (`unifiedToolbarBackground()`), and the list's paper stops at the toolbar's bottom edge, so the bar is one continuous strip over list and map. Radius, sort and filters are not in the toolbar; they are the menu in the list header:

| Item | Control |
|---|---|
| Search | System search field in the toolbar, one field for places and requests, prompt "Search places or ask Iter" (⌘F focuses it, in the list and in the panel). Return runs the first suggestion: see Search suggestions below. Any change to the text returns the column to the list. |
| Windy | Button, `wind`, label "Windy". Tooltip "Open this map area on windy.com". Opens `windy.com` in the browser at the map's centre, with a zoom taken from the visible latitude span (see [WindyLink](COMPONENTS.md#windylink)). Disabled until the map has reported its region. Before Add Spot. |
| Add Spot | Toggle button, `mappin.and.ellipse`. Tooltip "Add your own spot: click the map to drop a pin (Esc to cancel)". |

**Search status slot** (in the header): while searching, a spinner with "Searching Apple Maps…" and a small Cancel button; on failure a violet `exclamationmark.triangle` line "Couldn't search Apple Maps for “query”." with a Retry button; the suggestions for text that has not been run are in the list, not here.

**Components.** [ExploreLightPanel](COMPONENTS.md#explorelightpanel), [ExploreSuggestions](COMPONENTS.md#exploresuggestions), [ExploreAskSection](COMPONENTS.md#exploreasksection) (running, failure, results), [ExploreRow](COMPONENTS.md#explorerow), [ExplorePinView](COMPONENTS.md#explorepinview), [ExploreClusterView](COMPONENTS.md#exploreclusterview), [SpotImageStrip](COMPONENTS.md#spotimagestrip), [LightTimeline](COMPONENTS.md#lighttimeline), [DayWindowsSection](COMPONENTS.md#daywindowssection), [AddSpotBanner](COMPONENTS.md#addspotbanner), [EventScore](COMPONENTS.md#eventscore-the-event-unit), [EventLane](COMPONENTS.md#eventlane), [WindowSymbol](COMPONENTS.md#windowsymbol), [WeatherStatusBanner](COMPONENTS.md#weatherstatusbanner), [ProvenanceTag](COMPONENTS.md#provenancetag), [LayoutGridOverlay](COMPONENTS.md#layoutgridoverlay), [AddToTripMenu](COMPONENTS.md#addtotripmenu), [SampleDataLabel](COMPONENTS.md#sampledatalabel), [ForecastSourceLines](COMPONENTS.md#forecastsourcelines), [WindyLink](COMPONENTS.md#windylink), [SpotEditorSheet](COMPONENTS.md#spoteditorsheet), ContentUnavailableView, [MapStandIn](COMPONENTS.md#mapstandin)-style stand-in (snapshots).

**Actions.** Click a row to select it: its pin becomes the selected pin at once and, after the double-click interval, the light panel replaces the list. A double-click inside that interval opens the spot page instead. The arrow keys in the list move the selection and open the panel at once; Return opens it. In the panel, Up and Down step to the previous and next place in list order (the pin follows and the map pans only if the pin is out of view), and Esc or **‹ Places** goes back to the list at the same scroll position with the row still selected. Typing in or changing the search, or running a suggestion, returns to the list. **Show Full Page** opens the spot page for the row's day. Click a pin to select it: the list scrolls to its row and the panel opens (or switches to that place if it was already open). Click empty map to clear the selection and return to the list. A row selection recentres the map without zooming out. Rows do not expand in place. Right-click on a row or pin: Open, Save or Unsave (not on your own spots), Add to Trip ▸, divider, Open in Maps, Copy Coordinates. Hovering a pin gives it a chip. In Add Spot mode a click on the map drops a pin and opens the [Spot editor sheet](#spot-editor-sheet); the cursor is a crosshair and pins do not respond. A spot you just added opens in the panel.

**Which window a row shows.** One rule for Explore, Locations and Ask: the next sunrise or sunset event at the spot, in the spot's own local time. A window counts until it ends; after today's sunset the row shows tomorrow's sunrise; it looks up to 4 days ahead; where the sun gives neither (polar) it falls back to the first non-night window not yet over. Blue hours and night are never in a list row; they are in the panel and on the spot page. The start time's tooltip says "Tomorrow" when the window is tomorrow's.

**Search suggestions.** There is one search field. While it has text, the top of the list offers two labelled groups, each a header (`type/moduleTitle`, `text/secondary`) over a button row (`type/bodyEmphasis`, a leading symbol, padding `space/xs` vertical): **Apple Maps** (`magnifyingglass`, "Search Apple Maps for “text”") and **Ask Iter** (`sparkles`, "Ask Iter: text", and under it `type/caption` "Find real places that fit, with a note on why"). They are ranked by `SearchIntent.classify`: text that reads like a request (five or more words, a question mark, a request opener such as "find", "show me" or "where", or a constraint such as "within", "hours of" or "for sunset") puts Ask Iter first; anything else puts Apple Maps first. Return runs the first suggestion, which carries a `return` glyph at its trailing edge (tooltip "Press Return"); a click runs either. An Ask that Apple Intelligence cannot run stays in the list, quiet and disabled, with the reason as its second line ("Ask Iter isn't available: Apple Intelligence is off", "…this Mac can't run Apple Intelligence", "…is still downloading", "Ask Iter isn't available right now"); it is never first, so Return always does something. The suggestions go away once the chosen search or Ask is running or shown for that text, and when the field is cleared.

**Ask.** Describe the place in your own words ("Foggy forest within two hours of Portland for sunrise"); Apple Intelligence finds real places and the Light Index scores them. It is part of the Explore list, not a screen, and it starts from the Ask Iter suggestion (or `-IterAsk`). Ask uses the area the map shows when the request names no place. Rows come only from places the model's tools returned (grounded); the model's own words are the note under each row and are labelled as Apple Intelligence's.

| Ask state | Trigger | What the list shows |
|---|---|---|
| Running | An Ask is in progress | An **Ask Iter** section first, header `sparkles` + "Ask Iter" with the request in quotes under it. One row: a small spinner, the stage ("Understanding your request", "Searching near Portland, Oregon" or "Searching for places", "Checking the drive to <place>" or "Checking the drive", "Choosing the best matches"), then "Step 2 of 4 · 0:14" (`type/caption`, `text/secondary`, digits monospaced), after 10 seconds "Still working. A request can take up to a minute.", and a small **Cancel** button (tooltip "Stop looking"). Cancel keeps the text in the field. |
| Results | The scout returned places | The Ask Iter section, first, with the count at its trailing edge. Each row is the normal [ExploreRow](COMPONENTS.md#explorerow), then, when the scout checked one, `car` + "1 hr, 30 min drive", then the note (`sparkles` and the note in `type/callout`, tooltip "Note from Apple Intelligence"). A caption closes the section: "Places come from Apple Maps and Iter's curated list. Iter checks every place exists; the notes are written by Apple Intelligence." Ask rows ignore the text query and the filters, a place shown here is not repeated below, and the map fits them. |
| Failed | Nothing matched, the request was declined, too long, in an unsupported language, or it failed | The section holds `symbol` + title ("Nothing matched", "Ask Iter can't help with that request", "That request is too long", "Ask Iter doesn't support that language", "Ask Iter couldn't finish"), a sentence of detail, and **Search Apple Maps Instead** (prominent) and **Try Again** (small). |
| Unavailable | Apple Intelligence cannot run | The same layout, with the honest reason and no Try Again: "Apple Intelligence is turned off" (`sparkles`, detail "Turn on Apple Intelligence in System Settings to describe the place you want in your own words.", also **Open System Settings**), "This Mac can't run Apple Intelligence" (`macbook.slash`), "Apple Intelligence is still downloading" (`arrow.down.circle`), "Ask Iter isn't available right now" (`exclamationmark.triangle`). **Search Apple Maps Instead** drops the Ask and searches Apple Maps for the same text. |

Clearing the search field removes the Ask section. Snapshots: `snapshots/explore-search-place-{light,dark}-{1280x820,960x640}.png` (Mesa Arch: Apple Maps first), `snapshots/explore-search-request-…` (a request: Ask Iter first) and `snapshots/explore-search-unavailable-…` (Apple Intelligence off: the Ask row disabled with its reason), each drawn as the list column alone (the toolbar's search field cannot render offscreen); and `snapshots/explore-ask-results-{light,dark}-{1280x820,960x640}.png` and `snapshots/explore-ask-unavailable-{light,dark}-{1280x820,960x640}.png`.

**Weather for any location.** A spot's score comes from a forecast fetched for its own coordinate (curated, your own, Apple Maps, Ask results, trip stops), shared per spot per hour and counted against the daily cap. A spot you add is fetched as soon as you save it.

**States.**

| State | Trigger | What changes | Snapshots |
|---|---|---|---|
| Default | Open Explore, sample weather | 45 rows sorted by best light (no location in the snapshots, so one list): event unit (symbol, score and start time in one capsule), in one measured lane. Map: dots tinted by band, up to six chip pins (the compact event unit with its time, one band fill), plain dots for spots with no score. The list column shows the list. | `snapshots/explore-default-{light,dark}-{1280x820,960x640}.png` |
| Selected, list | A row selected and the panel closed (after Back) | The row is highlighted and its pin is the selected pin: the same capsule as a chip pin with the start time added, scaled up 1.15 with a larger shadow and a pointer at the bottom tip; no outline. The column shows the list. | `snapshots/explore-selected-{light,dark}-{1280x820,960x640}.png`, `snapshots/explore-panel-list-{light,dark}-1280x820.png` |
| Light panel | Click a row or pin and wait out the double-click interval, or arrow keys, Return, or `-IterSelectRow` | The panel described above replaces the list, at the column's ideal width. The images are generated stand-ins (no network in snapshots). | `snapshots/explore-panel-{light,dark}-1280x820.png` |
| Light panel, narrowest column | The list column at its 340 pt minimum | The same panel, to check the timeline, the legend and the place header at the least room. The "Drag to read any time" hint is dropped below 350 pt. | `snapshots/explore-panel-340-{light,dark}-1280x820.png` |
| Light panel, scrolled | `-IterPanelScrolled YES` | The panel opened scrolled to its lower half: When to go at the top, then sun and moon, hour by hour, Good to know and the actions. | `snapshots/explore-panel-scrolled-{light,dark}-1280x820.png` |
| Weather not enabled | Apple Weather chosen without WeatherKit | The weather banner under the header: "Apple Weather isn't enabled for this build. Choose another source in Settings." with **Settings…**. Rows keep their symbol (alone, where the chip would be) and start time; pins are plain dots. The source footer is empty. The panel is open for Mesa Arch. | `snapshots/explore-noforecast-{light,dark}-{1280x820,960x640}.png` |
| Weather offline | The weather service fails (the fixture) | The banner reads "Weather isn't answering." for a service failure, or "Weather is offline. Scores are from the last update at 06:29." for a connectivity error (`URLError`) once something has loaded. Rows keep their last cached score, or the symbol alone; the selected row's panel is open. | `snapshots/explore-weather-offline-{light,dark}-{1280x820,960x640}.png` |
| Near You (location known) | A location inside the radius | Sections "Near You · Within 300 mi", "Popular", "More Places" (collapsed), rows show distance after the locality, sort is Distance. The snapshots use San Francisco and Moab; `near-more` is scrolled to the Popular and More Places headers (More Places collapsed, with its count); `near-selected` has Tunnel View selected with its panel open. | `snapshots/explore-near-sf-…`, `explore-near-moab-…`, `explore-near-more-…`, `explore-near-selected-…`, each `{light,dark}-{1280x820,960x640}.png` |
| Location denied | Location Services off for Iter | One "Spots" list under the banner with **Open Location Settings**. (Not asked yet shows **Use My Location**; finding shows a spinner.) | `snapshots/explore-location-denied-{light,dark}-{1280x820,960x640}.png` |
| Panel images | Open a place | The panel's image strip with a Look Around or satellite image and its label; a placeholder with the category symbol while loading or when there are none. Drawn in the panel snapshots above with generated images. | in `snapshots/explore-panel-*` |
| Filtered empty | Filters exclude everything (here Source = Your Spots, none exist) | Header reads "0 places". List area shows "No Matching Spots" (`line.3.horizontal.decrease.circle`), "Nothing fits the current search and filters." and a **Clear Filters** button. Map is empty. | `snapshots/explore-filtered-empty-{light,dark}-{1280x820,960x640}.png` |
| Add Spot mode | Add Spot toggle or ⇧⌘N | A capsule banner at the top of the map: accent `mappin.and.ellipse`, "Click the map to drop a pin for your spot", **Cancel** (Esc). 1 pt accent outline. An open panel stays; Esc belongs to the mode (the panel ignores it) until the mode ends. | `snapshots/explore-addspot-mode-{light,dark}-{1280x820,960x640}.png` |
| Apple Maps search results | Return in the search field | A second list section "Apple Maps" with its count; rows carry no provenance tag (only your own spots are tagged "Added by you"). | not rendered (search is stubbed in tests) |
| Search found nothing | A real search returns zero | "No places found" (`mappin.slash`), "Nothing on Apple Maps matches “query” around the map.", plus Clear Filters if narrowed. | not rendered |
| Search failed | Network or service failure | Violet inline error with Retry (see above). | not rendered |
| Windy source | Settings: Use = Windy, forecasts answered by Windy's GFS model | Footer reads "Windy · GFS", then "Contains data from the Windy database" with a **Windy.com** link, then "Light Index modified from forecast data". The panel carries its own line "Windy · GFS · updated 09:00". | `snapshots/explore-windy-source-{light,dark}-{1280x820,960x640}.png` |
| OpenWeather as fallback | Use = OpenWeather, If it fails, try = Apple Weather; Apple Weather is not enabled | Footer reads "OpenWeather (Apple Weather unavailable)", then the **Weather data © OpenWeather** link, then the Light Index line. The panel's line reads "OpenWeather (Apple Weather unavailable) · updated 09:00". The fallback is never hidden behind the chosen source. | `snapshots/explore-openweather-fallback-{light,dark}-{1280x820,960x640}.png` |
| Polar, no event | The spot has no sunrise or sunset ahead | The row's light column is blank and the panel has no next-event summary. A spot with only blue hours and night falls back to the first non-night window not yet over. | not rendered |

Explore snapshots show "Sample data" once in the sample states, in the header (the attribution footer is gone; see Settings ▸ Weather). Apple Maps search results (a section "Apple Maps") are scored the same way, each from its own coordinate; launch with `-IterSearch <text>` to see one.

---

## Spot page

**Purpose.** Answer "when should I be here?" in the first screenful, then show the evidence: windows, timeline, sun and moon, weather, facts.

**Placement.** Pushed onto the current section's navigation stack (Explore, Locations, trips). Window title is the spot's name. Back is the system back button.

**Layout.** A single scrolling column on `background/window`, under the [WeatherStatusBanner](COMPONENTS.md#weatherstatusbanner) when weather is missing. Content is at most 940 pt wide (`layout/listMax` + `layout/inspectorMax` = 520 + 420), including side padding, and centred; side padding `space/xl`; modules spaced `space/xl` (24, whitespace only: no rules between them). Every module is a [ModuleCard](COMPONENTS.md#modulecard): `background/module` fill, `radius/card` (12), 16 pt padding, no stroke, its title inside at the top-left in `type/moduleTitle` (`text/secondary`, with a leading symbol). Each module has one strong fact. The charts share one left gutter (40 pt, five grid units) and a right inset of 16, so their x-axes line up.

**Sections, top to bottom.**

1. **Header** ([SpotHeader](COMPONENTS.md#spotheader)), plain on the window ground (no card). Spot name in `type/title/spot` (New York serif). One metadata line in `type/secondary`, `text/secondary`: locality, provenance ([ProvenanceTag](COMPONENTS.md#provenancetag), plain text) and the category with its symbol, **separated by middle dots** ("Moab, UT · Curated · Landscape"). Then the header's one strong fact: the spot's next event as a large event unit (44 pt chip with the window's symbol and the score, then its start time) with "Today" or "Tomorrow" in `type/secondary` beside it. Then an action row, bordered system buttons spaced `space/sm`: **Add to Trip** (prominent menu, `plus.circle`), **Save** / **Saved** (`bookmark` / `bookmark.fill`, ⌘D, hidden for your own spots), **Open in Maps** (`map`), **Share** (`square.and.arrow.up`, shares an Apple Maps link plus the coordinates). For your own spots, after a divider: **Edit** (`pencil`, ⌘E) and **Delete** (`trash`, destructive). When the row does not fit, the buttons collapse to icons only.
2. **When to go** (`calendar`; [WhenToGoSection](COMPONENTS.md#whentogosection)). There is no intent picker; the page follows the spot's own best light. The strong fact is the best window as a large event unit (symbol, score and time range in one capsule). The text column beside it, in this order: "Best sunrise in the next 8 days" (`type/secondary`), "Mon, Oct 12, 2026" (`type/headline`), the top reason (`type/body`), "Updated 09:00" (`type/secondary`). Then, in the same card, the outlook ([OutlookStrip](COMPONENTS.md#outlookstrip)): on the full page a row of day cells (weekday, day number, a compact event unit with its start time, a range), the best day marked with a **Best** capsule and fading with confidence; in the Explore panel a vertical day list on the lane grid.
3. **Light windows** (`sun.horizon`; [DayWindowsSection](COMPONENTS.md#daywindowssection)). The card's accessory is the selected day ("Mon, Oct 12, 2026"; "Today · Tue, Oct 6, 2026" style when relative) and a small **Today** button when the day is not today. Inside, up to five [WindowRow](COMPONENTS.md#windowrow)s in time order on the shared [lanes](COMPONENTS.md#windowlanes): disclosure chevron (16) | window name (`type/headline`) | event unit (symbol, score and time range in one capsule) | band word and confidence bars (`type/secondary`). Rows are at least 32 pt, 8 pt gaps between lanes, text on one first baseline; hairline dividers inset to the label lane. Morning blue hour, Sunrise, Sunset, Evening blue hour and Night each have their symbol inside the unit. On today the card lists only the windows that have not ended, then tomorrow's under a "Tomorrow" sub-label (`type/moduleTitle`); a tomorrow row opens that day when clicked. Selecting a row fills it with `selection/fill`.
4. **Light through the day** (`chart.line.uptrend.xyaxis`; [LightTimeline](COMPONENTS.md#lighttimeline)). The card's accessory is a segmented zoom picker: Full day, Sunrise ±2 h, Sunset ±2 h. Inside: a readout line (`type/headline`), the canvas, and a legend (`type/secondary`).
5. **Sun and moon** (`moon.stars`; [SkyArc](COMPONENTS.md#skyarc)). The canvas, a legend, the strong fact as one sentence about where the sun is (`type/headline`: "At 07:43 the sun is 3° above the horizon, toward 102° ESE."), one qualifying sentence (`type/body`, `text/secondary`), and a moon line.
6. **Hour by hour** (`cloud.sun`; [HourlyStrip](COMPONENTS.md#hourlystrip)). The card's accessory is the source line with its time ("Windy · GFS · updated 09:00"; "OpenWeather (Apple Weather unavailable) · updated 09:00" when a fallback answered). Inside the strip, then "Wind in mph" ("Rain in mm/h · Wind in mph" when rain is an amount). Only when a forecast exists.
7. **Windy** (`wind`; [WindySection](COMPONENTS.md#windysection)). A card with a sentence and a bordered **Open in Windy** button. Full page only; always shown, with or without a forecast.
8. **Good to know** (`info.circle`; [SpotFactsRow](COMPONENTS.md#spotfactsrow)). A card with a grid of facts, then the blurb and notes.
9. **Look Around** (`binoculars`; [LookAroundSection](COMPONENTS.md#lookaroundsection)). Only live, only when Apple has imagery. Full page only.

The Explore light panel ([ExploreLightPanel](COMPONENTS.md#explorelightpanel)) reuses these sections at **panel density** (`.panel`, 340 to 520 pt wide) in this order: Light through the day, then **Today** and **Coming up** (the Light windows card split in two: the windows still ahead today, then tomorrow's), When to go, Sun and moon, Hour by hour, Good to know. At panel density module titles sit on the panel's 16 pt inset with no card fill and the content runs the column's inset width; only the Today and Coming up lists keep a filled card. The light timeline has no label gutter, a taller sky band and plot, and a time pill on the axis. Each window row is named in the label lane (`type/headline`, one line, short names such as "Blue PM" as on the timeline) on the same lanes as the page (event unit with its time range, band and confidence), expandable to its reasons.

**Shared selection.** One selected day, one selected window and one marker time drive every section: choosing a day in the outlook updates the windows, timeline, arc and hourly strip. Selecting a window row (or tapping a window on the timeline) highlights it everywhere with `selection/fill` (a 2 pt accent outline on the timeline). Hovering or dragging on the timeline moves the marker for the readout, the arc markers and the hourly strip's highlighted hour.

**Components.** [SpotHeader](COMPONENTS.md#spotheader), [ModuleCard](COMPONENTS.md#modulecard), [EventScore](COMPONENTS.md#eventscore-the-event-unit) (large in the header and the lead, regular in window rows, compact in the outlook), [WindowLanes](COMPONENTS.md#windowlanes), [BandConfidence](COMPONENTS.md#bandconfidence), [WindowSymbol](COMPONENTS.md#windowsymbol), [WeatherStatusBanner](COMPONENTS.md#weatherstatusbanner), [ConfidenceMark](COMPONENTS.md#confidencemark), [SunTimesLine](COMPONENTS.md#suntimesline), [OutlookStrip](COMPONENTS.md#outlookstrip), [WindowRow](COMPONENTS.md#windowrow), [ReasonsGrid](COMPONENTS.md#reasonsgrid), [SignedBar](COMPONENTS.md#signedbar), [ExplainBlock](COMPONENTS.md#explainblock), [LightTimeline](COMPONENTS.md#lighttimeline), [SkyArc](COMPONENTS.md#skyarc), [HourlyStrip](COMPONENTS.md#hourlystrip), [WindySection](COMPONENTS.md#windysection), [WindyLink](COMPONENTS.md#windylink), [SpotFactsRow](COMPONENTS.md#spotfactsrow), [LookAroundSection](COMPONENTS.md#lookaroundsection), [ForecastSourceLine and WeatherAttributionView](COMPONENTS.md#weatherattributionview), [SampleDataLabel](COMPONENTS.md#sampledatalabel), [AddToTripMenu](COMPONENTS.md#addtotripmenu), [SpotEditorSheet](COMPONENTS.md#spoteditorsheet).

**Actions.**

- Click an outlook day to show that day. **Show this day** (small button in the When to go card) jumps to the best day and window when you are looking at another. **Today** returns to today.
- Click a window row to expand its reasons (chevron rotates 90 degrees). Selecting a row selects the window across the page. **Explain** (when Apple Intelligence is available) writes two or three plain sentences from the listed factors only.
- Timeline: hover or drag to scrub; click a window to select it; VoiceOver adjustable action steps through windows. Zoom segmented control (only offered when more than one focus exists).
- There is no Retry button on the page; **Light ▸ Refresh Forecasts** (⌘R) re-requests a failed forecast.
- **Open in Windy** (Windy section) opens windy.com in the browser at the spot, zoom 9. Nothing is embedded: Windy's terms do not allow its map inside other weather apps.
- Share, Open in Maps, Save, Add to Trip as above. Delete asks for confirmation only when trip stops use the spot: "Delete “name”?" with "It is also removed from N trip stops. You can undo this with Edit > Undo."

**States.**

| State | Trigger | What changes | Snapshots |
|---|---|---|---|
| Sample (scored) | Mesa Arch, sample data on | Lead: a large event unit (sunrise symbol and "87" in an amber capsule at 85% opacity, because confidence is Low), then the text column: "Best sunrise in the next N days" (N is the days the forecast covers, at most 10), "Mon, Oct 12, 2026 · 07:25–08:01", the top factor's sentence ("Mid and high cloud catches colour."), "Updated 09:00". Outlook: the days the forecast covers, starting tomorrow when today's window has passed; later days fade (80% medium, 60% low confidence; days scored by persistence are low) and show ranges ("65–81"); Mon 12 has the "Best" capsule (`accent/emphasis`) and the selected fill. Windows: the rows still ahead plus tomorrow's, Sunrise row selected, each with its chip, band word and confidence bars. Timeline: full-day sky strip, cloud layers, rain bars, window brackets labelled "Sunrise 87", "Blue AM 85", ... Sun and moon: arc with the sun's coral marker and the classic-view dashed line "Classic view faces 100° E". Hourly: weather symbols for 24 hours with "Sample data" under the strip. | `snapshots/spot-sample-{light,dark}-{1280x820,960x640,1280x2600}.png` |
| Window expanded | A window row is clicked | The row expands in place: "Why this score" (`type/moduleTitle`), indented to the label lane, a grid of factors (name, value, signed bar with +21, a sentence), the confidence line "Low confidence · Likely 72–100 · Sample data · updated 09:00" (source and time, as in the hourly strip), an explanatory footnote with the forecast lead time, then one footnote line per score note (see Windy and OpenWeather states below), and an **Explain** button (`apple.intelligence` icon). The row's background is the `selection/fill` of a selected row. | `snapshots/spot-window-expanded-{light,dark}-{1280x820,960x640,1280x2600}.png` |
| Weather offline (not enabled) | Weather not enabled | The weather banner at the top: "Apple Weather isn't enabled for this build. Choose another source in Settings." with **Settings…**. Lead: only "Next sunrise Wed 07:20" and "Next sunset 18:54" with icons. Outlook cells have an empty chip slot and no caption. Window rows show the window's name, its symbol alone where the chip would be, and the exact time range, and do not expand. Timeline shows the sky strip only, with nothing under it. Sun and moon arc is complete. No hourly section. | `snapshots/spot-weather-offline-{light,dark}-{1280x820,960x640,1280x2600}.png` |
| Failed | The weather service could not be reached | Same as above, with the banner reading "Weather isn't answering." There is no Retry button. | `snapshots/spot-failed-{light,dark}-{1280x820,960x640,1280x2600}.png` |
| Polar | Tromsø harbour on 10 Dec 2026 (the sun does not rise) | Header: "Tromsø, Norway", tag "Apple Maps", category Coast, **Save** (not saved). Night is the page's intent (the spot's best light is Night). Windows: only Morning blue hour, Evening blue hour (both `moon.haze.fill` in their chips, told apart by the time and the order) and Night (no sunrise or sunset). Sky arc shows a flat sun path (the sun never leaves the horizon), no classic-view line. Facts: "Walk-in unknown", "Facing unknown", "Best at night sky", and a time-zone note ("Central European Time · 9 h ahead of you"). If no window exists at all, the polar sentence appears with `moon.stars` or `sun.max`: "The sun doesn't rise here on this day. The light is the blue hour either side of noon." / "The sun doesn't set here on this day. No blue hour, but a long golden window while the sun is low." | `snapshots/spot-polar-{light,dark}-{1280x820,960x640,1280x2600}.png` |
| User spot | A spot you added (Cottonwood bend) | Provenance tag "Added by you"; actions: Add to Trip, Open in Maps, Share, divider, **Edit**, **Delete** (no Save). Facts include your notes. The page's intent is the spot's best light (Sunset). | `snapshots/spot-user-{light,dark}-{1280x820,960x640,1280x2600}.png` |
| Loading forecast | Forecast request in flight | Lead: spinner "Checking the forecast…" plus the sun times line. Outlook and window rows show a spinner beside the symbol. Timeline note "Checking the forecast…". | not rendered |
| Explanation states | **Explain** pressed | Loading: spinner, "Writing an explanation…", Cancel. Done: the text (selectable), then `apple.intelligence` "Written by Apple Intelligence from the factors listed above." and **Explain again**. Failed: a sentence ("Apple Intelligence isn't available right now.", "The explanation didn't match the numbers, so it was discarded. Try again.", ...) and **Explain**. Absent when Apple Intelligence is unavailable. | not rendered |
| Windy (GFS) | Settings: Use = Windy, spot not covered by a regional model | Hour by hour header: "Windy · GFS · updated 09:00". Under the strip: "Contains data from the Windy database", **Windy.com** link, "Light Index modified from forecast data", and "Rain in mm/h · Wind in mph" at the right (Windy gives rain as an amount). The Windy section follows with **Open in Windy**. The expanded Sunrise row's confidence line reads "Low confidence · Likely 70–100 · Windy · GFS · updated 09:00". Expanded windows name the cloud layers in their reasons ("High cloud 29%, mid 17%, little low cloud: colour likely.", "Low cloud 6%: the horizon should be open.") and carry the footnotes "Windy's model steps every three hours; Iter fills the hours between." and "Rain judged from the forecast amount (no probability from Windy)." | `snapshots/spot-windy-gfs-{light,dark}-{1280x820,960x640,1280x2600}.png` |
| OpenWeather as fallback | Use = OpenWeather, fallback Apple Weather, Apple Weather not enabled | Hour by hour header: "OpenWeather (Apple Weather unavailable) · updated 09:00". OpenWeather has total cloud only, so the cloud reasons read "Cloud cover suits this window." / "Cloud layers unavailable; judged on total cover." and the expanded window carries "OpenWeather gives total cloud only, not cloud by height: confidence is one step lower." Beyond 48 hours: "Scored from a daily summary: beyond OpenWeather's 48 hours." and "No visibility from this source." | `snapshots/spot-openweather-fallback-{light,dark}-{1280x820,960x640,1280x2600}.png` |
| Provider problem | The chosen source has no key, rejected key, daily cap, testing key or failed | The banner names it: "Add a weather key in Settings to see light scores." / "OpenWeather rejected the weather key. Check it in Settings." / "Iter's daily limit for OpenWeather is reached." / "Windy's testing key gives shuffled data, so Iter won't score from it." / "OpenWeather isn't answering." Full list under [WeatherStatusBanner](COMPONENTS.md#weatherstatusbanner). The page itself looks as in Weather offline. | not rendered |
| Beyond the forecast | A window falls past the provider's last forecast day (for example a trip stop planned far ahead, opened on its spot page) | Scored by persistence: the last forecast day's weather carried forward by whole days, confidence Low, and the footnote "Beyond the forecast: the last forecast day's weather carried forward." in the expanded window. The outlook strip itself stops at the horizon. | not rendered |
| Zoomed timeline | Zoom set to Sunrise ±2 h or Sunset ±2 h | Timeline and hourly strip share the narrower time domain (the sky arc does not zoom); two label tiers and hourly ticks. | not rendered |

---

## Locations

**Purpose.** Everything you kept: curated and Apple Maps spots you saved, and every spot you added, each with its next sunrise or sunset, beside its own map. Folders sort them. Replaces Saved.

**Placement.** Sidebar > All Locations, or a location folder. Window title "All Locations" or the folder's name. A folder shows its own spots and its subfolders' spots, and only those.

**Regions.** A split like Explore's (`ResizableSplit`): list column (min 300, ideal 360, max 520 pt, `layout/listMin`, `listIdeal`, `listMax`) beside a map. Toolbar: search field "Search locations" and a **Sort and Filter** menu (`line.3.horizontal.decrease.circle`) with two inline pickers: **Sort By** (Name, Light Today, Kind) and **Show** (All Spots, Added by You, Curated, Apple Maps). Bottom bar of the list (a system bar material with a divider above): "3 spots" on the left and the [ForecastSourceLines](COMPONENTS.md#forecastsourcelines) on the right. The [WeatherStatusBanner](COMPONENTS.md#weatherstatusbanner) sits above the list when weather is missing.

List rows are [SavedRow](COMPONENTS.md#savedrow)s (the type keeps its old name), each at least 48 pt, on the same lanes as an Explore row: the category symbol in the 16 pt disclosure lane, then the label lane (name in `type/headline`, over one `type/secondary` line: the locality, or the category, then a middle dot and the plain-text [ProvenanceTag](COMPONENTS.md#provenancetag), "Lone Pine, CA · Added by you"), and on the right the regular event unit (the window's symbol, the score and the start time in one capsule), by the same rule as Explore (the spot's next sunrise or sunset in its own time; "Tomorrow" is the tooltip and VoiceOver label, not a word in the row). Multi-selection is on, and rows can be dragged onto a sidebar location folder. The layout grid overlay can be switched on over the list.

Map: [LocationsMap](COMPONENTS.md#locationsmap), one pin per listed spot, framed to fit them. A pin is the same event unit as Explore's (the `pin` variant: symbol, score and start time on the band fill, a pointer below), showing the spot's next sunrise or sunset, the same window as its row (`AppModel.savedEvent(for:)`). A spot with no window is a small dot; selected pins are scaled up with a larger shadow and drawn last, and a selected spot with no window shows its name in a capsule.

**Components.** [SavedRow](COMPONENTS.md#savedrow), [LocationsMap](COMPONENTS.md#locationsmap), [EventScore](COMPONENTS.md#eventscore-the-event-unit), [EventLane](COMPONENTS.md#eventlane), [LayoutGridOverlay](COMPONENTS.md#layoutgridoverlay), [WeatherStatusBanner](COMPONENTS.md#weatherstatusbanner), [ForecastSourceLines](COMPONENTS.md#forecastsourcelines), [ProvenanceTag](COMPONENTS.md#provenancetag), [AddToTripMenu](COMPONENTS.md#addtotripmenu), ContentUnavailableView, [MapStandIn](COMPONENTS.md#mapstandin) (snapshots).

**Actions.** Double-click or Return opens the spot page. Selecting a marker selects its row, and the other way round; clicking empty map clears the selection. Context menu: for one spot Open and Add to Trip ▸; then for any selection Move to Folder ▸ (No Folder, each folder, each subfolder as "Folder › Subfolder"; the current one is checked), New Folder with Selection, and inside a folder Remove from Folder; then for your own spot Edit… and Delete, for a saved one Unsave (several: Unsave). Drag rows onto a location folder in the sidebar to file them, or onto All Locations to unfile them. The Delete key removes your own spot (asks first if trips use it) or unsaves a saved one. Filing and unfiling are undoable.

**States.**

| State | Trigger | What changes | Snapshots |
|---|---|---|---|
| All | Saved spots exist, sample weather | Rows for every saved and own spot, each with its next window's event unit (symbol, score and start time in one capsule); the map beside them. Footer "5 spots" plus Sample data label. | `snapshots/locations-all-{light,dark}-{1280x820,960x640}.png` |
| Map, one spot selected | Mesa Arch selected in All Locations | Its pin is scaled up with a shadow and drawn on top of the others; its row is highlighted. | `snapshots/locations-map-selected-{light,dark}-{1280x820,960x640}.png` |
| Folder | A location folder selected | Title is the folder name; only its spots, and the map frames them. | `snapshots/locations-folder-{light,dark}-{1280x820,960x640}.png` |
| Empty | Nothing saved | "Nothing saved yet" (`mappin.and.ellipse`), "Save a spot from Explore and it shows up here with its next sunrise or sunset. Spots you add yourself live here too.", prominent **Browse Explore**, and **Add Your Own Spot** (goes to Explore in Add Spot mode). | `snapshots/locations-empty-{light,dark}-{1280x820,960x640}.png` |
| Empty folder | A folder with no spots | "This folder is empty" (`folder`), "Drag locations here from All Locations, or choose Move to Folder from a location's menu.", **Show All Locations**. | `snapshots/locations-empty-folder-{light,dark}-{1280x820,960x640}.png` |
| Weather not enabled | Weather not enabled | The weather banner at the top of the list. Every row keeps its symbol (alone, where the event unit's head would be) and start time. No Sample data label. | `snapshots/locations-noforecast-{light,dark}-{1280x820,960x640}.png` |
| Filter or search empty | A filter matches nothing / a query matches nothing | "No spots here" ("No saved spots match this filter.") or the system search-empty view. | not rendered |
| Delete confirmation | Deleting your own spot that trip stops use | Dialog "Delete “name”?" with "It is also removed from N trip stops. You can undo this with Edit > Undo." and **Delete Spot** (singular: "1 trip stop"). | not rendered |

---

## Spot editor sheet

**Purpose.** Create a spot from a dropped pin, or edit one of your own. Anything you type is yours; a lookup never overwrites it.

**Placement.** Sheet, sized to its content, with a 20 pt margin (`space/sheet`) and system controls only (see [Controls](COMPONENTS.md#controls)); `.tint(nil)` at the root keeps the coral tint off the neutral buttons. The 960x640 snapshots may crop it.

**Regions, top to bottom.**

1. Title "New Spot" or "Edit Spot" (`type/title/section`), inset 20 pt (`space/sheet`).
2. Grouped form:
   - **Pin map** (168 pt high, `chart/arcHeight`; 12 pt corners with a hairline). The pin's tip is the map centre; drag the map to move it. Footer: "Drag the map to move the pin." and the coordinates ("36.5786, -118.2920", monospaced digits); a **Reset Pin** link appears once the pin has moved.
   - Fields: **Name** (placeholder "Name this spot"; while looking up, a spinner and "Looking up this place…"), **Place** ("Park, town or region"), **Category** (menu picker with symbols, ten categories), **Time zone** (read-only, e.g. "Mountain Time"). The zone starts as an estimate from the pin, not this Mac's: the nearest curated spot's zone within 150 km, else a whole-hour offset from the longitude (`TimeZoneEstimate`); the reverse lookup replaces it with the real zone when it answers.
   - **Best light (choose any)**: a three-column grid of checkboxes: Sunrise, Sunset, Blue hour, Night sky, Midday, Overcast. Footer "With none chosen, light is shown for sunset."
   - **Walk-in (minutes)** (placeholder "Optional") and **Notes** (placeholder "Access, gear, crowds, permits", 3 to 6 lines).
3. Divider, then buttons trailing: system **Cancel** (Esc) and **Add Spot** (create) or **Save** (edit), the default button (Return).

**Validation.** Name is required ("Name this spot to save it."); walk-in must be whole minutes within the limit ("Enter whole minutes from 0 to N, or leave it empty if you don't know."). Each message is raspberry (`status/danger`) with `exclamationmark.triangle.fill`. Errors show after the field is touched or after a failed save.

**Components.** System grouped Form, MapKit map (stand-in in snapshots), TextField, Picker, Toggle (checkbox style), [WarningLine](COMPONENTS.md#warning-lines) (time zone fallback), [MapStandIn](COMPONENTS.md#mapstandin).

**Actions.** Save creates or updates the spot through the store (undoable) and closes. Create mode: the new spot is selected in Explore and its forecast is fetched at once, so its score appears within seconds.

**States.**

| State | Trigger | What changes | Snapshots |
|---|---|---|---|
| Create | A click in Add Spot mode | Reverse lookup filled the name ("Dropped pin" in the stub), place ("Moab, UT") and time zone. No best light ticked. Button "Add Spot". | `snapshots/editor-create-{light,dark}-{1280x820,960x640}.png` |
| Edit | Edit on your own spot | Fields hold the spot's values (Sunrise and Night sky ticked, walk-in 12, notes). Button "Save". No lookup on open. | `snapshots/editor-edit-{light,dark}-{1280x820,960x640}.png` |
| Create, lookup failed | The reverse lookup fails (offline) | Name and Place are empty with placeholders; the time zone row shows the estimated zone with a violet line "Couldn't look up this place's time zone, so it's estimated from the map position." | `snapshots/editor-create-lookup-failed-{light,dark}-{1280x820,960x640}.png` |
| Looking up | Lookup in flight (300 ms debounce) | Spinner and "Looking up this place…" in the name field; time zone says "Estimated from the map position until the lookup finishes." | not rendered |
| Validation errors | Save with a blank name or bad walk-in | Raspberry problem lines under the fields. | not rendered |

---

## Settings

**Purpose.** Units, set-up time; forecast and Apple Intelligence status; about.

**Placement.** The Settings window (⌘,), a separate window, 552 pt wide (`layout/listMax` + `space/xxl`), tab view with four tabs along the top: **General** (`gearshape`), **Weather** (`cloud.sun`), **Apple Intelligence** (`sparkles`), **About** (`info.circle`). Each pane is a grouped form of system controls only (see [Controls](COMPONENTS.md#controls)); `Stepper` labels carry their value.

**General.** Section 1: **Temperature** (System, Celsius (°C), Fahrenheit (°F)). Section 2: a stepper whose label carries its value, "Set-up time before a window: 20 min" (0 to 90 in steps of 5), with footer "How long before a light window starts that a new stop wants you set up. Each stop can change it."

**Weather.** A grouped form of one source section, one section per provider, then optional setup steps and the data sources. Top to bottom:

1. Section **Forecast source**: a **Use** pop-up (Apple Weather, OpenWeather, Windy) and an **If it fails, try** pop-up (None, divider, the other two). Picking the fallback's source as the primary clears the fallback. When sample data is on: a **Sample Data** row with the inline [SampleDataLabel](COMPONENTS.md#sampledatalabel) and the caption "Scores use made-up weather, not a real forecast. Turn this off in the Debug menu." Footer: "If the first source can't answer, Iter asks the second. A fallback is always named next to the forecast."
2. One section per provider (Apple Weather, OpenWeather, Windy), header the provider's name, each a [ProviderStatusRow](COMPONENTS.md#providerstatusrow) group:
   - a description (`type/caption`, `text/secondary`): Apple Weather "Hourly for 10 days, with cloud cover and visibility. Needs a paid Apple developer team to turn on."; OpenWeather "Hourly for 48 hours, then daily. Total cloud only. 1,000 free calls a day."; Windy "Cloud by height (low, mid, high) from the GFS, ICON and NAM models. Testing keys return shuffled data."
   - the status line (strings below) with a button when one applies.
   - OpenWeather and Windy: the **API key** row. No key saved: a secure field, prompt "Paste your key", button **Save** (disabled while empty). Key in the Keychain: prompt "Saved in Keychain. Paste to replace", **Save**, and a destructive **Remove**. Key from outside the Keychain: no field, a read-only row "From environment (ITER_OPENWEATHER_KEY)" (or `ITER_WINDY_KEY`) or "From launch argument". A Keychain failure shows a raspberry line "Couldn't save the key to your Keychain." or "Couldn't remove the key from your Keychain." The key is never shown.
   - Windy only: **Key type** pop-up (Testing, Professional) and **Model** pop-up (Best for the spot, GFS everywhere).
   - OpenWeather and Windy: a **Calls today** row with the count ("12", monospaced digits), and a stepper whose label carries its value, "Daily cap: 800 calls", 0 to 10,000 in steps of 50. The cap defaults to 800 (OpenWeather) and 400 (Windy).
   - OpenWeather and Windy: a **Get a key** link (home.openweathermap.org/api_keys, api.windy.com/keys).
3. Only when Apple Weather is "Not enabled for this build": section **To turn on Apple Weather** with three numbered steps (selectable): "Sign in to Xcode with an Apple Developer Program account."; "In Certificates, Identifiers & Profiles, enable WeatherKit for the App ID com.dwjames.iter, on both the Capabilities and App Services tabs."; "Build with `scripts/run.sh --weatherkit`." Footer: "Until a forecast source works, sun and moon times are exact and light scores stay empty."
4. Section **Data Sources and Attribution**, always shown, below the provider sections (moved here from the content screens, owner's instruction 2026-10-06; to be revisited before release): `WeatherDataSources` ([WeatherAttributionView](COMPONENTS.md#weatherattributionview) strings, all providers): the Apple Weather mark with **Legal attribution** (once attribution info has loaded), "Weather data © OpenWeather" linking openweathermap.org, "Contains data from the Windy database" with a **Windy.com** link (Windy's logo is still not shipped, a known gap), the inline Sample data label when sample is on, then "Light Index modified from forecast data".

Status line strings ([ProviderStatusRow](COMPONENTS.md#providerstatusrow)): "Working · last update 19:40" (button **Check**); "Needs an API key"; "Not enabled for this build" (**Check Again**); "Testing key: Windy's data is shuffled, so Iter won't score from it" (**Check**); "Key rejected" (**Check Again**); "Daily cap reached (800 of 800)" (**Check Again**); "Couldn't reach OpenWeather" (**Check Again**, and the technical detail under it, selectable); "Not checked yet" (**Check**); "Checking…" with a spinner. Opening the tab checks Apple Weather always, and OpenWeather or Windy only when it is the primary or fallback and has a key.

**Apple Intelligence.** Section "Ask Iter": a status row. Ready: `checkmark.circle` "Apple Intelligence is ready" and "Ask Iter, in Explore's search, understands your request with the model on this Mac, then looks up real places in Apple Maps and Iter's curated list." Otherwise the same notice as Ask's unavailable states (title with icon, detail) and, when it is turned off, **Open System Settings**.

**About.** Centred: logo (64 pt high, the `Logo` image set), "Iter" (`type/title/section`), "Version 0.1 (1)" (`type/caption`), the tagline "Be in the right place when the light is right." (`type/body`), and the data-sources paragraph, then the same **Data Sources and Attribution** block (heading `type/caption`, `text/secondary`; `WeatherDataSources`, left-aligned, max 360 pt) (paragraph: `type/caption`, `text/secondary`, centred, max 360 pt): "Sun and moon times are calculated on this Mac. Weather is from the source you choose in Settings ▸ Weather: Apple Weather, OpenWeather or Windy (contains data from the Windy database). Places and drive times are from Apple Maps, alongside Iter's curated spots."

**States.**

| State | Trigger | What changes | Snapshots |
|---|---|---|---|
| General | Open Settings | As above, defaults shown. | `snapshots/settings-general-{light,dark}-{1280x820,960x640}.png` |
| Weather: needs a key | Use = OpenWeather, If it fails, try = Apple Weather; no keys saved | Apple Weather: violet triangle "Not enabled for this build" with **Check Again**. OpenWeather: violet `key` "Needs an API key", empty field "Paste your key" with disabled **Save**, "Calls today 0" and "Daily cap: 800 calls", **Get a key**. Windy: the same, partly below the fold. | `snapshots/settings-weather-needs-key-{light,dark}-{1280x820,960x640}.png` |
| Weather: OpenWeather working | Use = OpenWeather, fallback Apple Weather (not enabled), OpenWeather key saved | OpenWeather status `checkmark.circle.fill` "Working · last update 09:00" with **Check**; key row "Saved in Keychain. Paste to replace" with disabled **Save** and **Remove**; "Calls today 0" and "Daily cap: 800 calls". Windy still "Needs an API key". | `snapshots/settings-weather-openweather-working-{light,dark}-{1280x820,960x640}.png` |
| Weather: Windy testing key | Use = Windy, If it fails, try = OpenWeather, Windy Testing key saved | Windy status (lower in the form): violet triangle "Testing key: Windy's data is shuffled, so Iter won't score from it" with **Check**; OpenWeather above it still "Needs an API key". Windy's Key type and Model pop-ups sit below the crop. | `snapshots/settings-weather-testing-key-{light,dark}-{1280x820,960x640}.png` |
| Weather: default, not enabled | Use = Apple Weather, If it fails, try = None, no keys, WeatherKit not provisioned | Apple Weather: violet triangle "Not enabled for this build" with **Check Again**. OpenWeather and Windy each "Needs an API key". The three steps follow the provider sections (below the fold; the snapshot is cropped to the window height). | `snapshots/settings-weather-{light,dark}-{1280x820,960x640}.png` |
| Weather: working (with sample data on) | Forecast probe succeeds | Apple Weather status "Working · last update 09:00" with **Check**; the Sample Data row and caption sit inside the Forecast source section under the two pop-ups (Use = Apple Weather, fallback None); OpenWeather "Needs an API key". The Data Sources and Attribution section is below the crop. | `snapshots/settings-weather-working-{light,dark}-1280x820.png` |
| Weather: checking | Probe in flight | Spinner and "Checking…" in that provider's status row. | not rendered |
| Weather: failed | Probe fails | Violet triangle "Couldn't reach Apple Weather" (or the provider's name) with **Check Again**, and the technical text under it. | not rendered |
| Weather: key rejected, daily cap, key from environment or launch argument | Real keys | "Key rejected"; "Daily cap reached (800 of 800)"; a read-only "From environment (ITER_WINDY_KEY)" row in place of the field. | not rendered |
| Apple Intelligence: unavailable | The scout reports it cannot run | In the snapshot: `exclamationmark.triangle` "Ask Iter isn't available right now", "Apple Intelligence reported it can't run. Searching places in Explore still works." | `snapshots/settings-intelligence-{light,dark}-1280x820.png` |
| Apple Intelligence: ready, off, device, downloading | Real availability | Ready and the three unavailable variants as described. | not rendered |
| About | Open the tab | As above. | `snapshots/settings-about-{light,dark}-1280x820.png` |

In the snapshots, the tab bar renders as a blank grey strip with a fragment of the tab labels ("pple Intelligence", "About") and a black rounded blob over the selected tab. That is an offscreen-rendering artefact; design the tab bar as the standard macOS Settings tab bar.

---

## Menus, popovers and dialogs

These exist in the app but are **not drawn in any snapshot** (menus, popovers and system dialogs need the window server).

| Element | Where | Contents |
|---|---|---|
| [AddToTripMenu](COMPONENTS.md#addtotripmenu) | Explore light panel, Explore row and pin context menus, Spot page header, Locations context menu, Ask rows | Button "Add to Trip" with `plus.circle`. One submenu per trip, named by the trip; inside, one item per day: "Day 2 · Thu, Oct 8, 2026 · 64" with the sunset symbol as its icon (just the date and the symbol when there is no score). Divider. "New Trip with This Spot". |
| [AddStopPopover](COMPONENTS.md#addstoppopover) | Trip builder, Add Stop | 480 x 504 pt popover: search field "Search spots", caption "Nearest to <stop> first", then a list of candidate spots (see component). Stays open so several stops can be added. |
| Set-up time popover | Trip builder, "20 min set-up" | A system stepper whose label carries its value, "Set up 20 min before the window", padding `space/lg`. |
| Session menu | Trip builder stop row | System pop-up menu; one item per window of that day: "Sunrise · 07:21–07:56 · 74". |
| Trip actions menu | Trip builder toolbar | Change Dates… (⇧⌘D), Export… (⇧⌘E), Duplicate, divider, Delete Trip. |
| Trip context menu | Sidebar trip rows, trip cards | Open, Pin Trip or Unpin Trip, divider, Move to Folder ▸ (No Folder, folders, subfolders), New Folder with Selection, Rename, divider, Duplicate, Share…, divider, Delete Trip. |
| Folder context menu | Sidebar folder rows | New Folder Inside (top-level folders only), Rename, divider, Delete Folder. |
| Library menus | Sidebar New menu, File menu | New Trip, New Folder, New Location; File also has New Folder (⌥⌘N). |
| Stop context menu | Trip builder | See Trip builder. |
| Explore radius, sort and filter menu | Explore list header | See Explore. |
| Spot and pin context menu | Explore | Open, Save/Unsave, Add to Trip ▸, divider, Open in Maps, Copy Coordinates. |
| Locations sort and filter menu | Locations toolbar | Sort By (Name, Light Today, Kind), Show (All Spots, Added by You, Curated, Apple Maps). |
| Share sheet | Trip builder, Spot page | System share sheet (a trip is shared as an `.iter` file; a spot as an Apple Maps link). |
| File importer and exporter | Import Trip…, Export… | System open and save panels. Default file name derived from the trip name. |
| Alerts and dialogs | Reset All Data…, Couldn't Open or Import or Export Trip, Delete spot | System alerts and confirmation dialogs. Strings are in the code (see each screen). |
| Window title bar and toolbars | Everywhere | See next section. |

## Not in the snapshots

| Thing | Why it is missing or looks wrong |
|---|---|
| Live MapKit maps (Explore, Locations, Trip route, Spot editor) | MapKit does not draw offscreen. A stand-in draws a flat `background/control` ground with a "Map (snapshot stand-in)" label (`type/caption`, `text/tertiary`) and the same pins at projected positions. The real map has Apple's cartography, a zoom stepper, a compass and a scale. In the Trip builder stand-in, the pins of the active day are all drawn selected-size and accent; in the live map, only the selected stop's pin is large (36 pt) and the other pins of the active day are 28 pt accent, pins of other days 28 pt `text/secondary`. |
| Toolbar items | Render as blank rounded squares (width and position are right, content is not). Use the toolbar lists in each screen section. Grouped toolbar controls can also be drawn partly at the top-left of the window in offscreen renders; that is a renderer artifact, not app layout, so use the Explore toolbar table instead. |
| Window traffic lights, the sidebar toggle | Not drawn (a stray partial icon sits at the left edge). |
| Window title position | The title appears top-left ("Explore", "All Locations") because the render has no title bar chrome. |
| Look Around | Omitted offscreen. In the app it appears as the last section of the spot page when Apple has imagery: a 224 pt high (`chart/arcHeight` + `chart/timelineHeight`) clipped panel with 12 pt corners under the heading "Look Around". |
| Menus, popovers, pop-up buttons opened, system sheets and alerts | Not rendered (see the table above). |
| Sidebar selection colour | A neutral grey pill, not the accent pill of an active window. |
| Glass and vibrancy | Sidebar and toolbar glass and materials are drawn flat. The Add Spot banner uses a flat `background/content` in snapshots and `regularMaterial` in the app. |
| Hover states | Not renderable. Pin hover (a chip) and list row hover exist; there is no distinct row hover style in the code. |
| Focus rings, drag previews, drag indicators | Not rendered. |
| Settings tab bar | Renders badly (see Settings). |
| Renderer test sheets | `snapshots/renderer-*-{light,dark}-960x640.png` (chart, contrast, form, list-canvas, sidebar, sidebar-selection, toolbar) test the offscreen renderer itself. They are not app screens. Ignore them for design. |

## Cross-screen conventions

- **Light and dark** follow the system. Dark ramp fills get lighter, not darker (see TOKENS.md).
- **Times** are always in the spot's own time zone, in the Mac's clock style. A note appears only when the spot's zone differs from the Mac's ("Mountain Time · 1 h ahead of you").
- **Dates** use abbreviated weekday and month ("Wed 7 – Sat, Oct 10", "Tue, Oct 6, 2026").
- **Numbers** (scores, times, counts, durations) use monospaced digits.
- **Selection** in a system list is the system's accent fill, with the text falling back to the system's colours. Custom surfaces use `selection/fill` alone (outlook day, window row); the timeline's selected window has a 2 pt accent outline. Selection on the map is scale and shadow, never a coral outline.
- **Empty states** are the system's ContentUnavailableView: a large grey symbol, a bold title, a grey sentence, then up to two buttons (the first prominent).
- **Undo**: all edits go through the store and are undoable; the Edit menu names the action.
