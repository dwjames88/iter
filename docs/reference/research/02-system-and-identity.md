# 02 · Design system and visual identity

This is the system-level view: the token structure, type, colour, components, the data-visualisation system, accessibility and motion, how it will translate to native, and whether the overall identity is distinctive and fits the Iter brand. It ends with the ten changes that would raise perceived quality most.

**Evidence.** Code read on 2026-10-04 (`src/design/*`, `src/index.css`, `src/components/**`); contrast and colour-vision figures computed with WCAG 2.x luminance and Machado (2009) colour-vision simulation (scripts in the scratchpad, not in the repo); the screenshots in [screens/](screens/) (see [01](01-screen-by-screen-audit.md)); and the logo explorations in `brand/iter/`. I spot-checked the measurements (for example `#717171` on white = 4.88:1, `#B0B0B0` on white = 2.17:1, the focus ring = 1.24:1) and the cited code lines.

---

## Verdict in one paragraph

The engineering of the system is unusually good for a prototype: two clean token layers, zero drift between `tokens.ts` and `index.css`, almost no raw values in components, a living styleguide with stable ids for export. The *design* of the system is where the work is. Its colour and component language is close to a straight copy of Airbnb's (the brand red `#FF385C` and four of Airbnb's greys, white cards, black pills, photo cards with white pill badges), so Iter currently looks like a competent Airbnb theme rather than a product with its own point of view. Its one original idea, light, is encoded in a five-hue scale that fails contrast, collapses for colour-blind users and, because of how the score is computed, paints almost everything "Epic" red. The distinctive assets already exist (the sky-gradient timeline, the sun-and-moon arc with the camera "frame" wedge, the gold italic *light*), but they are buried below the fold. The rebrand is the moment to make light the system rather than a decoration.

---

## 1. Tokens

**What works (keep).**
- Two layers: 25 primitives (`palette`) and 28 semantic roles (`text/*`, `surface/*`, `border/*`, `brand/*`, `accent/*`, `light/*`). Components use the semantic names.
- No value drift between `tokens.ts` and `index.css` (every palette, semantic, radius, space, shadow, size, type and duration value checked). The header comments claim the CSS is generated, but no generator exists, so the sync is manual and will eventually break.
- A 4pt spacing scale, radii 4–32 plus full, component sizes as tokens (control 36/44/52, icon 14–24, ring 44/64/96), motion as three durations and one easing.
- Component code is nearly token-clean: no arbitrary text sizes and no hex literals outside two domain files (`spotTokens.ts`, 14 category-art colours; `lib/utils.ts`, 8 member colours, three of them off-palette).

**Gaps, in order of importance.**

| Gap | Why it matters | Fix |
|---|---|---|
| **No dark mode** | A photographers' app is used at dawn, dusk and night. A bright white UI at 5 a.m. ruins night vision. Native will get dark mode by default and the tokens have no answer for it. | Add a dark theme now (the semantic layer makes it a remap). Consider a dedicated **Night** mode (deep neutral with dimmed or red-shifted accents) as a feature, not just a theme. Figma imports DTCG JSON as a variable mode natively ([04](04-design-tool-path.md)). |
| **No data-viz palette** | Four ad-hoc colour sets (light bands, 10 day colours, 8 member colours, category art) overlap: `#FF385C` is Epic, the danger button, Day 1, member 1, the "Now" marker and the live dot. | A named `viz/*` group: one sequential ramp for the Light Index, one categorical set for days and people (max ~6, colour-blind-checked), and reserved status colours. |
| **No status colours** | Only `text/danger`. Warnings borrow brand gold, info borrows sky blue. | `status/success`, `status/warning`, `status/danger`, `status/info`, each with text-safe and fill variants. |
| **No focus token** | The focus ring is a 4px shadow of 10% black: **1.24:1** against white, and `outline: none` is set on every `.focus-ring`. Keyboard users effectively cannot see focus on buttons, chips, cards or nav. | A `focus/ring` colour token (ink or a strong accent at ≥3:1) with width 2 and offset 2. |
| **No material or translucency layer** | The bars use `white/85 + backdrop-blur` ad hoc; iOS 26 and macOS Tahoe put controls on Liquid Glass. | `material/bar`, `material/floating` tokens with a solid fallback. |
| **No z-index, breakpoint or elevation scales** | z-values 10–50 plus arbitrary 35/90/100/120; breakpoints are Tailwind defaults with Explore switching at 768 and Trip builder at 1024. | Name them (`z/map-controls`, `z/sheet`, `z/modal`, `z/toast`; `bp/compact`, `bp/regular`, `bp/wide`). Use one layout breakpoint per screen. |
| **Size tokens emitted as spacing** | `--spacing-control-md` also generates nonsense utilities (`p-control-md`) and odd Figma variable names. | Separate `size/*` from `space/*`. |

## 2. Typography

**The scale.** 18 styles: 5 serif display steps (88/64/48/36/24, weight 400), 4 sans headings (32/24/20/17), 3 body (17/15/13), 3 labels (15/13/12), an 11px overline and two numerals (40/24, at width 90). The steps are sensible and 15 of the 18 sit within about 2pt of an iOS Dynamic Type style, which helps the port.

**What works.** Roboto Serif at large sizes is the most characterful thing in the product: "Southwest Loop", "Trips" and the landing headline look editorial and confident ([46-trip-builder-desktop.webp](screens/46-trip-builder-desktop.webp), [44-trips-populated-desktop.webp](screens/44-trips-populated-desktop.webp)). Archivo is a good UI face with useful width and weight axes.

**Problems.**
1. **Two voices that don't agree, and a third coming.** The UI is serif-led (display, page titles, pull-quotes, italic accents), while every logo exploration is a geometric sans ([§8](#8-identity-distinctive-or-generic)). The brief says "modern, minimalistic, tech"; an italic serif accent ("Ask *Vantage*", "around the *light*", "Plan a trip around *the light*") says luxury travel magazine. The italic-gold-word device is repeated on at least four screens and is starting to feel like a template.
2. **The serif is used where it costs the most.** The spot page's serif pull-quote (about 28px, 4 lines on phone) pushes "When to shoot" out of the first viewport ([30-spot-top-phone.webp](screens/30-spot-top-phone.webp)). Serif belongs to *place and story*; data and decisions should be sans.
3. **Small text is weak.** The 11px overline and 12–13px labels in `#717171` (4.88:1) and `#B0B0B0` (2.17:1, used as informational text in 24 places) read thin and grey at 1x. Tracked uppercase eyebrows ("LIGHT INDEX · TUE, OCT 6", "BEST WINDOW", "TEMPLATE") appear on almost every card and flatten the hierarchy.
4. **Numbers deserve their own treatment.** The product is full of times and scores, but only the two numeral styles use tabular figures and the narrower width. Times such as "6:36–7:10 PM" are set in body text.
5. **`label-sm` defaults to 600** and is overridden to 400 in 100+ places, which signals a missing 12px regular caption style.

**Options.**
- **A. Keep the pair, split the jobs** (lowest risk): Roboto Serif only for place names and one display line per screen, no italics except the brand moment; Archivo for everything else, with a numeric style (tabular, width 90) for every time and score.
- **B. Go all-sans to match the brand** (most "tech"): Archivo as the only family, using its width axis for display (expanded) and data (condensed). Serif disappears. Closest to the logo explorations.
- **C. Native-first:** SF Pro for UI on iOS and macOS (free Dynamic Type, legibility, Liquid Glass harmony) with the brand face reserved for display and the wordmark. On the web, Archivo stands in for SF.

**Recommendation.** B or C. Decide with the logo, not after it. If the user loves the serif, A is a respectable fallback, but drop the italic accent everywhere except one place.

## 3. Colour

**Measured problems** (WCAG 2.x; 4.5:1 for text, 3:1 for large text and UI).

| Pair | Ratio | Where it shows |
|---|---|---|
| Focus ring (10% ink) on white | **1.24** | every control |
| `text/disabled` `#B0B0B0` on white | **2.17** | inactive phone tab labels, timeline hour axis, "est.", "overnight", "Day N", placeholders |
| White on gold `#F5B72B` | **1.80** | trip pins 2–3, member 2 avatar |
| Orange `#FF8A3D` text on white | **2.35** | "Sunrise is *in frame*", route warnings, "TEMPLATE" eyebrows |
| Gold `#F5B72B` as a graphic on white | **1.80** | "Great" score dots and ring |
| Green `#22C55E` as a graphic on white | **2.28** | "Good" score dots |
| White on rose `#FF385C` | **3.52** | danger button, "Now" pill, Day 1, the "Y" avatar |
| `text/tertiary` `#717171` on `#F0F0F0` | **4.28** | muted fills (just fails) |
| All 8 member colours with white initials | 1.80–3.96 | every avatar |
| 8 of 10 day colours with white numbers | 1.75–4.30 | every trip pin and stop badge |

**The palette is Airbnb's.** `#FF385C` is Airbnb's brand red, and `#717171`, `#DDDDDD`, `#EBEBEB` and `#F7F7F7` are its secondary text, border, hairline and light surface greys (from memory of Airbnb's public CSS; worth a quick check, but the resemblance is unmistakable on screen). The "Uber/Airbnb 2025" direction was meant as a *quality bar*, not a palette to copy, and with the rename it is a liability: the first impression of Explore is an Airbnb map of red dots ([04-explore-default-desktop.webp](screens/04-explore-default-desktop.webp)).

**Rose is overloaded.** It means *best* (Epic), *danger*, *Day 1*, *member 1*, *now* and *you* (the avatar). On the map, red reads as alert.

**Recommendations.**
1. **Retire rose as the accent.** Brand colour = ink plus one gold "light" accent (which the logos already use). Gold appears in exactly one role in the UI: the brand light moment (and perhaps the primary scout action), never as a data band.
2. **Light Index on a single-hue sequential ramp** (for example pale sand → deep amber, or grey → ink with gold reserved for the top band), always with the number and the band word. Lightness carries order, which survives colour blindness and greyscale. Today the five hues are not ordered by lightness (Epic is the darkest, Great the lightest, Fair and Poor have identical luminance) and Epic vs Good collapses to ΔE 5.8 under deuteranopia.
3. **Days and people on a separate categorical set** of no more than 6 hues, checked under protan/deutan/tritan, with dark text on light fills or white on dark fills only. Days beyond 6 repeat with a pattern or rely on the number.
4. **Text-safe variants** for every accent (`gold/text`, `orange/text` dark enough for 4.5:1), or simply set text in ink with a coloured icon.
5. **Dark and Night themes** (see §1).

## 4. Components

**Inventory.** 35 UI primitives and about 78 domain components, all rendered on `/styleguide` with variant/size/state matrices and `data-component` ids (that is what made the Figma scripts possible).

**Problems.**
- **Duplicates with the same names:** two `OverlayChip` (heights 24/32/40 vs 28), two `PopoverMenu`, two `IconTile`, `FeatureCard` in trip and landing (plus three landing variants of the same anatomy), three tag-like components (Tag, Badge, TagChip), and chip-as-toggle implemented three ways.
- **Unused primitives:** Switch, Checkbox, Tooltip, Tabs, and NativeSelect (outside one StopCard use) appear only on the styleguide.
- **`sm` is the default where it shouldn't be:** about 60 call sites are under 44px, including every default `Chip` (36), every modal's close button (36), the trip stop's up/down/delete trio (36 each with 0px between them), 28px session chips and the 14px collapsed map dot.
- **`tw()` doesn't resolve every class conflict, and it has already broken two screens.** The helper (`src/design/variants.ts:86`) lets a later class override an earlier one only for a few utility groups; position is not one of them. So `relative` from a primitive and `absolute` from the caller both survive, and the compiled CSS lets `relative` win. Result: **the Explore map is blank on phones** ([01 X0](01-screen-by-screen-audit.md)) and the scout's submit button renders outside its box. **Fix:** resolve the position group in `tw()` (or adopt `tailwind-merge`), then sweep for other overrides of layout utilities.
- **Selection is styled three ways** (2px ink ring with offset; strong border plus shadow; sunken fill), and **press feedback three ways** (`scale-.98`, `scale-98`, `scale-95`).
- **The styleguide documents what exists, not how to use it.** It has variant matrices but no "use when / don't use when", no anatomy, no content guidance, no Light Index foundation page, no iconography or layout rules. As a designer's tool, it is an inventory rather than a system ([62-styleguide-top-desktop.webp](screens/62-styleguide-top-desktop.webp)).

**Fixes.** Merge the duplicates into `ui/` primitives before the Figma import (otherwise Figma inherits them). Make 44 the default control size and keep 36 for dense desktop contexts only. Add one foundations page for light (bands, ramp, the window object, how the score works) and one for content (voice, terms such as "golden hour", "first light", "spot", "saved").

## 5. The data-visualisation system (the product's core)

The Light Index, the 24-hour timeline, the date strip, the sky arc and the hourly weather are Iter's reason to exist. As a system they have four problems. The first is critical.

1. **The headline score answers the wrong question (critical).** The day score is 70% of the best window plus 30% of the average (`src/lib/light.ts:48`), and the night window often scores highest in clear weather. So on the date of capture most spots show 88–94 "Epic" (14 of about 16 visible pins on the desktop map are rose), Delicate Arch (tagged "Best at sunset") reads "93 · Epic", and on a rainy Tuesday the ring says "87 · Great light" while both golden hours are "Thick overcast · 38" ([32-spot-light-timeline-desktop.webp](screens/32-spot-light-timeline-desktop.webp), [31-spot-date-strip-phone.webp](screens/31-spot-date-strip-phone.webp)). A photographer planning a sunset trusts the number and is misled. **Fix options:** (A) **intent-based scores**: the user picks what they shoot (Sunrise, Sunset, Blue hour, Night; default from the spot's "best at"), and every card, pin, strip and trip shows the score for that intent; (B) show the **best window by name** everywhere the number appears ("Night sky · 93", never a bare 93); (C) both: the intent sets the default and the name is always visible. I recommend C. Then check that "Epic" is rare in a normal week.
2. **Unknown looks like good.** With no forecast the windows score 58, the bottom of "Good", and the day lands at 58–64 green on cards, the spot page ring and the date strip. Only map markers (`···`) and the trip stop ("est." at 2.17:1) admit it. **Fix:** a distinct "no forecast" state: hollow ring, dashed arc, "No forecast · sun times only".
3. **The views don't share an axis or a key.** The date strip (daily score), timeline (24h sky and cloud), Light Index card (five window scores), sky arc (geometry, no time) and hourly rail (cards, no trend) each use a different scale, and none highlights the same window. Golden and blue hour are 1–2% slivers in a continuous gradient, with no labels. **Fix:** one *window* object (morning blue, morning golden, evening golden, evening blue, night) that is drawn as a labelled band on the timeline, listed in the card, marked on the arc and tinted in the hourly rail, highlighted everywhere when selected, with a scrubber that moves the sun on the arc. This is the Tide Guide and Apple Weather pattern ([03](03-benchmarks.md) #16).
4. **Uncertainty is invisible.** Day 7 is drawn with the same confidence as today. **Fix:** fade or hatch days 4–7, show ranges for them, and stamp "Updated 2:00 pm".

## 6. Accessibility (system level)

- **Focus:** 1.24:1 ring with the outline removed (see §1).
- **Modals:** no focus trap, no initial or return focus, no `aria-labelledby`. The bottom sheet handle is a `div` with pointer events only. The chip menu and search suggestions have no arrow-key navigation or combobox semantics.
- **Nested interactives:** a button inside a link on `SpotCard` and `TripCard`.
- **Map markers** are buttons named only with the spot name, not its score or band.
- **Headings:** Explore has no h1; several pages skip levels.
- **Reduced motion** covers four CSS animations and the reveal hook; the 54 transitions, hero parallax, map fly-to/fit-bounds, smooth scrolls and score-ring animation are unguarded.
- **Targets:** about 60 call sites under 44px (§4).

None of this is exotic; a focused pass on the primitives (Modal, Sheet, Chip, IconButton, focus ring) fixes most of it, because the domain components inherit from them.

## 7. Motion

Three durations and one easing are defined and used consistently (`motion-fast` 35 times, `motion-base` 11, `motion-slow` 8). Missing: a reduced-motion variant for transitions, a spring for sheets and drag (the sheet uses a linear height transition), and meaningful motion where it would help comprehension, such as the sun moving along the arc as you scrub, or drive times recomputing after a reorder. Natively, use system springs, `.sensoryFeedback` for selection and success, and honour `accessibilityReduceMotion`.

## 8. Identity: distinctive or generic?

**Generic today.** Strip the logo and the photos and Explore, Trips and Saved are an Airbnb theme: white, black pills, Rausch red, Airbnb greys, image cards with white pill badges, a search pill with a coloured action. Competitors in the space (Wanderlog, Roadtrippers) look generic in the same way, so the bar to stand out is low, and Iter isn't clearing it.

**What is genuinely Iter's.** Four things, all about light:
1. The **sky-gradient timeline**: a day drawn as the sky itself.
2. The **sun-and-moon arc with "Your frame"**: geometry turned into a shooting decision ("Sunrise is in frame: backlit, starburst & silhouettes").
3. The **gold light moment**: the gold italic *light.* on the landing page, and the gold tittle in the logo.
4. The **Light Index** and the plain-language window reasons ("thin high cloud, clear horizon"), the best copy in the product.

**Direction.** Make light the system: a palette derived from the sky ramp (night navy, blue-hour indigo, golden amber, day white) used for data and a few signature surfaces, ink and white for everything else, gold only for the brand moment. Bring the timeline and the arc up to the hero position on the spot page and onto cards as a miniature. That is a look no competitor has, and it is about the user's actual job.

### Fit with the logo explorations (round 1: `brand/iter/logo-options.html`)

| Concept | What it is | Strengths | Risks | Fit with the UI direction above |
|---|---|---|---|---|
| **Tittle** (lead's pick) | Heavy geometric lowercase "iter"; the only colour is a gold dot on the i | Instantly legible at 16px; one gold moment = the sun; the app icon (gold dot over a bleeding white stem) is simple and strong | Dot-on-the-i wordmarks are common; it reads "tech" more than "photography" | Excellent with an all-sans system (Typography B/C); clashes with an italic-serif UI |
| **Frame** (second) | Two crop-mark corners framing a gold sun; spaced caps ITER | The most ownable and photographic idea; the best standalone app icon; echoes the "Your frame" wedge in the sky arc | Spaced caps feel cold beside the warm photography; crop marks are a known photo motif | Strong. The frame motif can become a UI device (selection brackets on the map, the frame wedge) |
| **Meridian** | Wide caps cut by a horizon line with gold ticks | Distinctive, engineered, "horizon" is on-message | Weak as an app icon (a cut T); wide caps are heavy in UI | OK for marketing; weaker in product |
| **Sun Arc** | Open sun-path arc over a floating horizon, gold sun | Literally the product's sky arc | Reads as a gauge or a cloud at small sizes; the navy icon breaks the ink/white system | Good if the sky arc becomes the hero graphic |
| **Sunrise, Route, Waypoints** | Half sun on the i; a monoline route out of the r; an i turned into a route | Route tells the journey story | Route's symbol is acknowledged in the sheet itself as the weakest part; Waypoints is friendly but generic | Lower priority |

**Round 2 (`brand/iter/round-2/`, created while this study was running).** The favourites have moved to **Meridian / Horizon** (now on Archivo Expanded 700 with font-metric spacing; the symbol is a cut *I* rather than a T) and **Waypoints / R-leg** (the r's arm becomes a tapering route ending in a dot), plus a 12-face typeface study and six palettes. Round 2's own pairing note proposes **Archivo Expanded with Gold Standard or Ink & Paper** for Meridian, and **Geist with Blue Hour** for R-leg. The cut-I symbol fixes the app-icon weakness noted for round-1 Meridian above.

**What this means for the UI (my recommendation).**
- **Meridian + Archivo is the most coherent system.** The UI already runs on Archivo, so Meridian on Archivo Expanded makes Typography option B (one family, using the width axis: expanded for brand and display, normal for UI, condensed for data) almost free. Pair it with **Gold Standard**, whose light-ground accent `#BC7F00` is exactly the "deepened gold for text and graphics on white" this audit recommends (§3). The horizon line can become a UI device: the timeline's horizon, the sky arc's baseline, section rules.
- **R-leg + Geist + Blue Hour is the bigger change.** It would replace the UI face and swap the accent from gold to blue `#2F6FE8`. Blue hour is on-theme and reads "tech", but it would collide with the blue-hour band in the light data. If you choose it, the Light Index ramp must not use the brand blue, and the gold "light" moment disappears from the brand.
- **Either way**, drop the italic-serif accent from the UI and keep Roboto Serif at most for place names, or retire it.
- The rename has to reach the product: "Vantage" appears 27 times in UI copy, and the Logo component and the "Ask Vantage" label are already baked into the Figma components.

*(Round 1's Tittle and Frame remain good fallbacks: Tittle for an all-sans UI with a single gold moment, Frame for its photographic, ownable app icon.)*

## 9. Native translation summary

| Web pattern | Native (iOS 26 / macOS Tahoe) | Change needed |
|---|---|---|
| Semantic colour tokens | Asset-catalog colours with light/dark | Add dark values (none exist) |
| Fixed px type scale | Dynamic Type via `Font.custom(_:size:relativeTo:)` | Layouts with fixed heights (chips, badges, 140px sheet peek) must grow |
| Lucide icons, stroke 2 | SF Symbols (weights, fill variants, Dynamic Type) | Most glyphs have equivalents; Aperture, Gem, Route, Milestone need choices |
| Custom bottom sheet (140 / 52% / full) | `.presentationDetents` with background interaction | Define detents by content, not pixels; map padding follows the sheet |
| MapLibre + CARTO Positron + HTML markers | MapKit `Annotation`, clustering, `.mapStyle(.standard(emphasis: .muted))` | Hover-only names need a selection-driven design; pins need 44pt hit areas |
| Flat white bars with blur | Liquid Glass for bars and floating controls | Glass for controls only; content stays opaque |
| Up/down/delete buttons on stops | `List` with `onMove`, `.swipeActions`, `.contextMenu` | Remove the button trio |
| Toasts | Banner overlay plus `.sensoryFeedback`; VoiceOver announcements | No native toast |
| Desktop top bar vs phone tab bar | `TabView` that becomes a sidebar on iPad and Mac | One IA across sizes |
| Light timeline, arc, hourly cards | Swift Charts (`AreaMark`, `RectangleMark`, `RuleMark`, `chartXSelection`) | Becomes easier and more accessible natively (`accessibilityChartDescriptor`) |

## 10. The changes that would raise perceived quality most

Ranked by how much they change what a user feels, for the effort.

1. **Make the Light Index honest:** intent-based scores, the window name always beside the number, a real "no forecast" state. This turns the core feature from misleading to trustworthy. *(critical)*
2. **Put "when to go" first.** On spot detail, lead with the best-window summary and the timeline; shrink the hero and the pull-quote on phone. On cards and pins, show "Sunset 7:12 · 82", not a bare number.
3. **Redraw the light timeline** as labelled golden/blue/night bands with window scores, a shared time axis for cloud and weather, and a scrubber linked to the sky arc. This becomes Iter's signature visual.
4. **Replace the Airbnb palette:** retire rose, use a sequential light ramp for data, ink/white for UI and gold for the single brand moment; add status and categorical palettes that pass contrast.
5. **Decide the type voice with the logo:** all-sans (or SF on native) with the serif reduced to place names, or kept only for the display line, with no italic gimmick.
6. **Fix the bugs a first-time user hits:** above all the blank phone map (the class-conflict bug above), the scout composer's misplaced submit button, broken image alt text in scout results, the React Router developer 404, the join button half under the tab bar, the developer copy in the scout fallback, the "You" name leaking to friends.
7. **One shell across sizes:** the same identity, profile and primary action on phone and desktop; an active tab on every screen; readable inactive tab labels.
8. **Map polish:** fit the camera to results, filters and trips; cluster with a count; a selected-pin state that pans into the visible area above the sheet; route lines coloured by day with distinguishable day colours.
9. **Stop card simplification:** drag handle instead of three arrows, one session control (the chosen window and its time), the conflict signal ("leave by 5:58 to make golden hour") as the headline.
10. **A visible focus ring, 44pt targets and dark/Night mode:** low glamour, but they decide whether the product feels finished, and Night mode is a genuine feature for this audience.
