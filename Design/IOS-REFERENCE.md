# iOS reference: Flighty

## Intro

Flighty (Flighty LLC) is an iPhone flight tracker. It won a 2023 Apple Design Award in the Interaction category. The jury praised "detailed flight maps, airport navigation, and delay forecasting - all through a beautifully designed app experience", with Siri Shortcuts, Apple Maps and Live Activities integrated. The ADA page adds "design mirroring time-honored airport design conventions" and "incredible Live Activities and Dynamic Island integration". It is a good reference for Iter because it solves the same problem: a time-critical, glanceable status (a flight / a light window) over a map, with a calm, dense, dark-first UI where colour means state.

Owner direction: copy layout and interaction patterns from Flighty. Never its icons, artwork, names or copy.

### Evidence and its limits

- Primary evidence is the two owner screenshots (map home "All Flights", flight detail "NZ 9072"). Everything described under "Flighty does" comes from those unless a source is cited.
- Web sources actually read (via fetch):
  - https://apps.apple.com/us/app/flighty-live-flight-tracker/id1358823008 (feature list, awards, v4.11.1: Dynamic Island refinements, Siri, app icons)
  - https://flighty.com (features, "pilot-grade data that you can actually understand", platforms)
  - https://www.apple.com/newsroom/2023/06/apple-announces-winners-of-the-2023-apple-design-awards/ (Interaction category, jury wording)
  - https://developer.apple.com/design/awards/2023/ (Flighty description)
- Not obtained: web search quota was exhausted, and the MacStories, flighty.com/live-activities and flighty.com/blog URLs returned 404; The Verge could not be fetched. There are therefore no interview or review quotes here. Reasoning about "why it works" is the author's reading of the screenshots and the ADA text, marked (inferred) where it goes beyond them.

## Pattern list

### 1. Full-bleed map as the home canvas
- Flighty: the whole screen is a dark map (night-lights imagery), with the Apple Maps attribution visible. All UI floats over it. Nothing is boxed in a nav bar.
- Why: the map is the hero content; chrome stays out of the way (inferred). Dark imagery lets small bright marks read instantly.
- Iter: Explore tab is a full-bleed MapKit `Map`. In dark mode use the standard style with muted/realistic elevation; Iter's spot pins carry the light-ramp colour of the next window's band. No top navigation bar; the safe area is used by the map.

### 2. Custom floating bottom sheet with named detents
- Flighty: a rounded sheet rises from the bottom above the tab bar. The map stays visible and interactive above it. The sheet holds a title row, chip row and list/empty state.
- Why: map and list co-exist without a modal context switch (inferred).
- Iter: a custom in-tab sheet (not a system sheet; on iOS 26 a `presentationDetents` sheet covers the tab bar, verified in the simulator). Three named detents: peek (title + chips), half (spot list), full (list with search-like density). Drag handle, velocity snapping, map camera inset follows the sheet height.

### 3. Very large bold title with round glass actions
- Flighty: sheet header "All Flights" in very large bold type; trailing round glass buttons (more, share, avatar), all the same diameter.
- Why: one glanceable "where am I" label, with actions kept to icon-only circles so the title gets the width (inferred).
- Iter: title is "Explore", or the selected place name. Trailing: more menu, share, and a Location/settings slot (round, `.glass`). Titles use `.largeTitle`-scale bold, truncating long place names with `minimumScaleFactor`.

### 4. Chip row under the title
- Flighty: horizontally scrolling chips (Today, people, Add Friend). Selected chip is a filled capsule; others are plain text with a small leading avatar/icon. A trailing "add" chip is dashed in intent.
- Why: filters one tap away, no filter screen (inferred).
- Iter: Today / Tomorrow / Near you, then categories and folders (Locations). Selected = filled capsule in surface-raised or accent tint, not a full accent fill. Scroll-clipped at the edges. Selecting "Today" / "Tomorrow" changes which window's Light Index the pins show.

### 5. Floating pill tab bar plus separate round search button
- Flighty: a glass pill with three tabs (My Flights, All Flights, Passport); the selected tab has a raised capsule and accent colour. Search is a separate round glass button on the right.
- Why: the iOS 26 tab bar pattern; keeps search reachable without spending a tab (inferred).
- Iter: iOS 26 `TabView` with Explore, Trips, Locations; search as `Tab(role: .search)`. The search destination holds Apple Maps suggestions plus "Ask" suggestions (natural-language questions about light).

### 6. Stacked floating glass map controls, top right
- Flighty: a vertical stack at the top right: map style, weather/cloud layer, a third control. Glass capsule, icon only.
- Why: map tools are secondary and out of the way of the sheet (inferred).
- Iter: map style, cloud layer (placeholder until a cloud-cover source exists), locate. Same glass treatment as the sheet buttons. Keep them below the status bar, clear of the sheet at every detent.

### 7. Empty state that explains in two lines
- Flighty: centred "No Flights" plus one explanatory line, in the sheet body.
- Iter: "No spots here" plus one line ("Nothing scored for tomorrow near here. Try Near you."), with at most one action. Own copy.

### 8. Detail sheet header: small-caps overline, big title, round close
- Flighty: overline "NZ 9072 - TUE, 6 OCT" in small caps / caps-tracking, below it a large title ("Denver to San Francisco"); a round close button at the trailing edge; a small brand glyph leading.
- Why: identity (what, when) in one compact block (inferred).
- Iter: overline "Category - Locality - Date" (e.g. "Viewpoint - Lofoten - Tue 6 Oct"), title is the spot name, round close button. Use `.textCase(.uppercase)` or small-caps with tracking; no leading glyph needed.

### 9. Full-width status band whose colour carries state
- Flighty: directly under the header, an edge-to-edge band in dark red with red text ("Took Off 6m ago / Landing in 2h 2m"): a two-line live status.
- Why: state is readable before reading any text (inferred), and the band doubles as the "what's happening now" line.
- Iter: band tinted by the next window's Light Index band; text e.g. "Sunset in 2h 14m - Great 76". Use Iter's light-ramp band colours (dark tinted background, bright tinted text, as Flighty does), not Flighty's red/green. Low confidence or beyond-forecast shows a neutral band, never a coloured one.

### 10. Large headline times with delta and struck-through original
- Flighty: 21:01 in very large numerals, coloured green (early) or red (late), the scheduled 21:05 struck through beside it, then secondary text ("4m Early - 47m ago"). Two such blocks (departure, arrival) joined by a thin line with duration and distance.
- Why: the number is the answer; delta and colour explain it (inferred).
- Iter: the next sunrise/sunset start in large monospaced-digit numerals, with secondary "set up by" / "leave by" times beneath. Colour only when it signals a state (band); struck-through is used only if the forecast time shifts. A thin rule with "walk-in 12 min - drive 40 min" mirrors the duration line.

### 11. Badge chips for compact facts
- Flighty: bold yellow rounded badges with an icon and short value (B24, D1, D12) aligned trailing, with a plain caption under them (Terminal Main).
- Why: operational facts are the most scannable form: icon, short value (inferred).
- Iter: badges for the event unit itself plus small fact chips: walk-in minutes, drive time, best light. One neutral badge style (surface-raised, mono digits); use the accent only for the single most important fact. Not yellow.

### 12. Two-up tappable cards
- Flighty: two equal rounded outlined cards: "Booking Code / Tap to Edit" (with a PASTE affordance) and "Seat / Tap to Edit". Icon top, title, grey hint.
- Iter: "Notes" and "Add to Trip" (or "Save"). Same structure: icon, title, grey hint ("Tap to add"). Radius 16-20, hairline outline, no fill beyond the surface.

### 13. "Good to Know" rounded outlined cards
- Flighty: a section title, then full-width rounded outlined cards: weather ("Current DEN Weather / 72F and broken clouds"), airport delays with a coloured status word ("Minor Issues") and a chevron to the airport.
- Why: ambient context separated from the primary answer; coloured word, not a coloured card (inferred).
- Iter: weather now, access notes, warnings (low confidence, beyond forecast), each with an icon, title and one line. A status word may carry colour; the card never does.

### 14. Floating bottom action pill plus one primary accent action
- Flighty: a glass pill bottom-left (share, notifications, more) and a single filled pill bottom-right ("Get Pro"), both floating over scrolled content.
- Iter: glass pill (share, Open in Maps, more) bottom-left; primary accent pill "Add to Trip" bottom-right in the coral accent. Content scrolls underneath; add bottom safe-area padding to the scroll content.

### 15. Trips list = "My Flights"
- Flighty: a titled list of flights (My Flights), each a card: date overline, route/title, next-event status. (Not visible in the owner screenshots; inferred from the tab name, the ADA description and common knowledge of the app. Verify against the live app.)
- Iter: Trips tab with a large title, trip cards with a date overline ("12-18 Oct"), title, next-session status line in the same band/colour logic, and day chips ("Day 1... Day 7") across the top of a trip, same style as the Explore chip row.

### 16. General register
- Dark-first; one accent (Iter's coral accent); big numerals with monospaced digits (`.monospacedDigit()`); generous rounded cards (radius 12-20); dense but breathing (16 pt gutters, 12 pt gaps). Colour carries state only: light bands, warnings. Icons are SF Symbols or Iter's own set.

### 17. Roadmap only: Live Activity, Dynamic Island, widgets
- Flighty is cited by Apple for Live Activities, Dynamic Island, widgets, Siri Shortcuts (ADA page).
- Iter later: a Live Activity for "Sunset in 2h 14m - Great 76" with leave-by countdown, Dynamic Island compact = band colour + time; a widget for the next window at a saved Location; App Intents for "when is golden hour at X". Not built now; keep the status-band data model reusable for these.

## What we do not copy

- Icons, glyphs (the Air New Zealand-style brand mark, airplane/passport symbols), app icons ("Mappy", "Speedy"), illustrations and the night-lights imagery.
- The names: "All Flights", "My Flights", "Passport", "Good to Know" (use our own section title, e.g. "Conditions" or "Worth knowing"), "Flighty Friends", "Connection Assistant".
- Any copy ("Took Off", "Tap to Edit", "Get Pro", "Minor Issues").
- Flighty's hues: the green/red early/late scheme, the yellow badges, the purple Pro pill. Iter uses its light-ramp and coral accent.
- The Pro upsell pattern and any paywall button in the detail view.
- Flighty's data model and product features (delay prediction, friends sharing).

## Native APIs

All names target iOS 26 / SwiftUI; "verify" marks API details to confirm in Xcode before relying on them.

| Pattern | API |
| --- | --- |
| 1 Full-bleed map | `Map(position:)` with `.mapStyle(.standard(elevation: .realistic))` (verify exact parameters), `Annotation` / `Marker` for spots, `.ignoresSafeArea()` |
| 2 Custom sheet, 3 detents | Custom `ZStack` overlay view with `DragGesture` and a `Detent` enum (peek/half/full); `.safeAreaInset(edge: .bottom)` or camera padding for map inset. Do not use `.presentationDetents` for Explore (covers tab bar). |
| 3 Title and glass buttons | `Text(...).font(.largeTitle.bold())`; `Button` with `.buttonStyle(.glass)` and `.buttonBorderShape(.circle)` (verify); `GlassEffectContainer` to group |
| 4 Chip row | `ScrollView(.horizontal)` + `HStack`, `Capsule` backgrounds, `.scrollIndicators(.hidden)`, `.contentMargins` |
| 5 Pill tab bar, search | `TabView` with `Tab(...)` and `Tab(role: .search)` (verify exact initialiser); `.tabBarMinimizeBehavior` optional (verify) |
| 6 Map controls | `.mapControls { MapCompass(); MapUserLocationButton() }` (system), or custom glass buttons with `.glassEffect(.regular, in: .circle)`; verify placement control |
| 7 Empty state | `ContentUnavailableView` (system) or custom |
| 8 Detail header | `Text` with `.textCase(.uppercase)` and `.tracking`, close `Button` with `.buttonStyle(.glass)` |
| 9 Status band | `HStack`/`VStack` with `.background(bandColor.opacity(...))`, full width via `.frame(maxWidth: .infinity)` |
| 10 Big numerals | `.font(.system(size: 56, weight: .semibold, design: .rounded))` + `.monospacedDigit()`; `.strikethrough()` for shifted times |
| 11 Badges | `Label` in `Capsule`/`RoundedRectangle` background |
| 12 Two-up cards | `Grid` or `HStack` of `Button`s, `RoundedRectangle(cornerRadius: 16).strokeBorder(...)` |
| 13 Good to Know | `VStack` of cards, `Label`, `Link`/`NavigationLink` chevron |
| 14 Bottom action pill | `.safeAreaInset(edge: .bottom)` with glass `HStack` and a filled `Button` (`.buttonStyle(.borderedProminent)` or `.glassProminent`, verify); `ShareLink` for share |
| 15 Trips list | `NavigationStack`, `List` or `LazyVStack`, `ScrollView(.horizontal)` day chips |
| 17 Live Activity / widgets | ActivityKit `ActivityAttributes`, WidgetKit `Widget`, App Intents; later |

## Open items

- Re-run the review/interview research once search quota is available (MacStories, 9to5Mac, The Verge, Ryan Jones interviews); add quotes for patterns 2, 9 and 10.
- Capture owner screenshots of the My Flights list and a Live Activity to firm up patterns 15 and 17.
