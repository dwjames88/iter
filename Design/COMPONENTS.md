# Iter components

Hand-off for rebuilding Iter's components in a design tool. Companion files: [SCREENS.md](SCREENS.md) (every screen and state), [TOKENS.md](TOKENS.md) and `tokens.json`.

## How to read this

- Each component names its Swift type and file (under `App/Sources/`), its one job, its anatomy, variants, states, tokens, accessibility and the screens that use it.
- **Token names** are written the design-tool way: `space/md` is `IterSpace.md`, `light/ramp/good` is `IterColor.ramp(.good)`, `type/headline` is `IterFont.headline`, `size/badge/height` is `IterSize.badgeHeight`, `stroke/hairline` is `IterStroke.hairline`, `radius/card` is `IterRadius.card`. "System" means a system colour, material or control that Iter does not restyle.
- "Compact", "regular" and "large" are the real variant names in the code.
- Text is always in `text/primary` unless a row says otherwise. Every card is `background/control` with a `stroke/hairline` border in `separator/default`.
- Scores are always paired with a window name. Bands: Poor, Fair, Good, Great, Epic. Confidence: Low, Medium, High (three bars).

## Contents

1. [Light Index components](#light-index-components): [LightBadge](#lightbadge), [ScoreChip](#scorechip), [NoForecastRing](#noforecastring), [ConfidenceMark](#confidencemark)
2. [Honesty and provenance](#honesty-and-provenance-components): [SampleDataLabel](#sampledatalabel), [WeatherAttributionView](#weatherattributionview), [ProvenanceTag](#provenancetag), [Warning lines](#warning-lines)
3. [Shared](#shared-components): [AddToTripMenu](#addtotripmenu), [MapStandIn](#mapstandin), [SpotEditorSheet](#spoteditorsheet), [SpotCard](#spotcard)
4. [Shell](#shell-components): [TripContextMenu](#tripcontextmenu)
5. [Trips](#trips-components): [TripCard](#tripcard), [TemplateRow](#templaterow), [TripHeader](#tripheader), [TripPlanList](#tripplanlist), [DayHeader](#dayheader), [StopRow](#stoprow), [StopNumberBadge](#stopnumberbadge), [ConnectorRow](#connectorrow), [SuggestionBanner](#suggestionbanner), [TripRouteMap](#triproutemap), [AddStopPopover](#addstoppopover)
6. [Explore](#explore-components): [ExploreListPanel](#explorelistpanel), [ExploreRow](#explorerow), [ExploreMapPane](#exploremappane), [ExplorePinView](#explorepinview), [ExplorePlaceCard](#exploreplacecard), [AddSpotBanner](#addspotbanner)
7. [Spot page](#spot-page-components): [SpotHeader](#spotheader), [WhenToGoSection](#whentogosection), [SunTimesLine](#suntimesline), [OutlookStrip](#outlookstrip), [DayWindowsSection](#daywindowssection), [WindowRow](#windowrow), [ReasonsGrid](#reasonsgrid), [SignedBar](#signedbar), [ExplainBlock](#explainblock), [LightTimeline](#lighttimeline), [SkyArc](#skyarc), [HourlyStrip](#hourlystrip), [SpotFactsRow](#spotfactsrow), [LookAroundSection](#lookaroundsection)
8. [Saved and Scout](#saved-and-scout-components): [SavedRow](#savedrow), [ScoutResultRow](#scoutresultrow), [ScoutProgress](#scoutprogress)
9. [System components](#system-components)
10. [Rules that cut across components](#rules-that-cut-across-components)

---

## Light Index components

### LightBadge

- **Type, file:** `LightBadge`, `Components/LightBadge.swift`.
- **One job:** show one Light Index window: the window name always beside the number, the band word, the confidence; or, with no forecast, a hollow dashed ring and the reason.
- **Input:** a `LightWindow` (kind: Morning blue hour, Sunrise, Sunset, Evening blue hour, Night; assessment: scored or no forecast with a reason) and a style. Option `showsSource`: add an inline [SampleDataLabel](#sampledatalabel) for sample-weather scores (off for rows and pins).
- **Variants and anatomy:**

| Style | Scored | No forecast |
|---|---|---|
| **compact** | [ScoreChip](#scorechip) compact (18 pt square) + short window name (`type/caption`, `text/secondary`): "Sunrise", "Sunset", "Blue AM", "Blue PM", "Night". Gap `space/xs`. **No band word, no confidence.** | 18 pt [NoForecastRing](#noforecastring) + short window name. No reason text. |
| **regular** | [ScoreChip](#scorechip) regular (22 pt tall, min 28 wide) + a two-line block (gap `space/sm`): window name (`type/subheadline`, `text/primary`; full names "Morning blue hour", "Evening blue hour"), then `type/caption` `text/secondary`: band word, [ConfidenceMark](#confidencemark), optional Sample data. | 22 pt ring + window name, then "No forecast" (`type/caption`, `text/secondary`). |
| **large** | [ScoreChip](#scorechip) large (64 pt) + block (gap `space/md`): headline "Sunset · 87" (`type/headline`), then `type/subheadline` `text/secondary`: band word, and "· Likely 72–100" when the range is not a single value; then `type/caption` row: ConfidenceMark and "Low confidence" (also Medium, High), optional Sample data. | 64 pt ring + headline "Sunset · No forecast" and the full reason sentence (`type/subheadline`, `text/secondary`, wraps). |

- **States:** scored (band Poor to Epic, colour from the band); low confidence (chip at 85% opacity); no forecast (any of five reasons, see below); sample data (inline label when `showsSource`). The no-forecast reason sentence is only in the large variant; compact and regular never show a number or a band for no forecast.
- **No-forecast reasons** (`ForecastUnavailableReason`), long form and short form:

| Reason | Long (large badge, lead card, notices) | Short (rows, outlook cells, Saved, Scout) |
|---|---|---|
| Weather service not enabled | "Weather isn't enabled for this build of Iter, so only sun and moon times are shown." | "Weather off" |
| Service failed | "Couldn't reach Apple Weather. Sun and moon times are still exact." | "Offline" |
| Beyond horizon | "Too far ahead for a forecast. Planned on sun angle and season until about ten days out." | "Too far ahead" |
| In the past | "This window has passed." | "Passed" |
| Not loaded | "Forecast not loaded yet." | "Loading" |

- **Tokens:** `type/subheadline`, `type/caption`, `type/headline`, `text/primary`, `text/secondary`, `space/xs`, `space/sm`, `space/md`, `space/xxs`; chip and ring tokens below.
- **Accessibility:** one element (children ignored). Label: "Sunset, Light Index 87, Great, High confidence" or "Sunset, no forecast. <reason>".
- **Used on:** Trip builder (regular), Explore rows (regular) and place card (regular), pins (compact), Spot page lead (large) and window rows (regular), Saved rows (compact), Scout rows (compact), Add Stop rows (compact).

### ScoreChip

- **Type, file:** `ScoreChip`, `Components/LightBadge.swift`.
- **One job:** the number on its band fill.
- **Anatomy:** the score as text (monospaced digits) on a rounded rectangle filled with the band colour, with a `stroke/hairline` border in `separator/default` (so pale bands show against the window), and a `light/rampText/*` text colour.
- **Sizes:**

| Size | Height | Min width | Type | Corner radius | Horizontal padding |
|---|---|---|---|---|---|
| compact | 18 (`size/badge/heightCompact`) | 18 | `type/score/badge` | `radius/badge` (6) | `space/xs` |
| regular | 22 (`size/badge/height`) | 28 (`size/badge/minWidth`) | `type/score/medium` | `radius/badge` | `space/xs` |
| large | 64 (`size/lightRing/large`) | 64 | `type/score/large` | `radius/card` (12) | none |

- **States, by band** (fill / text, light then dark; see TOKENS.md for the values): Poor `light/ramp/poor` / `light/rampText/poor`; Fair `fair`; Good `good`; Great `great`; Epic `epic`. Low confidence: 85% opacity. Never green, red or coral.
- **Used on:** inside every LightBadge, and by itself on the [OutlookStrip](#outlookstrip) cells (regular size, no band word; the band is implied by the colour and the day's caption shows the range).
- **Accessibility:** the parent supplies the label.

### NoForecastRing

- **Type, file:** `NoForecastRing`, `Components/LightBadge.swift`.
- **One job:** the "no forecast" mark: a hollow circle with a dashed outline, no fill, no number. Unknown is not poor.
- **Anatomy:** circle, inside stroke `stroke/regular` (1.5) in `status/noForecast`, dashed `stroke/dashLength` 4 on, `stroke/dashGap` 3 off.
- **Diameters:** 18 (`size/badge/heightCompact`, compact), 22 (`size/badge/height`, regular), 64 (`size/lightRing/large`, large and lead card), 16 (`size/icon/medium`, Scout row), 22 on outlook cells.
- **Map-pin variant** (inside [ExplorePinView](#explorepinview)): a 12 pt dot, fill `background/content`, 1.5 pt `status/noForecast` ring.
- **Accessibility:** hidden; the reason is spoken by the parent.
- **Used on:** every place a score would be when there is no forecast.

### ConfidenceMark

- **Type, file:** `ConfidenceMark`, `Components/LightBadge.swift`.
- **One job:** how far to trust the score, as three ascending bars.
- **Anatomy:** three bars, each 2 pt wide (`stroke/thick`), heights one third, two thirds and full of 14 pt (`size/confidenceMark`), 1 pt gap (`stroke/thin`), corner radius 1. Filled bars `text/secondary`, unfilled `separator/default`.
- **States:** low = 1 bar, medium = 2, high = 3.
- **Accessibility:** label "High confidence" (Medium, Low).
- **Used on:** regular and large LightBadge, [ReasonsGrid](#reasonsgrid) confidence line.

---

## Honesty and provenance components

### SampleDataLabel

- **Type, file:** `SampleDataLabel`, `Components/SampleDataLabel.swift`.
- **One job:** say that scores come from made-up weather.
- **Variants:**

| Style | Anatomy | Tokens |
|---|---|---|
| **inline** | `flask` icon + "Sample data" | `type/captionStrong`, `status/warning` (violet) |
| **banner** | A rounded box: `flask` icon (violet), title "Sample data" (`type/captionStrong`), body "Scores use made-up weather. Turn off in the Debug menu." (`type/caption`, `text/secondary`, wraps). Full width, padding `space/sm`, corner `radius/control` (8), fill `background/control`, 1 pt (`stroke/thin`) `status/warning` border. | as shown |

- **States:** shown only in Sample data mode. The banner lives at the bottom of the sidebar; the inline label is used in headers, footers and reasons. See the "once per screen" rule below.
- **Used on:** sidebar (banner), Explore header, Saved footer (via attribution), Scout results header, Spot page hourly strip and reasons, Settings > Weather, in place of the Apple Weather mark in [WeatherAttributionView](#weatherattributionview).

### WeatherAttributionView

- **Type, file:** `WeatherAttributionView`, `Components/WeatherAttributionView.swift`.
- **One job:** the legal attribution that must appear wherever Apple Weather data appears.
- **Anatomy (Apple Weather):** a row, gap `space/sm`: Apple Weather mark image (14 pt high, `size/icon/small`; the dark or light combined mark per appearance; falls back to the service name text), a **Legal attribution** link (`type/caption`), and "Light Index modified from forecast data" (`type/caption`, `text/tertiary`).
- **States:** Sample data on: an inline [SampleDataLabel](#sampledatalabel) replaces the whole row (sample data is not Apple Weather). No attribution info loaded and sample off: nothing is drawn (so no-forecast screens have an empty footer).
- **Accessibility:** the mark carries the service name as its label.
- **Used on:** Explore list footer, Trip builder list footer (only when some stop is scored), Spot page hourly strip card, Saved footer bar, Scout results footer, Settings > Weather "Attribution".

### ProvenanceTag

- **Type, file:** `ProvenanceTag`, `Components/ProvenanceTag.swift`.
- **One job:** where a spot came from.
- **Anatomy:** a capsule with a `stroke/hairline` `separator/default` outline and no fill; text `type/caption`, `text/secondary`; padding `space/xs` horizontal, `space/xxs` vertical.
- **States (text):** Curated, Added by you, Apple Maps, Scout. (Scout results use Curated or Apple Maps only.)
- **Used on:** Explore place card (always), Explore rows (only "Added by you"), Spot header, Saved rows, Scout rows.

### Warning lines

- **Type, file:** `IssueLine` in `Trips/StopRow.swift`; the same pattern is used inline in the Change Dates sheet, the Spot editor (time zone fallback) and Explore's search error.
- **One job:** a warning is violet and always carries an icon.
- **Anatomy:** `exclamationmark.triangle.fill` (or `exclamationmark.triangle`) + text, both `status/warning`, `type/caption` (`type/callout` in Change Dates). Wraps.
- **Wording seen:** "Out of order: this Sunrise is earlier than the previous stop's Sunset"; "No Sunset window on this day at this place"; "Drive doesn't fit: 2 hr, 58 min short"; "N stops will move to Day D, the new last day. You can undo this."; "Couldn't find this place's time zone, so using this Mac's."; "Couldn't search Apple Maps for “query”."
- **Danger variant:** validation messages in the Spot editor use `status/danger` (crimson) with `exclamationmark.triangle.fill` at `type/caption`.
- **Used on:** Trip builder rows and connectors, Change Dates sheet, Spot editor, Explore header.

---

## Shared components

### AddToTripMenu

- **Type, file:** `AddToTripMenu`, `Components/AddToTripMenu.swift`.
- **One job:** add a spot to a trip day, where the choice of day is a light decision.
- **Anatomy:** a system Menu with the label "Add to Trip" and `plus.circle`. Contents: one submenu per trip; inside, one item per day, "Day 2 · Wed 7 Oct · Sunset 64" (window name and score for that day at this spot, or "Sunset · No forecast"); a divider; "New Trip with This Spot" (creates a one-day trip named "Trip to <spot>" starting tomorrow, adds the stop, opens the trip).
- **Style by context:** button style (prominent on the Spot header, bordered on the place card and Scout rows), or a menu row in context menus.
- **Used on:** Spot header, Explore place card and context menus, Saved context menu, Scout rows.

### MapStandIn

- **Type, file:** `MapStandIn`, `Components/MapStandIn.swift`; `ExploreMapStandIn` in `Explore/ExploreMapPane.swift`.
- **One job:** snapshots only. A labelled stand-in for a live map.
- **Anatomy:** a `background/control` ground; the same pins at projected positions; for trips, the active day's route as a `route/active` polyline (`stroke/route` 4); pins 28 pt (36 selected), selected `accent/primary`, others `text/secondary`, each with a `type/caption` label; the label "Map (snapshot stand-in)" at top-left in `text/tertiary`.
- Not part of the product design. Design the real map from [ExploreMapPane](#exploremappane), [TripRouteMap](#triproutemap) and the Map entry under System components.

### SpotEditorSheet

- **Type, file:** `SpotEditorSheet`, `Components/SpotEditorSheet.swift`.
- **One job:** create or edit your own spot.
- **Anatomy and states:** see [Spot editor sheet](SCREENS.md#spot-editor-sheet). 520 x 750 pt. Title `type/title/section`; map `chart/arcHeight` 168 high, `radius/card`, hairline; pin SF Symbol `mappin` (largest title size) in `accent/primary` with a small shadow, tip at the map centre; fields in a system grouped form; buttons Cancel and Add Spot or Save.
- **Tokens:** `space/lg`, `space/sm`, `space/xs`, `radius/card`, `stroke/hairline`, `accent/primary`, `status/warning`, `status/danger`, `text/secondary`.
- **Accessibility:** map labelled "Map with the spot's pin at the centre" with the coordinates as its value.
- **Used on:** Explore (create), Spot page and Saved (edit).

### SpotCard

- **Type, file:** `SpotCard`, `Spot/SpotLayout.swift`.
- **One job:** the card surface for the spot page's lead and charts.
- **Anatomy:** content padded `space/md`, full width, `background/control`, `radius/card` (12), 0.5 pt hairline `separator/default`.
- **Used on:** Spot page (When to go lead, timeline, arc, hourly strip, facts).

---

## Shell components

### TripContextMenu

- **Type, file:** `TripContextMenu`, `Shell/SidebarView.swift`.
- **One job:** act on a trip from the sidebar or a card.
- **Contents:** Open, Duplicate (creates "<name> copy" and opens it), Share… (a share link to a `.iter` file), divider, Delete Trip (destructive; if it is the selected trip, selects All Trips first). Undoable.
- **Used on:** sidebar trip rows, [TripCard](#tripcard).

---

## Trips components

### TripCard

- **Type, file:** `TripCard` (private), `Trips/TripsHomeView.swift`.
- **One job:** one trip on All Trips, with its next session.
- **Anatomy (top to bottom, gap `space/sm`):** name (`type/title/spot`, up to two lines); date range "Wed 7 – Sat, Oct 10" (`type/subheadline`, `text/primary`) and "4 days · 6 stops" (`type/subheadline`, `text/secondary`); divider; footer (see states). Padding `space/md`; card surface as above (`radius/card`).
- **States (footer):** next session: icon of the window kind (`sunset`, `sunrise`, ...; `text/secondary`) and "Next: Horseshoe Bend · Sunset from 17:25, Wed" (`type/subheadline`, up to two lines); no stops: `plus.circle` (`accent/primary`) and "No stops yet. Open the trip to add the first."; all passed: `checkmark.circle` and "All sessions have passed".
- **Interaction:** the whole card is a button; context menu = [TripContextMenu](#tripcontextmenu). There is no custom hover style.
- **Accessibility:** one combined element, hint "Opens the trip".
- **Used on:** All Trips.

### TemplateRow

- **Type, file:** `TemplateRow` (private), `Trips/TripsHomeView.swift`.
- **One job:** start a trip from a template.
- **Anatomy:** a card row, padding `space/md`: left column name (`type/headline`), "4 days · 6 stops" (`type/subheadline`, `text/secondary`), up to three spot names with "…" (`type/caption`, `text/secondary`, one line); right `chevron.right` (`type/caption`, `text/secondary`).
- **Accessibility:** "Canyon Country, 4 days · 6 stops", hint "Starts a new trip from this template".
- **Used on:** All Trips empty state.

### TripHeader

- **Type, file:** `TripHeader` (private), `Trips/TripBuilderView.swift`.
- **One job:** the trip's name, dates and totals.
- **Anatomy:** name text field (`type/title/spot`, plain, no border; tooltip "Click to rename"); below, `type/subheadline` `text/secondary`: borderless `calendar` + date range button, "·", "4 days · 6 stops", "·", "376 mi · 8 hr, 39 min driving" (hidden under 1 minute; ", (estimated)" suffix when estimated). Padding `space/lg`; gap `space/xs`.
- **States:** editing (system text-field focus; the snapshot shows the name selected); an empty name reverts on commit.
- **Used on:** Trip builder.

### TripPlanList

- **Type, file:** `TripPlanList`, `Trips/TripPlanList.swift`.
- **One job:** the plan as day sections of stops and connectors, with drag and drop.
- **Anatomy:** a system inset List with selection. Optional first row: one `type/caption` `text/secondary` line with the global no-forecast reason (when every stop has the same weather-off or offline reason). Per day: [DayHeader](#dayheader) as the section header, optional [SuggestionBanner](#suggestionbanner), [ConnectorRow](#connectorrow) + [StopRow](#stoprow) pairs, and an **Add Stop** row (`plus` icon and text in `accent/primary`, borderless). Last row: [WeatherAttributionView](#weatherattributionview) when something is scored.
- **Drop indicator:** a `stroke/thick` (2 pt) capsule in `accent/primary` at the top of the target row or day.
- **Non-selectable rows:** banners, connectors, Add Stop, caption, attribution.

### DayHeader

- **Type, file:** `DayHeader`, `Trips/TripPlanList.swift`.
- **One job:** which day, its light frame and its load.
- **Anatomy:** left: "Day 2 · Thu, Oct 8, 2026" (`type/headline`), then `sun.horizon` + "Sunrise 07:21 · Sunset 18:53" (`type/caption`, `text/secondary`, monospaced digits). Right: "2 stops · 5 hr, 27 min driving" or "No stops yet" (`type/caption`, `text/secondary`). Vertical padding `space/xs`. Not upper-cased.
- **States:** drop target (the whole header accepts a dropped stop and puts it at the end of that day).
- **Accessibility:** combined, header trait.

### StopRow

- **Type, file:** `StopRowView`, `Trips/StopRow.swift`.
- **One job:** one stop: when to leave and be set up first, then the session, the light, and the note.
- **Anatomy:** a horizontal row, gap `space/md`, vertical padding `space/sm`: [StopNumberBadge](#stopnumberbadge) at the left, then a column (gap `space/xs`):
  1. **Title line:** spot name (`type/headline`, up to two lines; a plain button that opens the spot page) with locality beneath it (`type/caption`, `text/secondary`); at the right a [LightBadge](#lightbadge) regular for the stop's session window.
  2. **Schedule headline** (`type/bodyEmphasis`, monospaced digits): "Leave 05:54 · park 06:50 · set up by 07:00"; "Leave 03:42 · set up by 07:01" (no "park" when walk-in is unknown or equal); "Set up by 17:05" for the first stop of a trip (no drive). The leave time is in the previous stop's time zone.
  3. **Session line** (`type/caption`, `text/secondary`, one line): a small pop-up menu (the session picker, with items such as "Sunset · 17:25–18:00 · 7"), "25 min walk-in" (or "walk-in unknown"), "·", and a link button "20 min set-up" that opens the set-up popover.
  4. **Issue lines** ([Warning lines](#warning-lines)), if any.
  5. **Note field:** plain text field, "Add a note" placeholder, `type/callout`, 1 to 4 lines.
- **States:** default; selected (system list selection, and the map pin follows); scored (badge by band); no forecast (ring, "No forecast", menu item "· Weather off"); out of order (violet line); window missing (violet line, menu shows "no window this day"); dragging (the row follows the pointer); infeasible incoming drive (shown on the connector above, not on the row).
- **Context menu:** Open Spot Page, Open in Maps, Move Up, Move Down, Move to Day ▸, Remove from Trip.
- **Accessibility:** container labelled "Stop 2, Monument Valley"; custom actions Move Up, Move Down, Remove from Trip.
- **Tokens:** `space/md`, `space/sm`, `space/xs`, `type/headline`, `type/bodyEmphasis`, `type/caption`, `type/callout`.
- **Used on:** Trip builder.

### StopNumberBadge

- **Type, file:** `StopNumberBadge`, `Trips/StopRow.swift`.
- **One job:** the stop's number, matching its map pin.
- **Anatomy:** a 22 pt (`size/badge/height`) circle filled with the system `quaternary` fill (about 10 to 15% of the label colour), the number in `type/captionStrong`, `text/primary`, monospaced digits.
- **Accessibility:** hidden (the row's label includes the number).

### ConnectorRow

- **Type, file:** `ConnectorRowView`, `Trips/StopRow.swift`.
- **One job:** the drive between two stops and whether it fits; across a day boundary, an explicit overnight break.
- **Anatomy:** left rail: a 2 pt (`stroke/thick`) by 16 pt (`size/icon/medium`) rounded bar in a 22 pt column, in `route/active` (teal) when the drive fits or `status/warning` (violet) when it does not. Then `car.fill` + "57 min · 41 mi" (`type/caption`, `text/secondary`, monospaced digits). Vertical padding `space/xs`.
- **Variants:** *same-day:* rail then drive text, left aligned. *Overnight:* rail, then `moon.stars` + "Overnight" (`type/captionStrong`, `text/secondary`), a hairline rule filling the width, then the drive text at the right.
- **States:** fits (teal); does not fit (violet rail, then "· ⚠ Drive doesn't fit: 12 hr, 57 min short" in violet with a triangle icon); estimated ("· estimated", tooltip "Drive time estimated"); loading (the drive text is absent until MapKit answers; a spinner is in the toolbar).
- **Accessibility:** one combined element.
- **Used on:** Trip builder.

### SuggestionBanner

- **Type, file:** `SuggestionBanner`, `Trips/TripPlanList.swift`.
- **One job:** offer, never apply, a light-first order for one day.
- **Anatomy:** a row on `background/control`, `radius/control` (8), hairline border, padding `space/sm`, small controls: `arrow.up.arrow.down` (`text/secondary`); a two-line block, "Reorder by light: fixes 2 conflicts" (`type/subheadline`) and "Puts the stops in the order their light arrives." (`type/caption`, `text/secondary`); trailing **Dismiss** (borderless) and **Apply** (bordered).
- **States:** one banner per day with a suggestion; disappears on Apply or Dismiss.
- **Used on:** Trip builder.

### TripRouteMap

- **Type, file:** `TripRouteMap`, `Trips/TripRouteMap.swift`.
- **One job:** the route sanity check.
- **Anatomy (live map):** MapKit map filling the right column. **Pins:** numbered circles, 28 pt (`size/mapPin`), 36 pt when selected (`size/mapPinSelected`); in the active day `accent/primary` fill with `accent/onAccent` number; other days `text/secondary` fill with a `background/window` number; border `background/window` 1 pt (2 pt when selected); number in `type/captionStrong`. **Routes:** the active day's legs as `route/active` 4 pt (`stroke/route`) over a `background/window` casing 7 pt (`stroke/routeCasing`); other days `route/inactive` 3 pt (`stroke/routeInactive`). Straight lines when the road path is unknown. Controls: zoom stepper, compass, scale. **Day picker:** a system segmented control (up to 5 days; a menu beyond that) in a `regularMaterial` pill (`radius/control`, padding `space/xs`) at the top-left with `space/md` margin; shown only when more than one day has stops.
- **States:** a stop selected (the camera recentres on it, zoom kept); the picked day; fit-to-trip on appear and when stops change.
- **Accessibility:** label "Route map"; pins "Stop 2, Monument Valley".

### AddStopPopover

- **Type, file:** `AddStopPopover`, `Trips/AddStopPopover.swift`.
- **One job:** add stops to a day, nearest first, each with its score for that day.
- **Anatomy:** popover 480 x 504 pt. Header (padding `space/md`): a search field (28 pt high, `background/control`, `radius/control`, hairline, magnifier, clear button) and "Nearest to <stop> first" (`type/caption`, `text/secondary`). Divider. Plain list of rows: name (`type/body`, one line) + `bookmark.fill` when saved (`type/caption`, `text/secondary`), a detail line "Page, AZ · 25 mi" (`type/caption`, `text/secondary`), then at the right a compact [LightBadge](#lightbadge) and `plus.circle` (`accent/primary`) or `checkmark.circle.fill` (`text/secondary`) once added.
- **States:** empty search result (system search-empty view); added (tick; the row stays); the spot already on that day shows the tick.
- **Accessibility:** rows "Add <name>", value "Added".

---

## Explore components

### ExploreListPanel

- **Type, file:** `ExploreListPanel`, `Explore/ExploreListPanel.swift`.
- **One job:** the reading surface of Explore: summary, notices, search status, the list, attribution.
- **Anatomy:** see [Explore](SCREENS.md#explore). Background `background/content`. Header: summary "45 places · Tue, Oct 6, 2026 · Each spot's best" (`type/subheadline`, `text/secondary`, "·" in `text/tertiary`), sample label, notice (`cloud.slash` + reason, `type/caption`, `text/secondary`), search status. Section headers: `type/captionStrong`, `text/secondary`, with a count at right.
- **States:** list; loading (small spinner); searching; search failed; empty ("No Matching Spots" or "No places found", via ContentUnavailableView, with Clear Filters).

### ExploreRow

- **Type, file:** `ExploreRowView`, `Explore/ExploreListPanel.swift`.
- **One job:** one spot and its light on the chosen day.
- **Anatomy:** row, gap `space/md`, vertical padding `space/xs`: left, name (`type/bodyEmphasis`, one line) over locality (`type/caption`, `text/secondary`) with a [ProvenanceTag](#provenancetag) for your own spots; right, a column (gap `space/xxs`): a [LightBadge](#lightbadge) regular, then the window's start time (`type/timeSmall`, `text/secondary`, monospaced digits, e.g. "19:54").
- **States:** scored; no forecast (ring, "No forecast", start time still shown); no such light today ("No such light today", `type/caption`); selected (system list selection); hovered (the map pin gets a chip; the row itself has no distinct hover style).
- **Accessibility:** one element: "Mesa Arch, Canyonlands National Park, UT, Curated, Sunrise, Light Index 68, Good, Medium confidence, starts 07:20".

### ExploreMapPane

- **Type, file:** `ExploreMapPane`, `Explore/ExploreMapPane.swift`.
- **One job:** the map with pin hierarchy, shared selection, the place card and Add Spot mode.
- **Anatomy:** a MapKit map (standard, flat, points of interest hidden; zoom stepper, compass, scale), pins as [ExplorePinView](#explorepinview), a "New spot" `mappin.circle.fill` (`accent/primary`, title size) at a dropped draft pin; overlays: [AddSpotBanner](#addspotbanner) top, [ExplorePlaceCard](#exploreplacecard) bottom (slides up with a fade), each inset `space/md`.
- **States:** default; a selection; Add Spot mode (crosshair cursor, pins not clickable, the card hidden); a draft pin placed (the editor sheet is open).

### ExplorePinView

- **Type, file:** `ExplorePinView`, `Explore/ExplorePinView.swift`.
- **One job:** map hierarchy: one selected pin, a few chips, the rest dots.
- **Anatomy and variants:**

| Style | Drawn as |
|---|---|
| **dot** | 12 pt (`space/md`) circle filled with the band colour (`light/ramp/*`) with a 0.5 pt `separator/default` ring; with no score, a `background/content` circle with a 1.5 pt `status/noForecast` ring. |
| **chip** | A capsule (`background/content`, hairline `separator/default`, padding `space/xs` by `space/xxs`) holding a compact [LightBadge](#lightbadge) ("86 Night"). With no window: a dot. |
| **selected** | A capsule (`background/content`, **2 pt `accent/primary` border**, padding `space/sm` by `space/xs`) holding a compact LightBadge and the window start time (`type/timeSmall`, `text/primary`); with no window the spot name (`type/captionStrong`). Below it a small down-pointing triangle in `accent/primary` (`type/caption`), so the anchor is the bottom tip. |

- **Rules:** the selected pin always wins; a hovered pin and the best **six** scored spots in view (`pinBudget = 6`, excluding the selected one) are chips; everything else is a dot. The selected pin is drawn on top, then chips, then dots.
- **Accessibility:** button (and selected) trait; label as the list row.

### ExplorePlaceCard

- **Type, file:** `ExplorePlaceCard`, `Explore/ExplorePlaceCard.swift`.
- **One job:** the selected spot's identity, its light that day, and one primary action.
- **Anatomy:** a panel, max width 360 pt (`layout/listIdeal`), padding `space/md`, `radius/panel` (16), a `regularMaterial` fill (flat `background/content` in snapshots), hairline `separator/default`. Gap `space/md`. Top: name (`type/headline`), a line with locality (`type/subheadline`, `text/secondary`) and a [ProvenanceTag](#provenancetag); at top right a `xmark.circle.fill` close button (`text/tertiary`, tooltip "Deselect", label "Close"). Light block: a regular [LightBadge](#lightbadge) at left; at right the start time (`type/time`, `text/primary`) over the range "07:20–07:55" (`type/caption`, `text/secondary`); beneath, the no-forecast reason in `type/caption`, `text/secondary` when there is one. With no window that day: "No such light today". Buttons: **Open** (prominent, default, Return), **Save** or **Saved** (`star` / `star.fill`, hidden for your own spots), **Add to Trip** ([AddToTripMenu](#addtotripmenu), button style).
- **States:** scored (badge by band, no reason); no forecast (ring, "No forecast", the reason sentence; this is what the snapshots show); no window; saved; your own spot (no Save button).
- **Accessibility:** container labelled "Place card for Mesa Arch".

### AddSpotBanner

- **Type, file:** `AddSpotBanner`, `Explore/ExploreMapPane.swift`.
- **One job:** tell the user what a click will do in Add Spot mode.
- **Anatomy:** a capsule, padding `space/md` by `space/sm`, `regularMaterial` fill (flat in snapshots), 1 pt `accent/primary` outline: `mappin.and.ellipse` (accent), "Click the map to drop a pin for your spot" (`type/subheadline`), **Cancel** button (Esc).
- **Accessibility:** combined element.

---

## Spot page components

### SpotHeader

- **Type, file:** `SpotHeaderView`, `Spot/SpotHeaderView.swift`.
- **One job:** who this place is and what you can do with it.
- **Anatomy:** see [Spot page](SCREENS.md#spot-page). Name `type/title/spot` (header trait); line of locality (`type/subheadline`, `text/secondary`), [ProvenanceTag](#provenancetag), category symbol and name (`type/subheadline`, `text/secondary`); action row spaced `space/sm`.
- **Variants:** titled buttons, or icon-only when the width is tight. Your own spots: Edit and Delete after a divider, no Save.
- **States:** saved (`bookmark.fill`, "Saved"); not saved; delete confirmation when trips use the spot.

### WhenToGoSection

- **Type, file:** `WhenToGoSection`, `Spot/WhenToGoView.swift`.
- **One job:** lead the page with "when should I be here?".
- **Anatomy:** title row ("When to go" `type/title/section`; segmented intent picker at right), a [SpotCard](#spotcard) lead, the [OutlookStrip](#outlookstrip).
- **Lead states:**

| State | Contents |
|---|---|
| Best window | Large [LightBadge](#lightbadge) at left. Right column (gap `space/xs`): "Best sunrise in the next 10 days" (`type/caption`, `text/secondary`); "Mon, Oct 12, 2026 · 07:25–08:01" (`type/headline`, monospaced digits; "Today" or "Tomorrow" in place of the date when relevant); the top factor's sentence (`type/callout`); "Updated 09:00" (`type/footnote`, `text/secondary`); **Show this day** (small) when the page is on a different day or window. |
| Loading | Small spinner + "Checking the forecast…" (`type/callout`, `text/secondary`), then [SunTimesLine](#suntimesline). |
| No score | A 64 pt [NoForecastRing](#noforecastring) at left; "No scored sunrise window in the next 10 days." (`type/headline`), the reason (`type/callout`, `text/secondary`), **Retry** (small, `arrow.clockwise`, ⌥⌘R) only when the service failed; divider; [SunTimesLine](#suntimesline). |

### SunTimesLine

- **Type, file:** `SunTimesLine`, `Spot/WhenToGoView.swift`.
- **One job:** the always-exact sun times when there is no score.
- **Anatomy:** `sunrise` + "Next sunrise Wed 07:20" and `sunset` + "Next sunset 18:54" (`type/callout`, monospaced digits), gap `space/lg`. Polar: `moon.stars` or `sun.max` with the polar sentence (`type/callout`, `text/secondary`).

### OutlookStrip

- **Type, file:** `OutlookStrip`, `Spot/WhenToGoView.swift`.
- **One job:** ten days at a glance for the chosen intent, fading with confidence.
- **Anatomy:** caption "10-day outlook for Sunrise" (`type/subheadline`, `text/secondary`); a row of ten equal cells (gap `space/xs`); key line "Fainter days are less certain. A dashed ring means no forecast." (`type/caption`, `text/tertiary`). Each cell, top to bottom (gap `space/xxs`, vertical padding `space/xs`): a **Best** tab (`type/captionStrong`, `accent/onAccent` on an `accent/primary` capsule; an empty line on other days), weekday (`type/caption`, `text/secondary`), day number (`type/bodyEmphasis`, monospaced), a [ScoreChip](#scorechip) regular or a 22 pt [NoForecastRing](#noforecastring), and a caption (up to two lines, `type/caption`, `text/secondary`, min height 24): the range "65–81", or "Passed", "Weather off", "Offline", "Too far ahead", "Loading", "No window".
- **States:** default; selected day (fill `accent/primary` at 16%, 1.5 pt `accent/primary` outline, `radius/control`); best day (the Best tab); confidence fade (medium 80% opacity, low 60%); no forecast (ring, short reason); no window (empty).
- **Accessibility:** each cell is a button, label "Monday, October 12, Sunrise, Light Index 87, Great, Low confidence, Best", selected trait.

### DayWindowsSection

- **Type, file:** `DayWindowsSection`, `Spot/DayWindowsView.swift`.
- **One job:** the selected day's windows in time order.
- **Anatomy:** header "Light windows" (`type/title/section`) + day label (`type/subheadline`, `text/secondary`) + **Today** (small, when not today). A card of [WindowRow](#windowrow)s separated by dividers; clipped to `radius/card`. If no windows (polar): `moon.stars` or `sun.max` with the sentence, or "No golden hour, blue hour or night window today."

### WindowRow

- **Type, file:** `WindowRow` (private), `Spot/DayWindowsView.swift`.
- **One job:** one window with its score, expandable to its reasons.
- **Anatomy:** a button row, padding `space/md` by `space/sm`: `chevron.right` (`type/captionStrong`, `text/secondary`, 14 pt column; rotates 90 degrees when open), a regular [LightBadge](#lightbadge), then at the right the time range "07:25–08:01" (`type/time`). When open, [ReasonsGrid](#reasonsgrid) below, indented past the chevron, padding `space/md` at the bottom.
- **States:** collapsed; expanded; selected (row fill `accent/primary` at 16%); no forecast (ring, "No forecast"; expanded: the reason sentence and, if the service failed, **Retry**).
- **Accessibility:** combined; value "Expanded" or "Collapsed"; hint "Shows why this window scores as it does".

### ReasonsGrid

- **Type, file:** `Reasons` (private), `Spot/DayWindowsView.swift`.
- **One job:** why the score is what it is.
- **Anatomy:** "Why this score" (`type/captionStrong`, `text/secondary`). A grid, gap `space/md` by `space/sm`, one row per factor: name (`type/bodyEmphasis`: Low cloud, Mid and high cloud, Cloud cover, Clear sky, Rain, Visibility, Moonlight, Dark sky, Wind, Sun direction), measured value (`type/time`, `text/secondary`, right aligned: "29%", "15 mi", "12 mph", "34°"), a [SignedBar](#signedbar), and a sentence (`type/callout`). Then a confidence line (gap `space/sm`): [ConfidenceMark](#confidencemark), "Low confidence" (`type/subheadline`), "· Likely 72–100", "· Updated 09:00", Sample data label if sample. Then a footnote (`type/footnote`, `text/secondary`): the confidence meaning plus "Forecast is about 6 days ahead of this window." Then [ExplainBlock](#explainblock).

### SignedBar

- **Type, file:** `SignedBar` (private), `Spot/DayWindowsView.swift`.
- **One job:** a factor's points, right helps and left hurts.
- **Anatomy:** a 1 pt (`stroke/thin`) centre line 14 pt high in `separator/default` on a track 2 x (32 + 4) = 72 pt wide; a bar 8 pt (`space/sm`) high from the centre, length proportional to the points (scale: the largest factor, minimum 10), at least 2 pt long. Colour `accent/primary` for helps and neutral, `status/warning` for hurts. The signed number ("+21", "−4") at the right (`type/timeSmall`, `text/secondary`, 28 pt wide), so colour is never the only cue.
- **Accessibility:** hidden; the row label says helps or hurts and the points.

### ExplainBlock

- **Type, file:** `ExplainBlock` (private), `Spot/DayWindowsView.swift`.
- **One job:** a plain-language reading of the factors by Apple Intelligence.
- **States:** idle (small **Explain** button with `apple.intelligence`); loading (spinner, "Writing an explanation…", Cancel); done (text `type/callout`, selectable; `apple.intelligence` + "Written by Apple Intelligence from the factors listed above." in `type/caption`, `text/secondary`; **Explain again**); failed (one sentence in `type/callout`, `text/secondary`, plus Explain); unavailable (the block is not drawn).

### LightTimeline

- **Type, file:** `LightTimelineSection` and `TimelineRenderer`, `Spot/LightTimelineView.swift`.
- **One job:** the 24 hours of light: sky by sun altitude, the five windows with scores, cloud by altitude, rain chance, and a scrubber.
- **Anatomy** (a canvas inside a [SpotCard](#spotcard); left gutter 44 pt, right inset `space/lg`):
  1. **Readout line:** "07:43 · 44% cloud · 3% rain" (`type/bodyEmphasis`, monospaced), "·" and the window name under the marker (`type/subheadline`, `text/secondary`); right, "Hover or drag to read any time" (`type/caption`, `text/tertiary`) when not scrubbing. Min height 22.
  2. **Bracket label tiers** (3 tiers of 16 pt in Full day, 2 in zoomed views): each window gets a bracket over its span and a label "Sunrise 87", "Blue AM 85", "Sunset 56", "Blue PM 54", "Night 30" (short name + score, no score when no forecast), `type/caption` (`type/captionStrong` for the selected window), `text/primary` (`text/secondary` with no score). Labels move up a tier when they would overlap, with a hairline leader. Bracket 4 pt drop, `text/secondary` 1.5 pt; selected 2 pt `accent/primary`.
  3. **Sky band:** 56 pt tall (`chart/timelineHeight`), corner `radius/badge`, a left-to-right gradient coloured by the sun's altitude: below −18° `sky/night`, −18° to −6° night to `sky/blueHour`, −6° to the horizon `sky/blueHour`, across the horizon blueHour to `sky/golden`, up to +6° `sky/golden`, to +14° golden to `sky/day`, then `sky/day`.
  4. **Axis:** 18 pt, ticks 4 pt long in `text/secondary`, hour labels `type/timeSmall` (every 3 hours in Full day, hourly when zoomed), in the spot's time zone.
  5. **Weather plot** (only with a forecast): 80 pt tall, 8 pt below the axis; 0%, 50%, 100% gridlines (`separator/default`, hairline) with labels at the left (`type/timeSmall`, `text/secondary`); cloud layers drawn as overlapping (not stacked) filled areas at 50% opacity with a 1.5 pt top line: `cloud/high`, `cloud/mid`, `cloud/low` (or a single `cloud/mid` "Cloud cover" when the layers are unavailable); rain chance bars (hours at 10% or more, 60% width) in `sky/blueHour`; each window tints the plot with its sky colour at 20% (the selected window with `accent/primary` at 16% added).
  6. **Selected window:** a 2 pt `accent/primary` outline across the sky band and plot, with a `background/window` halo.
  7. **Marker:** a vertical line in `text/primary` through the sky band and plot (dashed 1 pt at rest, solid 1.5 pt while scrubbing) with a `background/window` halo, and an 8 pt knob on the sky band's bottom edge.
  8. **Legend** (below, `type/caption`, `text/secondary`): swatches 12 pt with hairline: High cloud, Mid cloud, Low cloud, Chance of rain. With no forecast, the legend is replaced by `cloud.slash` + the reason (or "Checking the forecast…").
- **Zoom variants:** Full day (all 24 h, 3 tiers); Sunrise ±2 h and Sunset ±2 h (a four-hour domain, 2 tiers, hourly ticks). The picker is only offered when more than one is available.
- **Interaction:** hover or drag scrubs the marker (shared with the arc and the hourly strip); a click on a window selects it.
- **Accessibility:** one adjustable element "Light timeline for Monday, October 12" with the windows and times listed; increment and decrement select the next or previous window.

### SkyArc

- **Type, file:** `SkyArcSection` and `ArcRenderer`, `Spot/SkyArcView.swift`.
- **One job:** where the sun and moon are, by compass direction and height, at the shared marker time.
- **Anatomy** (canvas in a [SpotCard](#spotcard); plot 168 pt high (`chart/arcHeight`), 20 pt above and 34 pt below for labels; total about 222 pt):
  - Sky above the horizon filled `sky/day` at 20%; ground below `sky/night` at 10%; plot outlined hairline `separator/default`.
  - Height gridlines every 30°, labelled "30°", "60°" (`type/timeSmall`, `text/secondary`) left of the plot; "0°" at the horizon; the horizon line `text/secondary` 1 pt with "Horizon" (`type/caption`).
  - Compass along the bottom: N, E, S, W, N (`type/captionStrong`, `text/primary`) with ticks; minor ticks at 45° steps. Axis titles "Compass direction →" and "↑ Height above the horizon" (`type/caption`, `text/secondary`).
  - **Classic view line:** a dashed `accent/primary` vertical line at the spot's facing bearing with a label "Classic view faces 100° E" (`type/captionStrong`, `accent/text`) above the plot. Absent when the facing is unknown.
  - Sunrise and sunset direction marks on the horizon (2 pt ticks, `text/primary`) with two label lines: "Sunrise 07:25" (`type/caption`, `text/primary`) and "99° E" (`type/caption`, `text/secondary`).
  - **Paths:** the sun's path `text/primary` 2 pt; the moon's path `map/moon` 2 pt; drawn only above the horizon.
  - **Markers** (14 pt, `chart/arcMarker`): the sun marker is `map/sun` (coral) with a 1.5 pt `background/window` ring when above the horizon, and a hollow `background/window` disc with a 2 pt `map/sun` ring when below (down to −20°); the moon marker is `map/moon` with the same ring, only when above the horizon.
  - **Legend:** 12 pt dot `map/sun` "Sun", dot `map/moon` "Moon", a 2 pt `accent/primary` bar "Classic view" (only when facing is known); `type/caption`, `text/secondary`.
  - **Text lines:** "At 07:43 the sun is 3° above the horizon, toward 102° ESE." (`type/callout`); "The sun is in your frame." (`type/callout`, `text/secondary`; also "off to one side", "behind you"); the moon line with its phase symbol (20 pt, `text/primary`) and "Waxing crescent · 6% lit · rises 09:38 · sets 19:33" (`type/callout`, `text/secondary`).
- **States:** default; no classic view; sun below the horizon ("At 18:25 the sun is below the horizon."); polar (a near-flat path).
- **Accessibility:** one element, label "Sun and moon for Monday, October 12" with sunrise and sunset directions and the facing.

### HourlyStrip

- **Type, file:** `HourlyWeatherSection`, `Spot/HourlyWeatherView.swift`.
- **One job:** the day's weather hour by hour, on the timeline's x-axis.
- **Anatomy:** header "Hour by hour" (`type/title/section`) + "Updated 09:00" (`type/footnote`, `text/secondary`). A [SpotCard](#spotcard) containing a 5-row grid (rows 22 pt, `space/xxs` added to `size/icon/large`): a multicolour weather symbol (`type/subheadline`), then **Temp**, **Cloud**, **Rain**, **Wind** rows in `type/timeSmall`, monospaced digits. Row labels sit in the left gutter (`type/caption`, `text/secondary`). Rain shows a percent only at 20% or more, in `accent/text`. Temperature follows the Settings unit. Window spans are tinted with their sky colour at 20%, the selected window with `accent/primary` at 16%, the marker hour with `text/primary` at 8%. Under the strip: [WeatherAttributionView](#weatherattributionview) at left, "Wind in mph" (or km/h; `type/caption`, `text/secondary`) at right.
- **States:** with a forecast only. No forecast: the whole section is absent.
- **Accessibility:** a summary of every third hour ("6 AM: 36°, 43% cloud").

### SpotFactsRow

- **Type, file:** `SpotFactsSection`, `Spot/SpotFactsView.swift`.
- **One job:** the practical facts.
- **Anatomy:** header "Good to know" (`type/title/section`); a [SpotCard](#spotcard) with an adaptive grid of facts (min 150 pt per item, gap `space/sm`), each a Label with a `text/secondary` icon and `type/callout` text: `figure.walk` "10 min walk-in" (or "Walk-in unknown" in `text/secondary`), `mountain.2` "6,102 ft elevation" (when known; feet or metres by locale), `safari` "Faces 100° E" (or "Facing unknown"), `sun.horizon` "Best at sunrise" (when set), `clock` "Mountain Time · 1 h ahead of you" (only when the spot's zone differs from the Mac's). Then the blurb (`type/body`), and "Notes" (`type/captionStrong`, `text/secondary`) with the notes (`type/callout`).

### LookAroundSection

- **Type, file:** `LookAroundSection`, `Spot/SpotFactsView.swift`.
- **One job:** show Apple's street-level imagery where it exists.
- **Anatomy:** header "Look Around" (`type/title/section`) and a system Look Around preview, 224 pt high, clipped to `radius/card`.
- **States:** absent when Apple has no imagery, and in snapshots.

---

## Saved and Scout components

### SavedRow

- **Type, file:** `SavedRow` (private), `Saved/SavedView.swift`.
- **One job:** a kept spot and today's light.
- **Anatomy:** row, gap `space/md`, vertical padding `space/xs`: category symbol (`title3`, `text/secondary`, 32 pt column, hidden from VoiceOver); a column of name (`type/headline`, one line) and, gap `space/sm`, locality (or category if there is none; `type/subheadline`, `text/secondary`) plus a [ProvenanceTag](#provenancetag); at the right a column (right aligned, gap `space/xxs`): a compact [LightBadge](#lightbadge), "Tomorrow" when today's window has passed (`type/caption`, `text/secondary`), and the short reason when there is no forecast ("Weather off").
- **States:** scored; no forecast (ring plus reason); tomorrow's light; selected.
- **Accessibility:** one combined element.

### ScoutResultRow

- **Type, file:** `ScoutResultRow` (private), `Scout/ScoutView.swift`.
- **One job:** one suggested place, its light, drive and the scout's note.
- **Anatomy (gap `space/sm`, vertical padding `space/sm`):** name (`type/headline`) over locality (`type/subheadline`, `text/secondary`), a [ProvenanceTag](#provenancetag) at the right (Curated or Apple Maps); a line: compact [LightBadge](#lightbadge) + the day it is for ("Wed, Oct 7, 2026", `type/caption`) and `car` + "12 min drive" (`type/caption`, `text/secondary`); the note block (only when there is a note): `sparkles` + "Scout's note" (`type/captionStrong`, `text/secondary`) and the note (`type/callout`); buttons (small, bordered): **Open**, **Save** or **Saved** (`bookmark` / `bookmark.fill`), **Add to Trip**.
- **Light-line states:** scored; no forecast (16 pt [NoForecastRing](#noforecastring) + short reason; tooltip is the long reason); loading (small spinner + "Checking the forecast").
- **Accessibility:** container; the ring line carries the full reason.

### ScoutProgress

- **Type, file:** the `running` view in `Scout/ScoutView.swift`.
- **One job:** real progress for a slow request.
- **Anatomy:** centred stack, gap `space/md`: large spinner; the stage (`type/headline`); four capsules 24 x 4 pt (`space/xl` by `space/xs`) gap `space/xs`, filled `accent/primary` up to the current stage and `separator/default` after; "Step 2 of 4" (`type/caption`, `text/secondary`); after 10 seconds the elapsed time "0:14" (`type/time`, `text/secondary`) over "Still working. A request can take up to a minute." (`type/caption`, `text/secondary`); a large **Cancel** button.
- **Stage texts:** "Understanding your request", "Searching near Portland, Oregon" (or "Searching for places"), "Checking the drive to <place>" (or "Checking the drive"), "Choosing the best matches".

---

## System components

Iter relies on these system controls. Do not restyle them in the design; use the macOS 26 versions. Notes say how Iter configures them.

| System component | How Iter uses it |
|---|---|
| **NavigationSplitView** with a **sidebar** List | `.listStyle(.sidebar)`; two sections ("Trips": All Trips + one row per trip; "Find": Explore, Saved, Scout), selection bound to the window's navigation; sidebar width 200 / 240 / 320 pt; the Sample data banner is a bottom safe-area inset; a "New Trip" toolbar button. Detail column is a NavigationStack per section. |
| **List** | Explore (inset, sectioned, selection and context menu with primary action), Trip builder (inset, selection, drag and drop, section headers), Saved (inset, multi-selection), Scout results (inset, visible separators), Add Stop popover (plain). Selection is the system accent tint. |
| **HSplitView** | Explore (list, map), Trip builder (plan, map): draggable native divider. |
| **Toolbar** | Unified title bar. Items per screen are listed in SCREENS.md. Window title is the section name; the trip builder replaces the title with the editable name. |
| **searchable** (toolbar search field) | Explore ("Search spots and places"), Saved ("Search saved spots"). |
| **ContentUnavailableView** | Empty and error states: large grey symbol, bold title, grey description, 0 to 2 action buttons. Used for Trip Not Found, Explore empty, Saved empty and filter-empty, Scout unavailable and failure states, search-empty. |
| **Map** (MapKit) | Explore: standard style, flat elevation, points of interest hidden, controls zoom stepper, compass, scale, custom annotations, selection. Trip route: polylines and numbered annotations. Spot editor: a small map with pan and zoom, the pin fixed at the centre. Scout: accent-tinted markers with category symbols. |
| **LookAroundPreview** | Spot page, 224 pt high, `radius/card` clip; only when a scene exists. |
| **Picker** | Segmented (intent on the Spot page, timeline zoom, trip map day picker up to 5 days); menu (session menu, Explore Light picker, Settings pickers, Category in the editor); inline in menus (Sort, Show Light For). |
| **Menu** | Add to Trip, Explore Filters and Sort, Saved Sort and Filter, Trip Actions, context menus. |
| **ShareLink** | Trip (toolbar and context menu; shares a `.iter` document), Spot (header; shares an Apple Maps link and a coordinate message). |
| **DatePicker, Stepper, TextField, Toggle** | Forms (grouped style) in the sheets and Settings; Explore's date control is a DatePicker flanked by chevron buttons; the Explore Add Spot control is a button-style Toggle. |
| **Sheet, popover, confirmationDialog, alert, fileImporter, fileExporter** | As listed in SCREENS.md. |
| **TabView** | Settings (four tabs). |
| **Materials** | `regularMaterial` for the place card, Add Spot banner and route day picker; `bar` for the Saved footer. Flat colours in snapshots. |
| **ProgressView** | Small circular spinners next to loading text; large in Scout's running state. |
| **Buttons** | Prominent (accent fill, `accent/onAccent` text) for the single primary action of a view; bordered for secondary; borderless or link for inline actions; plain for tappable cards and rows. |

---

## Rules that cut across components

1. **Every score names its window.** A number is never alone: "Sunset · 87", or the window name beside the chip in every variant (compact shows "Sunset", regular shows "Sunset" plus the band, large shows "Sunset · 87"). Pins and outlook cells inherit the window from context (the pin's chip text, the outlook title "10-day outlook for Sunrise").
2. **No forecast is a hollow dashed ring plus a reason, never a number, never a low score.** Ring in `status/noForecast`. Long reason in large surfaces, short reason in rows ("Weather off", "Offline", "Too far ahead", "Passed", "Loading"). Sun and moon times stay exact and visible.
3. **The band word is always printed beside the ramp colour** in the regular and large badges. Colour alone never carries the band. (The compact badge, the outlook chips and pin dots rely on the number or context; see the inconsistencies reported with this document.) A badge always has its hairline, because Poor and Fair are too pale to reach 3:1 on the window.
4. **Coral (`map/sun`) is only the sun marker.** Never a score, status, button, pin or fill. Teal (`accent/primary`, `route/active`) is the land and the journey: selection, actions, routes. It is never "good".
5. **A warning is violet (`status/warning`) and always has an icon.** Failure and validation are crimson (`status/danger`) with an icon. Never amber, never coral, never green. Green is not used anywhere.
6. **"Sample data" appears once per screen.** The banner sits in the sidebar; screens that show sample scores carry one inline label; [WeatherAttributionView](#weatherattributionview) substitutes the label for the Apple mark.
7. **Attribution wherever weather appears.** Apple Weather mark, Legal attribution link and "Light Index modified from forecast data" on Explore, Trip builder (when scored), Saved, Scout results, the Spot page hourly strip and Settings > Weather.
8. **Confidence is shown, and low confidence fades.** Three bars on regular and large badges; ranges ("Likely 72–100") for days four and later; outlook cells fade to 80% and 60%.
9. **Times are the spot's own and monospaced; units follow the Mac and Settings.**
10. **System chrome stays system.** Window, sidebar, list, control and text colours are system aliases; only the ramp, accent, route, status, sky and cloud colours are Iter's.
11. **Never reorder or change a plan automatically.** Suggestions are offered, and every edit is undoable.
12. **The scout's words are labelled** ("Scout's note", "Written by Apple Intelligence from the factors listed above."). Iter scores the light, not the model.

## Known deviations from the rules (open for the design pass)

Found in the hand-off audit and left for the design work, because each one is a design decision rather than a bug:

1. **Band word in compact places.** Compact badges (map pins, Saved, Scout and Add Stop rows) and the outlook cells show the number and window name but not the band word. The VoiceOver label includes the band. Decide whether compact spaces carry the word, a glyph, or nothing.
2. **"Sample data" can appear twice on one screen**, in the header and in the attribution footer (Explore, Scout, Settings ▸ Weather). The rule says once per screen.
3. **Rain colour.** There is no rain token. The timeline's rain bars use `sky/blueHour`, and the hourly strip's rain figures use `accent/text`. A `weather/rain` token is needed.
4. **Accent on the outlook "Best" tag** marks the best day. Accent is for interaction and the route, so this edges toward accent meaning "good".
5. **Two coral marks on the sky arc**: the legend dot and the sun marker. The rule allows one per view.
6. **Serif beyond place names.** `type/title/spot` (New York) is also used for trip names and the empty-state headline.
7. **Literal opacities** in `App/Sources/Spot/SpotLayout.swift` (selection fills, chart layers) and the low-confidence chip opacity (0.85) are not tokens yet.
8. **Explore rows have no hover style** (`ExploreRowView.isHovered` is unused); only the pin reacts to hover.
9. **At 960×640 the trip builder's session line truncates** ("25 min wal…").

Fixed in the audit pass: Explore uses the bookmark symbol for Save like every other screen; the Light Index factor bars are neutral (direction shows helps or hurts, not colour); the spot editor's time-zone warning has its icon.
