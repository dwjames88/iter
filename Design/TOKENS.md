# Iter design tokens

The single source is `Packages/IterKit/Sources/IterDesign/TokenValues.swift`. Everything else is derived from it:

- the Swift API (`IterColor`, `IterSpace`, `IterRadius`, `IterSize`, `IterStroke`, `IterFont`), which reads the registry at run time and contains no literals;
- `Design/tokens.json`, in the Design Tokens Community Group (DTCG) format, for design tools;
- `App/Resources/Assets.xcassets/Tokens/*.colorset` and `AccentColor.colorset`, so colours are also available as named asset colours.

Do not edit the generated files by hand. Edit `TokenValues.swift` (or `tokens.json`, see "Round trip") and run `scripts/tokens.sh`.

## The identity, in one paragraph (option C)

Alpine is the land and the journey: the interface accent, route lines and connectors. First Light's coral is the light moment only: the sun marker. The logo dot stays the gold of the chosen Step files until the owner decides on option C. The Light Index is a single-hue ramp from neutral sand to deep amber, ordered by lightness, and the band word is always printed beside it. Status colours have their own hues and always come with an icon. Window, sidebar, list and control colours are the system's, not ours: text, separators and backgrounds are aliases of `labelColor`, `separatorColor`, `windowBackgroundColor` and friends.

## Colour role rules (what each colour must never be used for)

| Colour | Is for | Must never be |
|---|---|---|
| `accent/primary` (Alpine glacier teal) | Selection, primary actions, focus, icons that act | A score, a rating, "good", "done" or "success". Body text on a light background (use `accent/text`). |
| `accent/text` | Accent-coloured words | A fill. |
| `route/active`, `route/inactive` | Route lines, trip connectors, the switchback device | Pin colours for data, or any rating. Teal means "the way", never "good light". |
| `brand/dot` (the Step file's gold) | The logo dot | Anything but the logo. |
| `map/sun` (First Light coral) | One sun marker | A score, a status, a button, a map pin, a large fill, text. At most one coral mark per view. It is not part of the ramp (we chose not to put coral at the top of it). |
| `map/moon` | The moon marker | A status. |
| `light/ramp/*` | The Light Index fill for a band | Green, red or coral. Shown without the band word or number. Used for anything that is not a Light Index value. |
| `light/rampText/*` | Text and icons on the matching ramp fill | Text on any other ground. |
| `status/warning` (violet) | A warning, always with an icon | Amber (that is the ramp), coral, green. |
| `status/danger` (crimson) | A failure or destructive action, always with an icon | Coral (it sits close to the brand dot and must not be confused with it). |
| `status/noForecast` (neutral grey) | The hollow ring and dashed arc: no forecast | A "low score". Unknown is not poor. |
| `sky/*` | The timeline's sky bands | Light Index fills (golden sky is not "Great"). |
| `cloud/*` | Cloud layers by altitude | Anything else. |
| `text/*`, `separator/default`, `background/*` | Everything the system draws | Replaced by custom chrome colours. They are aliases of system colours. |

Green is not used anywhere, and in particular never for "good". Success is ink with a check icon.

## Light Index ramp

Single hue (amber), sand to deep amber. In light mode the fills get darker as light gets better; in dark mode they get lighter (a brighter amber glows on a dark ground). Both are strictly monotonic in luminance, so the order survives greyscale. Adjacent bands differ by at least 1.2:1 in luminance, and Good versus Epic stays at 1.8:1 or more after a deuteranopia simulation (Machado 2009), so lightness, not hue, separates them. These are checked by `ContrastTests`.

| Band | Light fill | Light text | Text contrast | Dark fill | Dark text | Text contrast |
|---|---|---|---|---|---|---|
| Poor | `#E4DCCB` | `#2B2112` | 11.59 | `#3A362F` | `#F2EBDD` | 10.12 |
| Fair | `#D8C08E` | `#2B2112` | 8.92 | `#5C4F36` | `#FFF3DA` | 7.27 |
| Good | `#D9A646` | `#2B1A00` | 7.59 | `#8F6A21` | `#FFFFFF` | 4.94 |
| Great | `#A8640A` | `#FFFFFF` | 4.67 | `#D9962B` | `#1F1300` | 7.25 |
| Epic | `#6B3800` | `#FFFFFF` | 9.59 | `#FFC05A` | `#1F1300` | 11.24 |

Known limit: the lightest fills (Poor, Fair) cannot reach 3:1 against the window and be sand at the same time. A badge therefore always carries its word or number (4.5:1 or better on the fill) and a hairline stroke in `separator/default`; the fill alone is never the only signal.

## Contrast numbers (WCAG 2.x, checked in tests)

Window grounds: light `#ECECEC`, dark `#1E1E1E` (the resolved values of `windowBackgroundColor`; cards are `#FFFFFF` / `#1E1E1E`).

| Pair | Light on window | Dark on window | Rule |
|---|---|---|---|
| `accent/primary` | 4.31 | 10.31 | graphic, 3:1 |
| `accent/text` | 5.51 | 10.31 | text, 4.5:1 |
| `route/active` | 4.31 | 10.31 | graphic, 3:1 |
| `route/inactive` | 3.73 | 5.33 | graphic, 3:1 |
| `focus/ring` | 4.31 | 10.31 | graphic, 3:1 |
| `map/sun` | 3.73 | 7.18 | graphic, 3:1 |
| `brand/dot` | logo, exempt | logo, exempt | WCAG 1.4.11 exempts logos |
| `map/moon` | 4.53 | 11.01 | graphic, 3:1 |
| `status/warning` | 5.54 | 7.59 | text, 4.5:1 |
| `status/danger` | 5.24 | 6.71 | text, 4.5:1 |
| `status/noForecast` | 4.29 | 5.96 | graphic, 3:1 |
| `accent/onAccent` on `accent/primary` | 5.10 | 11.09 | text on fill, 4.5:1 |

The system's own `text/secondary` is 3.84:1 on the light window (4.54 on a card) and `text/tertiary` about 1.9:1. They are Apple's choices, and we follow them: secondary for supporting text that is also available elsewhere, tertiary for decoration and placeholders, never for information.

## Tokens

Every token, its values and its one job. Generated from the registry.

### Colours

| Token | Light | Dark | System alias | Single job |
|---|---|---|---|---|
| `accent/primary` | `#0A7C6E` | `#5FE0C8` |  | Alpine glacier. Interface accent for the land and the journey: selection tint, primary buttons, links' icons, focus. Never a score, never a state of good. |
| `accent/text` | `#076A5D` | `#5FE0C8` |  | Accent when it is text on a window or card background (4.5:1 or better). Use instead of accent/primary for words. |
| `accent/onAccent` | `#FFFFFF` | `#0A1A14` |  | Text or icon placed on a fill of accent/primary. |
| `focus/ring` | `#0A7C6E` | `#5FE0C8` |  | Keyboard focus ring on custom controls (3:1 or better against the window). Standard controls keep the system ring. |
| `route/active` | `#0A7C6E` | `#5FE0C8` |  | The route line, trip connectors and the switchback device for the leg being looked at. Not a rating. |
| `route/inactive` | `#5C7F79` | `#6F9A92` |  | Route lines and connectors for legs that are not selected. Still 3:1 against the window. |
| `brand/dot` | `#F5B72B` | `#F5B72B` |  | The logo's dot, as drawn in the chosen Step files (gold). Graphic only, never text. Whether it becomes First Light coral (option C) is the owner's call. |
| `map/sun` | `#D9431A` | `#FF8A5C` |  | The sun marker on the sky arc and the timeline. One small mark; never a fill behind text. |
| `map/moon` | `#5B6B8C` | `#C8D2EA` |  | The moon marker on the sky arc and the timeline. |
| `status/warning` | `#7A3EB8` | `#C79BFF` |  | Something needs attention (a tight schedule, stale forecast). Violet, always with a warning icon. Never amber, coral or green. |
| `status/danger` | `#C0123C` | `#FF7A93` |  | A destructive action or a failure. Crimson, always with an icon. Never coral. |
| `status/noForecast` | `#6E6E73` | `#9A9AA0` |  | No forecast: the hollow ring and dashed arc. Neutral by design; it is never a score colour. |
| `sky/night` | `#0B1530` | `#070D1F` |  | Timeline band: night. |
| `sky/blueHour` | `#3A4FA0` | `#34468F` |  | Timeline band: blue hour and twilight. |
| `sky/golden` | `#F0B35A` | `#C98A2E` |  | Timeline band: golden hour. Sky only; the Light Index uses light/ramp. |
| `sky/day` | `#CFE3F2` | `#5E87A8` |  | Timeline band: daylight. |
| `cloud/low` | `#8A94A3` | `#9AA3B2` |  | Low cloud layer fill in the cloud-by-altitude chart. |
| `cloud/mid` | `#B4BCC8` | `#6F7888` |  | Mid cloud layer fill. |
| `cloud/high` | `#DCE1E8` | `#4A5160` |  | High cloud layer fill. |
| `light/ramp/poor` | `#E4DCCB` | `#3A362F` |  | Light Index fill, Poor band. Sand. Single hue ramp, ordered by lightness. Always printed with the band word. |
| `light/ramp/fair` | `#D8C08E` | `#5C4F36` |  | Light Index fill, Fair band. |
| `light/ramp/good` | `#D9A646` | `#8F6A21` |  | Light Index fill, Good band. Amber, not green. |
| `light/ramp/great` | `#A8640A` | `#D9962B` |  | Light Index fill, Great band. |
| `light/ramp/epic` | `#6B3800` | `#FFC05A` |  | Light Index fill, Epic band. Deepest amber in light mode, brightest in dark mode. |
| `light/rampText/poor` | `#2B2112` | `#F2EBDD` |  | Band word or number on light/ramp/poor (4.5:1 or better). |
| `light/rampText/fair` | `#2B2112` | `#FFF3DA` |  | Band word or number on light/ramp/fair. |
| `light/rampText/good` | `#2B1A00` | `#FFFFFF` |  | Band word or number on light/ramp/good. |
| `light/rampText/great` | `#FFFFFF` | `#1F1300` |  | Band word or number on light/ramp/great. |
| `light/rampText/epic` | `#FFFFFF` | `#1F1300` |  | Band word or number on light/ramp/epic. |
| `text/primary` | `#262626` | `#DFDFDF` | `labelColor` | Primary text: system labelColor. |
| `text/secondary` | `#767676` | `#9A9A9A` | `secondaryLabelColor` | Secondary text: system secondaryLabelColor. |
| `text/tertiary` | `#AFAFAF` | `#565656` | `tertiaryLabelColor` | Tertiary text: system tertiaryLabelColor. Decoration and placeholders only; never information. |
| `text/quaternary` | `#D4D4D4` | `#424242` | `quaternaryLabelColor` | Disabled text: system quaternaryLabelColor. |
| `separator/default` | `#D6D6D6` | `#3C3C3C` | `separatorColor` | Hairlines and dividers: system separatorColor. |
| `background/window` | `#ECECEC` | `#1E1E1E` | `windowBackgroundColor` | Window background: system windowBackgroundColor. |
| `background/control` | `#FFFFFF` | `#1E1E1E` | `controlBackgroundColor` | Lists, cards and controls surface: system controlBackgroundColor. |
| `background/content` | `#FFFFFF` | `#1E1E1E` | `textBackgroundColor` | Text areas and editable content: system textBackgroundColor. |

### Dimensions (points)

| Token | Value | Single job |
|---|---|---|
| `space/xxs` | 2 | Half step: icon to label inside a badge. |
| `space/xs` | 4 | Tight gap: inline items. |
| `space/sm` | 8 | Default gap between related items. |
| `space/md` | 12 | Padding inside cards and rows. |
| `space/lg` | 16 | Gap between groups; content margin. |
| `space/xl` | 24 | Gap between sections. |
| `space/xxl` | 32 | Page-level margin and large separations. |
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
| `size/lightRing/small` | 32 | Score ring in rows. |
| `size/lightRing/medium` | 44 | Score ring on cards. |
| `size/lightRing/large` | 64 | Score ring in headers. |
| `chart/timelineHeight` | 56 | Height of the sky-gradient light timeline. |
| `chart/timelineAxisHeight` | 18 | Height of the timeline's hour axis. |
| `chart/arcHeight` | 168 | Height of the sun and moon arc chart. |
| `chart/arcMarker` | 14 | Sun and moon marker diameter on the arc. |
| `chart/hourlyTintHeight` | 40 | Height of the hourly tint strip. |
| `chart/windowMinWidth` | 4 | Narrowest a light window may be drawn on the timeline. |
| `layout/sidebarMin` | 200 | Sidebar minimum width. |
| `layout/sidebarIdeal` | 240 | Sidebar ideal width. |
| `layout/sidebarMax` | 320 | Sidebar maximum width. |
| `layout/listMin` | 300 | Content list minimum width. |
| `layout/listIdeal` | 360 | Content list ideal width. |
| `layout/listMax` | 520 | Content list maximum width. |
| `layout/inspectorMin` | 280 | Inspector minimum width. |
| `layout/inspectorIdeal` | 320 | Inspector ideal width. |
| `layout/inspectorMax` | 420 | Inspector maximum width. |
| `layout/windowMinWidth` | 900 | Main window minimum width. |
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
| `type/caption` | `caption` | regular | standard | false | Captions. |
| `type/captionStrong` | `caption` | semibold | standard | false | Emphasised captions and badge words. |
| `type/score/large` | `largeTitle` | semibold | standard | true | Headline Light Index number. |
| `type/score/medium` | `title3` | semibold | standard | true | Light Index number on cards. |
| `type/score/badge` | `caption` | semibold | standard | true | Number inside a badge. |
| `type/time` | `body` | regular | standard | true | Clock times and durations. |
| `type/timeSmall` | `footnote` | regular | standard | true | Small times and chart axes. |

Spacing is on a 4-pt grid (`space/xxs` is the one half step). Type uses system fonts only: SF Pro, with New York (`.serif` design) for the spot and trip title voice, and monospaced digits for every number, time and score. Each type token names a `Font.TextStyle`, weight and design, so system sizing and Dynamic Type still apply; the px size in `tokens.json` is the macOS default for that style, for reference in design tools.

## Using them in code

```swift
Text("Sunset").font(IterFont.captionStrong).foregroundStyle(IterColor.rampText(band))
    .padding(.horizontal, IterSpace.sm).frame(height: IterSize.badgeHeight)
    .background(IterColor.ramp(band), in: RoundedRectangle(cornerRadius: IterRadius.badge))
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

Milestone 2 adds a Night mode (red and dim, with greens remapped). The registry is shaped for it: a colour token is a name plus a set of appearance values (today `light` and `dark`), and the API resolves a name through one function (`IterColor.color(for:)`). Adding a night column means adding a field to `ColorToken`, a `night` entry under the DTCG extension, an extra appearance in the colour sets and a branch in that one resolver. No token names or call sites change. System-aliased tokens would need a night override too, since system colours do not know Night mode.

## App icon

Convention for macOS 26 (Apple HIG, "App icons"): icons are square and the system applies the rounded-rectangle mask, so artwork should be unmasked, square layers on a 1024 by 1024 canvas, with the primary content centred and no baked-in shadows, highlights or rounded corners. The older macOS convention (an 824-pt rounded rectangle with a margin and a drop shadow inside the 1024 canvas) is what the new system would double-mask, so we do not use it.

Decision: `Brand/logo/app-icon.svg` has a rounded ground (`rx=230`). `scripts/make-icon.sh` removes the rounding, so the ground is a full-bleed square, and renders that to all ten macOS sizes (16, 32, 128, 256, 512 at 1x and 2x) at exact pixel sizes with AppKit (no windows opened). The mark is vertical and centred, well inside the corners, so masking does not touch it. The dot keeps the gold of the chosen Step file (`#F5B72B`); recolouring it First Light coral (option C) is the owner's decision, and `scripts/make-icon.sh` has the two colour variables to change.

Limitation, to revisit: a PNG-only `AppIcon.appiconset` does not get the layered Liquid Glass treatment or the dark and tinted variants of macOS 26. For that, make an Icon Composer `.icon` file (ground as the background layer, the `i` as a foreground layer, the dot as a second layer) in a later milestone; the full-bleed square is already the right input for it.

## In-app logo

`Logo`, `Symbol` (full colour) and `LogoMono`, `SymbolMono` (template) image sets are vector assets. The brand SVGs use `currentColor`, which an asset catalog does not resolve, so colours are written out: Alpine ink (`#0F2A20` light, `#EEF4F1` dark) with the coral dot (`#D9431A` light, `#FF8A5C` dark); the dark file is the dark-appearance variant. The mono sets are black templates that take the view's foreground style. Regenerate with `scripts/make-icon.sh`.
