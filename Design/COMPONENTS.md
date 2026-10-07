# Iter components

Hand-off for rebuilding Iter's components in a design tool. Companion files: [SCREENS.md](SCREENS.md) (every screen and state), [TOKENS.md](TOKENS.md) and `tokens.json`.

## How to read this

- Each component names its Swift type and file (under `App/Sources/`), its one job, its anatomy, variants, states, tokens, accessibility and the screens that use it.
- **Token names** are written the design-tool way: `space/md` is `IterSpace.md`, `light/ramp/good` is `IterColor.ramp(.good)`, `type/headline` is `IterFont.headline`, `event/height/regular` is `IterEvent.heightRegular`, `stroke/hairline` is `IterStroke.hairline`, `radius/card` is `IterRadius.card`. "System" means a system colour, material or control that Iter does not restyle.
- "Compact", "regular", "large" and "pin" are the real variant names of the event unit in the code.
- Text is always in `text/primary` unless a row says otherwise. The spot page's modules are [ModuleCard](#modulecard)s: `background/module`, `radius/card`, 16 padding, no border. The trip cards and template rows on All Trips are `background/control` with a `stroke/hairline` border in `separator/default`.
- The type scale has five levels (Display, Title, Headline, Body, Secondary) and the layout an 8 pt grid; the rules are in [HIERARCHY.md](HIERARCHY.md). Metadata is always `type/secondary` in `text/secondary`.
- Scores are always paired with their window by the [event unit](#eventscore-the-event-unit): the window's symbol sits inside the unit with the score and the time (list rows, pins, the light panel's header, trip stops, Locations and Ask rows, the overview strip's day cells, the Add Stop rows), with the window's word as tooltip and VoiceOver label; the Add to Trip menu items carry the symbol as their icon; the spot page's window rows and headings use the word itself. Bands: Poor, Fair, Good, Great, Epic. Confidence: Low, Medium, High (three bars).

## Contents

1. [Light Index components](#light-index-components): [EventScore (the event unit)](#eventscore-the-event-unit), [WindowSymbol](#windowsymbol), [ScoreLegend](#scorelegend), [BandConfidence](#bandconfidence) (deprecated), [ConfidenceMark](#confidencemark), [WindowLanes](#windowlanes), [EventLane](#eventlane), [LayoutGridOverlay](#layoutgridoverlay)
2. [Honesty and provenance](#honesty-and-provenance-components): [SampleDataLabel](#sampledatalabel), [WeatherStatusBanner](#weatherstatusbanner), [WeatherAttributionView](#weatherattributionview) (with ForecastSourceLine, [ForecastSourceLines](#forecastsourcelines) and WeatherDataSources), [WindyLink](#windylink), [ProvenanceTag](#provenancetag), [Warning lines](#warning-lines), [Weather status text and score notes](#weather-status-text-and-score-notes)
3. [Shared](#shared-components): [AddToTripMenu](#addtotripmenu), [MapStandIn](#mapstandin), [SpotEditorSheet](#spoteditorsheet), [ModuleCard](#modulecard)
4. [Shell](#shell-components): [TripContextMenu](#tripcontextmenu), [FolderContextMenu](#foldercontextmenu), [Sidebar rows](#sidebar-rows), [OfflineStatusBadge](#offlinestatusbadge)
5. [Trips](#trips-components): [TripCard](#tripcard), [TemplateRow](#templaterow), [TripHeader](#tripheader), [TripOverviewStrip](#tripoverviewstrip), [TripPlanList](#tripplanlist), [DayHeader](#dayheader), [StopRow](#stoprow), [StopNumberBadge](#stopnumberbadge), [DriveRow](#driverow), [OvernightBoundary](#overnightboundary), [SuggestionBanner](#suggestionbanner), [TripRouteMap](#triproutemap), [AddStopPopover](#addstoppopover)
6. [Explore](#explore-components): [ExploreListPanel](#explorelistpanel), [ExploreLocationBanner](#explorelocationbanner), [ExploreRow](#explorerow), [ExploreMapPane](#exploremappane), [ExplorePinView](#explorepinview), [ExploreClusterView](#exploreclusterview), [ExploreLightPanel](#explorelightpanel), [ExploreSuggestions](#exploresuggestions), [SpotImageStrip](#spotimagestrip), [AddSpotBanner](#addspotbanner)
7. [Spot page](#spot-page-components): [SpotHeader](#spotheader), [WhenToGoSection](#whentogosection), [SunTimesLine](#suntimesline), [OutlookStrip](#outlookstrip), [DayWindowsList](#daywindowslist), [WindowRow](#windowrow), [ReasonsGrid](#reasonsgrid), [SignedBar](#signedbar), [ExplainBlock](#explainblock), [LightTimeline](#lighttimeline), [SkyRose](#skyrose), [TimeScrubber](#timescrubber), [FullWidthSegmentedPicker](#fullwidthsegmentedpicker), [HourlyStrip](#hourlystrip), [WindySection](#windysection), [SpotFactsRow](#spotfactsrow), [LookAroundSection](#lookaroundsection)
8. [Locations and Ask](#locations-and-ask-components): [SavedRow](#savedrow), [LocationsMap](#locationsmap), [ExploreAskSection](#exploreasksection)
9. [Settings components](#settings-components): [ProviderStatusRow](#providerstatusrow)
10. [Controls](#controls)
11. [System components](#system-components)
12. [Rules that cut across components](#rules-that-cut-across-components)

---

## Light Index components

### EventScore (the event unit)

- **Type, file:** `EventScore`, `Components/EventScore.swift`. Same file: `TimeStyle`, `BandConfidence`, `ConfidenceMark`. The row-level block that places the unit in measured lanes is `EventLane`, `Explore/ExploreRowLayout.swift` (see [EventLane](#eventlane)).
- **One job:** one light window as one fact: which window, how good, when. It replaces the earlier badge, chip and window-symbol-plus-chip pairs.
- **What it is:** **one rounded rectangle in one continuous fill**, the band's ramp colour (`light/ramp/*`); corner radius `event/cornerRatio` (a quarter of the height), not a capsule. Left: the score as a very large heavy numeral (SF Pro, `.heavy`, monospaced digits, `event/score/*`, cap height about half the unit's height). Right: a column centred vertically, the window's SF Symbol (`LightText.symbol`, `event/symbol/*`) above and the time ("18:09", `event/time/*`, about a third of the numeral, thin or light) below, with `event/stackGap/*` between. Everything is white (`light/rampText/*`). There is no second fill, no tail and no divider. **Why:** owner drawing: "This is what i want for scores app-wide". White on every band fill is at least 4.5:1, in light and dark (`ContrastTests`), which covers the thin time. Sizes are fixed points from tokens, not Dynamic Type.
- **Input:** a `LightWindow` (kind: Morning blue hour, Sunrise, Sunset, Evening blue hour, Night; assessment: scored or unscored) and the spot's time zone (required), `timeStyle` (`start` "18:09", `range` "18:09–18:43"), a variant, `isLoading`, `isTomorrow` (VoiceOver and tooltip only) and `isSelected` (pin only). A second initializer, `EventScore(kind:start:zone:variant:)`, draws the unscored form from a kind and a start alone (the trips list "Next:" line).
- **Variants:**

| Variant | Height | Symbol | Number | Padding (per lane) | Time | Used on |
|---|---|---|---|---|---|---|
| **compact** | 28 (`event/height/compact`), radius 7 | 8 pt | 18 pt heavy (`event/score/compact`) | 6 (`event/paddingCompact`), gap 4 | 8 pt light (`event/time/compact`) | The Add Stop popover rows, the trip overview strip cells, the outlook cells and day list |
| **regular** | 44 (`event/height/regular`), radius 11 | 10 pt | 30 pt heavy | 10 (`event/padding`), gap 6 | 10 pt light | Explore and Locations rows, Ask rows, trip stops, window rows (Light windows) |
| **large** | 64 (`event/height/large`), radius 16 | 14 pt | 44 pt heavy | 14 (`event/paddingLarge`), gap 8 | 15 pt thin | The light panel's header, the spot header, When to go (the module's one strong fact) |
| **pin** | as compact (28), with a pointer | as compact | as compact | as compact | 8 pt light | Map pins (see [ExplorePinView](#explorepinview)) |

  Widths are about 2.2 x height (large 139, regular 97, compact about 66 for a start time). A 100 shrinks (minimum scale 0.6) inside the two-digit numeral lane instead of widening every unit. The `.range` time style shows "05:45–06:20" on one line in the time slot (the unit is wider for it, by the same measured rule) rather than a third stacked row.

  The **pin** variant is the same compact unit with the start time on every pin, selected or not, filled with the band colour like any unit; a small downward pointer (8 wide, 4 high) in the same fill sits below, so the anchor is the bottom tip. An unscored pin is filled with `regularMaterial` (flat `background/content` in snapshots) so the time stays legible over the map. Selection is scale and shadow (see ExplorePinView).
- **Unscored:** same size as the scored unit, no fill, one `stroke/hairline` outline in `separator/default` (a pin keeps its material fill), the window's symbol above the time centred in the unit: symbol in its standalone colour ([WindowSymbol](#windowsymbol): `light/blueHour` for the two blue hours, `text/secondary` otherwise), a mini spinner beside it while that spot's forecast is in flight, the time in `text/primary`. An unscored unit never shows a number, a band or a ring; the screen's [WeatherStatusBanner](#weatherstatusbanner) says why a score is missing.
- **Hairline:** none on scored units (every fill is dark enough to stand on the ground).
- **Low confidence:** the whole unit drops to `event/lowConfidenceOpacity` (0.85). Medium and High are fully opaque. The band word and confidence bars are not drawn anywhere beside the unit (owner: the unit is the whole rating); the VoiceOver label and tooltip still say "Sunrise, 74, Great, high confidence", and [ScoreLegend](#scorelegend) explains the colours and scores. (Formerly [BandConfidence](#bandconfidence) was a separate lane on the spot page.
- **Colour by band** (fill / text, light then dark; values in TOKENS.md): Poor `light/ramp/poor` / `light/rampText/poor`; Fair `fair`; Good `good`; Great `great`; Epic `epic`. Never green, red or coral.
- **Measured widths:** `EventScore.laneWidth(variant)` is the head: left padding + the width of "88" in the heavy numeral font + the gap. `tailWidth(variant, style)` is the stack lane (the wider of 1.25 x symbol size and `timeLaneWidth(style, variant:)`, the widest time the locale and clock format can produce, sampled at :58 past every hour, in the variant's time font) + the right padding. `EventScore.unitWidth(variant, timeStyle:)` is their sum, so every unit of a variant and time style has the same width and stacks align. See [WindowLanes](#windowlanes) and [EventLane](#eventlane).
- **Accessibility:** one element, children ignored. Label: "Sunset, Light Index 87, Great, High confidence, 18:09"; "…, tomorrow at 07:20" when the window is tomorrow's; just the window's name and time when unscored. The same string is the tooltip. A "Today" or "Tomorrow" word printed beside the unit stays outside it.
- **Where it appears, by variant:** see the table. Explore, Locations and Ask rows and trip stops use regular; the Add Stop popover and the trip overview strip cells use compact; the outlook uses compact; the light panel's header, the spot header and When to go use large; map pins use pin.

**Rejected alternatives.** The unit was drawn four ways (render: `Design/event-unit-alternatives.png`). Chosen first: **D refined**, a band-coloured head (symbol and score) plus a quiet tinted tail (the time) in one capsule. Superseded by owner direction ("pill should the same color"): the whole capsule is now one band fill.

- **A: a symbol-and-score chip with the time as a separate trailing label.** Owner: the time floated as a separate column, away from the symbol and score.
- **B: the symbol as a separate glyph in the band colour, beside the chip.** Pale bands (Fair, Poor) make a glyph in the band colour illegible on paper, and it still reads as two things (a symbol, then a number).
- **C: the symbol stacked above the number.** 38 pt tall. It breaks the shared row baselines and the 32 and 48 pt row heights.
- **D as first drawn (a heavy tail).** The time competed with the score for attention. Refined to a tinted tail, then dropped: the unit is one fill with the time lighter in weight than the score, and fixed measured widths keep it compact enough to stack.

### WindowSymbol

- **Type, file:** `WindowSymbol`, `Components/WindowLight.swift` (16 pt, `IterSize.windowSymbol`; the event unit sizes its own symbol: 10, 12 or 20 pt).
- **One job:** name a light window with an SF Symbol instead of a word. Inside the event unit the symbol is drawn by the chip and takes the chip's ramp text colour; on its own (an unscored slot, the trip card's Next line, menu items) it is a `WindowSymbol`.
- **Symbols** (`LightText.symbol(_:)`):

| Window | Symbol |
|---|---|
| Morning blue hour | `sun.haze.fill` |
| Sunrise | `sunrise.fill` |
| Sunset | `sunset.fill` |
| Evening blue hour | `moon.haze.fill` |
| Night | `moon.stars.fill` |

- **Why these.** The earlier blue-hour symbols were the outline `sunrise` and `sunset`: weak copies of the golden pair, which read as "the same thing, thinner". The blue hours now use the haze family, which has no horizon line and no arrow, so neither reads as golden hour. Evening blue hour is `moon.haze.fill` (a crescent over haze: the cool light after the sun is down). Morning blue hour is `sun.haze.fill` (a sun in haze: the light before the sun is up). Both differ from the golden pair at a glance at 10 to 16 pt, which matters inside a chip, where the symbol takes the ramp text colour and the meaning has to come from the silhouette. **Morning and evening blue hour are told apart by the symbol as well as by the time and the order of the list.** This is the owner's decision of 2026-10-07. `LightText.symbol(_:)` is the one mapping; an intent resolves through it (`.blueHour`, which has no time of day, takes the evening symbol).
- **Standalone colour:** outside a chip (an unscored slot, menus, the trip card's Next line) the blue-hour symbols take `light/blueHour` (`#3A4FA0` light, `#8FA4E8` dark, 3:1 or better on paper and on module cards); sunrise, sunset and night take `text/secondary`. A caller can pass another style.
- **Candidates surveyed** at 16 and 24 pt in both appearances (`Design/blue-hour-symbols-survey.png`): `sun.horizon(.fill)`, `sun.and.horizon(.fill)`, `sun.haze(.fill)`, `moon.haze(.fill)`, `sunrise.circle`, `sunset.circle`, `moonrise(.fill)`, `moonset(.fill)`, `cloud.sun`, `light.max`, `sparkles`, `aqi.low`, `sun.min(.fill)`, `sun.lefthalf.filled`, `sun.righthalf.filled`, `moon.stars`, `sun.dust`. The main rejections:
  - `sun.horizon`, `sun.and.horizon`: the sun disc again, which still reads as golden hour.
  - `moonrise`, `moonset`: they mean the moon's own events, which the compass ([SkyRose](#skyrose)) shows.
  - `light.max`: dashes at 16 pt.
  - `sparkles`: Apple Intelligence, and the astro category.
  - `aqi.low`: air quality.
  - `sun.haze`: first rejected as "a risen sun in haze"; the owner chose it on 2026-10-07 for the morning blue hour, where the haze is the light before the sun is up.
  - `cloud.sun`: weather.
  No new twilight symbol exists in the SF Symbols on macOS 27 (`name_availability` lists none after 2023 for this family).
- **Accessibility:** the window's word is the tooltip and the VoiceOver label ("Sunset"). Headings on the spot page and the window rows there keep the word itself.
- **Used on:** [EventScore](#eventscore-the-event-unit) (inside the chip, and alone when unscored), [TripCard](#tripcard) (Next line), the session menu items in [StopRow](#stoprow) and the day items in [AddToTripMenu](#addtotripmenu) (as the item's icon).

### BandConfidence

- **Deprecated.** No module outside the Light windows rows ([WindowLanes](#windowlanes)) still draws it, and those rows are being moved off it; the type, `BandConfidence.laneWidth` and `LayoutLane.standardRowLanes(band:)` stay only until then, then are deleted. The trip stop (Mac and iOS day list), the iOS status band and every list row no longer show a band word or confidence bars.

- **Type, file:** `BandConfidence`, `Components/EventScore.swift`.
- **One job:** the band word and how far to trust it, in the one secondary style.
- **Anatomy:** the band word ("Great", `type/secondary`, `text/secondary`, one line), gap `space/xs`, a [ConfidenceMark](#confidencemark), on one first baseline. Not drawn for an unscored window.
- **Measured lane:** `BandConfidence.laneWidth` is the widest band word in the current language at the secondary size, plus the gap and the mark.
- **Used on:** the band lane of [WindowLanes](#windowlanes) (Light windows) only.

### ConfidenceMark

- **Type, file:** `ConfidenceMark`, `Components/EventScore.swift`.
- **One job:** how far to trust the score, as three ascending bars.
- **Anatomy:** three bars, each 2 pt wide (`stroke/thick`), heights one third, two thirds and full of 14 pt (`size/confidenceMark`), 1 pt gap (`stroke/thin`), corner radius 1; total width 8. Filled bars `text/secondary`, unfilled `separator/default`.
- **States:** low = 1 bar, medium = 2, high = 3.
- **Accessibility:** label "High confidence" (Medium, Low).
- **Used on:** [ReasonsGrid](#reasonsgrid) confidence line, [ScoreLegend](#scorelegend) (the "How sure" row), [BandConfidence](#bandconfidence) (deprecated).

### ScoreLegend

- **Type, file:** `ScoreLegend` and `ScoreLegendPopover`, `Components/ScoreLegend.swift` (shared Mac and iOS). Mac: the "i" button (`info.circle`, borderless, tooltip "What the scores mean") at the bottom of the sidebar opens `ScoreLegendPopover` (340 x 700, scrolls). iOS: Settings row "What the scores mean" (`info.circle`) pushes `ScoreLegendPage` (iPad's Settings sheet is the same screen).
- **One job:** say what the colours and numbers mean, once, so no module has to print a band word.
- **Content, top to bottom:** **Colours and scores**: the five bands worst to best, each a small event-unit swatch (the band's `light/ramp` fill, a white sample score at the band's midpoint in the unit's numeral), the band name (`type/headline`), its score range from `LightBand.scoreRange` (Poor 0–39, Fair 40–57, Good 58–73, Great 74–87, Epic 88–100) and a one-line meaning. **Light windows**: the five window symbols (`LightText.symbol`) with their names. **How sure**: scores further out are less certain: high within about 36 h, medium to about 72 h, low beyond, for daily-summary days and for days carried forward past the forecast; missing fields and three-hourly data lower it a step; low-confidence units are drawn slightly faded; three [ConfidenceMark](#confidencemark) samples. **Source line**: "Light Index modified from <provider> forecast data." (the configured primary provider; none for sample data).
- **Tokens:** `light/ramp/*` and `light/rampText/*`, `type/event/score` with `event/score/compact`, `event/height/compact`, `event/cornerRatio`, `type/headline`, `type/secondary`, `type/moduleTitle`, `text/*`.
- **Tests:** `bandScoreRangesMatchTheThresholds` (IterCoreTests) and `ScoreLegendIOSTests` (the legend lists exactly the engine's bands, in order, with the engine's ranges).

### WindowLanes

- **Type, file:** `WindowLanes`, `Spot/DayWindowsView.swift` (the measured widths); `LayoutLane.standardRowLanes`, `Components/LayoutGridOverlay.swift` (the same lanes as guides).
- **One job:** the lane spec of a window row, so every window row in an open outlook day lines up, and the list matches [HIERARCHY.md](HIERARCHY.md).
- **Lanes, left to right**, gap `grid/lane/gap` (8), all rows on the first text baseline:

| Lane | Holds | Width |
|---|---|---|
| disclosure | a chevron (`type/moduleTitle`, `text/secondary`; rotates 90 degrees when open), or kept blank on rows that cannot expand | 16 (`grid/lane/disclosure`) |
| label | the window's name (`type/headline`, `text/primary`, one line) in page density; the short name in the light panel ("Blue PM", as the timeline labels) | flexible |
| event unit | a regular [EventScore](#eventscore-the-event-unit) with `.range`: symbol, score and time range "07:25–08:01" in one capsule (spinner while loading; neutral head when unscored) | measured (`EventScore.unitWidth(.regular, timeStyle: .range)`) |

- **Row:** minimum height 32 (`grid/row/single`), 8 vertical padding (`space/sm`), 16 horizontal padding (`grid/inset`) so the first lane starts 16 pt from the card edge and the last ends 16 pt from it (the card is `flush`, see [ModuleCard](#modulecard)). Rows are separated by a hairline divider inset to the label lane (16 + 16 + 8 = 40 from the card edge); no divider above the first row. A sub-group label ("Tomorrow") is `type/moduleTitle` in `text/secondary` on the label lane, 16 above and 4 below (8 above the first), and replaces the divider at a group change.
- **Used on:** [WindowRow](#windowrow) and [DayWindowsList](#daywindowslist).

### EventLane

- **Type, file:** `EventLane`, `Explore/ExploreRowLayout.swift`.
- **One job:** the trailing event unit of an Explore or Locations row: one regular capsule (symbol, score, start time) in one fixed-width trailing lane, so units stack and align down the whole list.
- **Anatomy:** a single [EventScore](#eventscore-the-event-unit) of `EventScore.unitWidth(.regular, timeStyle: .start)`. With no window the block stays empty at the same width so the label lane does not move.
- **Accessibility:** one element; label and tooltip as [EventScore](#eventscore-the-event-unit), with "tomorrow at" when the window is tomorrow's.
- **Used on:** [ExploreRow](#explorerow), [SavedRow](#savedrow). Guides: `LayoutLane.eventRow(disclosure:)`.

### LayoutGridOverlay

- **Type, file:** `LayoutGridOverlay`, `Components/LayoutGridOverlay.swift`: the `layoutGrid(lanes:inset:)` view modifier, `LayoutLane`, and the `showsLayoutGrid` environment value (set once at the window root).
- **One job:** let the design be checked against the grid on a live screen. Debug only; it ships off and adds nothing when off.
- **Turned on by:** **Debug ▸ Show Layout Grid** (a toggle, remembered between launches), or the launch argument `-IterShowLayoutGrid YES` (same key; the argument wins). Screenshots use the argument.
- **Draws** (over the view, never taking clicks): the 8 pt grid as hairlines in `debug/grid` at `debug/gridOpacity` (0.12); the two 16 pt inset edges (`grid/inset`) in `debug/grid` at four times that, 1 pt; and each given lane as a band in `debug/lane` at `debug/laneOpacity` (0.18) with hairline edges. A lane is a width and an offset from the leading or trailing edge, taken from the measured widths (`LayoutLane.standardRowLanes`), so what the overlay shows is what the layout uses.
- **Used on:** the Explore list, Locations, the window rows inside an open outlook day.

---

## Honesty and provenance components

### SampleDataLabel

- **Type, file:** `SampleDataLabel`, `Components/SampleDataLabel.swift`.
- **One job:** say that scores come from made-up weather.
- **Variants:**

| Style | Anatomy | Tokens |
|---|---|---|
| **inline** | `flask` icon + "Sample data", plain secondary text | `type/secondary`, `text/secondary` |
| **banner** | A rounded box: `flask` icon (violet), title "Sample data" (`type/captionStrong`), body "Scores use made-up weather. Turn off in the Debug menu." (`type/caption`, `text/secondary`, wraps). Full width, padding `space/sm`, corner `radius/control` (8), fill `background/control`, 1 pt (`stroke/thin`) `status/warning` border. | as shown |

- **States:** shown only in Sample data mode. The banner lives at the bottom of the sidebar; the inline label is used in headers, footers and reasons. See the "once per screen" rule below.
- **Used on:** sidebar (banner), Explore header, Locations footer, Spot page hourly strip and reasons, Settings > Weather (sample data has no provider credit).

### WeatherStatusBanner

- **Type, file:** `WeatherStatusBanner` and `WeatherStatusText`, `Components/WindowLight.swift`; state is `WeatherStatus` (`ok`, `needsKey`, `offline(lastUpdate)`, `failed(reason, lastUpdate)`) from `ForecastCenter`.
- **One job:** the only place the app says weather is missing. Nothing per row, chip or outlook cell says "No forecast".
- **Anatomy:** a full-width strip, padding `space/md` by `space/sm`, fill `background/control`, a divider below. A symbol (`text/secondary`), the message (`type/caption`, `text/primary`, wraps) and, where Settings can help, a small **Settings…** button (opens Settings). Not drawn at all when the status is `ok`.
- **Messages:**

| Status | Symbol | Text | Settings… |
|---|---|---|---|
| needs a key | `key` | "Add a weather key in Settings to see light scores." | yes |
| offline, with a last update | `wifi.slash` | "Weather is offline. Scores are from the last update at 06:29." | no |
| offline, nothing cached | `wifi.slash` | "Weather is offline. Scores appear when it's back." | no |
| failed: Apple Weather not enabled | `exclamationmark.triangle` | "Apple Weather isn't enabled for this build. Choose another source in Settings." | yes |
| failed: key rejected | triangle | "OpenWeather rejected the weather key. Check it in Settings." | yes |
| failed: daily cap | triangle | "Iter's daily limit for OpenWeather is reached." | yes |
| failed: testing key | triangle | "Windy's testing key gives shuffled data, so Iter won't score from it." | yes |
| failed: provider not answering | triangle | "OpenWeather isn't answering." (any other failure: "Weather isn't answering.") | no |

  A failure with a last update adds " Scores are from the last update at 06:29." The provider's name is the one that was chosen; the time is the newest forecast still held, in the Mac's clock style.
- **Rules:** rows keep their last cached score (`ForecastCenter` keeps the last good forecast per spot), or leave the score slot empty. The banner is one per screen.
- **Accessibility:** one combined element.
- **Used on:** Explore (under the list header, above the location banner), Locations (top of the list), Trip builder (above the plan list), Spot page (top of the page).

### WeatherAttributionView

- **Type, file:** `WeatherAttributionView`, `Components/WeatherAttributionView.swift`. Same file: `ForecastSourceInfo` (source, model, fetch time, fallback list) [ForecastSourceLine](#forecastsourceline), [ForecastSourceLines](#forecastsourcelines) and `WeatherDataSources`.
- **One job:** the credit each forecast provider's licence requires, shown only in Settings (2026-10-06, owner's instruction: no attribution on content screens), and Iter's own "modified data" notice. It takes one or more sources and draws one credit per distinct source, gap `space/xxs`, stacked.
- **Anatomy, per provider** (all `type/caption`):

| Source | Credit |
|---|---|
| **Apple Weather** | A row, gap `space/sm`: the Apple Weather mark (14 pt high, `size/icon/small`; dark or light combined mark per appearance; falls back to the service name) and a **Legal attribution** link. Drawn only once attribution info has loaded. |
| **OpenWeather** | One link, "Weather data © OpenWeather" (the licence page URL), or plain text until the URL is known. `text/primary` link. |
| **Windy** | A row, gap `space/xs`: "Contains data from the Windy database" and a **Windy.com** link to `https://www.windy.com`. Windy's terms also require its logo, unscaled and linked to windy.com. **The logo is not shipped yet**, so the text and link stand in (a `TODO(Windy logo)` in the code). |
| **Sample data** | The inline [SampleDataLabel](#sampledatalabel). No provider credit. |

  After the credits, when any source is not Sample data: "Light Index modified from forecast data" (`type/caption`, `text/tertiary`).
- **States:** sample only: the label alone, no modified-data line. Apple Weather chosen but no attribution info and sample off: no Apple row (so a screen with no forecast has an empty footer, and the notice line still appears if the source is not sample). Mixed list (for example OpenWeather and Windy): both credits, one notice.
- **Accessibility:** the Apple mark carries the service name as its label.
- **Used on:** only through `WeatherDataSources`: Settings > Weather, section "Data Sources and Attribution" (below the provider sections), and Settings > About (same block under the data-sources paragraph, heading in `type/caption`, `text/secondary`). It lists every provider (Apple Weather, OpenWeather, Windy, plus the Sample data label when sample is on), then one "Light Index modified from forecast data" line. Removed from Explore, Trip builder, Locations and the Spot page hourly strip. Before any release, revisit: the providers' terms ask for attribution where the data is shown (see docs/DATA-PROVIDERS.md).

### ForecastSourceLine

- **Type, file:** `ForecastSourceLine`, `Components/WeatherAttributionView.swift`.
- **One job:** say which provider (and model) a forecast came from, in words, so a fallback is never hidden.
- **Anatomy:** one line, `type/caption`, `text/secondary`, wraps. Strings: "Windy · GFS · updated 09:00" with a time; "Windy · GFS" without (lists, where each place has its own fetch time); "OpenWeather" and "Apple Weather" when no model is known. A fallback adds the sources that failed: "OpenWeather (Apple Weather unavailable) · updated 09:00". The reason is not claimed beyond "unavailable".
- **Quiet by design:** it is honesty about the data, not legal attribution. No link styling, no logo. **States:** with time (spot page hourly header, light panel, expanded window confidence line); without time (list footers). Never drawn for Sample data in footers.
- **Used on:** Spot page "Hour by hour" header (right of the title), [ExploreLightPanel](#explorelightpanel) (above Show Full Page), every [ForecastSourceLines](#forecastsourcelines). The expanded [ReasonsGrid](#reasonsgrid) uses the same words in its confidence line.

### ForecastSourceLines

- **Type, file:** `ForecastSourceLines` (was ForecastSourceFooter), `Components/WeatherAttributionView.swift`.
- **One job:** the quiet source lines for places that show many forecasts. No attribution.
- **Anatomy:** a column, gap `space/xxs`: one [ForecastSourceLine](#forecastsourceline) (no time) per distinct source, model and fallback among the forecasts loaded for the screen's places, in first-seen order. Sample data gets no line, only its label.
- **States:** forecasts loaded (lines); none loaded (nothing).
- **Used on:** Explore list footer (padding `space/md` by `space/sm`, scored rows only), Trip builder list (last row, only when something is scored, separator hidden), Locations bottom bar (right of "3 spots").

### WindyLink

- **Type, file:** `WindyLink`, `Components/WindyLink.swift`. Not a view: the URLs behind every "open in Windy" control.
- **One job:** open windy.com in the browser at a place. Windy's terms do not allow its map inside other weather apps, so nothing is embedded.
- **Rules:** URL shape `https://www.windy.com/?LAT,LON,ZOOM`; latitude and longitude to three decimal places with a dot, "-0.000" never printed ("36.5786, -118.292" is `36.579,-118.292`); zoom an integer. A single spot uses zoom 9. A map area uses a zoom from the visible latitude span, about log2(360 / span in degrees), rounded and clamped to 3...11 (an invalid span gives 11). `https://www.windy.com` is the target of the "Windy.com" attribution link.
- **Used on:** [WindySection](#windysection) (Open in Windy), the Explore toolbar **Windy** button (map centre and span), the Windy attribution link.

### Weather status text and score notes

- **Type, file:** `WeatherStatusText` (`Components/WindowLight.swift`, the banner strings above) and `LightText.note`, `LightText.sentence`, `Text/LightText.swift`. Strings only. The earlier per-window no-forecast reason sentences and their short forms ("Weather off", "Offline", "Too far ahead", "Passed", "Loading", "Needs key", ...) are gone; the banner carries the reason.
- **One job:** say what weather problem there is (once per screen), and what a provider could not supply for a given score.
- **Score notes**, one `type/footnote`, `text/secondary` line each under the confidence footnote in the expanded [ReasonsGrid](#reasonsgrid): "OpenWeather gives total cloud only, not cloud by height: confidence is one step lower."; "Scored from a daily summary: beyond OpenWeather's 48 hours." (other providers: "... beyond Windy's hourly forecast."); "Beyond the forecast: the last forecast day's weather carried forward." (persistence: the last forecast day's weather carried forward by whole days, confidence forced to Low); "Windy's model steps every three hours; Iter fills the hours between."; "Rain judged from the forecast amount (no probability from Windy)."; "No visibility from this source."
- **Cloud reason sentences** (when the provider gave cloud by height; the plain sentence is used otherwise): "Low cloud 6%: the horizon should be open." / "Low cloud 62% may block the sun at the horizon."; "High cloud 29%, mid 17%, little low cloud: colour likely." (low cloud under 10%) / "High cloud 29%, low cloud 14%: good chance of a lit sky." / "High cloud 80%, low cloud 14%: a thick upper deck mutes the colour." / "High cloud 40%, low cloud 14%: little effect on colour." ("Mid cloud" leads when mid exceeds high). With total cloud only: "Cloud cover suits this window." / "Heavy cloud cover." / "Cloud layers unavailable; judged on total cover." Rain when only an amount is known: "Rain is expected." / "Little or no rain forecast." (with the value in mm/h, for example "0.3 mm/h").
- **Used on:** [WeatherStatusBanner](#weatherstatusbanner), [ReasonsGrid](#reasonsgrid), [ExploreLightPanel](#explorelightpanel) (through the spot sections).

### ProvenanceTag

- **Type, file:** `ProvenanceTag`, `Components/ProvenanceTag.swift`.
- **One job:** where a spot came from, as one more piece of metadata, not a badge.
- **Anatomy:** plain secondary text: `type/secondary`, `text/secondary`. No capsule, no outline, no fill. It sits in the metadata line beside the locality, separated by a middle dot where the line has one ("Big Sur, CA · Added by you"; on headers "Moab, UT · Curated · Landscape").
- **States (text):** Curated, Added by you, Apple Maps. (Ask results use Curated or Apple Maps only.)
- **Used on:** Explore light panel (always), Explore rows (only "Added by you"), Spot header, Locations rows.

### Warning lines

- **Type, file:** `IssueLine` in `Trips/StopRow.swift`; the same pattern is used inline in the Change Dates sheet, the Spot editor (time zone fallback) and Explore's search error.
- **One job:** a warning is violet and always carries an icon.
- **Anatomy:** `exclamationmark.triangle.fill` (or `exclamationmark.triangle`) + text, both `status/warning`, `type/caption` (`type/callout` in Change Dates). Wraps.
- **Wording seen:** "Out of order: this Sunrise is earlier than the previous stop's Sunset"; "No Sunset window on this day at this place"; "Drive doesn't fit: 2 hr, 58 min short"; "N stops will move to Day D, the new last day. You can undo this."; "Couldn't look up this place's time zone, so it's estimated from the map position."; "Couldn't search Apple Maps for “query”."
- **Danger variant:** validation messages in the Spot editor use `status/danger` (raspberry) with `exclamationmark.triangle.fill` at `type/caption`.
- **Used on:** Trip builder rows and drives, Change Dates sheet, Spot editor, Explore header.

---

## Shared components

### AddToTripMenu

- **Type, file:** `AddToTripMenu`, `Components/AddToTripMenu.swift`.
- **One job:** add a spot to a trip day, where the choice of day is a light decision.
- **Anatomy:** a system Menu with the label "Add to Trip" and `plus.circle`. Contents: one submenu per trip; inside, one item per day, "Day 2 · Thu, Oct 8, 2026 · 64" with the sunset symbol as its icon (that day's sunset window at this spot and its score; just the date and the symbol when there is no score); a divider; "New Trip with This Spot" (creates a one-day trip named "Trip to <spot>" starting tomorrow, adds the stop, opens the trip).
- **Style by context:** button style (prominent on the Spot header, bordered in the light panel), or a menu row in context menus.
- **Used on:** Spot header, Explore light panel and context menus, Locations context menu, Ask rows.

### MapStandIn

- **Type, file:** `MapStandIn`, `Components/MapStandIn.swift`; `ExploreMapStandIn` in `Explore/ExploreMapPane.swift`.
- **One job:** snapshots only. A labelled stand-in for a live map.
- **Anatomy:** a `background/control` ground; the same pins at projected positions; for trips, the active day's route as a `route/active` polyline (`stroke/route` 4); pins 28 pt (36 selected), selected `map/pin`, others `map/pinInactive`, each with a `type/caption` label; the label "Map (snapshot stand-in)" at top-left in `text/tertiary`.
- Not part of the product design. Design the real map from [ExploreMapPane](#exploremappane), [TripRouteMap](#triproutemap) and the Map entry under System components.

### SpotEditorSheet

- **Type, file:** `SpotEditorSheet`, `Components/SpotEditorSheet.swift`.
- **One job:** create or edit your own spot.
- **Anatomy and states:** see [Spot editor sheet](SCREENS.md#spot-editor-sheet). Sized to its content, with a 20 pt sheet margin (`space/sheet`) like the other sheets. Title `type/title/section`; map `chart/arcHeight` 168 high, `radius/card`, hairline; pin SF Symbol `mappin` (largest title size) in `accent/primary` with a small shadow, tip at the map centre; fields in a system grouped form; buttons Cancel and Add Spot or Save.
- **Tokens:** `space/sheet`, `space/sm`, `space/xs`, `radius/card`, `stroke/hairline`, `accent/primary`, `status/warning`, `status/danger`, `text/secondary`.
- **Accessibility:** map labelled "Map with the spot's pin at the centre" with the coordinates as its value.
- **Used on:** Explore (create), Spot page and Locations (edit).

### ModuleCard

- **Type, file:** `ModuleCard`, `Spot/SpotLayout.swift` (replaces `SpotCard`).
- **One job:** the one container for every module of the spot page and the light panel, in the macOS Weather idiom: a quiet title, one strong fact, the same padding and radius everywhere.
- **Anatomy:** fill `background/module`, `radius/card` (12, continuous corners), padding 16 (`grid/inset`), **no stroke**. Inside, top to bottom, gap `space/sm` (8): the **title row** at the card's top-left (a leading SF Symbol and the title, gap `space/xs`, `type/moduleTitle`, all `text/secondary`, one line, header trait), with an optional **accessory** at its trailing edge (a control such as the day label and Today button, or the timeline zoom picker; where the two do not fit side by side the accessory drops below the title); then the content.
- **Variants:** **panel density** (`.panel`, in the Explore light panel): no card fill. The title row sits on the column's 16 pt inset and the content runs the column's inset width, so the light timeline gets all the room; only a `flush` list keeps its `background/module` card with `radius/card`, 16 pt in from the column edge. `flush` lets a list inside run edge to edge of the card: the card's horizontal padding is 0, the title row keeps its 16 pt inset, rows carry their own 16 pt inset, and the bottom padding is 8. Used by the two window lists so their lanes measure from the card edge ([WindowLanes](#windowlanes)).
- **Module titles and symbols:** Good to know `info.circle`; Outlook `calendar`; Light through the day `chart.line.uptrend.xyaxis` (it also holds the compass; there is no separate Sun and moon module); Hour by hour `cloud.sun`; Windy `wind`; Look Around `binoculars`.
- **Rules:** one subject and one strong fact per module; no border and no second container inside it (inside a card, grouping is whitespace and hairline dividers inset to the label lane). Spaced `space/xl` (24) apart in both densities.
- **Used on:** the spot page and the Explore light panel ([WhenToGoSection](#whentogosection), [OutlookStrip](#outlookstrip), [LightTimeline](#lighttimeline), [SkyRose](#skyrose), [HourlyStrip](#hourlystrip), [WindySection](#windysection), [SpotFactsRow](#spotfactsrow), [LookAroundSection](#lookaroundsection)).

---

## Shell components

### TripContextMenu

- **Type, file:** `TripContextMenu`, `Sidebar/TripContextMenu.swift`.
- **One job:** act on a trip from the sidebar or a card.
- **Contents:** Open; **Pin Trip** (`pin`) or **Unpin Trip** (`pin.slash`); divider; **Move to Folder ▸** (No Folder, then every top-level trips folder, each followed by its subfolders as "Folder › Subfolder"; the trip's current folder is checked and disabled); **New Folder with Selection**; **Rename** (edits the row in the sidebar); divider; Duplicate (creates "<name> copy" in the same folder, right after the original, and opens it); Share… (a share link to a `.iter` file); divider; Delete Trip (destructive; if it is the selected trip, selects All Trips first). Undoable.
- **Used on:** sidebar trip rows, [TripCard](#tripcard).

### FolderContextMenu

- **Type, file:** `FolderContextMenu`, `Sidebar/TripContextMenu.swift`.
- **One job:** act on a folder row (trips or locations).
- **Contents:** **New Folder Inside** (top-level folders only; folders nest one level), **Rename**, divider, **Delete Folder** (destructive; the folder's trips or locations and subfolders move up a level, nothing else is deleted). Undoable.
- **Used on:** sidebar folder rows.

### Sidebar rows

- **Type, file:** `SidebarTripRow`, `TripsFolderRow`, `FolderLabel`, `RenamableLabel`; `Sidebar/SidebarTripsSection.swift`, `Sidebar/SidebarSupport.swift`. Locations folder rows: `Sidebar/SidebarLocationsSection.swift`.
- **One job:** a trip or a folder in the system sidebar list, with rename and drag and drop. No custom chrome: system sidebar styles and the accent selection.
- **Pinned trip row:** icon `point.topleft.down.to.point.bottomright.curvepath`, the name (one line), then trailing `pin.fill` (`caption2`, `text/secondary`, tooltip "Pinned: kept ready offline", VoiceOver "Pinned") and the [OfflineStatusBadge](#offlinestatusbadge). An unpinned trip row has neither. A pinned trip shows in the pinned group only, not in its folder.
- **Folder row (trips):** a `DisclosureGroup` (system disclosure arrow), label `folder` + name. Clicking the label also opens and closes it. Not selectable. Children: subfolders (also disclosure rows), then the folder's unpinned trips. Open and closed state is remembered per folder.
- **Folder row (locations):** `folder` + name, selectable (opens the folder's Locations screen). A folder with subfolders is a disclosure row and its subfolders sit inside it, each selectable.
- **Inline rename:** while a row is being renamed (from Rename, or right after New Folder), its name is a plain text field, focused with the text ready to replace. Return or leaving the field saves, Esc cancels, an empty name or an unchanged name changes nothing. The row's disclosure group opens first so the row is visible.
- **Drag and drop:** rows are draggable. A row being dragged over highlights with a light accent fill (18% `accent/primary`, `radius/control`). Drop targets: a trips folder (files trips at its end, nests a folder), All Trips (unfiles), a trip row (places the dragged trips before it; a pinned row pins them), a locations folder, All Locations.
- **Used on:** [Shell: sidebar and detail](SCREENS.md#shell-sidebar-and-detail).

### OfflineStatusBadge

- **Type, file:** `OfflineStatusBadge` and `OfflineStatusText`, `Sidebar/OfflineStatusBadge.swift`.
- **One job:** show whether a pinned trip is ready offline. Draws nothing for a trip that is not pinned.
- **Styles:** *row* (sidebar): the glyph alone, tooltip and VoiceOver label are the words. *header* (trip header): glyph then the words in `type/subheadline`, `text/secondary`; the tooltip is the base-map note.
- **States:**

| State | Glyph | Words |
|---|---|---|
| Downloading | a small circular progress (determinate once the total is known, indeterminate before) | "Downloading for offline use, 3 of 9" |
| Ready | `checkmark.circle`, `text/secondary` | "Ready offline" |
| Stale: trip changed | `exclamationmark.arrow.circlepath`, `status/warning` | "Trip changed since download" |
| Stale: forecast old | the same | "Forecast is more than 12 hours old" |
| Stale: incomplete | the same | "Some items didn't download" |
| Failed | `exclamationmark.triangle`, `status/warning` | "Couldn't download for offline use" |

- **Tooltip in the header:** "Pinned trips keep forecasts, drive times, routes and spot images on this Mac. The base map isn't stored: MapKit has no way to download map tiles for offline use."
- **Accessibility:** one element labelled with the words.
- **Used on:** sidebar pinned trip rows, [TripHeader](#tripheader).

---

## Trips components

### TripCard

- **Type, file:** `TripCard` (private), `Trips/TripsHomeView.swift`.
- **One job:** one trip on All Trips, with its next session.
- **Anatomy (top to bottom, gap `space/sm`):** name (`type/title/spot`, up to two lines); date range "Wed 7 – Sat, Oct 10" (`type/subheadline`, `text/primary`) and "4 days · 6 stops" (`type/subheadline`, `text/secondary`); divider; footer (see states). Padding `space/md`; card surface as above (`radius/card`).
- **States (footer):** next session: one line on a first baseline, gap `space/sm`: "Next: Horseshoe Bend" (`type/secondary`, `text/secondary`, one line), then the [WindowSymbol](#windowsymbol) (standalone colour: `light/blueHour` for a blue hour, `text/secondary` otherwise) and "Sunset from 17:25, Wed" (`type/secondary`, `text/secondary`, one line). VoiceOver reads it as one phrase, "Next: Horseshoe Bend · Sunset from 17:25, Wed"; no stops: `plus.circle` (`accent/primary`) and "No stops yet. Open the trip to add the first."; all passed: `checkmark.circle` and "All sessions have passed".
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
- **Offline line:** for a pinned trip, an [OfflineStatusBadge](#offlinestatusbadge) in header style under the dates line.
- **States:** editing (system text-field focus; the snapshot shows the name selected); an empty name reverts on commit.
- **Used on:** Trip builder.

### TripOverviewStrip

- **Type, file:** `TripOverviewStrip`, `Trips/TripDayViews.swift`. Data: `TripOverviewCell` (IterFeatures, `TripDayLayout.swift`).
- **One job:** the whole trip at a glance, and a way to pick a day.
- **Anatomy:** a horizontal row of equal-width buttons (minimum 104 pt, gap `space/xs`), padding `space/lg` by `space/sm`. Each cell (padding `space/sm`, `radius/control`): "Day 2" (`type/captionStrong`) with a `exclamationmark.triangle.fill` mark in `status/warning` at the right when the day has a conflict; "Thu 8" (`type/caption`, `text/secondary`); "2 stops"; the day's best window as one compact [EventScore](#eventscore-the-event-unit) (symbol, score and the start time in the stop's zone, in one capsule), or "No stops". The best window is the highest-scoring session window of the day's stops (the first stop's when nothing is scored).
- **States:** unselected (`background/content`, hairline stroke); selected (`accent/primary` at 14% fill, 2 pt accent stroke). With more days than fit, the row scrolls horizontally.
- **Interaction:** a click selects the day (the list scrolls to it, the map frames it).
- **Accessibility:** each cell is a button labelled "Day 2, Thursday, October 8, 2 stops, Best light: Sunrise at 7:21 AM, 1 conflict", with the selected trait on the selected day.
- **Used on:** Trip builder.

### TripPlanList

- **Type, file:** `TripPlanList`, `Trips/TripPlanList.swift`.
- **One job:** the plan as day containers of stops and drives, with drag and drop.
- **Anatomy:** a system List with selection on `background/window`, separators hidden. Each day is one container drawn with per-row `listRowBackground` (`DayContainerBackground`): rounded top corners on the first row, rounded bottom corners on the last, `background/content` fill, hairline stroke, accent stroke when the day is selected. Rows of a day: [DayHeader](#dayheader), optional [SuggestionBanner](#suggestionbanner), optional conflict line, the timeline ([DriveRow](#driverow) and [StopRow](#stoprow) items), an **Add Stop** row (`plus` icon and text in `accent/primary`, borderless). Between containers: [OvernightBoundary](#overnightboundary). Last row: [ForecastSourceLines](#forecastsourcelines) when something is scored.
- **Drop indicator:** a `stroke/thick` (2 pt) capsule in `accent/primary` at the top of the target row, drive row or day header.
- **Non-selectable rows:** header, banners, conflict line, drives, Add Stop, overnight boundaries, source lines.
- **Scrolling:** choosing a day in the strip or the map switcher scrolls the list to that day's header.

### DayHeader

- **Type, file:** `DayHeaderRow`, `Trips/TripDayViews.swift`.
- **One job:** which day, its light bookends and its load.
- **Anatomy:** the first row of the container, on `background/control`, hairline below. "Day 2" (`type/title/section`) with "Thursday, October 8" (`type/subheadline`, `text/secondary`) beside it; a line with the sunrise and sunset symbols and their times (`type/caption`, `text/secondary`, monospaced digits, in the first stop's zone); "2 stops · 5 hr, 27 min driving" or "No stops yet" (`type/caption`, `text/secondary`).
- **States:** drop target (the whole header accepts a dropped stop and puts it at the end of that day); a click selects the day.
- **Accessibility:** combined, header trait.

### StopRow

- **Type, file:** `StopRowView`, `Trips/StopRow.swift`.
- **One job:** one stop on the day's timeline: the set-up time, the session, the light and the note.
- **Anatomy:** a horizontal row with three columns, padding `space/sm` top and bottom. Left, the time gutter (68 pt): the set-up time in `type/timeSmall` and "Set up" in `type/secondary`, `text/secondary`. Middle, the rail (28 pt): the [StopNumberBadge](#stopnumberbadge) node on a content-coloured disc, with the rail line above and below it, coloured by the drive into and out of the stop. Right, a column (gap `space/xs`):
  1. **Title line:** spot name (`type/headline`, up to two lines; a plain button that opens the spot page) with locality beneath it (`type/secondary`, `text/secondary`); at the right, on one first baseline (gap `space/sm`), the stop's session as a regular [EventScore](#eventscore-the-event-unit) with its start time (no band word or confidence bars). A stop shows its own session on its assigned day, not the "next event" rule of the lists.
  2. **Session line** (`type/caption`, `text/secondary`, one line when it fits): a small pop-up menu (the session picker: closed, it names the session and its time, "Sunset · 17:25–18:00", without the score, which the event unit above it already shows; open, each item has the window's symbol as its icon and reads "Sunset · 17:25–18:00 · 7", the score for that day, so the windows can be compared), "Park 16:40 · 25 min walk-in" (the park time only when the walk-in is known; or "walk-in unknown"), "·", and a link button "20 min set-up" that opens the set-up popover.
  3. **Issue lines** ([Warning lines](#warning-lines)), if any.
  4. **Note field:** plain text field, "Add a note" placeholder, `type/callout`, 1 to 4 lines.
  The old schedule headline ("Leave … · park … · set up by …") is gone: the leave time is in the drive row's gutter, the set-up time in the stop's gutter.
- **States:** default; selected (system list selection, and the map pin follows); scored (event unit by band); unscored (the window's symbol alone with a spinner beside it while the stop's forecast is in flight; the session menu items simply have no score; the screen's weather banner says why); out of order (violet line); window missing (violet line, menu shows "no window this day"); dragging (the row follows the pointer); infeasible incoming drive (shown on the drive row above, not on the stop).
- **Context menu:** Open Spot Page, Open in Maps, Move Up, Move Down, Move to Day ▸, Remove from Trip.
- **Accessibility:** container labelled "Stop 2, Monument Valley"; custom actions Move Up, Move Down, Remove from Trip.
- **Tokens:** `space/sm`, `space/xs`, `type/headline`, `type/timeSmall`, `type/caption`, `type/callout`.
- **Used on:** Trip builder.

### StopNumberBadge

- **Type, file:** `StopNumberBadge`, `Trips/StopRow.swift`.
- **One job:** the stop's number, matching its map pin.
- **Anatomy:** a 22 pt (`size/badge/height`) circle filled with the system `quaternary` fill (about 10 to 15% of the label colour), the number in `type/captionStrong`, `text/primary`, monospaced digits.
- **Accessibility:** hidden (the row's label includes the number).

### DriveRow

- **Type, file:** `DriveRowView`, `Trips/TripTimeline.swift`.
- **One job:** a drive on the day's timeline and whether it fits. Replaces the old connector row; the overnight break is now a separate [OvernightBoundary](#overnightboundary).
- **Anatomy:** the time gutter shows "Leave" with the leave-by time (in the zone of the stop you leave from). On the rail, a `car.fill` node (20 pt disc) with the rail line through it in `route/active` (coral) when the drive fits, `status/warning` (violet) when it does not, `separator/default` while the drive is unknown. Right: "2 hr, 19 min · 101 mi" (`type/caption`, `text/secondary`, monospaced digits), and when the drive is a straight-line estimate "· estimated" (tooltip "Drive time estimated").
- **Variants:** *between stops:* rail through the row. *Drive in:* the first item of a day, for the drive from the previous day's last stop; the rail starts at the car, and a line "From Horseshoe Bend" (`type/caption`, `text/tertiary`) names where it starts.
- **States:** fits; does not fit (violet rail, then "⚠ Drive doesn't fit: 12 hr, 57 min short" in violet on a second line); estimated; loading (no drive text until MapKit answers; a spinner is in the toolbar).
- **Accessibility:** one combined element.
- **Used on:** Trip builder.

### OvernightBoundary

- **Type, file:** `OvernightBoundaryRow`, `Trips/TripDayViews.swift`. Data: `OvernightBoundary` (IterFeatures).
- **One job:** say where you sleep between two day containers.
- **Anatomy:** a hairline rule, `moon.stars` and "Overnight · near Page, AZ" (`type/captionStrong`, `text/secondary`), a hairline rule; vertical padding `space/md`. The place is the locality of the last stop placed on or before the day (its name when it has no locality). It carries no drive information; the drive is the next day's first item.
- **Not selectable, not a drop target.**

### SuggestionBanner

- **Type, file:** `SuggestionBanner`, `Trips/TripPlanList.swift` (drawn inside the day's container).
- **One job:** offer, never apply, a light-first order for one day.
- **Anatomy:** a row on `background/control`, `radius/control` (8), hairline border, padding `space/sm`, small controls: `arrow.up.arrow.down` (`text/secondary`); a two-line block, "Reorder by light: fixes 2 conflicts" (`type/subheadline`) and "Puts the stops in the order their light arrives." (`type/caption`, `text/secondary`); trailing **Dismiss** (borderless) and **Apply** (bordered).
- **States:** one banner per day with a suggestion; disappears on Apply or Dismiss.
- **Used on:** Trip builder.

### TripRouteMap

- **Type, file:** `TripRouteMap`, `Trips/TripRouteMap.swift`.
- **One job:** the route sanity check.
- **Anatomy (live map):** MapKit map filling the right column. **Pins:** numbered circles, 28 pt (`size/mapPin`), 36 pt when selected (`size/mapPinSelected`); in the active day `accent/emphasis` fill with an `accent/onAccent` number; other days `map/pinInactive` fill with a `background/window` number, at 55% opacity; border `background/window` 1 pt (2 pt when selected); number in `type/captionStrong`. **Routes:** the active day's legs as `route/active` 4 pt (`stroke/route`) over a `background/window` casing 7 pt (`stroke/routeCasing`); other days `route/inactive` 3 pt (`stroke/routeInactive`). With no day selected, every day is drawn as the active day. Map style: standard, flat, no points of interest. Straight lines when the road path is unknown. Controls: zoom stepper, compass, scale. **Your location:** with location permission, MapKit's own blue dot (`UserAnnotation`) and a user-location button leading the controls; with a simulated location (`-IterLocation`) a 14 pt `map/userLocation` dot with a 2.5 pt white ring, labelled "Your location (simulated)", and no button. Without permission, neither. **Day switcher:** a capsule on `regularMaterial` with a hairline, centred at the top edge with `space/md` margin, shown on trips of more than one day: `chevron.left`, a menu button "Day 2 · Thu, Oct 8" (All Days, divider, one item per day), `chevron.right`. The arrows step through the days with All Days as one more stop in the loop. It edits the same selected day as the [TripOverviewStrip](#tripoverviewstrip).
- **States:** a stop selected (its day becomes the selected day; the camera frames that day, or recentres on the stop with the zoom kept when the day is already framed); the selected day (its stops are framed unless you have moved the map); fit-to-trip on first appearance, never wider than a 40° span; once you move the map the camera is yours, saved per trip and restored on relaunch, and stop changes refit only while you have not touched it.
- **Accessibility:** label "Route map"; pins "Stop 2, Monument Valley".

### AddStopPopover

- **Type, file:** `AddStopPopover`, `Trips/AddStopPopover.swift`.
- **One job:** add stops to a day, nearest first, each with its score for that day.
- **Anatomy:** popover 480 x 504 pt. Header (padding `space/md`): a search field (28 pt high, `background/control`, `radius/control`, hairline, magnifier, clear button) and "Nearest to <stop> first" (`type/caption`, `text/secondary`). Divider. Plain list of rows: name (`type/body`, one line) + `bookmark.fill` when saved (`type/caption`, `text/secondary`), a detail line "Page, AZ · 25 mi" (`type/caption`, `text/secondary`), then at the right a compact [EventScore](#eventscore-the-event-unit) with its start time and `plus.circle` (`accent/primary`) or `checkmark.circle.fill` (`text/secondary`) once added.
- **States:** empty search result (system search-empty view); added (tick; the row stays); the spot already on that day shows the tick.
- **Accessibility:** rows "Add <name>", value "Added".

---

## Explore components

### ExploreListPanel

- **Type, file:** `ExploreListPanel`, `Explore/ExploreListPanel.swift`.
- **One job:** the reading surface of Explore: count, the weather banner, search status, the search suggestions, the Ask section, the list, the source lines. It is the list column's first state; its second is the [ExploreLightPanel](#explorelightpanel), which takes the column's place (the list stays mounted underneath, hidden, so its scroll position survives).
- **Anatomy:** see [Explore](SCREENS.md#explore). Background `background/content`. Header: "45 places" (`type/secondary`, `text/secondary`), a small spinner while forecasts load, and **one borderless menu button** labelled `line.3.horizontal.decrease.circle` (filled, with a count, when filters are on). The menu: inline picker **Near You Radius** (100, 200, 300, 500 mi; default 300), inline picker **Sort By** (Best Light, Name, Distance, Popularity; Distance by default when Iter knows where you are), submenus **Category** (10 categories), **Known For** (Sunrise, Sunset, Blue hour, Night sky, Midday, Overcast) and **Source** (Curated, Your Spots, Apple Maps), divider, Clear Filters. There is no light choice and no date: the list shows each spot's next sunrise or sunset. Under the header row: a Sample data label when sample weather is on, then the search status. After a divider: the [WeatherStatusBanner](#weatherstatusbanner), then the [ExploreLocationBanner](#explorelocationbanner), then the list. Section headers: `type/moduleTitle`, `text/secondary` (24 above, 8 below), with a count; with a location they read "Near You · Within 300 mi", "Popular", "More Places" (collapsed until opened, or while a search narrows the list) and "Apple Maps"; without one, a single "Spots" section under the location banner. Footer: [ForecastSourceLines](#forecastsourcelines) for the scored rows.
- **Search and Ask:** when the field has text and its chosen action is not already running or shown, the [ExploreSuggestions](#exploresuggestions) sit first in the list (also above the empty state), and a running, failed or finished Ask is the first section: see [ExploreAskSection](#exploreasksection). Rows of that section are left out of the other sections.
- **Forecast fetching:** rows are requested in list order as they appear; a collapsed "More Places" is requested when it is opened. Each row's score slot shows a small spinner until its own forecast is in.
- **States:** list; panel open (the list is hidden and not hit-testable); loading (small spinner); searching; search failed; suggestions shown; Ask running, failed or answered; empty ("No Matching Spots" or "No places found", via ContentUnavailableView, with Clear Filters).
- **Interaction:** a click selects a row and, after `NSEvent.doubleClickInterval`, opens its light panel (a double-click inside that interval opens the spot page instead and cancels the pending open); the arrow keys move the selection and open the panel at once; Return opens the panel; double-click opens the spot page; context menu Open, Save or Unsave (not on your own spots), Add to Trip ▸, divider, Open in Maps, Copy Coordinates.

### ExploreRow

- **Type, file:** `ExploreRowView`, `Explore/ExploreRowView.swift`; lane widths in `ExploreRowLayout`, `Explore/ExploreRowLayout.swift`.
- **One job:** one spot and its next sunrise or sunset, with every row's light on the same grid. A row is only light.
- **Which window:** the next sunrise or sunset event at the spot, in the spot's own local time (`LightEngine.nextEvent`): a window counts until it ends; after today's sunset the next is tomorrow's sunrise; it looks up to 4 days ahead; the polar fallback is the first non-night window not yet over. Blue hours and night are not in the list.
- **Anatomy:** a row of two parts on one first baseline, gap `grid/lane/gap` (8); vertical padding `space/sm` (8), minimum height 48 (`grid/row/double`), because the label lane has two lines. Left, the **label lane** (flexible): the spot name (`type/headline`, `text/primary`, up to two lines, wraps rather than truncates) over one metadata line (`type/secondary`, `text/secondary`): the locality, then, when Iter knows where you are, "· 101 mi" (the distance is never the part cut off), then the [ProvenanceTag](#provenancetag) "Added by you" for your own spots. Gap between the two lines `space/xs`. Right, the **event block** ([EventLane](#eventlane)), two measured lanes separated by 8:

| Lane | Holds | Width |
|---|---|---|
| event unit | a regular [EventScore](#eventscore-the-event-unit) (24 pt, `.start`): symbol, score and the start time (e.g. "19:54") in one band-coloured capsule; unscored: one neutral capsule with the symbol, mini spinner while loading, time still shown; the tooltip says "Tomorrow" when the window is tomorrow's | `EventScore.unitWidth(.regular, timeStyle: .start)` |

  Each width is measured once, so nothing in the column is typed in and all rows line up. No word, band or confidence is drawn in the row; the chip's tooltip and the VoiceOver label carry the window's name and band. Section headers above the rows are `type/moduleTitle` (see [ExploreListPanel](#explorelistpanel)).
- **States:** scored; unscored (the symbol alone in the chip lane, start time still shown); loading (a mini spinner beside the symbol); no window (the light column is blank; a spot with neither sunrise nor sunset ahead); selected (system list selection); hovered (the map pin gets a chip; the row itself has no distinct hover style). The whole row is the click target (a plain row, not a button with its own styling).
- **Interaction:** a click selects the row and, after the double-click interval, opens its [ExploreLightPanel](#explorelightpanel). The arrow keys and Return open the panel at once. Double-click opens the spot page. Rows do not expand.
- **Accessibility:** one element: name, locality, the distance when a location is known, then the window's words, score, band, confidence and start time ("Sunrise, Light Index 68, Good, Medium confidence, starts 07:20").

### ExploreMapPane

- **Type, file:** `ExploreMapPane`, `Explore/ExploreMapPane.swift`.
- **One job:** the map with pin hierarchy, shared selection and Add Spot mode. Nothing else floats over it: the selected place opens in the list column.
- **Anatomy:** a MapKit map (standard, flat, points of interest hidden; zoom stepper, compass, scale), the user's location (with location permission, MapKit's own blue dot (`UserAnnotation`) and a user-location button leading the controls; with a simulated location (`-IterLocation`) a 14 pt `map/userLocation` dot with a 2.5 pt white ring, labelled "Your location (simulated)", and no button. Without permission, neither.), pins as [ExplorePinView](#explorepinview) and, where pins would overlap, [ExploreClusterView](#exploreclusterview) counts, a "New spot" `mappin.circle.fill` (`accent/primary`, title size) at a dropped draft pin; overlay: [AddSpotBanner](#addspotbanner) top, inset `space/md`. **Camera:** [MapCameraPolicy](SCREENS.md#explore) fits the Near You set (else every listed spot), never wider than a 40° span; once you move the map it stays yours, is saved for this screen and restored on relaunch, and a change in the list refits only if you have not touched it; selecting a spot pans to it without zooming out, keeping the pin just inside the edge on every side (no part of the map is covered).
- **Selection:** selecting a pin opens the light panel for it (or switches the open panel to it); clicking empty map clears the selection and the column returns to the list.
- **Items and clustering:** the pane draws `explore.mapItems` and computes nothing in `body`. Items are ordered for drawing: dots, clusters, chips, the hovered pin, then the selected pin on top; by id within each group. Pins that fall in the same cell of a world-fixed grid (about 48 pt at the current zoom, regrouped only when the zoom bucket changes, never by panning) become one cluster; the selected and hovered pins are never clustered, a cell with one pin keeps its normal style, and nothing is clustered before the map's first settle or when the view is narrower than 0.1° of longitude. The chip budget (the best 6 scored pins in view) is spent only on pins that stay individual. A pin's context menu looks its spot up when it opens. The pane reports its size to the model (`setMapViewport`).
- **States:** default; a selection; Add Spot mode (crosshair cursor, pins not clickable); a draft pin placed (the editor sheet is open).

### ExploreClusterView

- **Type, file:** `ExploreClusterView`, `Explore/ExploreClusterView.swift`.
- **One job:** stand for several map pins too close to tell apart, with their count.
- **Anatomy:** a borderless capsule like the pins (minimum `size/badge/height` square, padding `space/xs`): a small dot (`space/sm`, 8 pt) in the best member's `light/ramp` band colour (none when no member is scored), then the count in `type/captionStrong`, `text/primary`, digits monospaced. Fill `regularMaterial` over the map (flat `background/content` in snapshots) and a shadow of `event/pinShadowRadius`, as on a chip pin. No ring or stroke.
- **Behaviour:** clicking zooms the map to fit its members. Not clickable in Add Spot mode.
- **Accessibility:** one button, "N places, zoom in".
- **Used on:** [ExploreMapPane](#exploremappane).

### ExplorePinView

- **Type, file:** `ExplorePinView`, `Explore/ExplorePinView.swift`.
- **One job:** map hierarchy: one selected pin, a few chips, the rest dots.
- **Anatomy and variants:**

| Style | Drawn as |
|---|---|
| **dot** | 12 pt (`space/sm` + `space/xs`) circle filled with the band colour (`light/ramp/*`) with a 0.5 pt `separator/default` ring; with no score, a `background/control` circle with the same ring. |
| **chip** | The `pin` variant of [EventScore](#eventscore-the-event-unit) **with its time**: one compact capsule (20 pt): symbol, score and start time on the band fill (an unscored chip is `regularMaterial`; flat `background/content` in snapshots), with a small downward pointer in the same fill; shadow radius `event/pinShadowRadius` (4). With no window: a dot. |
| **selected** | The same pin **with the start time** (`type/timeSmall`, `text/primary`) after the chip, scaled by `event/pinScaleSelected` (1.15) anchored at the pointer's tip, with a larger shadow (`event/pinShadowRadiusSelected`, 12). With no window, the spot name (`type/captionStrong`) in the same capsule. |

- **Data:** the pin draws the cached `ExplorePin`, which carries only what it shows; `EventScore(pin:zone:isSelected:)` builds the unit from its `ExplorePinLight` (kind, score value, band, confidence, start), so an unrelated forecast leaves the pin equal and undrawn. Overlapping pins merge into an [ExploreClusterView](#exploreclusterview).
- **Selection is scale and shadow**, the Apple Maps idiom: the selected pin grows and lifts. There is no coral (or any) outline and no border on any pin.
- **Rules:** the selected pin always wins; a hovered pin and the best **six** scored spots in view (`pinBudget = 6`, excluding the selected one) are chips; everything else is a dot. The selected pin is drawn on top, then chips, then dots. The window is the same next sunrise or sunset as the list row. Pins are map annotations, so they stay custom.
- **Accessibility:** button trait (and selected trait on the selected pin); label as the list row.

### ExploreLightPanel

- **Type, file:** `ExploreLightPanel`, `Explore/ExploreLightPanel.swift`.
- **One job:** the selected place and its light, in the list column, in place of the list. It opens for a row or a pin selection.
- **Anatomy:** fills the list column (340 to 520 pt wide, the full height), `background/content`, with the [layout grid](#layoutgridoverlay) available over it. Top to bottom:
  1. **Header** (padding `grid/inset` horizontal, `space/sm` vertical), then a divider: **‹ Places** (`chevron.left` and the word, `type/subheadline`, accent, borderless; tooltip "Back to places (Esc)"), a spacer, "3 of 16" (`type/subheadline`, `text/secondary`, monospaced digits; VoiceOver "Place 3 of 16"), and two borderless steppers `chevron.up` and `chevron.down` in `text/secondary` (tooltips "Previous place (Up Arrow)" and "Next place (Down Arrow)"; each disabled at its end of the list).
  2. The [WeatherStatusBanner](#weatherstatusbanner) when weather is missing.
  3. A scroll view, sections `space/xl` apart:
     - **Place header** (16 pt inset, `space/xs` between lines): the name (`type/title/spot`, up to two lines, header trait) and, on its first baseline at the trailing edge, the next window as a large [EventScore](#eventscore-the-event-unit) (44 pt, start time) with "Tomorrow" (`type/secondary`, `text/secondary`) before it when it is tomorrow's; beneath both, one line of locality · distance (only when Iter knows where you are) · [ProvenanceTag](#provenancetag) (`type/secondary`, `text/secondary`). No unit when the spot has no such window.
     - **Image strip** ([SpotImageStrip](#spotimagestrip)), `size/imageStripHeight` (200), edge to edge of the column, `space/lg` below the header.
     - **Spot sections** at panel density, built by one `SpotModel` for the place and the day, in this order: [SpotFactsRow](#spotfactsrow) ("Good to know", with the best window first), [LightTimeline](#lighttimeline) ("Light through the day", with the compass), [OutlookStrip](#outlookstrip) (the days open in place) and [HourlyStrip](#hourlystrip). Windy and Look Around are on the full page only. The hour-by-hour section drops its source line; the actions below carry it.
     - **Actions** (16 pt inset): **Save** / **Saved** (`bookmark`, hidden for your own spots) and [AddToTripMenu](#addtotripmenu) side by side; below them the [ForecastSourceLine](#forecastsourceline) and a link-style **Show Full Page** that opens the spot page for the row's day. (There is no Open button.)
- **States:** scored; unscored (the sections still show sun and moon); loading; no window; saved; your own spot (no Save button); scrolled to the lower half (`-IterPanelScrolled YES`, see TESTING.md); at the narrowest column (340 pt: the timeline's "Drag to read any time" hint is dropped below 350 pt).
- **Behaviour:** the panel takes keyboard focus when it opens. Up and Down step to the previous and next place in list order (`ExploreModel.selectPrevious()` and `selectNext()`; the list scrolls to the row and the pin follows). Esc and **‹ Places** call `closePanel()`: the list returns at the same scroll position with the row still selected and takes the keyboard. Esc is ignored while Add Spot mode is on. The scroll view starts at the top for each place; sections are rebuilt for each place and day. A new or changed search, running a suggestion or an Ask, and clearing the selection also close it. `showsPanel` and `panelPosition` ("3 of 16") live on the model.
- **Transition:** slides in from the trailing edge with a fade (`.snappy`, 0.2 s); none with Reduce Motion.
- **Accessibility:** container labelled "Place panel for Mesa Arch". The back button reads "Back to places"; the steppers "Previous place" and "Next place"; the place header's unit reads as the list row does.
- **Tokens:** `size/imageStripHeight`, `layout/listColumnMin`, `layout/listMax`, `grid/inset`, `space/xl`, `space/lg`; the timeline's sizes are `SpotLayout.panelSkyHeight` (88) and `panelPlotHeight` (112).

### ExploreSuggestions

- **Type, file:** `ExploreSuggestionsView` and `ExploreSuggestionRow`, `Explore/ExploreAskSection.swift`; the ranking is `SearchSuggestions.make(query:askAvailability:)` in `IterFeatures` (using `SearchIntent.classify`); words in `Explore/AskText.swift`.
- **One job:** one search field for places and requests: offer both ways of running the text, the likelier one first.
- **Anatomy:** a vertical stack at the top of the list (and above the empty state), `space/sm` between groups, `space/xs` vertical padding. Each group: a header (`type/moduleTitle`, `text/secondary`, header trait) over one row. A row is a plain button, `space/md` between its parts, `space/xs` vertical padding, the whole width the target: a symbol in a `size/iconSmall` column (`sparkles` for Ask Iter, `magnifyingglass` for Apple Maps; accent, or `text/secondary` when disabled), the title (`type/bodyEmphasis`, up to two lines) with an optional second line (`type/caption`, `text/secondary`), and at the trailing edge, on the top suggestion only, a `return` glyph (`type/caption`, `text/secondary`; tooltip "Press Return").
- **Groups and titles:** **Apple Maps**: "Search Apple Maps for “text”". **Ask Iter**: "Ask Iter: text", second line "Find real places that fit, with a note on why".
- **Ranking:** text that reads like a request (`SearchIntent.classify` returns `.ask`) puts Ask Iter first; anything else puts Apple Maps first. Empty or blank text offers nothing. Return in the search field runs the top suggestion.
- **States:** place-like text (Apple Maps first); request-like text (Ask Iter first); Ask unavailable (the row stays, disabled, title and symbol in secondary colour, second line the reason: "Ask Iter isn't available: Apple Intelligence is off", "…this Mac can't run Apple Intelligence", "…Apple Intelligence is still downloading", or "Ask Iter isn't available right now"; never the top suggestion, so Return always does something, and no return glyph on it); gone once the chosen Apple Maps search is running or done for that text, or an Ask is running or shown for it.
- **Accessibility:** each row is one button: "Search Apple Maps for text" or "Ask Iter: text" (for a disabled Ask: "Ask Iter: text, unavailable. <reason>"); the top row's hint is "Runs when you press Return"; the group titles are headers.
- **Used on:** [ExploreListPanel](#explorelistpanel).

### SpotImageStrip

- **Type, file:** `SpotImageStrip` and `SpotImages`, `Components/SpotImageStrip.swift`; provider `SpotImageryProviding` (`SpotImagery.swift`) and `MapKitSpotImagery` in `Packages/IterKit/Sources/IterServices/Maps/`.
- **One job:** show what the place looks like, honestly labelled.
- **Anatomy:** a fixed `size/imageStripHeight` (200) strip as wide as its column (the light panel's, 340 to 520 pt), clipped, paging horizontally. Images are requested and cached at `layout/imageRequestWidth` (360 pt) by 200, also for the offline pack. Each page is one image filling the strip with a source label top-leading, `grid/inset` in from the corner (a `regularMaterial` capsule, `type/captionStrong`): **Look Around** (Apple's street-level snapshot, only where Apple has imagery) or **Satellite** (a hybrid satellite snapshot with a dot at the spot). Look Around comes first when it exists. With more than one image: a dot indicator bottom-centre (capsule, material), and on hover previous and next chevrons (`size/hitTarget`, material circles) because a mouse has no swipe.
- **States:** loading (placeholder with a small spinner); one image (no dots, no chevrons); several; placeholder when there are none (a calm `background/control` surface with the spot's category symbol in `text/tertiary`).
- **Imagery and caching:** images are cached in memory and on disk, keyed by spot id, source, pixel size and the coordinate at 5 decimal places, so a moved spot refetches. Offscreen snapshots read the cache only. Coverage in the curated set was measured on 2026-10-06: Look Around exists for 4 of 45 (`tunnel-view`, `valley-view`, `bixby-bridge`, `golden-gate-battery-spencer`); the other 41 show the satellite image only.
- **Built for photos:** the strip draws a list of `SpotImage`s. User photos will be one more source (a case on `SpotImageSource`, the provider returning the spot's own photos first, and the two label strings); nothing else changes.
- **Accessibility:** each image is labelled ("Look Around view of Bixby Bridge"); the dots read "Image 1 of 2"; chevrons are labelled "Previous image" and "Next image".

### ExploreLocationBanner

- **Type, file:** `ExploreLocationBanner`, `Explore/ExploreLocationBanner.swift`; state in `UserLocationModel`.
- **One job:** say why the list is not sorted by distance and offer the way out, without ever blocking the list.
- **Anatomy:** a strip above the list, padding `space/md` by `space/sm`, `background/control`, a divider below. Prompt states carry a title ("Use your location", `type/subheadline` semibold) over a caption ("Iter uses your location to show spots within 300 miles.") and a small button at the right. Not drawn at all once a location is known.
- **States:** not asked yet (**Use My Location**); denied or restricted (**Open Location Settings**, which opens Location Services in System Settings); finding your location (a small spinner and "Finding your location…"); no fix (a message and **Try Again**).
- **Rules:** without a location the list is one "Spots" section and the sort is not Distance.

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
- **Anatomy:** see [Spot page](SCREENS.md#spot-page). Gap 16 between the groups. **Title group** (gap `space/xs`): name (`type/title/spot`, header trait), then one metadata line (`type/secondary`, `text/secondary`) of locality, [ProvenanceTag](#provenancetag) and category (symbol and name), **separated by middle dots** ("Moab, UT · Curated · Landscape"). **Strong fact:** when the spot has an upcoming window, its next event as a large [EventScore](#eventscore-the-event-unit) (44 pt, start time in the tail) with the relative day ("Today", "Tomorrow") beside it in `type/secondary`. **Action row** spaced `space/sm` (system bordered buttons; Add to Trip is the one prominent button).
- **Variants:** titled buttons, or icon-only when the width is tight. Your own spots: Edit and Delete after a divider, no Save.
- **States:** saved (`bookmark.fill`, "Saved"); not saved; delete confirmation when trips use the spot.

### WhenToGoSection

- **Type, file:** `BestWindowLead` (the lead) and `OutlookSection` (the outlook card), `Spot/WhenToGoView.swift`. The "When to go" module no longer exists: its lead lives in [SpotFactsRow](#spotfactsrow) ("Good to know") and its outlook is its own module ([OutlookStrip](#outlookstrip)).
- **One job (the lead):** answer "when should I be here?" as the first line of Good to know.
- **Lead states:**

| State | Contents |
|---|---|
| Best window | The one strong fact: a large [EventScore](#eventscore-the-event-unit) (`.range`) for the best window, and beside it (page density) or below it (panel density), gap `space/xs`, a text column: "Best sunrise in the next 10 days" (`type/secondary`, `text/secondary`; the number is the days the outlook shows); "Mon, Oct 12, 2026" (`type/headline`; "Today" or "Tomorrow" when relevant); the top factor's sentence (`type/body`); "Updated 09:00" (`type/secondary`). Then **Show this day** (small system button) when the page is on a different day or window. No band word or confidence marks: the unit is the rating. |
| Loading | Small spinner + "Checking the forecast…" (`type/body`, `text/secondary`), then [SunTimesLine](#suntimesline). |
| No score | [SunTimesLine](#suntimesline) alone; the screen's [WeatherStatusBanner](#weatherstatusbanner) says why. |

### SunTimesLine

- **Type, file:** `SunTimesLine`, `Spot/WhenToGoView.swift`.
- **One job:** the always-exact sun times when there is no score.
- **Anatomy:** `sunrise` + "Next sunrise Wed 07:20" and `sunset` + "Next sunset 18:54" (`type/callout`, monospaced digits), gap `space/lg`. Polar: `moon.stars` or `sun.max` with the polar sentence (`type/callout`, `text/secondary`).

### OutlookStrip

- **Type, file:** `OutlookSection` (the card) and `OutlookStrip` (the days), `Spot/WhenToGoView.swift`.
- **One job:** the coming days for the page's intent, fading with confidence, each openable in place to its windows.
- **Anatomy:** a flush [ModuleCard](#modulecard) titled "10-day outlook for Sunrise" (`calendar`; the number is the days shown, at most 10 and never past the provider's horizon, 8 with OpenWeather), then one row per day, **today first** (today is always the first day, even when its windows have passed), hairline dividers inset to the label lane, then the key line "Fainter days are less certain." (`type/secondary`, `text/secondary`, 16 inset). The same vertical list at every density (the page's old row of cells is gone).
- **Day row** (a plain button, minimum 32, `space/sm` vertical, 16 horizontal, centred): disclosure lane 16 with `chevron.right` (rotates 90 degrees when open) | label (`type/headline`, `text/primary`: "Today", "Thu 8"; the **Best** marker in `type/moduleTitle`, `accent/text` after it) | compact [EventScore](#eventscore-the-event-unit) (`.start`; an empty slot of the same size when there is no score, a spinner while loading) | a state word only when there is no chip ("Passed" for today after its headline window is over, "No window"; `type/secondary`, trailing, fixed width). The score range is not on the row; it is in a window's reasons.
- **Open day:** clicking a day opens it in place (`SpotModel.expandedDay`; one at a time, clicking it again closes it, clicking another moves the opening) and selects it, so the timeline, compass and hourly strip follow. Under it, [DayWindowsList](#daywindowslist). The expand uses a short snappy animation and an opacity transition; with Reduce Motion it is instant.
- **States:** closed; open (chevron down; no row fill, the selected window's row carries `selection/fill`); selected and closed (row fill `selection/fill`, for a day chosen elsewhere); best day; confidence fade (medium 80%, low 60%); unscored (empty slot); no window ("No window"); passed (today).
- **Accessibility:** each day is a button, label "Monday, October 12, Sunrise, Light Index 87, Great, Low confidence, Best" (band and confidence stay in speech), value "Expanded" or "Collapsed", hint "Shows this day's light windows", selected trait. Space and Return toggle a focused day.

### DayWindowsList

- **Type, file:** `DayWindowsList`, `Spot/DayWindowsView.swift`. (Replaces DayWindowsSection and its Today and Coming up cards.)
- **One job:** one day's windows in time order, inside the open outlook day.
- **Anatomy:** [WindowRow](#windowrow)s on the [WindowLanes](#windowlanes), nested one disclosure lane (24 pt) so a window's chevron sits under the day's label; no divider under the day row, hairlines between windows inset to the nested label lane. Row lanes are centred vertically against the 44 pt unit. Today lists only the windows that have not ended; any other day, all of them. A day with none shows one `type/secondary` line on the label lane: "No light windows are left today." on today, or the polar-day or polar-night sentence.
- **Reasons and Explain:** a row opens to [ReasonsGrid](#reasonsgrid) and, on the full Mac page, the [ExplainBlock](#explainblock); the page's old Light windows list is gone, so these live only in the open day's rows.

### WindowRow

- **Type, file:** `WindowRow`, `Spot/DayWindowsView.swift`.
- **One job:** one window with its score, expandable to its reasons.
- **Anatomy:** a plain button row on the [WindowLanes](#windowlanes): `chevron.right` in the disclosure lane (kept, but invisible, on a row that cannot expand), the window's name (`type/headline`, `text/primary`, one line; the full name on the page, the short name in the light panel: "Blue AM", "Sunrise", "Sunset", "Blue PM", "Night", as the timeline labels; VoiceOver keeps the full name), the regular [EventScore](#eventscore-the-event-unit) (`.range`, so the time range is inside the unit) (the whole rating; VoiceOver still hears band and confidence). When open, [ReasonsGrid](#reasonsgrid) below, indented to the label lane, 16 below.
- **States:** collapsed; expanded; selected (row fill `selection/fill`, no stroke); unscored (the symbol alone in the chip lane, a spinner beside it while loading; no band; the row does not expand); a row whose day is not the selected one (the day was changed elsewhere): clicking opens that day instead of expanding.
- **Custom, and why:** the whole row is the click target, so it is a plain button, not a bordered control.
- **Accessibility:** combined; label "Sunset, Light Index 87, Great, High confidence, 17:25–18:00"; value "Expanded" or "Collapsed"; hint "Shows why this window scores as it does" (or "Opens this day" for another day's row).

### ReasonsGrid

- **Type, file:** `Reasons` (private), `Spot/DayWindowsView.swift`.
- **One job:** why the score is what it is.
- **Anatomy:** "Why this score" (`type/moduleTitle`, `text/secondary`). A grid, gap `space/md` by `space/sm`, one row per factor: name (`type/bodyEmphasis`: Low cloud, Mid and high cloud, Cloud cover, Clear sky, Rain, Visibility, Moonlight, Dark sky, Wind, Sun direction), measured value (`type/time`, `text/secondary`, right aligned: "29%", "15 mi", "12 mph", "34°"), a [SignedBar](#signedbar), and a sentence (`type/callout`; it names the cloud layers when the provider gave them, see [Weather status text](#weather-status-text-and-score-notes)). Then a confidence line (gap `space/sm`): [ConfidenceMark](#confidencemark), "Low confidence" (`type/secondary`), "· Likely 72–100", then the source and time ("· Windy · GFS · updated 09:00", `text/secondary`; for sample data the Sample data label), with a fallback named as in [ForecastSourceLine](#forecastsourceline). Then a footnote (`type/footnote`, `text/secondary`): the confidence meaning plus "Forecast is about 6 days ahead of this window." Then one footnote line per score note (see [Weather status text and score notes](#weather-status-text-and-score-notes)). Then [ExplainBlock](#explainblock).

### SignedBar

- **Type, file:** `SignedBar` (private), `Spot/DayWindowsView.swift`.
- **One job:** a factor's points, right helps and left hurts.
- **Anatomy:** a 1 pt (`stroke/thin`) centre line 14 pt high in `separator/default` on a track 2 x (32 + 4) = 72 pt wide; a bar 8 pt (`space/sm`) high from the centre, length proportional to the points (scale: the largest factor, minimum 10), at least 2 pt long. Colour `text/secondary` for both helps and hurts (direction is the left or right side; colour must not read as good or bad). The signed number ("+21", "−4") at the right (`type/timeSmall`, `text/secondary`, 28 pt wide), so colour is never the only cue.
- **Accessibility:** hidden; the row label says helps or hurts and the points.

### ExplainBlock

- **Type, file:** `ExplainBlock` (private), `Spot/DayWindowsView.swift`.
- **One job:** a plain-language reading of the factors by Apple Intelligence.
- **States:** idle (small **Explain** button with `apple.intelligence`); loading (spinner, "Writing an explanation…", Cancel); done (text `type/callout`, selectable; `apple.intelligence` + "Written by Apple Intelligence from the factors listed above." in `type/caption`, `text/secondary`; **Explain again**); failed (one sentence in `type/callout`, `text/secondary`, plus Explain); unavailable (the block is not drawn).

### LightTimeline

- **Type, file:** `LightTimelineSection` and `TimelineRenderer`, `Spot/LightTimelineView.swift`.
- **One job:** the 24 hours of light: sky by sun altitude, the five windows with scores, cloud by altitude, rain chance, and a scrubber; beneath it the compass ([SkyRose](#skyrose)) for the same day and time.
- **Anatomy** (a [ModuleCard](#modulecard) titled "Light through the day", with the zoom control (a [FullWidthSegmentedPicker](#fullwidthsegmentedpicker), shown when more than one zoom is available) running the full width under the title; order: zoom control, readout, timeline canvas, legend, then the compass block ([SkyRose](#skyrose), `space/xl` minus `space/sm` below the legend); the canvas has left gutter 40 pt (`SpotLayout.gutter`, 5 grid units), right inset 16):
  1. **Readout line:** "07:43 · 44% cloud · 3% rain" (`type/headline`, monospaced), "·" and the window name under the marker (`type/secondary`, `text/secondary`); right, "Hover or drag to read any time" (`type/secondary`, `text/secondary`) when not scrubbing (page density). Min height 22.
  2. **Bracket label tiers** (3 tiers of 16 pt in Full day, 2 in zoomed views): each window gets a bracket over its span and a label "Sunrise 87", "Blue AM 85", "Sunset 56", "Blue PM 54", "Night 30" (short name + score, no score when no forecast), `type/caption` (`type/captionStrong` for the selected window), `text/primary` (`text/secondary` with no score). Labels move up a tier when they would overlap, with a hairline leader. Bracket 4 pt drop, `text/secondary` 1.5 pt; selected 2 pt `accent/primary`.
  3. **Sky band:** 56 pt tall (`chart/timelineHeight`), corner `radius/badge`, a left-to-right gradient coloured by the sun's altitude: below −18° `sky/night`, −18° to −6° night to `sky/blueHour`, −6° to the horizon `sky/blueHour`, across the horizon blueHour to `sky/golden`, up to +6° `sky/golden`, to +14° golden to `sky/day`, then `sky/day`.
  4. **Axis:** 18 pt, ticks 4 pt long in `text/secondary`, hour labels `type/timeSmall` (every 3 hours in Full day, hourly when zoomed), in the spot's time zone.
  5. **Weather plot** (only with a forecast): 80 pt tall, 8 pt below the axis; 0%, 50%, 100% gridlines (`separator/default`, hairline) with labels at the left (`type/timeSmall`, `text/secondary`); cloud layers drawn as overlapping (not stacked) filled areas at 50% opacity with a 1.5 pt top line: `cloud/high`, `cloud/mid`, `cloud/low` (or a single `cloud/mid` "Cloud cover" when the layers are unavailable); rain chance bars (hours at 10% or more, 60% width) in `sky/blueHour`; each window tints the plot with its sky colour at 20% (the selected window with `accent/primary` at 16% added).
  6. **Selected window:** a 2 pt `accent/primary` outline across the sky band and plot, with a `background/window` halo.
  7. **Marker:** a vertical line in `text/primary` through the sky band and plot (dashed 1 pt at rest, solid 1.5 pt while scrubbing) with a `background/window` halo, and an 8 pt knob on the sky band's bottom edge.
  8. **Legend** (below, `type/caption`, `text/secondary`): swatches 12 pt with hairline: High cloud, Mid cloud, Low cloud, Chance of rain. Without hourly weather the legend is absent; while the forecast loads a spinner and "Checking the forecast…" stand in. The screen's banner says why.
  9. **Compass block:** the [SkyRose](#skyrose) content (orientation toggle, the strong fact, the rose, key, readout and [TimeScrubber](#timescrubber)), in the same card and sharing its time.
- **Panel density** (`.panel`, in the [ExploreLightPanel](#explorelightpanel); the module grows with the column, 340 to 520 pt): the canvas runs the column's full inset width with **no label gutter and no right inset**. The sky band is 88 pt (`SpotLayout.panelSkyHeight`) and the weather plot 112 pt (`panelPlotHeight`). The plot's 0, 50 and 100 percent labels sit inside the plot at its leading edge, over the data. The marker's time is a **pill** on the axis (`text/primary` capsule, `radius/badge`, the time in `type/timeSmall` in `background/window`; kept inside the plot's edges); hour labels it would touch are left out, and the first and last labels are pulled inside the edges. The legend items sit `space/sm` apart. The hint reads "Drag to read any time" (not "Hover or drag…"), is shown from a column of 350 pt (`SpotLayout.panelHintMinWidth`) and sits at the legend's trailing end, or at the readout line's trailing edge when the legend has no room and the readout leaves space. Hover or drag reads any time, exactly as on the page.
- **Zoom variants:** Full day (all 24 h, 3 tiers); Sunrise ±2 h and Sunset ±2 h (a four-hour domain, 2 tiers, hourly ticks). The picker is only offered when more than one is available.
- **Interaction:** **hovering** the timeline previews a time (a transient scrub, `SpotModel.scrub`) that ends when the pointer leaves; **dragging** or **clicking** commits the chosen time (`chosenTime`, `commitScrub()`), which stays after the gesture; a click inside a window also selects that window. The rose, the [TimeScrubber](#timescrubber), the timeline marker, the readout and the [HourlyStrip](#hourlystrip)'s highlighted hour all show one time, `SpotModel.markerTime`: the hover scrub, else the chosen time, else the selected window's midpoint, else the day's headline window, else solar noon. Choosing a window or a day clears the chosen time. The rose's drag and the scrubber also set the chosen time.
- **Accessibility:** one adjustable element "Light timeline for Monday, October 12" with the windows and times listed; increment and decrement select the next or previous window.

### SkyRose

- **Type, file:** `SkyRoseContent`, `SkyRoseCanvas` and `RoseRenderer`, `Spot/SkyRoseView.swift`; the data model is `SkyRose` (`IterFeatures/Spot/SkyRose.swift`). Not a card of its own: it is the compass block at the bottom of the [LightTimeline](#lighttimeline) module ("Light through the day").
- **One job:** where the sun and moon are, by compass direction and height, at the shared marker time, and whether the sunrise or sunset lands inside the spot's classic view.
- **Anatomy** (top to bottom, `space/md` apart; at page density with room for it the rose sits left and the readout, key and scrubber form a column to its right):
  1. **Orientation toggle:** a [FullWidthSegmentedPicker](#fullwidthsegmentedpicker) "North up" / "View up" (equal segments, full width), shown only when the spot has a classic view direction. The choice is remembered (`iter.skyRose.viewUp`); without a facing the rose is always north up.
  2. **The one strong fact** (`type/headline`, `text/primary`): "Sun rises at 96° E, inside your view", "Sun sets at 263° W, outside your view by 12°", "Sun sets at 263° W at 18:25" (no classic view), or "The sun doesn't rise on this day" / "The sun doesn't set on this day" (polar). It is about the sunrise when the marker time is before solar noon and about the sunset after it, so it follows the scrubber across noon.
  3. **The rose** (a square canvas, at most 45 grid units, `SpotLayout.roseMaxDiameter`, narrower columns draw it at their width). A top-down sky: the observer at the centre, **altitude as radius** (the horizon on the rim, the zenith at the centre, linear), **azimuth clockwise**, north at the top ("North up") or the classic view direction at the top ("View up", turned by a 0.35 s ease-in-out unless Reduce Motion is on). Layers, bottom to top:
     - **Disc and rim:** `sky/day` at 20% (`SpotLayout.windowTintOpacity`), a 1 pt `stroke/thin` rim in `text/secondary`.
     - **Altitude rings** at 30° and 60° (dashed hairline `separator/default`), labelled "30°" and "60°" (`type/timeSmall`, `text/secondary`, 2 pt halo) at a fixed screen angle of 22.5°, so the labels do not turn with the rose.
     - **Degree ring:** inward ticks every 30° on the rim (longer and `text/secondary` at N, E, S, W; shorter `separator/default` otherwise).
     - **Labels in the outer band** (3 grid units wide, always upright): N, E, S, W (`type/moduleTitle`, `text/primary`), NE, SE, SW, NW (`type/timeSmall`, `text/secondary`) and the 30° degree numbers (30, 60, 120, 150, 210, 240, 300, 330; `type/timeSmall`, `text/secondary`).
     - **Classic view wedge:** the spot's facing ±35° (`SkyRose.viewHalfWidth`) from the centre to the rim, a neutral fill (`text/primary` at 7%) with hairline `text/secondary` edges (no accent colour), and a label inside it: "Classic view" over "100° E", or the short "View 100° E" when two lines do not fit. The label is placed fully inside the wedge, clear of the markers, ring labels and event marks, and on the least path crossing. Absent when the facing is unknown.
     - **Paths:** the sun's path `map/sun` and the moon's path `light/blueHour`, each 2 pt round, the moon under the sun, drawn only where the body is above the horizon (below-horizon stretches are not drawn).
     - **Sight lines:** a hairline from the observer to each body above the horizon, in its colour at 40%.
     - **Event marks and labels:** a 6 pt dot in the body's colour on the rim at sunrise, sunset, moonrise and moonset, and on the path at solar noon, each with a label of symbol (`sunrise.fill`, `sun.max.fill`, `sunset.fill`, `moonrise.fill`, `moonset.fill`, 12 pt, in the body's colour), time ("07:20", `type/timeSmall`, `text/primary`) and, on a second line, the azimuth ("96° E") or, for solar noon, the height ("52° up") in `text/secondary`. Labels are placed by collision: the inward side of the mark first, then turned and pushed out, each taking the position with the least path under it and staying inside the rim and clear of the observer dot, markers, ring labels, wedge label and earlier labels (sun first, then moon). Every label and ring or wedge text has a 2 pt halo in the surface colour (`background/module`, or `background/window` in the panel) so it stays legible over a path.
     - **Observer dot:** 4 pt, `text/primary`, at the centre.
     - **Markers at the shared time:** a 14 pt (`chart/arcMarker`) disc in `map/sun` and one in `light/blueHour` with a 1.5 pt surface-colour ring, on the path at the body's azimuth and height. A body below the horizon is a **hollow marker just inside the rim** at its azimuth (surface fill at 80%, a 2 pt ring at 50%), not on the path.
  4. **The key line** (`type/secondary`, `text/secondary`): "Edge: horizon · Centre: overhead".
  5. **Readout** (`type/secondary`): a coloured 8 pt dot, "Sun" and "241° WSW · 12° up" (or "· below the horizon"); a dot, "Moon" and "120° ESE · 35° up · Waxing gibbous, 78% lit".
  6. **[TimeScrubber](#timescrubber)** for the day.
- **Interaction:** dragging on the rose (after 4 pt of travel) picks the time of the **nearest path point within 24 pt** (`SpotLayout.roseHitDistance`, 3 grid units) and commits it as the chosen time; the sun's and moon's markers, the readout, the scrubber thumb, the timeline marker and the hourly strip all move together. Touching empty sky does nothing. See [LightTimeline](#lighttimeline) for what the shared time is.
- **States:** sunrise inside the view (the headline words say so); sunset inside the view; sunset or sunrise missed (outside by N°); "View up" (the wedge points up and the cardinal labels turn around the rim); no classic view (no toggle, no wedge, fact without a view clause, North up only); polar (no sunrise or sunset, a flat sun path or none above the horizon, polar sentence); sun or moon below the horizon at the marker time (hollow marker inside the rim, readout says "below the horizon"); a day with no moonrise or moonset (no moon event marks).
- **Accessibility:** the rose is one element labelled "Sun and moon for Monday, October 12. Sun rises at 96° E, inside your view. Sunrise 07:20, 96° E. Solar noon 12:41, 52° up. Sunset 18:08, 264° W. Classic view faces 100° E." The readout is one element with the spoken value of the scrubber. The orientation picker and scrubber are separate controls. Colour is never the only cue (every mark has symbol, time and bearing). Dragging has the keyboard and VoiceOver equivalent in the [TimeScrubber](#timescrubber).
- **Snapshots:** see the table in [SCREENS.md](SCREENS.md#spot-page) (`skyrose-panel-*`, `skyrose-page-*`, `ios-skyrose-*`).

### TimeScrubber

- **Type, file:** `TimeScrubber`, `Spot/TimeScrubber.swift`.
- **One job:** pick any time of the selected day under the rose, whatever the timeline's zoom; it always spans the whole day.
- **Anatomy** (a canvas, top to bottom):
  1. **Window symbols** row (16 pt, `space/lg`): the symbol of each window (not Night) centred over its stretch of the track, 12 pt (`space/md`), `text/secondary`. Symbols that would touch are spread evenly around the middle of their windows; any that would touch the "Now" mark are left out.
  2. **Track:** a capsule 8 pt high (`SpotLayout.scrubberTrack`, one grid unit) in `separator/default`, inset half a thumb from each edge, clipped to the capsule and tinted with `sky/night` where the sun is below −18° (before dawn and after dusk) and, over it, each window's sky colour (the timeline's window tints).
  3. **Now mark:** when the day is today, a 1.5 pt `text/primary` tick from the symbol row down to the track and the label "Now" (`type/timeSmall`, `text/secondary`) above it, kept inside the edges.
  4. **Thumb:** a disc in `background/window` with a 1.5 pt `text/primary` ring at the shared marker time. 16 pt (2 grid units) on the Mac; 28 pt (`size/hitTarget`) on iOS.
  5. **Hour labels** 8 pt under the thumb: 00:00 (12 AM), 06:00, 12:00, 18:00, 24:00 in the user's clock style (`type/timeSmall`, `text/secondary`), the end labels pulled inside the edges.
- **Sizes and hit area:** Mac, thumb 16 pt, hit area 28 pt high (`size/hitTarget`); iOS, thumb 28 pt, hit area 44 pt (5.5 grid units) high. The whole width is the target: a press or drag anywhere sets the time (a drag has no minimum distance) and commits it.
- **Keyboard:** focusable; ← and → move the time 15 minutes; Shift or Option with an arrow moves 1 hour. The time stays inside the day.
- **Accessibility:** one adjustable element, label "Time of day", value the readout sentence "18:41, golden hour. Sun 263° W, 1° up. Moon 120° ESE, 35° up, waxing gibbous, 78% lit."; increment and decrement move 15 minutes.
- **States:** at rest the thumb sits on the shared marker time (the chosen time, else the selected window's middle, ...); a day with no night span (polar) has no night tint; the Now mark is absent on other days.

### FullWidthSegmentedPicker

- **Type, file:** `FullWidthSegmentedPicker`, `Spot/SegmentedPicker.swift` (private `MacSegmented` on the Mac).
- **One job:** a segmented control of a few exclusive choices, full width, with equal segments (the timeline zoom, the rose's North up / View up).
- **Anatomy:** the system segmented control stretched to its container. On the Mac it is an `NSSegmentedControl` hosted in SwiftUI with `segmentDistribution = .fillEqually`, because SwiftUI's segmented `Picker` keeps its intrinsic width on macOS (`.frame(maxWidth: .infinity)` does not stretch it). On iOS it is the SwiftUI `Picker` with `.pickerStyle(.segmented)`, `.labelsHidden()` and `.frame(maxWidth: .infinity)`, which already fills the width.
- **Custom, and why:** only the hosting; the control itself is the system's, with its native look, focus ring and Dark Mode. No pills, custom backgrounds or `.fixedSize()`.
- **Accessibility:** the control's label is the `label` argument ("Orientation", "Zoom"); the help text is the tooltip on the Mac.

### HourlyStrip

- **Type, file:** `HourlyWeatherSection`, `Spot/HourlyWeatherView.swift`.
- **One job:** the day's weather hour by hour, on the timeline's x-axis.
- **Anatomy:** a [ModuleCard](#modulecard) titled "Hour by hour" (`cloud.sun`); in page density the trailing accessory is the [ForecastSourceLine](#forecastsourceline) with its time ("Windy · GFS · updated 09:00", `type/secondary`, `text/secondary`); the light panel omits it (its footer carries the source line), adds a visibility line (`eye`) and scrolls the strip horizontally instead of fitting it. Inside, a 5-row grid (rows 24 pt, `SpotLayout.hourlyRow`): a multicolour weather symbol (`type/secondary`), then **Temp**, **Cloud**, **Rain**, **Wind** rows in `type/timeSmall`, monospaced digits. Row labels sit in the left gutter (`type/secondary`, `text/secondary`). Rain shows a percent only at 20% or more, in `accent/text`. Temperature follows the Settings unit. Window spans are tinted with their sky colour at 20%, the selected window with `accent/primary` at 16%, the marker hour with `text/primary` at 8%. Under the strip: "Wind in mph" (or km/h; "Rain in mm/h · Wind in mph" when rain is an amount rather than a chance, as with Windy; `type/secondary`, `text/secondary`).
- **States:** with a forecast only. Without one the whole section is absent.
- **Accessibility:** a summary of every third hour ("6 AM: 36°, 43% cloud").

### WindySection

- **Type, file:** `WindySection`, `Spot/WindySectionView.swift`.
- **One job:** hand the user to Windy's map, which Iter may not embed.
- **Anatomy:** a [ModuleCard](#modulecard) titled "Windy" (`wind`) with a row, gap 16: the sentence "Windy's map shows cloud by height, rain and wind around this spot. It opens on windy.com: Windy doesn't allow its map inside other weather apps." (`type/body`, `text/secondary`, wraps), a spacer, and a bordered system **Open in Windy** button (`arrow.up.forward.square`). Tooltip "Open this spot on windy.com in your browser". Opens [WindyLink](#windylink) at the spot, zoom 9. Full page only.
- **States:** always shown, whatever the forecast state; sits after Hour by hour and before Good to know. Not an embedded map and not part of the shared selection.
- **Accessibility:** a container; the button is labelled "Open in Windy".

### SpotFactsRow

- **Type, file:** `SpotFactsSection`, `Spot/SpotFactsView.swift`.
- **One job:** when to be here, and the practical facts.
- **Anatomy:** a [ModuleCard](#modulecard) titled "Good to know" (`info.circle`; the title stays: the best-window line is the first fact). First the [best-window lead](#whentogosection) (`BestWindowLead`, from `page: SpotModel?`; absent until the spot's model is built), then an adaptive grid of facts (min 150 pt per item, gap `space/sm`), each a Label with a `text/secondary` icon and `type/body` text: `figure.walk` "10 min walk-in" (or "Walk-in unknown" in `text/secondary`), `mountain.2` "6,102 ft elevation" (when known; feet or metres by locale), `safari` "Faces 100° E" (or "Facing unknown"), `sun.horizon` "Best at sunrise" (when set), `clock` "Mountain Time · 1 h ahead of you" (only when the spot's zone differs from the Mac's). Then the blurb (`type/body`), and "Notes" (`type/moduleTitle`, `text/secondary`) with the notes (`type/body`).

### LookAroundSection

- **Type, file:** `LookAroundSection`, `Spot/SpotFactsView.swift`.
- **One job:** show Apple's street-level imagery where it exists.
- **Anatomy:** a [ModuleCard](#modulecard) titled "Look Around" (`binoculars`) and a system Look Around preview, 224 pt high, clipped to `radius/control`. Full page only.
- **States:** absent when Apple has no imagery, and in snapshots. The light panel's [SpotImageStrip](#spotimagestrip) shows Look Around too, with a satellite image where Apple has none.

---

## Locations and Ask components

### SavedRow

- **Type, file:** `SavedRow`, `Saved/SavedView.swift` (the file keeps its old name; the screen is `LocationsView`).
- **One job:** a kept spot and its next sunrise or sunset.
- **Anatomy:** a row on the same lanes as [ExploreRow](#explorerow), gap `grid/lane/gap` (8), vertical padding `space/sm`, minimum height 48 (`grid/row/double`): the category symbol in the disclosure lane (16 pt column, `text/secondary`, hidden from VoiceOver); the label lane: name (`type/headline`, one line) over one metadata line (`type/secondary`, `text/secondary`): the locality (or the category if there is none), a middle dot and the [ProvenanceTag](#provenancetag) ("Lone Pine, CA · Added by you"); then the [EventLane](#eventlane): a regular [EventScore](#eventscore-the-event-unit) with the window's start time, in the spot's own zone. The window comes from `AppModel.savedEvent(for:)`, the same call the map pin uses, and is the spot's next sunrise or sunset by the same rule as [ExploreRow](#explorerow); its tooltip and VoiceOver label say "Tomorrow" when it is tomorrow's.
- **States:** scored; unscored (the symbol alone in the chip lane); loading (a mini spinner beside the symbol); tomorrow's window; selected; dragging (the row can be dragged onto a sidebar location folder).
- **Accessibility:** one combined element.
- **Used on:** Locations.

### LocationsMap

- **Type, file:** `LocationsMap`, `Locations/LocationsMap.swift`.
- **One job:** show the listed locations on a map beside the list.
- **Anatomy:** a MapKit map (standard, flat, points of interest hidden; zoom stepper, compass, scale) clipped to its pane, with one annotation per listed spot, drawn as the event unit's `pin` variant exactly as [ExplorePinView](#explorepinview) draws a chip: symbol, score and start time on the band fill, a pointer below, `regularMaterial` when unscored. The window is the same as the row's (`AppModel.savedEvent(for:)`). A spot with no window is a small `background/control` dot with a hairline ring; selected pins are scaled by `event/pinScaleSelected` with a larger shadow and drawn last, so they sit on top (a selected spot with no window shows its name in a capsule). No outline on any pin. Framed to fit the listed spots (padding 0.4, at least 0.2 degrees across) when it first draws and whenever the listed spots change. No location dot.
- **States:** one or several selected (shared with the list; a click on a pin selects its row, a click on empty map clears the selection); no spots (the screen shows its empty state instead). Snapshots draw a [MapStandIn](#mapstandin) with the same event-unit pins (`snapshots/locations-map-selected-*`).
- **Used on:** Locations.

### ExploreAskSection

- **Type, file:** `ExploreAskSection`, `ExploreAskRow`; `Explore/ExploreAskSection.swift`. Words in `Explore/AskText.swift`.
- **One job:** put a request to Apple Intelligence from Explore's list and show what comes back, with every state honest.
- **Starting an Ask:** from the Ask Iter row of the [ExploreSuggestions](#exploresuggestions) (Return when it is first, or a click), or `-IterAsk`. There is no toggle, no Ask mode and no menu item.
- **Section (`ExploreAskSection`):** a list section, first. Header: `sparkles` + "Ask Iter" (`type/captionStrong`), the result count at the trailing edge once there are results, and the request in quotes under it (`type/caption`, two lines at most).
  - *Running:* a small spinner, the stage (`type/bodyEmphasis`: "Understanding your request", "Searching near <place>" or "Searching for places", "Checking the drive to <place>" or "Checking the drive", "Choosing the best matches"), then "Step 2 of 4 · 0:14" (`type/caption`, `text/secondary`, monospaced digits), and after 10 seconds "Still working. A request can take up to a minute."; a small **Cancel** button at the trailing edge (tooltip "Stop looking"). The elapsed time ticks once a second.
  - *Results:* the [ExploreAskRow](#exploreaskrow)s, then the source caption (`type/caption`, `text/tertiary`): "Places come from Apple Maps and Iter's curated list. Iter checks every place exists; the notes are written by Apple Intelligence."
  - *Failed or unavailable:* a notice: symbol and title (`type/bodyEmphasis`), detail (`type/caption`, `text/secondary`), then small buttons: **Search Apple Maps Instead** (prominent; drops the Ask and searches Apple Maps for the same text), **Try Again** (not for unavailable states) and, when Apple Intelligence is off, **Open System Settings**. Titles: "Nothing matched", "Ask Iter can't help with that request", "That request is too long", "Ask Iter doesn't support that language", "Ask Iter couldn't finish", "Apple Intelligence is turned off", "This Mac can't run Apple Intelligence", "Apple Intelligence is still downloading", "Ask Iter isn't available right now".
- **States:** running; failed; unavailable; results.
- **Accessibility:** the header reads as one element; a failure is one container; each Ask row is one element: the row's words, the drive, then "Note from Apple Intelligence: <note>".
- **Used on:** [ExploreListPanel](#explorelistpanel).

#### ExploreAskRow

- A normal [ExploreRow](#explorerow), then, gap `space/xxs`, `car` + "1 hr, 30 min drive" (`type/caption`, `text/secondary`; only when the scout checked a drive), then the note when there is one: `sparkles` and the text in `type/callout`, `text/secondary`, wrapping, with the tooltip "Note from Apple Intelligence". Bottom padding `space/xs`. The row selects, hovers and opens the spot page like any Explore row.

---

## Settings components

### ProviderStatusRow

- **Type, file:** `WeatherProviderSection` and `WeatherSettingsText`, `Settings/WeatherSettingsPane.swift`.
- **One job:** one forecast provider's state in Settings > Weather, with its key and allowance.
- **Anatomy:** a grouped-form section headed by the provider's name: description (`type/caption`, `text/secondary`), the status row (icon, text, trailing button), the key row, Windy's Key type and Model pop-ups, the **Calls today** stepper and a **Get a key** link. Full layout and strings in [SCREENS.md](SCREENS.md#settings).
- **Status line:**

| Status | Text | Icon | Button |
|---|---|---|---|
| Working | "Working · last update 19:40" | `checkmark.circle.fill`, `text/secondary` | Check |
| Needs a key | "Needs an API key" | `key`, `status/warning` | none |
| Not enabled | "Not enabled for this build" | `exclamationmark.triangle.fill`, `status/warning` | Check Again |
| Testing key | "Testing key: Windy's data is shuffled, so Iter won't score from it" | triangle, `status/warning` | Check |
| Key rejected | "Key rejected" | `xmark.octagon.fill`, `status/warning` | Check Again |
| Daily cap | "Daily cap reached (800 of 800)" | `gauge.with.dots.needle.100percent`, `status/warning` | Check Again |
| Failed | "Couldn't reach OpenWeather" (the provider's name), then the technical detail under it (`type/caption`, selectable) | triangle, `status/warning` | Check Again |
| Not checked | "Not checked yet" | `circle.dashed`, `text/secondary` | Check |
| Checking | "Checking…" | small spinner | none |

- **Key row:** secure field (label "API key", prompt "Paste your key", or "Saved in Keychain. Paste to replace") + **Save** (disabled while empty; Return also saves) + destructive **Remove** once a key exists. A key from the environment or a launch argument replaces the field with a read-only value: "From environment (ITER_WINDY_KEY)" or "From launch argument". Keychain errors: "Couldn't save the key to your Keychain." / "Couldn't remove the key from your Keychain." in `status/danger`, `type/caption`. A key is never displayed.
- **Calls today:** a system labelled row "Calls today" with the count ("12", monospaced digits), and below it a `Stepper` whose label carries its value, "Daily cap: 800 calls" (0 to 10,000, step 50), that sets the daily cap. OpenWeather and Windy only.
- **Used on:** Settings > Weather, three times (Apple Weather without key row or calls).

## Controls

Sheets and Settings use **system controls only**. Standard controls are not restyled; Iter configures them and draws nothing around them.

- **Form:** the grouped Form (`.formStyle(.grouped)`), scrolling off in a sheet. Sections and footers are the system's; a footer carries the explanation (for example, why Days is disabled under a template).
- **Date:** a compact `DatePicker` (date only, shown in UTC so the date does not shift).
- **Day count:** a menu `Picker` whose items read as inflected text ("1 day", "3 days"), not a stepper, because the range is small and the value is the label.
- **Value that is a number you nudge:** a `Stepper` **whose label carries its value** ("Set-up time before a window: 20 min", "Daily cap: 800 calls", "Set up 20 min before the window"), so the value is never a separate, unlabelled number.
- **Choices:** menu `Picker`s ("Start from", Temperature, forecast sources), `Toggle`s, a secure field for keys, system `TextField`s.
- **Buttons:** the system **Cancel** (`.cancelAction`, Esc) and the system default button (`.defaultAction`, Return; the accent-filled default). No custom button styles in a sheet or in Settings.
- **Tint:** `.tint(nil)` at the sheet root, so the app-wide coral tint does not paint the neutral buttons and pickers; the default button keeps the system's own default-button look.
- **Margin:** a sheet is sized to its content, with a 20 pt margin (`space/sheet`) around it.

**What stays custom, and why:**

| Custom | Why |
|---|---|
| The event unit ([EventScore](#eventscore-the-event-unit)) | The product's one fact: symbol, score and time as one band-coloured capsule. No system control draws it. It is the one deliberate custom chip. |
| Map pins ([ExplorePinView](#explorepinview), trip route pins) | They are map annotations: positioned, scaled and layered by the map. |
| The outlook "Best" capsule | It is data (it marks the best day), not a control. |
| Image-strip overlay captions and dots ([SpotImageStrip](#spotimagestrip)) | Materials over imagery; the system has no equivalent. |
| Row-sized plain buttons where the whole row is the target (Explore and Locations rows, window rows, outlook cells, stop rows) | The row is the control: a bordered button inside a list row would be a second, smaller target for the same action. |

---

## System components

Iter relies on these system controls. Do not restyle them in the design; use the macOS 26 versions. Notes say how Iter configures them.

| System component | How Iter uses it |
|---|---|
| **NavigationSplitView** with a **sidebar** List | `.listStyle(.sidebar)`; three sections ("Trips": All Trips, pinned trips, trip folders as disclosure groups, unfiled trips; "Locations": All Locations and location folders; "Find": Explore), selection bound to the window's navigation; sidebar width 200 / 240 / 320 pt; the Sample data banner is a bottom safe-area inset; a "New" menu button (New Trip, New Folder, New Location). See [Sidebar rows](#sidebar-rows). Detail column is a NavigationStack per section. |
| **List** | Explore (inset, sectioned, selection and context menu with primary action), Trip builder (inset, selection, drag and drop, section headers), Locations (inset, multi-selection, drag), Add Stop popover (plain). Selection in a system list is the system accent fill, with the text falling back to the system's colours; custom surfaces use `selection/fill` with an `accent/primary` stroke. |
| **HSplitView** | Explore (list, map), Trip builder (plan, map): draggable native divider. |
| **Toolbar** | Unified title bar. Items per screen are listed in SCREENS.md. Window title is the section name; the trip builder replaces the title with the editable name. |
| **searchable** (toolbar search field) | Explore ("Search places or ask Iter": one field, with [ExploreSuggestions](#exploresuggestions) in the list), Locations ("Search locations"). |
| **ContentUnavailableView** | Empty and error states: large grey symbol, bold title, grey description, 0 to 2 action buttons. Used for Trip Not Found, Explore empty, Locations empty, filter-empty and search-empty. |
| **Map** (MapKit) | Explore: standard style, flat elevation, points of interest hidden, controls zoom stepper, compass, scale, custom annotations, selection. Trip route: polylines and numbered annotations. Spot editor: a small map with pan and zoom, the pin fixed at the centre. Scout: accent-tinted markers with category symbols. |
| **LookAroundPreview** | Spot page, 224 pt high, `radius/card` clip; only when a scene exists. |
| **Picker** | Segmented (intent on the Spot page, timeline zoom); menu (session menu, Settings pickers, Category in the editor); inline in menus (Near You Radius and Sort By in the Explore list header menu). |
| **Menu** | Add to Trip, Explore list header menu (radius, sort, filters), Locations Sort and Filter, Trip Actions, context menus. |
| **ShareLink** | Trip (toolbar and context menu; shares a `.iter` document), Spot (header; shares an Apple Maps link and a coordinate message). |
| **DatePicker, Picker, Stepper, TextField, Toggle** | Forms (grouped style) in the sheets and Settings, in their default styles (see [Controls](#controls)); the Explore Add Spot control is a button-style Toggle. |
| **Sheet, popover, confirmationDialog, alert, fileImporter, fileExporter** | As listed in SCREENS.md. |
| **TabView** | Settings (four tabs). |
| **Materials** | `regularMaterial` for the Add Spot banner, the cluster and unscored pins and the image strip's labels; `bar` for the Locations footer. Flat colours in snapshots. |
| **ProgressView** | Small circular spinners next to loading text; none large; Ask's running row uses a small one. |
| **Buttons** | Prominent (accent fill, `accent/onAccent` text) for the single primary action of a view; bordered for secondary; borderless or link for inline actions; plain for tappable cards and rows. |

---

## Rules that cut across components

1. **Every score is paired with its window, inside one unit.** A number is never alone: the window's symbol sits inside the unit with the score and the time ([EventScore](#eventscore-the-event-unit): list rows, pins, the card header, trip stops, Locations and Ask rows, the overview strip, the Add Stop rows), with the word as tooltip and VoiceOver label; the Add to Trip menu items carry the symbol as their icon; the spot page's window rows name the window in the label lane. Outlook cells inherit the window from context (the outlook title "8-day outlook for Sunrise").
2. **No weather is one banner, never a number, never a low score.** The only no-data situations (no key, offline, provider error) show one [WeatherStatusBanner](#weatherstatusbanner) at the top of the screen. Rows keep their last cached score or leave the score slot empty (a small spinner while the forecast is in flight). Nothing per row says "No forecast"; there is no dashed ring. Beyond the provider's forecast a window is still scored, by persistence, at Low confidence. Sun and moon times stay exact and visible.
3. **The unit is the whole rating; the legend explains it.** No module prints the band word ("Good", "Great") beside the unit; [ScoreLegend](#scorelegend) (the sidebar "i", iOS Settings) says what each colour and score range means, and the VoiceOver label and tooltip always name the band and confidence. The ramp appears only inside the event unit and the pin dot. Poor and Fair chips carry a hairline, because those fills are too pale to reach 3:1 on the window.
4. **Coral is used with restraint.** `accent/primary` is the one thing that acts or is selected, `route/active` the route, `map/pin` the pins and `map/sun` the sun. Never a score, a status, an error or a large fill behind text. Small text uses `accent/text`; small text on a coral fill uses `accent/emphasis`. It is never "good".
5. **A warning is violet (`status/warning`) and always has an icon.** Failure and validation are raspberry (`status/danger`) with an icon and words. Never amber, never coral, never green. Green is not used anywhere.
6. **"Sample data" appears once per screen.** The banner sits in the sidebar; screens that show sample scores carry one inline label; [WeatherAttributionView](#weatherattributionview) shows the label in place of a provider credit (in Settings).
7. **Source wherever weather appears; attribution in Settings.** Each provider's own credit (Apple mark and Legal attribution; "Weather data © OpenWeather"; "Contains data from the Windy database" and Windy.com) plus "Light Index modified from forecast data" now lives only in Settings > Weather and Settings > About (owner's instruction, 2026-10-06; to be revisited before release). Elsewhere a quiet [ForecastSourceLine](#forecastsourceline) names the source. Lists and the spot page also name the source and model in words, and a fallback is always named ("OpenWeather (Apple Weather unavailable)").
8. **Confidence is shown, and low confidence fades.** Low-confidence units at 85% opacity; ranges ("Likely 72–100") for days four and later; outlook cells fade to 80% and 60%.
9. **Times are the spot's own and monospaced; units follow the Mac and Settings.**
10. **System chrome stays system.** The sidebar, toolbar, Settings, sheets and standard controls (see [Controls](#controls)) keep the system's materials and colours and take coral only through the app accent. What the app draws itself uses First Light paper and ink (`text/*`, `background/*`), plus the ramp, accent, route, pin, status, sky and cloud colours.
11. **Never reorder or change a plan automatically.** Suggestions are offered, and every edit is undoable.
12. **The model's words are labelled** ("Note from Apple Intelligence", "Written by Apple Intelligence from the factors listed above."). Iter scores the light, not the model.

## Known deviations from the rules (open for the design pass)

Found in the hand-off audit and left for the design work, because each one is a design decision rather than a bug:

1. **Band word in compact places.** Compact units (map pins, Locations, Ask and Add Stop rows), Explore rows and the outlook show the window symbol and the number but not the band word. The VoiceOver label includes the band. This is deliberate: the band shows in the ramp colour and is explained by the [ScoreLegend](#scorelegend); no list prints it (the Light windows rows still did when this was written, and are being moved over).
2. **"Sample data" can appear twice on one screen**, in the header and in the Settings credits (Settings ▸ Weather). The rule says once per screen.
3. **Rain colour.** There is no rain token. The timeline's rain bars use `sky/blueHour`, and the hourly strip's rain figures use `accent/text`. A `weather/rain` token is needed.
4. **Accent on the outlook "Best" tag** (`accent/emphasis`) marks the best day. Accent is for interaction and the route, so this edges toward accent meaning "good".
5. **Serif beyond place names.** `type/title/spot` (New York) is also used for trip names and the empty-state headline.
6. **Literal opacities** in `App/Sources/Spot/SpotLayout.swift` (chart layers) are not tokens yet. (The low-confidence chip opacity is `event/lowConfidenceOpacity`.)
7. **Explore rows have no hover style** (`ExploreRowView.isHovered` is unused); only the pin reacts to hover.
8. **At 960×640 the trip builder's session line truncates** ("25 min wal…").

Fixed in the audit pass: Explore uses the bookmark symbol for Save like every other screen; the Light Index factor bars are neutral (direction shows helps or hurts, not colour); the spot editor's time-zone warning has its icon.
