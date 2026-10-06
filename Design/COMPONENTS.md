# Iter components

Hand-off for rebuilding Iter's components in a design tool. Companion files: [SCREENS.md](SCREENS.md) (every screen and state), [TOKENS.md](TOKENS.md) and `tokens.json`.

## How to read this

- Each component names its Swift type and file (under `App/Sources/`), its one job, its anatomy, variants, states, tokens, accessibility and the screens that use it.
- **Token names** are written the design-tool way: `space/md` is `IterSpace.md`, `light/ramp/good` is `IterColor.ramp(.good)`, `type/headline` is `IterFont.headline`, `size/badge/height` is `IterSize.badgeHeight`, `stroke/hairline` is `IterStroke.hairline`, `radius/card` is `IterRadius.card`. "System" means a system colour, material or control that Iter does not restyle.
- "Compact", "regular" and "large" are the real variant names in the code.
- Text is always in `text/primary` unless a row says otherwise. Every card is `background/control` with a `stroke/hairline` border in `separator/default`.
- Scores are always paired with their window: the window's symbol in compact places (list rows, pins, the card header, trip stops, Saved and Scout rows, the Add to Trip menu), with the word as tooltip and VoiceOver label; the word itself on the spot page and in headings. Bands: Poor, Fair, Good, Great, Epic. Confidence: Low, Medium, High (three bars).

## Contents

1. [Light Index components](#light-index-components): [LightBadge](#lightbadge), [ScoreChip](#scorechip), [WindowSymbol](#windowsymbol), [ConfidenceMark](#confidencemark)
2. [Honesty and provenance](#honesty-and-provenance-components): [SampleDataLabel](#sampledatalabel), [WeatherStatusBanner](#weatherstatusbanner), [WeatherAttributionView](#weatherattributionview) (with ForecastSourceLine, [ForecastSourceLines](#forecastsourcelines) and WeatherDataSources), [WindyLink](#windylink), [ProvenanceTag](#provenancetag), [Warning lines](#warning-lines), [Weather status text and score notes](#weather-status-text-and-score-notes)
3. [Shared](#shared-components): [AddToTripMenu](#addtotripmenu), [MapStandIn](#mapstandin), [SpotEditorSheet](#spoteditorsheet), [SpotCard](#spotcard)
4. [Shell](#shell-components): [TripContextMenu](#tripcontextmenu)
5. [Trips](#trips-components): [TripCard](#tripcard), [TemplateRow](#templaterow), [TripHeader](#tripheader), [TripPlanList](#tripplanlist), [DayHeader](#dayheader), [StopRow](#stoprow), [StopNumberBadge](#stopnumberbadge), [ConnectorRow](#connectorrow), [SuggestionBanner](#suggestionbanner), [TripRouteMap](#triproutemap), [AddStopPopover](#addstoppopover)
6. [Explore](#explore-components): [ExploreListPanel](#explorelistpanel), [ExploreLocationBanner](#explorelocationbanner), [ExploreRow](#explorerow), [ExploreMapPane](#exploremappane), [ExplorePinView](#explorepinview), [ExplorePlaceCard](#exploreplacecard), [SpotImageStrip](#spotimagestrip), [AddSpotBanner](#addspotbanner)
7. [Spot page](#spot-page-components): [SpotHeader](#spotheader), [WhenToGoSection](#whentogosection), [SunTimesLine](#suntimesline), [OutlookStrip](#outlookstrip), [DayWindowsSection](#daywindowssection), [WindowRow](#windowrow), [ReasonsGrid](#reasonsgrid), [SignedBar](#signedbar), [ExplainBlock](#explainblock), [LightTimeline](#lighttimeline), [SkyArc](#skyarc), [HourlyStrip](#hourlystrip), [WindySection](#windysection), [SpotFactsRow](#spotfactsrow), [LookAroundSection](#lookaroundsection)
8. [Saved and Scout](#saved-and-scout-components): [SavedRow](#savedrow), [ScoutResultRow](#scoutresultrow), [ScoutProgress](#scoutprogress)
9. [Settings components](#settings-components): [ProviderStatusRow](#providerstatusrow)
10. [System components](#system-components)
11. [Rules that cut across components](#rules-that-cut-across-components)

---

## Light Index components

### LightBadge

- **Type, file:** `LightBadge`, `Components/LightBadge.swift`. Also `WindowLightLine` in the same file (the compact badge and a start time, used by Saved and Scout rows).
- **One job:** show one Light Index window: its [WindowSymbol](#windowsymbol) beside the number, the band word and the confidence. Without a score the score slot is empty, or a small spinner while that spot's forecast is in flight. There is no "no forecast" variant; the screen's [WeatherStatusBanner](#weatherstatusbanner) says why a score is missing.
- **Input:** a `LightWindow` (kind: Morning blue hour, Sunrise, Sunset, Evening blue hour, Night; assessment: scored or unscored) and a style. Options: `showsSource` (add an inline [SampleDataLabel](#sampledatalabel) for sample-weather scores; off for rows and pins), `isLoading` (spinner in an unscored slot), `showsName` (regular only: the window's full name beside its symbol, used in the spot page's window rows).
- **Variants and anatomy:**

| Style | Scored | Unscored |
|---|---|---|
| **compact** | [WindowSymbol](#windowsymbol) (16 pt) + [ScoreChip](#scorechip) compact (18 pt tall, 26 wide). Gap `space/xs`. **No word, no band word, no confidence.** | The symbol and an empty 18 x 18 slot (spinner while loading). |
| **regular** | One line, gap `space/sm`: [WindowSymbol](#windowsymbol) (with `showsName`, followed by the window's full name in `type/bodyEmphasis`, `text/primary`: "Morning blue hour", "Evening blue hour"), [ScoreChip](#scorechip) regular (22 pt tall, min 36 wide), then `type/caption` `text/secondary`: band word, [ConfidenceMark](#confidencemark), optional Sample data. | The symbol (and name) and an empty slot, min 28 wide by 22 tall (spinner while loading). |
| **large** | [ScoreChip](#scorechip) large (64 pt) + block (gap `space/xxs`): headline "Sunset · 87" (`type/headline`), then `type/subheadline` `text/secondary`: band word, and "· Likely 72–100" when the range is not a single value; then a `type/caption` row: ConfidenceMark and "Low confidence" (also Medium, High), optional Sample data. | An empty 64 pt slot (spinner while loading) and the window's name as the headline. |

- **States:** scored (band Poor to Epic, colour from the band); low confidence (chip at 85% opacity); unscored (empty slot); loading (spinner in the slot); sample data (inline label when `showsSource`). An unscored badge never shows a number, a band or a ring.
- **Tokens:** `type/subheadline`, `type/caption`, `type/headline`, `type/bodyEmphasis`, `text/primary`, `text/secondary`, `space/xs`, `space/sm`, `space/md`, `space/xxs`; chip tokens below.
- **Accessibility:** one element (children ignored). Label: "Sunset, Light Index 87, Great, High confidence", or just the window's name when unscored.
- **Used on:** Trip builder stop rows (regular), Spot page lead (large) and window rows (regular with `showsName`), Add Stop rows (compact), pins (symbol and chip, see [ExplorePinView](#explorepinview)), Saved and Scout rows (compact, through `WindowLightLine`). Explore rows and the place card draw the symbol and a [ScoreChip](#scorechip) directly, not a LightBadge.

### ScoreChip

- **Type, file:** `ScoreChip`, `Components/LightBadge.swift`.
- **One job:** the number on its band fill.
- **Anatomy:** the score as text (monospaced digits) on a rounded rectangle filled with the band colour, with a `stroke/hairline` border in `separator/default` (so pale bands show against the window), and a `light/rampText/*` text colour.
- **Sizes:**

| Size | Height | Min width | Type | Corner radius | Horizontal padding |
|---|---|---|---|---|---|
| compact | 18 (`size/badge/heightCompact`) | 18 frame + 2 x 4 padding = 26 built | `type/score/badge` | `radius/badge` (6) | `space/xs` |
| regular | 22 (`size/badge/height`) | 28 (`size/badge/minWidth`) + 2 x 4 padding = 36 built | `type/score/medium` | `radius/badge` | `space/xs` |
| large | 64 (`size/lightRing/large`) | 64 | `type/score/large` | `radius/card` (12) | none |

- **States, by band** (fill / text, light then dark; see TOKENS.md for the values): Poor `light/ramp/poor` / `light/rampText/poor`; Fair `fair`; Good `good`; Great `great`; Epic `epic`. Low confidence: 85% opacity. Never green, red or coral.
- **Used on:** inside every LightBadge, and by itself on the [OutlookStrip](#outlookstrip) cells (regular size, no band word; the band is implied by the colour and the day's caption shows the range).
- **Accessibility:** the parent supplies the label.

### WindowSymbol

- **Type, file:** `WindowSymbol`, `Components/WindowLight.swift` (16 pt, `IterSize.windowSymbol`; 12 pt inside pins).
- **One job:** name a light window in a compact place with an SF Symbol instead of a word.
- **Symbols** (`LightText.symbol(_:)`): `sunrise.fill` sunrise (golden morning), `sunset.fill` sunset (golden evening), `sunrise` (outline) morning blue hour, `sunset` (outline) evening blue hour, `moon.stars.fill` night. The arrow says morning (up) or evening (down); filled is golden hour and outline is blue hour on the same side of the day, so the five read apart at 16 pt without colour.
- **Anatomy:** the symbol, monochrome, `text/secondary` by default (a caller can pass another style).
- **Accessibility:** the window's word is the tooltip and the VoiceOver label ("Sunset"). Headings on the spot page and window rows there keep the word itself.
- **Used on:** [LightBadge](#lightbadge), [ExploreRow](#explorerow), [ExplorePinView](#explorepinview), [ExplorePlaceCard](#exploreplacecard), [StopRow](#stoprow) (and the session menu items), [SavedRow](#savedrow), [ScoutResultRow](#scoutresultrow), [AddToTripMenu](#addtotripmenu).

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
- **Used on:** sidebar (banner), Explore header, Saved footer, Scout results header, Spot page hourly strip and reasons, Settings > Weather (sample data has no provider credit).

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
- **Used on:** Explore (under the list header, above the location banner), Saved (top of the list), Scout (top of the results list), Trip builder (above the plan list), Spot page (top of the page).

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
- **Used on:** only through `WeatherDataSources`: Settings > Weather, section "Data Sources and Attribution" (below the provider sections), and Settings > About (same block under the data-sources paragraph, heading in `type/caption`, `text/secondary`). It lists every provider (Apple Weather, OpenWeather, Windy, plus the Sample data label when sample is on), then one "Light Index modified from forecast data" line. Removed from Explore, Trip builder, Saved, Scout and the Spot page hourly strip. Before any release, revisit: the providers' terms ask for attribution where the data is shown (see docs/DATA-PROVIDERS.md).

### ForecastSourceLine

- **Type, file:** `ForecastSourceLine`, `Components/WeatherAttributionView.swift`.
- **One job:** say which provider (and model) a forecast came from, in words, so a fallback is never hidden.
- **Anatomy:** one line, `type/caption`, `text/secondary`, wraps. Strings: "Windy · GFS · updated 09:00" with a time; "Windy · GFS" without (lists, where each place has its own fetch time); "OpenWeather" and "Apple Weather" when no model is known. A fallback adds the sources that failed: "OpenWeather (Apple Weather unavailable) · updated 09:00". The reason is not claimed beyond "unavailable".
- **Quiet by design:** it is honesty about the data, not legal attribution. No link styling, no logo. **States:** with time (spot page hourly header, place card, expanded window confidence line); without time (list footers). Never drawn for Sample data in footers.
- **Used on:** Spot page "Hour by hour" header (right of the title), [ExplorePlaceCard](#exploreplacecard) (above Show Full Page), every [ForecastSourceLines](#forecastsourcelines). The expanded [ReasonsGrid](#reasonsgrid) uses the same words in its confidence line.

### ForecastSourceLines

- **Type, file:** `ForecastSourceLines` (was ForecastSourceFooter), `Components/WeatherAttributionView.swift`.
- **One job:** the quiet source lines for places that show many forecasts. No attribution.
- **Anatomy:** a column, gap `space/xxs`: one [ForecastSourceLine](#forecastsourceline) (no time) per distinct source, model and fallback among the forecasts loaded for the screen's places, in first-seen order. Sample data gets no line, only its label.
- **States:** forecasts loaded (lines); none loaded (nothing).
- **Used on:** Explore list footer (padding `space/md` by `space/sm`, scored rows only), Trip builder list (last row, only when something is scored, separator hidden), Saved bottom bar (right of "3 spots"), Scout results footer (under the scout source sentence).

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
- **Used on:** [WeatherStatusBanner](#weatherstatusbanner), [ReasonsGrid](#reasonsgrid), [ExplorePlaceCard](#exploreplacecard) (through the spot sections).

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
- **Wording seen:** "Out of order: this Sunrise is earlier than the previous stop's Sunset"; "No Sunset window on this day at this place"; "Drive doesn't fit: 2 hr, 58 min short"; "N stops will move to Day D, the new last day. You can undo this."; "Couldn't look up this place's time zone, so it's estimated from the map position."; "Couldn't search Apple Maps for “query”."
- **Danger variant:** validation messages in the Spot editor use `status/danger` (raspberry) with `exclamationmark.triangle.fill` at `type/caption`.
- **Used on:** Trip builder rows and connectors, Change Dates sheet, Spot editor, Explore header.

---

## Shared components

### AddToTripMenu

- **Type, file:** `AddToTripMenu`, `Components/AddToTripMenu.swift`.
- **One job:** add a spot to a trip day, where the choice of day is a light decision.
- **Anatomy:** a system Menu with the label "Add to Trip" and `plus.circle`. Contents: one submenu per trip; inside, one item per day, "Day 2 · Thu, Oct 8, 2026 · 64" with the sunset symbol as its icon (that day's sunset window at this spot and its score; just the date and the symbol when there is no score); a divider; "New Trip with This Spot" (creates a one-day trip named "Trip to <spot>" starting tomorrow, adds the stop, opens the trip).
- **Style by context:** button style (prominent on the Spot header, bordered on the place card and Scout rows), or a menu row in context menus.
- **Used on:** Spot header, Explore place card and context menus, Saved context menu, Scout rows.

### MapStandIn

- **Type, file:** `MapStandIn`, `Components/MapStandIn.swift`; `ExploreMapStandIn` in `Explore/ExploreMapPane.swift`.
- **One job:** snapshots only. A labelled stand-in for a live map.
- **Anatomy:** a `background/control` ground; the same pins at projected positions; for trips, the active day's route as a `route/active` polyline (`stroke/route` 4); pins 28 pt (36 selected), selected `map/pin`, others `map/pinInactive`, each with a `type/caption` label; the label "Map (snapshot stand-in)" at top-left in `text/tertiary`.
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
- **Anatomy:** a system inset List with selection. The [WeatherStatusBanner](#weatherstatusbanner) sits above the list, not in it. Per day: [DayHeader](#dayheader) as the section header, optional [SuggestionBanner](#suggestionbanner), [ConnectorRow](#connectorrow) + [StopRow](#stoprow) pairs, and an **Add Stop** row (`plus` icon and text in `accent/primary`, borderless). Last row: [ForecastSourceLines](#forecastsourcelines) when something is scored.
- **Drop indicator:** a `stroke/thick` (2 pt) capsule in `accent/primary` at the top of the target row or day.
- **Non-selectable rows:** banners, connectors, Add Stop, source lines.

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
  1. **Title line:** spot name (`type/headline`, up to two lines; a plain button that opens the spot page) with locality beneath it (`type/caption`, `text/secondary`); at the right a [LightBadge](#lightbadge) regular for the stop's session window (its [WindowSymbol](#windowsymbol), the score chip, the band word and confidence). A stop shows its own session on its assigned day, not the "next event" rule of the lists.
  2. **Schedule headline** (`type/bodyEmphasis`, monospaced digits): "Leave 05:54 · park 06:50 · set up by 07:00"; "Leave 03:42 · set up by 07:01" (no "park" when walk-in is unknown or equal); "Set up by 17:05" for the first stop of a trip (no drive). The leave time is in the previous stop's time zone.
  3. **Session line** (`type/caption`, `text/secondary`, one line): a small pop-up menu (the session picker; each item has the window's symbol as its icon and reads like "Sunset · 17:25–18:00 · 7"), "25 min walk-in" (or "walk-in unknown"), "·", and a link button "20 min set-up" that opens the set-up popover.
  4. **Issue lines** ([Warning lines](#warning-lines)), if any.
  5. **Note field:** plain text field, "Add a note" placeholder, `type/callout`, 1 to 4 lines.
- **States:** default; selected (system list selection, and the map pin follows); scored (badge by band); unscored (the score slot is empty, a spinner while the stop's forecast is in flight; the session menu items simply have no score; the screen's weather banner says why); out of order (violet line); window missing (violet line, menu shows "no window this day"); dragging (the row follows the pointer); infeasible incoming drive (shown on the connector above, not on the row).
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
- **Anatomy:** left rail: a 2 pt (`stroke/thick`) by 16 pt (`size/icon/medium`) rounded bar in a 22 pt column, in `route/active` (coral) when the drive fits or `status/warning` (violet) when it does not. Then `car.fill` + "57 min · 41 mi" (`type/caption`, `text/secondary`, monospaced digits). Vertical padding `space/xs`.
- **Variants:** *same-day:* rail then drive text, left aligned. *Overnight:* rail, then `moon.stars` + "Overnight" (`type/captionStrong`, `text/secondary`), a hairline rule filling the width, then the drive text at the right.
- **States:** fits (coral); does not fit (violet rail, then "· ⚠ Drive doesn't fit: 12 hr, 57 min short" in violet with a triangle icon); estimated ("· estimated", tooltip "Drive time estimated"); loading (the drive text is absent until MapKit answers; a spinner is in the toolbar).
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
- **Anatomy (live map):** MapKit map filling the right column. **Pins:** numbered circles, 28 pt (`size/mapPin`), 36 pt when selected (`size/mapPinSelected`); in the active day `accent/emphasis` fill with an `accent/onAccent` number; other days `map/pinInactive` fill with a `background/window` number; border `background/window` 1 pt (2 pt when selected); number in `type/captionStrong`. **Routes:** the active day's legs as `route/active` 4 pt (`stroke/route`) over a `background/window` casing 7 pt (`stroke/routeCasing`); other days `route/inactive` 3 pt (`stroke/routeInactive`). Straight lines when the road path is unknown. Controls: zoom stepper, compass, scale. **Your location:** with location permission, MapKit's own blue dot (`UserAnnotation`) and a user-location button leading the controls; with a simulated location (`-IterLocation`) a 14 pt `map/userLocation` dot with a 2.5 pt white ring, labelled "Your location (simulated)", and no button. Without permission, neither. **Day picker:** not on the map; a system segmented control (up to 5 days; a menu beyond that) in the trip builder toolbar (principal placement), shown only when more than one day has stops. The map takes the chosen day through a binding.
- **States:** a stop selected (the camera recentres on it, zoom kept); the picked day; fit-to-trip on first appearance, never wider than a 40° span; once you move the map the camera is yours, saved per trip and restored on relaunch, and stop changes refit only while you have not touched it.
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
- **One job:** the reading surface of Explore: count, the weather banner, search status, the list, the source lines.
- **Anatomy:** see [Explore](SCREENS.md#explore). Background `background/content`. Header: "45 places" (`type/subheadline`, `text/secondary`), a small spinner while forecasts load, and **one borderless menu button** labelled `line.3.horizontal.decrease.circle` (filled, with a count, when filters are on). The menu: inline picker **Near You Radius** (100, 200, 300, 500 mi; default 300), inline picker **Sort By** (Best Light, Name, Distance, Popularity; Distance by default when Iter knows where you are), submenus **Category** (10 categories), **Known For** (Sunrise, Sunset, Blue hour, Night sky, Midday, Overcast) and **Source** (Curated, Your Spots, Apple Maps), divider, Clear Filters. There is no light choice and no date: the list shows each spot's next sunrise or sunset. Under the header row: a Sample data label when sample weather is on, then the search status. After a divider: the [WeatherStatusBanner](#weatherstatusbanner), then the [ExploreLocationBanner](#explorelocationbanner), then the list. Section headers: `type/captionStrong`, `text/secondary`, with a count at right; with a location they read "Near You · Within 300 mi", "Popular", "More Places" (collapsed until opened, or while a search narrows the list) and "Apple Maps"; without one, a single "Spots" section under the location banner. Footer: [ForecastSourceLines](#forecastsourcelines) for the scored rows.
- **Forecast fetching:** rows are requested in list order as they appear; a collapsed "More Places" is requested when it is opened. Each row's score slot shows a small spinner until its own forecast is in.
- **States:** list; loading (small spinner); searching; search failed; empty ("No Matching Spots" or "No places found", via ContentUnavailableView, with Clear Filters).
- **Interaction:** click selects a row (the place card opens over the map); double-click or Return opens the spot page; context menu Open, Save or Unsave (not on your own spots), Add to Trip ▸, divider, Open in Maps, Copy Coordinates.

### ExploreRow

- **Type, file:** `ExploreRowView`, `Explore/ExploreRowView.swift`; lane widths in `ExploreRowLayout`, `Explore/ExploreRowLayout.swift`.
- **One job:** one spot and its next sunrise or sunset, with every row's light on the same grid. A row is only light.
- **Which window:** the next sunrise or sunset event at the spot, in the spot's own local time (`LightEngine.nextEvent`): a window counts until it ends; after today's sunset the next is tomorrow's sunrise; it looks up to 4 days ahead; the polar fallback is the first non-night window not yet over. Blue hours and night are not in the list.
- **Anatomy:** row, gap `space/md`, vertical padding `space/xs`. Left: spot name (`type/bodyEmphasis`, up to two lines, wraps rather than truncates) over locality (`type/caption`, `text/secondary`), then, when Iter knows where you are, the distance after it ("Big Sur, CA · 101 mi"; the distance is never the part cut off), then a [ProvenanceTag](#provenancetag) for your own spots. Right: the **light column**, three fixed lanes separated by `space/sm`:

| Lane | Holds | Width |
|---|---|---|
| symbol | the [WindowSymbol](#windowsymbol) (16 pt) | 16 pt plus `space/xs` |
| chip | a regular [ScoreChip](#scorechip); with no score, empty, or a small spinner while the forecast is in flight | the larger of `size/badgeMinWidth` and three digits at the score font, plus the chip padding |
| time | the window's start time (`type/timeSmall`, `text/secondary`, monospaced digits, trailing), e.g. "19:54"; its tooltip says "Tomorrow" when the window is tomorrow's | the widest time the locale and clock format can produce (sampled at :58 past every hour) |

  Each width is measured once, at the lane's own font, so nothing in the column is typed in and all rows line up. No word, band or confidence is drawn in the row; the symbol's tooltip and the VoiceOver label carry the window's name.
- **States:** scored; unscored (empty chip lane, start time still shown); loading (spinner in the chip lane); no window (the light column is blank; a spot with neither sunrise nor sunset ahead); selected (system list selection); hovered (the map pin gets a chip; the row itself has no distinct hover style).
- **Interaction:** a click selects the row and opens its [ExplorePlaceCard](#exploreplacecard) on the map. Double-click (or Return) opens the spot page. Rows do not expand.
- **Accessibility:** one element: name, locality, the distance when a location is known, then the window's words, score, band, confidence and start time ("Sunrise, Light Index 68, Good, Medium confidence, starts 07:20").

### ExploreMapPane

- **Type, file:** `ExploreMapPane`, `Explore/ExploreMapPane.swift`.
- **One job:** the map with pin hierarchy, shared selection, the place card and Add Spot mode.
- **Anatomy:** a MapKit map (standard, flat, points of interest hidden; zoom stepper, compass, scale), the user's location (with location permission, MapKit's own blue dot (`UserAnnotation`) and a user-location button leading the controls; with a simulated location (`-IterLocation`) a 14 pt `map/userLocation` dot with a 2.5 pt white ring, labelled "Your location (simulated)", and no button. Without permission, neither.), pins as [ExplorePinView](#explorepinview), a "New spot" `mappin.circle.fill` (`accent/primary`, title size) at a dropped draft pin; overlays: [AddSpotBanner](#addspotbanner) top, [ExplorePlaceCard](#exploreplacecard) bottom-trailing (slides up with a fade), each inset `space/md`. **Camera:** [MapCameraPolicy](SCREENS.md#explore) fits the Near You set (else every listed spot), never wider than a 40° span; once you move the map it stays yours, is saved for this screen and restored on relaunch, and a change in the list refits only if you have not touched it; selecting a spot pans to it without zooming out.
- **States:** default; a selection; Add Spot mode (crosshair cursor, pins not clickable, the card hidden); a draft pin placed (the editor sheet is open).

### ExplorePinView

- **Type, file:** `ExplorePinView`, `Explore/ExplorePinView.swift`.
- **One job:** map hierarchy: one selected pin, a few chips, the rest dots.
- **Anatomy and variants:**

| Style | Drawn as |
|---|---|
| **dot** | 12 pt (`space/md`) circle filled with the band colour (`light/ramp/*`) with a 0.5 pt `separator/default` ring; with no score, a `background/control` circle with the same ring. |
| **chip** | A capsule (`background/content`, hairline `separator/default`, padding `space/xs` by `space/xxs`) holding the [WindowSymbol](#windowsymbol) (12 pt) and a compact [ScoreChip](#scorechip) (no chip when unscored). With no window: a dot. |
| **selected** | A capsule (`background/content`, **2 pt `map/pin` border**, padding `space/sm` by `space/xs`) holding the symbol, a compact score chip (when scored) and the window start time (`type/timeSmall`, `text/primary`); with no window the spot name (`type/captionStrong`). Below it a small down-pointing triangle in `map/pin` (`type/caption`), so the anchor is the bottom tip. |

- **Rules:** the selected pin always wins; a hovered pin and the best **six** scored spots in view (`pinBudget = 6`, excluding the selected one) are chips; everything else is a dot. The selected pin is drawn on top, then chips, then dots. The window is the same next sunrise or sunset as the list row.
- **Accessibility:** button (and selected) trait; label as the list row.

### ExplorePlaceCard

- **Type, file:** `ExplorePlaceCard`, `Explore/ExplorePlaceCard.swift`.
- **One job:** the selected spot, its next light and a preview of its page, without leaving the map. It opens for a list row or a pin selection.
- **Anatomy:** a panel at the map's bottom-trailing corner, inset `space/md`. Width `layout/placeCardWidth` (360); height up to `layout/placeCardMaxHeight` (560), and never more than half the map's height so the selected pin stays visible. `radius/panel` (16), a `regularMaterial` fill (flat `background/content` in snapshots), hairline `separator/default`, a soft shadow. Top to bottom:
  1. **Pinned header** (padding `space/md`, stays put while the body scrolls): name (`type/headline`, up to two lines), locality (`type/subheadline`, `text/secondary`) with a [ProvenanceTag](#provenancetag), a close button at top right (`xmark.circle.fill`, `text/tertiary`, tooltip "Deselect", label "Close"), and the **next-event summary**: the [WindowSymbol](#windowsymbol), a regular [ScoreChip](#scorechip) (or a spinner while loading), the start time (`type/timeSmall`) and "Tomorrow" (`type/subheadline`, `text/secondary`) when it is tomorrow's. No summary when the spot has no such window.
  2. **Image strip** ([SpotImageStrip](#spotimagestrip)), `size/placeCardImageHeight` (200) high, edge to edge.
  3. **Spot sections** (scrolling, compact density, gap `space/lg`): When to go, Light windows, **Coming Up**, the light timeline, sun and moon, Hour by hour, Good to know (the access notes and facts). "Coming Up" (`type/headline`) lists today's windows that have not ended, then tomorrow's, one line each: the day (`type/subheadline`, `text/secondary`), then at the right the [WindowSymbol](#windowsymbol), a compact score chip and the start time (`type/timeSmall`).
  4. **Actions:** **Save** / **Saved** (hidden for your own spots) and [AddToTripMenu](#addtotripmenu).
  5. **Source line:** [ForecastSourceLine](#forecastsourceline), then a link-style **Show Full Page** that opens the spot page for the chosen day. (There is no Open button.)
- **States:** scored; unscored (empty chip, the sections still show sun and moon); loading; no window; saved; your own spot (no Save button); scrolled (see `-IterCardScrolled` in TESTING.md). The weather banner is on the list, not the card.
- **Accessibility:** container labelled "Place card for Mesa Arch".

### SpotImageStrip

- **Type, file:** `SpotImageStrip` and `SpotImages`, `Components/SpotImageStrip.swift`; provider `SpotImageryProviding` (`SpotImagery.swift`) and `MapKitSpotImagery` in `Packages/IterKit/Sources/IterServices/Maps/`.
- **One job:** show what the place looks like, honestly labelled.
- **Anatomy:** a fixed `size/placeCardImageHeight` (200) strip, clipped, paging horizontally. Each page is one image filling the strip with a source label top-leading (a `regularMaterial` capsule, `type/captionStrong`): **Look Around** (Apple's street-level snapshot, only where Apple has imagery) or **Satellite** (a hybrid satellite snapshot with a dot at the spot). Look Around comes first when it exists. With more than one image: a dot indicator bottom-centre (capsule, material), and on hover previous and next chevrons (`size/hitTarget`, material circles) because a mouse has no swipe.
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
- **Anatomy:** see [Spot page](SCREENS.md#spot-page). Name `type/title/spot` (header trait); line of locality (`type/subheadline`, `text/secondary`), [ProvenanceTag](#provenancetag), category symbol and name (`type/subheadline`, `text/secondary`); action row spaced `space/sm`.
- **Variants:** titled buttons, or icon-only when the width is tight. Your own spots: Edit and Delete after a divider, no Save.
- **States:** saved (`bookmark.fill`, "Saved"); not saved; delete confirmation when trips use the spot.

### WhenToGoSection

- **Type, file:** `WhenToGoSection`, `Spot/WhenToGoView.swift`.
- **One job:** lead the page with "when should I be here?".
- **Anatomy:** title ("When to go", `type/title/section`; there is no intent picker, the page follows the spot's own best light), a [SpotCard](#spotcard) lead, the [OutlookStrip](#outlookstrip).
- **Lead states:**

| State | Contents |
|---|---|
| Best window | Large [LightBadge](#lightbadge) at left. Right column (gap `space/xs`): "Best sunrise in the next 8 days" (`type/caption`, `text/secondary`; the number is the days the forecast covers, at most 10); "Mon, Oct 12, 2026 · 07:25–08:01" (`type/headline`, monospaced digits; "Today" or "Tomorrow" in place of the date when relevant); the top factor's sentence (`type/callout`); "Updated 09:00" (`type/footnote`, `text/secondary`); **Show this day** (small) when the page is on a different day or window. |
| Loading | Small spinner + "Checking the forecast…" (`type/callout`, `text/secondary`), then [SunTimesLine](#suntimesline). |
| No score | [SunTimesLine](#suntimesline) alone. No ring, no reason, no Retry; the screen's [WeatherStatusBanner](#weatherstatusbanner) says why. |

### SunTimesLine

- **Type, file:** `SunTimesLine`, `Spot/WhenToGoView.swift`.
- **One job:** the always-exact sun times when there is no score.
- **Anatomy:** `sunrise` + "Next sunrise Wed 07:20" and `sunset` + "Next sunset 18:54" (`type/callout`, monospaced digits), gap `space/lg`. Polar: `moon.stars` or `sun.max` with the polar sentence (`type/callout`, `text/secondary`).

### OutlookStrip

- **Type, file:** `OutlookStrip`, `Spot/WhenToGoView.swift`.
- **One job:** the coming days at a glance for the page's intent, fading with confidence.
- **Anatomy:** caption "8-day outlook for Sunrise" (`type/subheadline`, `text/secondary`; the number is the days shown); a row of equal cells (gap `space/xs`); key line "Fainter days are less certain." (`type/caption`, `text/tertiary`). **Length:** the days the forecast covers, at most 10 (`LightEngine.outlookDayCount`; 8 with OpenWeather, never past the provider's horizon). If today's window has already passed, the strip starts tomorrow. Each cell, top to bottom (gap `space/xxs`, vertical padding `space/xs`): a **Best** tab (`type/captionStrong`, `accent/onAccent` on an `accent/emphasis` capsule; an empty line on other days; a star in compact density), weekday (`type/caption`, `text/secondary`), day number (`type/bodyEmphasis`, monospaced), a [ScoreChip](#scorechip) (regular, or compact in compact density) or an empty slot of the same size (a spinner while loading), and, on the page, a caption (up to two lines, `type/caption`, `text/secondary`, min height 24): the range "65–81", "No window" or empty.
- **States:** default; selected day (fill `selection/fill`, 1.5 pt `accent/primary` outline, `radius/control`); best day (the Best tab); confidence fade (medium 80% opacity, low 60%; days scored by persistence are low); unscored (empty slot, no caption); no window ("No window").
- **Accessibility:** each cell is a button, label "Monday, October 12, Sunrise, Light Index 87, Great, Low confidence, Best", selected trait.

### DayWindowsSection

- **Type, file:** `DayWindowsSection`, `Spot/DayWindowsView.swift`.
- **One job:** the selected day's windows in time order.
- **Anatomy:** header "Light windows" (`type/title/section`) + day label (`type/subheadline`, `text/secondary`) + **Today** (small, when not today). A card of [WindowRow](#windowrow)s separated by dividers; clipped to `radius/card`. On today the card lists the windows that have not ended, then tomorrow's under a small day header ("Tomorrow", `type/captionStrong`, `text/secondary`); on any other day, all of that day's windows. If no windows (polar): `moon.stars` or `sun.max` with the sentence, or "No golden hour, blue hour or night window today."

### WindowRow

- **Type, file:** `WindowRow` (private), `Spot/DayWindowsView.swift`.
- **One job:** one window with its score, expandable to its reasons.
- **Anatomy:** a button row, padding `space/md` by `space/sm`: `chevron.right` (`type/captionStrong`, `text/secondary`, 14 pt column; rotates 90 degrees when open; hidden when the row cannot expand), a regular [LightBadge](#lightbadge) with the window's name beside its symbol (compact density: symbol only), then at the right the time range "07:25–08:01" (`type/time`). When open, [ReasonsGrid](#reasonsgrid) below, indented past the chevron, padding `space/md` at the bottom.
- **States:** collapsed; expanded; selected (row fill `selection/fill`, `accent/primary` stroke); unscored (empty slot, a spinner while loading; the row does not expand); a row from another day (tomorrow's, listed under today's): clicking opens that day instead of expanding.
- **Accessibility:** combined; value "Expanded" or "Collapsed"; hint "Shows why this window scores as it does" (or "Opens this day" for another day's row).

### ReasonsGrid

- **Type, file:** `Reasons` (private), `Spot/DayWindowsView.swift`.
- **One job:** why the score is what it is.
- **Anatomy:** "Why this score" (`type/captionStrong`, `text/secondary`). A grid, gap `space/md` by `space/sm`, one row per factor: name (`type/bodyEmphasis`: Low cloud, Mid and high cloud, Cloud cover, Clear sky, Rain, Visibility, Moonlight, Dark sky, Wind, Sun direction), measured value (`type/time`, `text/secondary`, right aligned: "29%", "15 mi", "12 mph", "34°"), a [SignedBar](#signedbar), and a sentence (`type/callout`; it names the cloud layers when the provider gave them, see [Weather status text](#weather-status-text-and-score-notes)). Then a confidence line (gap `space/sm`): [ConfidenceMark](#confidencemark), "Low confidence" (`type/subheadline`), "· Likely 72–100", then the source and time ("· Windy · GFS · updated 09:00", `text/secondary`; for sample data the Sample data label), with a fallback named as in [ForecastSourceLine](#forecastsourceline). Then a footnote (`type/footnote`, `text/secondary`): the confidence meaning plus "Forecast is about 6 days ahead of this window." Then one footnote line per score note (see [Weather status text and score notes](#weather-status-text-and-score-notes)). Then [ExplainBlock](#explainblock).

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
- **One job:** the 24 hours of light: sky by sun altitude, the five windows with scores, cloud by altitude, rain chance, and a scrubber.
- **Anatomy** (a canvas inside a [SpotCard](#spotcard); left gutter 44 pt, right inset `space/lg`):
  1. **Readout line:** "07:43 · 44% cloud · 3% rain" (`type/bodyEmphasis`, monospaced), "·" and the window name under the marker (`type/subheadline`, `text/secondary`); right, "Hover or drag to read any time" (`type/caption`, `text/tertiary`) when not scrubbing. Min height 22.
  2. **Bracket label tiers** (3 tiers of 16 pt in Full day, 2 in zoomed views): each window gets a bracket over its span and a label "Sunrise 87", "Blue AM 85", "Sunset 56", "Blue PM 54", "Night 30" (short name + score, no score when no forecast), `type/caption` (`type/captionStrong` for the selected window), `text/primary` (`text/secondary` with no score). Labels move up a tier when they would overlap, with a hairline leader. Bracket 4 pt drop, `text/secondary` 1.5 pt; selected 2 pt `accent/primary`.
  3. **Sky band:** 56 pt tall (`chart/timelineHeight`), corner `radius/badge`, a left-to-right gradient coloured by the sun's altitude: below −18° `sky/night`, −18° to −6° night to `sky/blueHour`, −6° to the horizon `sky/blueHour`, across the horizon blueHour to `sky/golden`, up to +6° `sky/golden`, to +14° golden to `sky/day`, then `sky/day`.
  4. **Axis:** 18 pt, ticks 4 pt long in `text/secondary`, hour labels `type/timeSmall` (every 3 hours in Full day, hourly when zoomed), in the spot's time zone.
  5. **Weather plot** (only with a forecast): 80 pt tall, 8 pt below the axis; 0%, 50%, 100% gridlines (`separator/default`, hairline) with labels at the left (`type/timeSmall`, `text/secondary`); cloud layers drawn as overlapping (not stacked) filled areas at 50% opacity with a 1.5 pt top line: `cloud/high`, `cloud/mid`, `cloud/low` (or a single `cloud/mid` "Cloud cover" when the layers are unavailable); rain chance bars (hours at 10% or more, 60% width) in `sky/blueHour`; each window tints the plot with its sky colour at 20% (the selected window with `accent/primary` at 16% added).
  6. **Selected window:** a 2 pt `accent/primary` outline across the sky band and plot, with a `background/window` halo.
  7. **Marker:** a vertical line in `text/primary` through the sky band and plot (dashed 1 pt at rest, solid 1.5 pt while scrubbing) with a `background/window` halo, and an 8 pt knob on the sky band's bottom edge.
  8. **Legend** (below, `type/caption`, `text/secondary`): swatches 12 pt with hairline: High cloud, Mid cloud, Low cloud, Chance of rain. Without hourly weather the legend is absent; while the forecast loads a spinner and "Checking the forecast…" stand in. The screen's banner says why.
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
  - **Markers** (14 pt, `chart/arcMarker`): the sun marker is `map/sun` with a 1.5 pt `background/window` ring when above the horizon, and a hollow `background/window` disc with a 2 pt `map/sun` ring when below (down to −20°); the moon marker is `map/moon` with the same ring, only when above the horizon.
  - **Legend:** 12 pt dot `map/sun` "Sun", dot `map/moon` "Moon", a 2 pt `accent/primary` bar "Classic view" (only when facing is known); `type/caption`, `text/secondary`.
  - **Text lines:** "At 07:43 the sun is 3° above the horizon, toward 102° ESE." (`type/callout`); "The sun is in your frame." (`type/callout`, `text/secondary`; also "off to one side", "behind you"); the moon line with its phase symbol (20 pt, `text/primary`) and "Waxing crescent · 6% lit · rises 09:38 · sets 19:33" (`type/callout`, `text/secondary`).
- **States:** default; no classic view; sun below the horizon ("At 18:25 the sun is below the horizon."); polar (a near-flat path).
- **Accessibility:** one element, label "Sun and moon for Monday, October 12" with sunrise and sunset directions and the facing.

### HourlyStrip

- **Type, file:** `HourlyWeatherSection`, `Spot/HourlyWeatherView.swift`.
- **One job:** the day's weather hour by hour, on the timeline's x-axis.
- **Anatomy:** header "Hour by hour" (`type/title/section`) with, at the trailing edge, the [ForecastSourceLine](#forecastsourceline) with its time ("Windy · GFS · updated 09:00", `type/caption`, `text/secondary`). A [SpotCard](#spotcard) containing a 5-row grid (rows 22 pt, `space/xxs` added to `size/icon/large`): a multicolour weather symbol (`type/subheadline`), then **Temp**, **Cloud**, **Rain**, **Wind** rows in `type/timeSmall`, monospaced digits. Row labels sit in the left gutter (`type/caption`, `text/secondary`). Rain shows a percent only at 20% or more, in `accent/text`. Temperature follows the Settings unit. Window spans are tinted with their sky colour at 20%, the selected window with `accent/primary` at 16%, the marker hour with `text/primary` at 8%. Under the strip: "Wind in mph" (or km/h; "Rain in mm/h · Wind in mph" when rain is an amount rather than a chance, as with Windy; `type/caption`, `text/secondary`).
- **States:** with a forecast only. Without one the whole section is absent.
- **Accessibility:** a summary of every third hour ("6 AM: 36°, 43% cloud").

### WindySection

- **Type, file:** `WindySection`, `Spot/WindySectionView.swift`.
- **One job:** hand the user to Windy's map, which Iter may not embed.
- **Anatomy:** a column, gap `space/md`: title "Windy" (`type/title/section`), then a [SpotCard](#spotcard) with a row, gap `space/md`: the sentence "Windy's map shows cloud by height, rain and wind around this spot. It opens on windy.com: Windy doesn't allow its map inside other weather apps." (`type/callout`, `text/secondary`, wraps), a spacer, and a bordered **Open in Windy** button (`arrow.up.forward.square`). Tooltip "Open this spot on windy.com in your browser". Opens [WindyLink](#windylink) at the spot, zoom 9.
- **States:** always shown, whatever the forecast state; sits after Hour by hour and before Good to know. Not an embedded map and not part of the shared selection.
- **Accessibility:** a container; the button is labelled "Open in Windy".

### SpotFactsRow

- **Type, file:** `SpotFactsSection`, `Spot/SpotFactsView.swift`.
- **One job:** the practical facts.
- **Anatomy:** header "Good to know" (`type/title/section`); a [SpotCard](#spotcard) with an adaptive grid of facts (min 150 pt per item, gap `space/sm`), each a Label with a `text/secondary` icon and `type/callout` text: `figure.walk` "10 min walk-in" (or "Walk-in unknown" in `text/secondary`), `mountain.2` "6,102 ft elevation" (when known; feet or metres by locale), `safari` "Faces 100° E" (or "Facing unknown"), `sun.horizon` "Best at sunrise" (when set), `clock` "Mountain Time · 1 h ahead of you" (only when the spot's zone differs from the Mac's). Then the blurb (`type/body`), and "Notes" (`type/captionStrong`, `text/secondary`) with the notes (`type/callout`).

### LookAroundSection

- **Type, file:** `LookAroundSection`, `Spot/SpotFactsView.swift`.
- **One job:** show Apple's street-level imagery where it exists.
- **Anatomy:** header "Look Around" (`type/title/section`) and a system Look Around preview, 224 pt high, clipped to `radius/card`.
- **States:** absent when Apple has no imagery, and in snapshots. The place card's [SpotImageStrip](#spotimagestrip) shows Look Around too, with a satellite image where Apple has none.

---

## Saved and Scout components

### SavedRow

- **Type, file:** `SavedRow` (private), `Saved/SavedView.swift`.
- **One job:** a kept spot and its next sunrise or sunset.
- **Anatomy:** row, gap `space/md`, vertical padding `space/xs`: category symbol (`title3`, `text/secondary`, 32 pt column, hidden from VoiceOver); a column of name (`type/headline`, one line) and, gap `space/sm`, locality (or category if there is none; `type/subheadline`, `text/secondary`) plus a [ProvenanceTag](#provenancetag); at the right a `WindowLightLine`: the [WindowSymbol](#windowsymbol), a compact [ScoreChip](#scorechip) (empty, or a spinner while loading, when unscored) and the window's start time in the spot's own zone (`type/caption`, `text/secondary`, monospaced digits). The window is the spot's next sunrise or sunset by the same rule as [ExploreRow](#explorerow); its tooltip and VoiceOver label say "Tomorrow" when it is tomorrow's.
- **States:** scored; unscored (empty slot); loading (spinner); tomorrow's window; selected.
- **Accessibility:** one combined element.

### ScoutResultRow

- **Type, file:** `ScoutResultRow` (private), `Scout/ScoutView.swift`.
- **One job:** one suggested place, its light, drive and the scout's note.
- **Anatomy (gap `space/sm`, vertical padding `space/sm`):** name (`type/headline`) over locality (`type/subheadline`, `text/secondary`), a [ProvenanceTag](#provenancetag) at the right (Curated or Apple Maps); a line: a `WindowLightLine` (the [WindowSymbol](#windowsymbol), a compact score chip and the start time of the spot's next sunrise or sunset) and `car` + "12 min drive" (`type/caption`, `text/secondary`); the note block (only when there is a note): `sparkles` + "Scout's note" (`type/captionStrong`, `text/secondary`) and the note (`type/callout`); buttons (small, bordered): **Open**, **Save** or **Saved** (`bookmark` / `bookmark.fill`), **Add to Trip**.
- **Light-line states:** scored; unscored (empty chip slot); loading (a small spinner alone); no event ahead (nothing drawn). The screen's [WeatherStatusBanner](#weatherstatusbanner) says why scores are missing.
- **Accessibility:** container; the light line's label names the window, score and start time (and "Tomorrow").

### ScoutProgress

- **Type, file:** the `running` view in `Scout/ScoutView.swift`.
- **One job:** real progress for a slow request.
- **Anatomy:** centred stack, gap `space/md`: large spinner; the stage (`type/headline`); four capsules 24 x 4 pt (`space/xl` by `space/xs`) gap `space/xs`, filled `accent/primary` up to the current stage and `separator/default` after; "Step 2 of 4" (`type/caption`, `text/secondary`); after 10 seconds the elapsed time "0:14" (`type/time`, `text/secondary`) over "Still working. A request can take up to a minute." (`type/caption`, `text/secondary`); a large **Cancel** button.
- **Stage texts:** "Understanding your request", "Searching near Portland, Oregon" (or "Searching for places"), "Checking the drive to <place>" (or "Checking the drive"), "Choosing the best matches".

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
- **Calls today:** "12 of 800", monospaced digits, with a stepper (0 to 10,000, step 50) that sets the daily cap. OpenWeather and Windy only.
- **Used on:** Settings > Weather, three times (Apple Weather without key row or calls).

## System components

Iter relies on these system controls. Do not restyle them in the design; use the macOS 26 versions. Notes say how Iter configures them.

| System component | How Iter uses it |
|---|---|
| **NavigationSplitView** with a **sidebar** List | `.listStyle(.sidebar)`; two sections ("Trips": All Trips + one row per trip; "Find": Explore, Saved, Scout), selection bound to the window's navigation; sidebar width 200 / 240 / 320 pt; the Sample data banner is a bottom safe-area inset; a "New Trip" toolbar button. Detail column is a NavigationStack per section. |
| **List** | Explore (inset, sectioned, selection and context menu with primary action), Trip builder (inset, selection, drag and drop, section headers), Saved (inset, multi-selection), Scout results (inset, visible separators), Add Stop popover (plain). Selection in a system list is the system accent fill, with the text falling back to the system's colours; custom surfaces use `selection/fill` with an `accent/primary` stroke. |
| **HSplitView** | Explore (list, map), Trip builder (plan, map): draggable native divider. |
| **Toolbar** | Unified title bar. Items per screen are listed in SCREENS.md. Window title is the section name; the trip builder replaces the title with the editable name. |
| **searchable** (toolbar search field) | Explore ("Search"), Saved ("Search saved spots"). |
| **ContentUnavailableView** | Empty and error states: large grey symbol, bold title, grey description, 0 to 2 action buttons. Used for Trip Not Found, Explore empty, Saved empty and filter-empty, Scout unavailable and failure states, search-empty. |
| **Map** (MapKit) | Explore: standard style, flat elevation, points of interest hidden, controls zoom stepper, compass, scale, custom annotations, selection. Trip route: polylines and numbered annotations. Spot editor: a small map with pan and zoom, the pin fixed at the centre. Scout: accent-tinted markers with category symbols. |
| **LookAroundPreview** | Spot page, 224 pt high, `radius/card` clip; only when a scene exists. |
| **Picker** | Segmented (intent on the Spot page, timeline zoom, trip builder toolbar day picker up to 5 days); menu (session menu, Settings pickers, Category in the editor); inline in menus (Near You Radius and Sort By in the Explore list header menu). |
| **Menu** | Add to Trip, Explore list header menu (radius, sort, filters), Saved Sort and Filter, Trip Actions, context menus. |
| **ShareLink** | Trip (toolbar and context menu; shares a `.iter` document), Spot (header; shares an Apple Maps link and a coordinate message). |
| **DatePicker, Stepper, TextField, Toggle** | Forms (grouped style) in the sheets and Settings; the Explore Add Spot control is a button-style Toggle. |
| **Sheet, popover, confirmationDialog, alert, fileImporter, fileExporter** | As listed in SCREENS.md. |
| **TabView** | Settings (four tabs). |
| **Materials** | `regularMaterial` for the place card, Add Spot banner; `bar` for the Saved footer. Flat colours in snapshots. |
| **ProgressView** | Small circular spinners next to loading text; large in Scout's running state. |
| **Buttons** | Prominent (accent fill, `accent/onAccent` text) for the single primary action of a view; bordered for secondary; borderless or link for inline actions; plain for tappable cards and rows. |

---

## Rules that cut across components

1. **Every score is paired with its window.** A number is never alone: in compact places (list rows, pins, the card header, trip stops, Saved and Scout rows, the Add to Trip menu) the window's [WindowSymbol](#windowsymbol) sits beside the chip, with the word as tooltip and VoiceOver label; on the spot page the word is used ("Sunset · 87" in the large badge, the name beside the symbol in window rows). Outlook cells inherit the window from context (the outlook title "8-day outlook for Sunrise").
2. **No weather is one banner, never a number, never a low score.** The only no-data situations (no key, offline, provider error) show one [WeatherStatusBanner](#weatherstatusbanner) at the top of the screen. Rows keep their last cached score or leave the score slot empty (a small spinner while the forecast is in flight). Nothing per row says "No forecast"; there is no dashed ring. Beyond the provider's forecast a window is still scored, by persistence, at Low confidence. Sun and moon times stay exact and visible.
3. **The band word is always printed beside the ramp colour** in the regular and large badges. Colour alone never carries the band. (The compact badge, list-row chips, the outlook chips and pin dots rely on the number or context; see the inconsistencies reported with this document.) A badge always has its hairline, because Poor and Fair are too pale to reach 3:1 on the window.
4. **Coral is used with restraint.** `accent/primary` is the one thing that acts or is selected, `route/active` the route, `map/pin` the pins and `map/sun` the sun. Never a score, a status, an error or a large fill behind text. Small text uses `accent/text`; small text on a coral fill uses `accent/emphasis`. It is never "good".
5. **A warning is violet (`status/warning`) and always has an icon.** Failure and validation are raspberry (`status/danger`) with an icon and words. Never amber, never coral, never green. Green is not used anywhere.
6. **"Sample data" appears once per screen.** The banner sits in the sidebar; screens that show sample scores carry one inline label; [WeatherAttributionView](#weatherattributionview) shows the label in place of a provider credit (in Settings).
7. **Source wherever weather appears; attribution in Settings.** Each provider's own credit (Apple mark and Legal attribution; "Weather data © OpenWeather"; "Contains data from the Windy database" and Windy.com) plus "Light Index modified from forecast data" now lives only in Settings > Weather and Settings > About (owner's instruction, 2026-10-06; to be revisited before release). Elsewhere a quiet [ForecastSourceLine](#forecastsourceline) names the source. Lists and the spot page also name the source and model in words, and a fallback is always named ("OpenWeather (Apple Weather unavailable)").
8. **Confidence is shown, and low confidence fades.** Three bars on regular and large badges; ranges ("Likely 72–100") for days four and later; outlook cells fade to 80% and 60%.
9. **Times are the spot's own and monospaced; units follow the Mac and Settings.**
10. **System chrome stays system.** The sidebar, toolbar, Settings, sheets and standard controls keep the system's materials and colours and take coral only through the app accent. What the app draws itself uses First Light paper and ink (`text/*`, `background/*`), plus the ramp, accent, route, pin, status, sky and cloud colours.
11. **Never reorder or change a plan automatically.** Suggestions are offered, and every edit is undoable.
12. **The scout's words are labelled** ("Scout's note", "Written by Apple Intelligence from the factors listed above."). Iter scores the light, not the model.

## Known deviations from the rules (open for the design pass)

Found in the hand-off audit and left for the design work, because each one is a design decision rather than a bug:

1. **Band word in compact places.** Compact badges (map pins, Saved, Scout and Add Stop rows), Explore rows and the outlook cells show the window symbol and the number but not the band word. The VoiceOver label includes the band. Decide whether compact spaces carry the word, a glyph, or nothing.
2. **"Sample data" can appear twice on one screen**, in the header and in the Settings credits (Settings ▸ Weather). The rule says once per screen.
3. **Rain colour.** There is no rain token. The timeline's rain bars use `sky/blueHour`, and the hourly strip's rain figures use `accent/text`. A `weather/rain` token is needed.
4. **Accent on the outlook "Best" tag** (`accent/emphasis`) marks the best day. Accent is for interaction and the route, so this edges toward accent meaning "good".
5. **Serif beyond place names.** `type/title/spot` (New York) is also used for trip names and the empty-state headline.
6. **Literal opacities** in `App/Sources/Spot/SpotLayout.swift` (chart layers) and the low-confidence chip opacity (0.85) are not tokens yet.
7. **Explore rows have no hover style** (`ExploreRowView.isHovered` is unused); only the pin reacts to hover.
8. **At 960×640 the trip builder's session line truncates** ("25 min wal…").

Fixed in the audit pass: Explore uses the bookmark symbol for Save like every other screen; the Light Index factor bars are neutral (direction shows helps or hurts, not colour); the spot editor's time-zone warning has its icon.
