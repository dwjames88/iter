# Iter design tokens

The single source is `Packages/IterKit/Sources/IterDesign/TokenValues.swift`. Everything else is derived from it:

- the Swift API (`IterColor`, `IterSpace`, `IterRadius`, `IterSize`, `IterStroke`, `IterFont`), which reads the registry at run time and contains no literals;
- `Design/tokens.json`, in the Design Tokens Community Group (DTCG) format, for design tools;
- `App/Resources/Assets.xcassets/Tokens/*.colorset` and `AccentColor.colorset`, so colours are also available as named asset colours.

Do not edit the generated files by hand. Edit `TokenValues.swift` (or `tokens.json`, see "Round trip") and run `scripts/tokens.sh`.

## The identity, in one paragraph

Everything is First Light. The palette is warm espresso ink, cream paper and a coral accent, used throughout: the interface accent, selection, focus, links, route lines, map pins, the sun marker, the logo dot and the app icon. The coral is used with restraint: it marks the one thing that acts or is selected, the route and the sun. The Light Index is a continuous ramp from white (no light) to the accent orange (score 100), with ink on top. Status colours have their own hues and always come with an icon: warning is violet, danger is raspberry. Text, separators and the app's own backgrounds are our First Light inks and paper, not system colours. The system colours in the registry are `background/systemWindow`, for snapshot stand-ins, and `map/userLocation` (system blue), for the simulated location dot.

## Colour role rules (what each colour must never be used for)

Coral is used with restraint. It is for the one thing that acts or is selected, the route and the sun. It is never a score, a status, an error or a large fill behind text. Small text in the accent uses `accent/text`; small text on a coral fill uses `accent/emphasis`.

| Colour | Is for | Must never be |
|---|---|---|
| `accent/primary` (First Light coral) | Selection stroke, primary actions, focus, icons that act, large text | A score, a rating, "good", "done" or "success". A status or an error. A large fill behind text. Small text (use `accent/text`). |
| `accent/text` | Accent-coloured words: links, small labels | A fill. |
| `accent/emphasis` | A fill behind small text: the Best tag, stop numbers (`accent/onAccent` on it is 6.00:1) | A large fill, or a fill behind anything but small `accent/onAccent` text. |
| `accent/hover`, `accent/pressed`, `accent/disabled` | The matching states of a custom control's accent fill or icon | Anything but a state. |
| `selection/fill` | The fill of a selected row, day or window in the app's own views, always with an `accent/primary` stroke | A fill for anything not selected. |
| `route/active`, `route/inactive` | Route lines, trip connectors, the switchback device | Pin colours for data, or any rating. Coral here means "the way", never "good light". |
| `map/userLocation` | The simulated user-location dot (`-IterLocation`), with a white ring; real locations use MapKit's own blue dot | Anything else; it is the one blue in the app. |
| `map/pin`, `map/pinInactive` | The selected spot pin and the stops of the day being looked at; the other stops and unselected stand-in pins | A rating. |
| `brand/dot` | The logo dot | Anything but the logo. |
| `map/sun` | The sun marker | A score, a status, a button, a large fill, text. It is not part of the ramp. |
| `map/moon` | The moon marker | A status. |
| `light/ramp/*` | The Light Index fill: five stops (0, 25, 50, 75, 100) of a continuous colour ramp by score | Green, red or a flat band colour. Anything that is not a Light Index value. |
| `light/rampText/*` | Score, symbol and time on the ramp fill: `ink` below the switch score, `inverse` from it | Text on any other ground. |
| `status/warning` (violet) | A warning, always with an icon and words | Amber (that is the ramp), coral, green. |
| `status/danger` (raspberry) | A failure or destructive action, always with an icon and words | Coral. It is kept 40 degrees or more (OKLCH) from the accent so it never reads as the brand. |
| `status/noForecast` (neutral grey) | The hollow ring and dashed arc: no forecast | A "low score". Unknown is not poor. |
| `sky/*` | The timeline's sky bands | Light Index fills (golden sky is not "Great"). |
| `cloud/*` | Cloud layers by altitude | Anything else. |
| `text/*`, `separator/default`, `background/window`, `background/control`, `background/content` | First Light ink and paper: everything the app draws itself. Text tokens are `IterInk`, which falls back to the system's hierarchical style in a selected system-list row | Replaced by system colours in the app's own views. |
| `background/systemWindow` | Snapshot stand-ins of system-drawn surfaces (sidebar, Settings) | The ground of the app's own content. |

Green is not used anywhere, and in particular never for "good". Success is ink with a check icon.

## Light Index ramp

The Light Index fill is a **continuous ramp by score**, not five flat bands: **score 0 is "no light"** (white in light appearance; the dark surface, just above the window, in dark appearance) and **score 100 is the First Light accent orange** (`accent/primary`: `#D9431A` light, `#FF8A5C` dark). The more vibrant the orange, the better the light. `IterColor.ramp(score:)` interpolates linearly in sRGB between five stop tokens, `light/ramp/0`, `/25`, `/50`, `/75` and `/100`; `IterRamp.fill(score:dark:)` is the same arithmetic as plain numbers, for tests. `IterColor.ramp(_ band:)` still works and returns the ramp at the band's midpoint (Poor 20, Fair 49, Good 66, Great 81, Epic 94). Used by the event unit, the map pin dots, the cluster dot and the legend.

| Stop | Light | Dark | Reads as |
|---|---|---|---|
| 0 | `#FFFFFF` | `#1F1512` | no light: white / dark surface |
| 25 | `#FFEED9` | `#4A291D` | cream-peach / deep ember |
| 50 | `#FFCFA1` | `#8E462C` | apricot / burnt orange |
| 75 | `#FF975C` | `#D96B3E` | bright orange |
| 100 | `#D9431A` | `#FF8A5C` | the accent |

The mid stops are OKLCH-derived (light: L 0.96, 0.89, 0.78 at chroma 0.035, 0.085, 0.15 and hue 70, 62, 48; dark: L 0.32, 0.48, 0.65 at chroma 0.055, 0.105, 0.15, hue 40), so the middle reads as peach and apricot, not tan. Luminance moves one way along the ramp (down in light, up in dark), so order survives greyscale.

**Text is ink across the ramp** (`light/rampText/ink` = `text/primary`: `#1E0F0A` light, `#FFF4E8` dark). It switches to `light/rampText/inverse` (`#FFFFFF` light, `#150C0A` dark) only from the **switch score**: `light/rampText/switchScore/light` = **100** and `/dark` = **65**. The switch is where the inverse becomes the better of the two, which is after ink falls below 4.5:1 for the time. Ink on the full orange is 4.23:1, white 4.40:1, so at the light end the switch only fires at 100. In dark appearance cream ink holds 4.5:1 up to score 61, and the dark surface takes over at 65.

Contrast of the chosen text on the fill at every integer score (`ContrastTests.rampTextContrast`): worst case **4.22:1** (dark, score 64; light 4.35:1 at 99), every score outside light 98 to 99 and dark 62 to 65 is **4.5:1 or better**, and the large heavy score numeral clears the 3:1 large-text rule everywhere. The time and symbol fall short of 4.5:1 only in those few scores, because the fill's luminance sits where neither a dark nor a light text can reach 4.5:1 (a continuous ramp has to cross that band); the floor of 4.2:1 is tested.

**Hairline.** Fills below score `event/hairlineBelowScore` (45) are too close to the ground (white and pale peach on paper, the dark surface on the dark window) to read as a shape, so the unit and its legend swatch get a `separator/default` hairline. Higher scores have no stroke.


## Contrast numbers (WCAG 2.x, checked in tests)

Window grounds are First Light paper: light `#FFF8F0`, dark `#150C0A`. Cards are `#FFFDF9` / `#1F1512`. The system window (`background/systemWindow`, `#ECECEC` / `#1E1E1E`) is only where the system draws, such as Settings.

| Pair | Light | Dark | Rule |
|---|---|---|---|
| `text/primary` on `background/window` | 17.68 | 17.78 | text 4.5 |
| `text/primary` on `background/control` | 18.33 | 16.48 | text 4.5 |
| `text/secondary` on `background/window` | 6.22 | 8.52 | text 4.5 |
| `text/secondary` on `background/control` | 6.45 | 7.90 | text 4.5 |
| `text/secondary` on `background/systemWindow` | 5.54 | 7.36 | text 4.5 (Settings) |
| `text/primary` on `background/module` | 15.82 | 15.47 | text 4.5 |
| `text/secondary` on `background/module` | 5.56 | 7.41 | text 4.5 |
| `light/blueHour` on `background/window` | 7.11 | 7.94 | graphic 3 |
| `light/blueHour` on `background/module` | 6.36 | 6.91 | graphic 3 |
| `text/tertiary` on `background/window` | 2.73 | 3.65 | decoration only |
| `accent/text` on `background/window` | 5.70 | 8.30 | text 4.5 |
| `accent/text` on `background/control` | 5.91 | 7.70 | text 4.5 |
| `accent/text` on `background/systemWindow` | 5.08 | 7.18 | text 4.5 |
| `accent/primary` on `background/window` | 4.18 | 8.30 | graphic 3, large text 3 |
| `accent/primary` on `background/control` | 4.34 | 7.70 | graphic 3 |
| `accent/primary` on `background/systemWindow` | 3.73 | 7.18 | graphic 3 (system controls) |
| `accent/onAccent` on `accent/emphasis` | 6.00 | 8.30 | text 4.5 |
| `accent/onAccent` on `accent/primary` | 4.40 | 8.30 | icons and large text 3 |
| `text/primary` on `selection/fill` | 15.47 | 13.81 | text 4.5 |
| `text/secondary` on `selection/fill` | 5.44 | 6.62 | text 4.5 |
| `accent/text` on `selection/fill` | 4.98 | 6.45 | text 4.5 |
| `focus/ring` on `background/window` | 4.18 | 8.30 | graphic 3 |
| `route/active` on `background/window` | 4.18 | 8.30 | graphic 3 |
| `route/inactive` on `background/window` | 3.64 | 4.20 | graphic 3 |
| `map/pin` on `background/window` | 4.18 | 8.30 | graphic 3 |
| `map/pinInactive` on `background/window` | 4.28 | 4.91 | graphic 3 |
| `map/sun` on `background/window` | 4.18 | 8.30 | graphic 3 |
| `status/warning` on `background/window` | 6.21 | 8.78 | text 4.5 |
| `status/warning` on `background/control` | 6.44 | 8.14 | text 4.5 |
| `status/danger` on `background/window` | 7.14 | 7.81 | text 4.5 |
| `status/danger` on `background/control` | 7.40 | 7.24 | text 4.5 |
| `status/noForecast` on `background/window` | 4.81 | 6.89 | graphic 3 |
| `brand/dot` on `background/window` | 4.18 | 8.30 | logo (exempt) |

- `accent/primary` `#D9431A` is 4.18:1 on paper. It is for fills, icons, large text and graphics, not small text.
- `accent/text` `#B5360F` is the darker text-accent: 5.70:1 on paper and 5.08:1 on the system window.
- White on `#D9431A` is 4.40:1, so small text on a coral fill uses `accent/emphasis`, where `accent/onAccent` is 6.00:1.
- The text levels are ours. `text/tertiary` is 2.73:1 on paper: decoration and placeholders only, never information.

## Tokens

Every token, its values and its one job. Generated from the registry.

### Colours

| Token | Light | Dark | System alias | Single job |
|---|---|---|---|---|
| `accent/primary` | `#D9431A` | `#FF8A5C` |  | First Light coral. Interface accent: fills, icons, selection tint, focus, large text. Not small text on paper (4.18:1; use accent/text). Never a score, a status or an error. |
| `accent/text` | `#B5360F` | `#FF8A5C` |  | Accent as words (links, small labels) on paper or cards: 5.70:1 light, 8.30:1 dark. |
| `accent/hover` | `#C83D17` | `#FF9E78` |  | Accent fill while the pointer is over a custom control. |
| `accent/pressed` | `#B23510` | `#F07A4C` |  | Accent fill while a custom control is pressed. |
| `accent/disabled` | `#EBC3B2` | `#5E3426` |  | Accent fill or icon on a disabled custom control. Decorative contrast by design; pair with text/quaternary. |
| `accent/emphasis` | `#B5360F` | `#FF8A5C` |  | Accent fill behind small text (the Best tag, stop numbers): accent/onAccent on it is 6.0:1 light, 8.3:1 dark. |
| `accent/onAccent` | `#FFFFFF` | `#150C0A` |  | Text or icon on accent/emphasis (any size) or on accent/primary (icons and large text only: 4.40:1 light). |
| `selection/fill` | `#FBE6DB` | `#36221B` |  | Selected row, day or window in the app's own views, with an accent/primary stroke. Text on it keeps text/* colours: text/primary 15.47:1 and text/secondary 5.44:1 light, 13.81:1 and 6.62:1 dark; accent/text 4.98:1 light. |
| `focus/ring` | `#D9431A` | `#FF8A5C` |  | Keyboard focus ring on custom controls (3:1 or better against the window). Standard controls keep the system ring. |
| `route/active` | `#D9431A` | `#FF8A5C` |  | The route line, trip connectors and the switchback device for the leg being looked at. Not a rating. |
| `route/inactive` | `#9C7B70` | `#8F6E62` |  | Route lines and connectors for legs that are not selected. Warm grey-coral, 3:1 or better on paper. |
| `brand/dot` | `#D9431A` | `#FF8A5C` |  | The logo's dot (First Light coral). Graphic only, never text. |
| `map/pin` | `#D9431A` | `#FF8A5C` |  | Selected spot pin and trip stop pins for the day being looked at. |
| `map/pinInactive` | `#857369` | `#8F7D73` |  | Trip stop pins outside the day being looked at, and unselected stand-in pins. |
| `map/userLocation` | `#007AFF` | `#0A84FF` | `systemBlueColor` | The simulated user-location dot (-IterLocation), drawn like the system's blue dot. Real locations use MapKit's own indicator. |
| `map/sun` | `#D9431A` | `#FF8A5C` |  | The sun marker on the sky arc and the timeline. The light moment; never a fill behind text. |
| `map/moon` | `#5B6B8C` | `#C8D2EA` |  | The moon marker on the sky arc and the timeline. |
| `status/warning` | `#7A3EB8` | `#C79BFF` |  | Something needs attention (a tight schedule, stale forecast). Violet, always with a warning icon. Never amber, coral or green. |
| `status/danger` | `#A3115C` | `#FF77AE` |  | A destructive action or a failure. Raspberry, always with an icon and words. Kept 40+ deg (OKLCH) from the coral accent so it never reads as the brand. |
| `status/noForecast` | `#6E6E73` | `#9A9AA0` |  | No forecast: the hollow ring and dashed arc. Neutral by design; it is never a score colour. |
| `sky/night` | `#0B1530` | `#070D1F` |  | Timeline band: night. |
| `sky/blueHour` | `#3A4FA0` | `#34468F` |  | Timeline band: blue hour and twilight. |
| `sky/golden` | `#F0B35A` | `#C98A2E` |  | Timeline band: golden hour. Sky only; the Light Index uses light/ramp. |
| `sky/day` | `#CFE3F2` | `#5E87A8` |  | Timeline band: daylight. |
| `cloud/low` | `#8A94A3` | `#9AA3B2` |  | Low cloud layer fill in the cloud-by-altitude chart. |
| `cloud/mid` | `#B4BCC8` | `#6F7888` |  | Mid cloud layer fill. |
| `cloud/high` | `#DCE1E8` | `#4A5160` |  | High cloud layer fill. |
| `light/ramp/0` | `#FFFFFF` | `#1F1512` |  | Light Index fill at score 0: no light. White in light mode (paper-coloured, always with a hairline); the dark surface in dark mode, just above the window. The fill is a continuous ramp by score: linear RGB between the stops 0, 25, 50, 75 and 100 (IterColor.ramp(score:)). |
| `light/ramp/25` | `#FFEED9` | `#4A291D` |  | Light Index fill at score 25: a pale cream-peach in light mode, a deep ember in dark mode. |
| `light/ramp/50` | `#FFCFA1` | `#8E462C` |  | Light Index fill at score 50: apricot in light mode, burnt orange in dark mode. |
| `light/ramp/75` | `#FF975C` | `#D96B3E` |  | Light Index fill at score 75: bright orange. |
| `light/ramp/100` | `#D9431A` | `#FF8A5C` |  | Light Index fill at score 100: the First Light accent (accent/primary), full orange. More vibrant is better light; white or the dark surface is no light. |
| `light/rampText/ink` | `#1E0F0A` | `#FFF4E8` |  | Score, symbol and time on the ramp fill below the switch score: First Light ink (text/primary). 4.5:1 or better on the fill up to the switch score, except scores 98 to 99 (4.35 and 4.47) in light mode and 62 to 65 (4.12 to 4.46) in dark mode, where the fill is near the luminance at which neither colour reaches 4.5:1. |
| `light/rampText/inverse` | `#FFFFFF` | `#150C0A` |  | Score, symbol and time on the ramp fill from the switch score up: white on the full orange in light mode (4.40:1 at 100), the dark surface on the bright orange in dark mode (8.30:1 at 100). |
| `light/blueHour` | `#3A4FA0` | `#8FA4E8` |  | Blue-hour window symbol when it stands alone, outside a chip (3:1 graphic on background/window). Inside the event unit the symbol is white. |
| `text/primary` | `#1E0F0A` | `#FFF4E8` |  | Primary text: First Light ink (espresso / warm cream). |
| `text/secondary` | `#6B5A51` | `#BBA99D` |  | Secondary text, 4.5:1 or better on paper, cards and the system window. |
| `text/tertiary` | `#A6958B` | `#7A685E` |  | Decoration and placeholders only; never information. |
| `text/quaternary` | `#CDBDB2` | `#4F423B` |  | Disabled text. |
| `separator/default` | `#E6D6C8` | `#3A2C26` |  | Hairlines and dividers, warm. |
| `background/window` | `#FFF8F0` | `#150C0A` |  | First Light paper: the ground of the app's own content (spot page, trip builder, trips home, list panels). |
| `background/control` | `#FFFDF9` | `#1F1512` |  | Cards and lifted surfaces on paper. |
| `background/content` | `#FFFDF9` | `#1F1512` |  | Lists, text areas and pin labels on paper. |
| `background/module` | `#F5EBE0` | `#261B17` |  | Module card fill on paper (the Weather-style module: When to go, Light windows). text/primary and text/secondary are 4.5:1 or better on it. |
| `background/systemWindow` | `#ECECEC` | `#1E1E1E` | `windowBackgroundColor` | The system window colour, for snapshot stand-ins of system-drawn surfaces (sidebar, settings). Not for the app's own content. |

### Dimensions (points)

| Token | Value | Single job |
|---|---|---|
| `debug/grid` | `#FF2D55` | `#FF6482` |  | Debug ▸ Show Layout Grid: the 8 pt grid lines, drawn at debug/gridOpacity. Never shipped in a screen. |
| `debug/lane` | `#00A3BF` | `#4FD8EB` |  | Debug ▸ Show Layout Grid: lane bands and their edges, drawn at debug/laneOpacity. |
| `debug/gridOpacity` | 0.12 | Opacity of the layout-grid lines (a ratio, not points). Debug only. |
| `debug/laneOpacity` | 0.18 | Opacity of the layout-grid lane bands (a ratio, not points). Debug only. |
| `space/xxs` | 2 | Half step: icon to label inside a badge. |
| `space/xs` | 4 | Tight gap: inline items. |
| `space/sm` | 8 | Default gap between related items. |
| `space/md` | 12 | Padding inside cards and rows. |
| `space/lg` | 16 | Gap between groups; content margin. |
| `space/sheet` | 20 | Standard macOS sheet margin. |
| `space/xl` | 24 | Gap between sections. |
| `space/xxl` | 32 | Page-level margin and large separations. |
| `grid/unit` | 8 | The layout grid unit. Every gap, inset and row height is a multiple of it. |
| `grid/inset` | 16 | Inset of every module card and list: first lane starts, last lane ends this far from the edge. |
| `grid/lane/gap` | 8 | Gap between lanes in a row. |
| `grid/lane/disclosure` | 16 | Width of the disclosure (chevron) lane. |
| `grid/row/single` | 32 | Minimum height of a single-line row. |
| `grid/row/double` | 48 | Minimum height of a two-line row. |
| `event/height/compact` | 26 | Event unit height for pins, outlook days and Add Stop rows (a soft rounded rectangle, not a capsule). |
| `event/height/regular` | 32 | Event unit height in list rows (Explore, Locations, trip stops, day windows), about the height of the old pill plus one line of padding. |
| `event/height/large` | 52 | Event unit height in panel and page headers and trip overview cells. |
| `event/cornerRatio` | 0.25 | Event unit corner radius as a fraction of its height (a ratio, not points). |
| `event/score/compact` | 14 | Score numeral point size in the compact unit (heavy weight). |
| `event/score/regular` | 16 | Score numeral point size in the regular unit: 3 pt above body text (13 pt). |
| `event/score/large` | 30 | Score numeral point size in the large unit. |
| `event/time/compact` | 8 | Start time point size in the compact unit (light weight; 8 pt is the legible minimum). |
| `event/time/regular` | 9 | Start time point size in the regular unit (light weight). |
| `event/time/large` | 12 | Start time point size in the large unit. |
| `event/symbol/compact` | 8 | Window symbol point size above the time in the compact unit. |
| `event/symbol/regular` | 9 | Window symbol point size above the time in the regular unit. |
| `event/symbol/large` | 12 | Window symbol point size above the time in the large unit. |
| `event/stackGap/compact` | 1 | Gap between the symbol and the time in the compact unit. |
| `event/stackGap/regular` | 2 | Gap between the symbol and the time in the regular unit. |
| `event/stackGap/large` | 4 | Gap between the symbol and the time in the large unit. |
| `event/gap` | 6 | Gap between the numeral and the symbol-and-time stack, regular unit. |
| `event/gapCompact` | 4 | Gap between the numeral and the stack, compact unit. |
| `event/gapLarge` | 8 | Gap between the numeral and the stack, large unit. |
| `event/padding` | 8 | Horizontal padding inside the regular unit. |
| `event/paddingCompact` | 6 | Horizontal padding inside the compact unit. |
| `event/paddingLarge` | 12 | Horizontal padding inside the large unit. |
| `event/pinShadowRadius` | 4 | Shadow radius under a map pin label. |
| `event/pinShadowRadiusSelected` | 12 | Shadow radius under the selected map pin label. |
| `event/pinScaleSelected` | 1.15 | Scale factor (a ratio, not points) of the selected map pin label, anchored at its pointer. |
| `event/lowConfidenceOpacity` | 0.85 | Opacity of an event chip whose score has low confidence (a ratio, not points). |
| `radius/badge` | 6 | Corner radius of Light Index badges and chips. |
| `radius/control` | 8 | Corner radius of custom controls. |
| `radius/card` | 12 | Corner radius of cards and thumbnails. |
| `radius/panel` | 16 | Corner radius of floating panels over the map. |
| `size/badge/heightCompact` | 18 | Light Index badge height in dense lists. |
| `size/badge/height` | 22 | Light Index badge height, default. |
| `size/badge/heightLarge` | 28 | Light Index badge height in headers. |
| `size/badge/minWidth` | 28 | Smallest badge width so two-digit scores line up. |
| `size/mapPin` | 28 | Map pin diameter. |
| `size/mapPinSelected` | 36 | Selected map pin diameter. |
| `size/control/height` | 28 | Custom control height on macOS. |
| `size/control/heightLarge` | 36 | Large custom control height. |
| `size/hitTarget` | 28 | Smallest click target for any control. |
| `size/icon/small` | 14 | Small symbol size. |
| `size/icon/medium` | 16 | Default symbol size. |
| `size/icon/large` | 20 | Large symbol size. |
| `size/confidenceMark` | 14 | Confidence mark diameter. |
| `size/imageStripHeight` | 200 | Height of the place image strip (Look Around or satellite) at the top of Explore's light panel and the offline image request. |
| `size/lightRing/small` | 32 | Score ring in rows. |
| `size/lightRing/medium` | 44 | Score ring on cards. |
| `size/lightRing/large` | 64 | Score ring in headers. |
| `chart/timelineHeight` | 56 | Height of the sky-gradient light timeline. |
| `chart/timelineAxisHeight` | 18 | Height of the timeline's hour axis. |
| `chart/arcHeight` | 168 | Height of the sun and moon arc chart. |
| `chart/arcMarker` | 14 | Sun and moon marker diameter on the arc. |
| `chart/hourlyTintHeight` | 40 | Height of the hourly tint strip. |
| `chart/windowMinWidth` | 4 | Narrowest a light window may be drawn on the timeline. |
| `layout/sidebarMin` | 240 | Sidebar minimum width: equal to the ideal, so the sidebar never squeezes; it collapses instead. |
| `layout/sidebarIdeal` | 240 | Sidebar ideal width. |
| `layout/sidebarMax` | 320 | Sidebar maximum width. |
| `layout/listMin` | 300 | Content list minimum width. |
| `layout/listIdeal` | 360 | Content list ideal width. |
| `layout/listMax` | 520 | Content list maximum width. |
| `layout/listColumnMin` | 340 | Narrowest a list column beside a map may be (Explore, Saved, Scout, the trip plan): the spot name plus the fixed light column still fit. |
| `layout/detailMin` | 420 | Narrowest the map or detail pane beside a list may be, so a map stays usable and the place card fits. |
| `layout/inspectorMin` | 280 | Inspector minimum width. |
| `layout/inspectorIdeal` | 320 | Inspector ideal width. |
| `layout/inspectorMax` | 420 | Inspector maximum width. |
| `layout/imageRequestWidth` | 360 | The point width at which place images are requested and cached (the list column's ideal width); the strip draws them at the column's width. |
| `layout/windowMinWidth` | 761 | Main window minimum width, derived: layout/listColumnMin (340) + layout/detailMin (420) + a 1 pt divider, so with the sidebar collapsed no column clips. The sidebar collapses on its own below layout/sidebarIdeal plus this. |
| `layout/windowMinHeight` | 600 | Main window minimum height. |
| `stroke/hairline` | 0.5 | Hairline border on cards and badges. |
| `stroke/thin` | 1 | Thin stroke: chart axes, outlines. |
| `stroke/regular` | 1.5 | Regular stroke: icons, ring tracks. |
| `stroke/thick` | 2 | Thick stroke: arcs, markers, score rings. |
| `stroke/route` | 4 | Route line width, active leg. |
| `stroke/routeInactive` | 3 | Route line width, inactive leg. |
| `stroke/routeCasing` | 7 | Casing drawn under the route line so it reads over the map. |
| `stroke/dashLength` | 4 | Dash length of the no-forecast arc. |
| `stroke/dashGap` | 3 | Dash gap of the no-forecast arc. |
| `stroke/focusRingWidth` | 3 | Focus ring width. |
| `stroke/focusRingOffset` | 2 | Gap between a control and its focus ring. |

### Type

| Token | Text style | Weight | Design | Monospaced digits | Single job |
|---|---|---|---|---|---|
| `type/title/spot` | `title` | semibold | serif | false | Spot and trip title voice. New York. Place names only. |
| `type/title/section` | `title2` | semibold | standard | false | Section titles. |
| `type/headline` | `headline` | semibold | standard | false | Row and card titles. |
| `type/body` | `body` | regular | standard | false | Running text. |
| `type/bodyEmphasis` | `body` | semibold | standard | false | Emphasised running text. |
| `type/callout` | `callout` | regular | standard | false | Explanations and reasons. |
| `type/subheadline` | `subheadline` | regular | standard | false | Secondary lines. |
| `type/footnote` | `footnote` | regular | standard | false | Footnotes and forecast age. |
| `type/secondary` | `subheadline` | regular | standard | false | All secondary metadata: locality, distance, band word, confidence word, axis labels. Used in text/secondary. |
| `type/moduleTitle` | `subheadline` | semibold | standard | false | Module card titles, in text/secondary with a leading symbol. |
| `type/caption` | `caption` | regular | standard | false | Captions. |
| `type/captionStrong` | `caption` | semibold | standard | false | Emphasised captions and badge words. |
| `type/score/large` | `largeTitle` | semibold | standard | true | Headline Light Index number. |
| `type/score/medium` | `title3` | semibold | standard | true | Light Index number on cards. |
| `type/score/badge` | `caption` | semibold | standard | true | Number inside a badge. |
| `type/time` | `body` | regular | standard | true | Clock times and durations. |
| `type/timeSmall` | `footnote` | regular | standard | true | Small times and chart axes. |
| `type/event/score` | `largeTitle` | heavy | standard | true | Score numeral in the event unit. Weight and design only: the size is event/score/* (a fixed-height unit does not scale with Dynamic Type). |
| `type/event/time` | `caption2` | thin | standard | true | Start time in the large event unit. Size is event/time/*. |
| `type/event/timeSmall` | `caption2` | light | standard | true | Start time in the regular and compact event unit (thin hairlines vanish at 7 to 10 pt). Size is event/time/*. |

Spacing is on an 8-pt scale (`space/sm` 8, `space/lg` 16, `space/xl` 24, `space/xxl` 32; the `grid/*` tokens name the lane, inset and row-height steps). 4 (`space/xs`) is only for hairline-tight pairs, such as a symbol and its number inside the event unit. `space/md` (12) and `space/xxs` (2) are kept for old code and are not used in new layout. Event-unit tokens (`event/*`) size the one score chip; `event/pinScaleSelected`, `event/lowConfidenceOpacity` and `debug/*Opacity` are ratios stored as dimension tokens. Type uses system fonts only: SF Pro, with New York (`.serif` design) for the spot and trip title voice, and monospaced digits for every number, time and score. Each type token names a `Font.TextStyle`, weight and design, so system sizing and Dynamic Type still apply; the px size in `tokens.json` is the macOS default for that style, for reference in design tools.

## Where First Light stops

- The sidebar, toolbar, Settings window, sheets (New Trip, Change Dates, Spot editor) and standard controls keep the system's materials and colours and take coral only through the app accent, because Liquid Glass and vibrancy need the system backdrop to stay legible and native.
- First Light paper and ink cover what the app draws itself (content backgrounds, lists, cards, the spot page, the trip builder, badges, pins and routes); in a selected row of a system list the text falls back to the system's colours so it stays readable on the accent fill.

## Using them in code

```swift
Text("82").font(IterFont.captionStrong).foregroundStyle(IterColor.rampText(score: 82))
    .padding(.horizontal, IterSpace.sm).frame(height: IterSize.badgeHeight)
    .background(IterColor.ramp(score: 82), in: RoundedRectangle(cornerRadius: IterRadius.badge))
```

No view may contain a literal point value or colour; add a token instead.

## Round trip with a design tool

1. `scripts/tokens.sh` (export) writes `Design/tokens.json` and the colour sets from `TokenValues.swift`.
2. Import `tokens.json` into the design tool (Figma reads DTCG as variables; dark values and system aliases are under `$extensions["com.dwjames.iter"]`, so map `dark` to a Dark mode). Colours use `{ colorSpace, components, hex }`; dimensions are `{ value, unit: "px" }`; type styles are composite tokens, with the SwiftUI text style, design and monospaced-digits flag in the extension.
3. Edit values in the tool, export them back to the same JSON shape, and replace `Design/tokens.json`.
4. `scripts/tokens.sh import` regenerates `TokenValues.swift` from the JSON.
5. Review the diff of `TokenValues.swift`, run `scripts/tokens.sh` to refresh the colour sets, then `swift test` (contrast and round-trip tests catch an edit that breaks 4.5:1 or monotonic order). Commit all of it together.

The tests also check that the committed `tokens.json` and `TokenValues.swift` are exactly what the generator writes, so they cannot drift apart. `iter-tokens` takes its paths as arguments: `iter-tokens export --json <file> --assets <catalog>` and `iter-tokens import --json <file> --swift <file>`.

## NightModeReady

Milestone 2 adds a Night mode (red and dim, with greens remapped). The registry is shaped for it: a colour token is a name plus a set of appearance values (today `light` and `dark`), and the API resolves a name through one function (`IterColor.color(for:)`). Adding a night column means adding a field to `ColorToken`, a `night` entry under the DTCG extension, an extra appearance in the colour sets and a branch in that one resolver. No token names or call sites change. The system-aliased tokens, `background/systemWindow` and `map/userLocation`, would need a night override too, since system colours do not know Night mode.

## App icon

Convention for macOS 26 (Apple HIG, "App icons"): icons are square and the system applies the rounded-rectangle mask, so artwork should be unmasked, square layers on a 1024 by 1024 canvas, with the primary content centred and no baked-in shadows, highlights or rounded corners. The older macOS convention (an 824-pt rounded rectangle with a margin and a drop shadow inside the 1024 canvas) is what the new system would double-mask, so we do not use it.

Decision: `Brand/logo/app-icon.svg` is the source, already in First Light colours, with a rounded ground (`rx=230`). `scripts/make-icon.sh` removes the rounding, so the ground is a full-bleed square, and renders that to all ten macOS sizes (16, 32, 128, 256, 512 at 1x and 2x) at exact pixel sizes with AppKit (no windows opened). The mark is vertical and centred, well inside the corners, so masking does not touch it. The icon is First Light: ground `#1E0F0A`, mark `#FFF4E8`, dot `#FF8A5C`, written in `app-icon.svg` itself; the script does not recolour it. `Brand/logo/_retired/` holds the retired gold files and an unused First Light icon with different mark geometry (see its README); no script reads them.

Limitation, to revisit: there are no dark or tinted variants in the PNG `AppIcon.appiconset`, and a PNG-only set does not get the layered Liquid Glass treatment of macOS 26. For that, make an Icon Composer `.icon` file (ground as the background layer, the `i` as a foreground layer, the dot as a second layer) in a later milestone; the full-bleed square is already the right input for it.

## In-app logo

`Logo`, `Symbol` (full colour) and `LogoMono`, `SymbolMono` (template) image sets are vector assets. An asset catalog does not resolve `currentColor`, so the full-colour brand SVGs have the colours written out: First Light ink (`#1E0F0A` light, `#FFF4E8` dark) with the coral dot (`#D9431A` light, `#FF8A5C` dark). `Brand/logo/lockup.svg` and `symbol.svg` are the light files, `lockup-dark.svg` and `symbol-dark.svg` the dark-appearance variants, and `scripts/make-icon.sh` copies them into the image sets unchanged. `favicon-16.svg` is the same geometry with the `#D9431A` dot and `currentColor` ink. The mono files are `currentColor` only; the script writes them out as black templates that take the view's foreground style. Regenerate with `scripts/make-icon.sh`.
