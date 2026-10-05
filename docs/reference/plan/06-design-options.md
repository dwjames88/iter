# 6 · Design options to weigh

Five open design questions. Each has the problem today, two or three ways to solve it, a lean, and the best argument against the lean. The leans are mine. You decide.

Pattern numbers (#N) are headings in the [benchmarks brief](../research/design-audit/03-benchmarks.md). Its at-a-glance table is numbered differently from its headings from #8 on; this section follows the headings.

---

## 6.1 Navigation model

**Problem today.** The shell is Explore / Trips / Saved, with Explore first, and the landing page's "Open app" goes to `/explore` ([global navigation](../flows/00-app-map.md#global-navigation)). Phone and desktop are two different products: desktop has a logo, "Plan a trip" and a profile; phone has none of them, and detail screens light no tab ([audit X6](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first), [shell parity](../research/design-audit/01-screen-by-screen-audit.md#global-app-shell--top-bar-and-tab-bar-parity)). Meanwhile the positioning work says the trip, not the map, is the home of the app ([positioning](../research/opportunities/04-positioning.md#recommendation)). The empty Trips screen is three screens tall on phone and buries its templates ([Trips list](../research/design-audit/01-screen-by-screen-audit.md#trips-list--empty-templates-populated)).

> **Option 6.1-A · Trip-first.** Tabs are Trips / Explore / Saved. A Now surface appears only when a session is within three hours. The tab bar becomes a sidebar on iPad and Mac, with trips listed under it.
>
> **Cost.** Reorders the shell and changes what first launch shows. Explore moves out of first place.
>
> **Draws on.** [pattern #14](../research/design-audit/03-benchmarks.md#14-tab-bar-that-becomes-a-sidebar), [pattern #13](../research/design-audit/03-benchmarks.md#13-now--next--later-and-live-activities-flighty), [E1](../research/opportunities/03-differentiation-options.md#e1--now-field-mode) (make it the home screen when a session is within three hours).

```text
 iPhone                    iPad / Mac
+----------------+   +---------+---------------------+
| Trips      (+) |   | TRIPS   | Southwest Loop      |
| Southwest Loop |   |  Loop   | Day 1  Day 2  Day 3 |
| Utah in Oct    |   |  Utah   | [ stops ] [ map ]   |
| ---- NOW ----- |   | Explore |                     |
| Mesa Arch      |   | Saved   | NOW: leave 5:31     |
| leave 5:31     |   +---------+---------------------+
+----------------+
| Trips Explore S|
+----------------+
```

> **Option 6.1-B · Map-first.** Explore stays home. Trips are a layer or sheet on the map, as the prototype works today.
>
> **Cost.** Keeps the map as the story, which is the story every competitor tells. The phone map is currently blank ([audit X0](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first)), so it cannot carry first launch until fixed.
>
> **Draws on.** [pattern #1](../research/design-audit/03-benchmarks.md#1-detented-sheet-over-a-live-map), [pattern #5](../research/design-audit/03-benchmarks.md#5-one-selection-drives-map-list-and-sheet).

```text
+------------------------------+
| (Search spots)        [ + ]  |
|     .map  (82)   (74)        |
|        (91)    .             |
|  ______________________      |
| | = Trips   Southwest Loop | |
| |   Explore list ...       | |
+------------------------------+
```

> **Option 6.1-C · Today hub.** One "Today" screen is first: next session, tonight's best light, trips below it.
>
> **Cost.** Empty for anyone without a trip, and it duplicates Trips. The positioning brief calls the calm field companion a design bar, not a standalone position ([Direction 2](../research/opportunities/04-positioning.md#direction-2--the-calm-field-companion)).
>
> **Draws on.** [pattern #7](../research/design-audit/03-benchmarks.md#7-three-ranked-answers-not-raw-data), [E2](../research/opportunities/03-differentiation-options.md#e2--answer-first-progressive-disclosure).

```text
+------------------------------+
| Today, Tue Oct 6             |
| +--------------------------+ |
| | Sunset 7:12 - 82 Great   | |
| | Mesa Arch, leave 5:31    | |
| +--------------------------+ |
| Tonight nearby  [a] [b] [c]  |
| Your trips      [x] [y]      |
+------------------------------+
```

> **Recommendation.** A. It follows the positioning line that the trip is the home and the map serves the plan ([positioning](../research/opportunities/04-positioning.md#recommendation)). One information architecture across sizes is the benchmark's own point ([#14](../research/design-audit/03-benchmarks.md#14-tab-bar-that-becomes-a-sidebar)), and it fixes the phone/desktop split in [X6](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first). Now is a conditional surface ([#13](../research/design-audit/03-benchmarks.md#13-now--next--later-and-live-activities-flighty)), not a fourth tab, so it earns its place only on shoot days.

> **Case against.** First-time users have no trip. Assumption: most first launches are tripless; the briefs hold no onboarding data. Explore must stay one tap away, and the empty Trips state has to sell the app: templates directly under the buttons, no landing-page feature cards ([Trips list, issue 1](../research/design-audit/01-screen-by-screen-audit.md#trips-list--empty-templates-populated)). If that screen cannot do the job, B wins for new users.

---

## 6.2 Map and sheet behaviour

**Problem today.** On phones the map is blank ([X0](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first)). The peek shows half a row, and tapping a pin replaces the list with a card that has no actions, so curated spots cannot be added to a trip from Explore ([Explore browse](../research/design-audit/01-screen-by-screen-audit.md#explore-browse--default-map--list-sheet-peekhalffull), [Spot selected](../research/design-audit/01-screen-by-screen-audit.md#spot-selected-desktop-card-ring-phone-floating-card-selected-marker), [flow brief](../flows/02-explore-browse-map.md#not-as-it-looks)). Selection does not pan the map, and desktop hover is one-way. In the builder the phone map takes about 530 of 844px and selecting a stop scrolls it out of view ([Trip builder](../research/design-audit/01-screen-by-screen-audit.md#trip-builder--populated-full-page-listmap-relationship)). No benchmark in the briefs supports a card carousel, so I give two options, not three.

> **Option 6.2-A · Detented sheet, one selection.** Three named detents over a live map. Peek: search, date, one summary line. Half: list. Full: list with sort. Selecting a pin or card moves the sheet to half with a spot summary and lifts the pin above it. Map padding follows the sheet.
>
> **Cost.** A custom gesture system on web; dragging inside a scrolling sheet needs its own handle; the handle must work by keyboard. One sheet at a time. Natively this is system detents.
>
> **Draws on.** [#1](../research/design-audit/03-benchmarks.md#1-detented-sheet-over-a-live-map), [#3](../research/design-audit/03-benchmarks.md#3-map-chrome-that-respects-the-sheet), [#5](../research/design-audit/03-benchmarks.md#5-one-selection-drives-map-list-and-sheet), [#6](../research/design-audit/03-benchmarks.md#6-place-card-with-one-primary-action-at-the-top).

```text
 peek            half            full
+-------+      +-------+      +-------+
| map   |      | map   |      |[search]|
| (82)  |      | (82)* |      |-------|
|       |      |-------|      | card  |
|=======|      |===    |      | card  |
|14 spots|     | card  |      | card  |
+-------+      | card  |      | card  |
               +-------+      +-------+
```

> **Option 6.2-B · Split list and map; sheet becomes a panel.** On iPad and Mac the list is a floating panel over a full-bleed map, or a fixed column as today. Spot detail pushes inside the panel. Add to trip is a popover.
>
> **Cost.** A second layout to design and test. The audit praises today's 46% column ([Explore browse](../research/design-audit/01-screen-by-screen-audit.md#explore-browse--default-map--list-sheet-peekhalffull)); the benchmark prefers the floating panel. Pick one. Do not scale the phone sheet up.
>
> **Draws on.** [#15](../research/design-audit/03-benchmarks.md#15-sheets-become-panels-on-large-screens), [#5](../research/design-audit/03-benchmarks.md#5-one-selection-drives-map-list-and-sheet).

```text
+----------------------------------------+
| (Search)  [Today v] [Best light v]     |
| +-----------+                          |
| | 45 spots  |      map, full bleed     |
| | [card]    |    (82)      (74)        |
| | [card]*---+--> (91)*                 |
| | [card]    |            (66)          |
| +-----------+                          |
+----------------------------------------+
```

> **Recommendation.** A on phone, becoming B on iPad and Mac, with one selection model underneath so hover, focus and tap all drive pin, card and sheet. The benchmarks say exactly this split: detents are an iPhone idiom ([#15](../research/design-audit/03-benchmarks.md#15-sheets-become-panels-on-large-screens)), and the audit calls the builder "the textbook case" for a full-bleed map with a detented sheet.

> **Case against.** Two layouts double the design and test load. The prototype already switches at 768px on Explore and 1024px on the builder, and the system brief asks for one breakpoint per screen ([flow brief](../flows/02-explore-browse-map.md#preconditions), [tokens](../research/design-audit/02-system-and-identity.md#1-tokens)). A custom web sheet is also the riskiest build. A single split layout would ship sooner, at the cost of the phone.

---

## 6.3 Trip builder interaction

**Problem today.** Reordering is arrow buttons, with delete next to them, no confirm and no undo ([flow brief](../flows/07-trip-builder.md#tweak-points)). Five equal session chips disagree with the light readout ([stop card, issue 1](../research/design-audit/01-screen-by-screen-audit.md#trip-builder--populated-full-page-listmap-relationship)). The only feasibility cue is a 13px orange sentence, and warnings fire only within a day and only when both stops have a session ([issue 9](../research/design-audit/01-screen-by-screen-audit.md#trip-builder--populated-full-page-listmap-relationship), [flow brief](../flows/07-trip-builder.md#not-as-it-looks)). Wanderlog edits more easily than Iter does ([gaps §5](../research/competitors/gaps-and-openings.md#5-where-a-competitor-does-it-better-than-iter-today)).

> **Option 6.3-A · Day list with feasibility connectors.** A vertical list. Between stops, a connector states the conflict: "42 min drive · leave by 5:58 pm to make golden hour", amber when the drive eats the window. Drag by a handle, across days. Drive times recompute with a shimmer. Undo toast.
>
> **Cost.** Needs a session on every stop for the connector to work. Dragging inside a sheet needs a dedicated handle. Wanderlog's density and paywalls are the thing to avoid ([Wanderlog](../research/competitors/11-wanderlog.md#what-iter-should-take-from-this)).
>
> **Draws on.** [#9](../research/design-audit/03-benchmarks.md#9-feasibility-connectors-between-stops), [#11](../research/design-audit/03-benchmarks.md#11-direct-manipulation-reorder-with-recompute-and-undo), Wanderlog.

```text
+------------------------------------------+
| Day 2 . Tue Oct 6                        |
| (=) 1 Delicate Arch    Sunset 6:48 . 82  |
|      set up by 6:25                      |
|   |  42 min . leave by 5:58  [amber]     |
| (=) 2 Mesa Arch        Blue hr 7:10 . 64 |
|   |                                      |
|   +  Add stop           [Undo: moved]    |
+------------------------------------------+
```

> **Option 6.3-B · Day timeline strip.** A time axis for the day showing drive segments and light windows together, the elevation-profile idea applied to a day. Day boundaries can be dragged later.
>
> **Cost.** Dense on a phone width. Needs the shared window object so bands match everywhere ([system §5](../research/design-audit/02-system-and-identity.md#5-the-data-visualisation-system-the-products-core)). The Komoot detail comes from search snippets, unverified. Draggable boundaries are tagged Later.
>
> **Draws on.** [gaps opening 1](../research/competitors/gaps-and-openings.md#1-the-light-aware-itinerary-that-re-plans-with-the-forecast), [#10](../research/design-audit/03-benchmarks.md#10-draggable-day-boundaries-komoot-multi-day), the [Structured day timeline](../research/design-audit/03-benchmarks.md#f-apple-design-awards-relevant-to-iter).

```text
 4a   6a   8a  ...  4p   6p   8p   10p
 |....|====|~~~~~~~~~~~|.....|====|~~~|
 .... sleep  drive 2h35 .... gold  night
      ^ blue/gold AM         ^ Delicate Arch
```

> **Option 6.3-C · Map-first route editing.** Add and reorder stops by dragging pins or the route on the map; the list follows.
>
> **Cost.** The briefs give no benchmark for reordering on the map. The nearest is "add to trip" from the map ([#12](../research/design-audit/03-benchmarks.md#12-add-to-trip-everywhere-plus-an-along-route-filter)). [#9](../research/design-audit/03-benchmarks.md#9-feasibility-connectors-between-stops) argues the other way: the list is the plan, the map is the sanity check. Fingers hide the pins.

```text
+------------------------------+
|   (1)--------(2)             |
|               \             |
|     drag (3) ->  (3')        |
|  [route recomputes]          |
+------------------------------+
```

> **Recommendation.** A as the editing surface, with B as a read-only strip in each day header (hybrid). Per-day totals in the header are the benchmark's "Now" step; draggable boundaries are "Later" ([#10](../research/design-audit/03-benchmarks.md#10-draggable-day-boundaries-komoot-multi-day)). The audit already asks for a day strip in place of the weak stat tiles ([issue 18](../research/design-audit/01-screen-by-screen-audit.md#trip-builder--populated-full-page-listmap-relationship)), and the connector is the chance to beat Wanderlog.

> **Case against.** Two views of one day can disagree, and the builder already does: chip says Sunrise, readout says Blue hour. The strip also leans on the unbuilt scheduler ([B1](../research/opportunities/03-differentiation-options.md#b1--light-first-itinerary), effort L). Ship A alone first, and add the strip only when the window object is shared.

---

## 6.4 Light Index presentation

**Problem today.** The headline score is the best window, which in clear weather is usually night. A rainy Tuesday reads "87 · Great light" while both golden hours score 38, and the date strip ranks days with the same number ([audit X1](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first), [system §5](../research/design-audit/02-system-and-identity.md#5-the-data-visualisation-system-the-products-core)). No forecast shows as a green 58 ([X2](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first)). Uncertainty is invisible. Reviewers of rival apps say the same thing: a score with no reason is not trusted ([A1](../research/opportunities/03-differentiation-options.md#a1--explainable-light-index)). The three options below are layers, not rivals.

> **Option 6.4-A · Intent score, window name always beside the number.** The user picks what they shoot (Sunrise, Sunset, Blue hour, Night), defaulting to the spot's "best at". Every pin, card, strip and trip stop shows that intent's score with its name: "Sunset · 38", never a bare 93. No forecast gets a hollow ring.
>
> **Cost.** One more control on Explore and Saved. Pins carry more text. "Epic" must be checked for rarity. This is the audit's own fix C ([system §5](../research/design-audit/02-system-and-identity.md#5-the-data-visualisation-system-the-products-core)).
>
> **Draws on.** [#20](../research/design-audit/03-benchmarks.md#20-named-bands-for-a-composite-score), [#4](../research/design-audit/03-benchmarks.md#4-pins-that-carry-the-decision-variable-with-a-pin-budget).

```text
 Show light for: [Sunrise] (Sunset) [Blue] [Night]
+----------------------------+
| Delicate Arch              |
| Sunset . 38  Poor          |
| Night  . 92  (not shown)   |
| Mesa Arch                  |
| No forecast  (o)           |
+----------------------------+
```

> **Option 6.4-B · Number with contributors and visible uncertainty.** Tap the score to see sun angle, low/mid/high cloud, rain, visibility, moon, each with a plus or minus and one sentence. Days 4-7 fade and show a range ("55-75"). "Updated 2:00 pm" on every score.
>
> **Cost.** More on an already long spot page. Weights are heuristics, so label them "estimated from forecast data". How Sunsethue draws uncertainty was not found, so this needs your own testing ([#22](../research/design-audit/03-benchmarks.md#22-visible-uncertainty-and-horizon)).
>
> **Draws on.** [#21](../research/design-audit/03-benchmarks.md#21-contributors-under-the-number), [#22](../research/design-audit/03-benchmarks.md#22-visible-uncertainty-and-horizon), [#18](../research/design-audit/03-benchmarks.md#18-cloud-layers-split-low--mid--high).

```text
+--------------------------------+
| Sunset . 74 Great   55-75      |
| Thin high cloud, clear horizon |
| Low  10% ##                    |
| Mid  35% #######               |
| High 50% ##########            |
| Rain 0   Moon -   Updated 2 pm |
+--------------------------------+
```

> **Option 6.4-C · Answer first.** Lead with the decision: "Leave 5:31 · set up by 6:12 · Great light, 78". Go, wait or skip. The number is one tap away.
>
> **Cost.** A verdict oversells a forecast that may be right about half the time (one blogger's test; directional only, per [A1](../research/opportunities/03-differentiation-options.md#a1--explainable-light-index)). Needs thresholds and a session on every stop. Low scores need kind wording ([Gentler Streak](../research/design-audit/03-benchmarks.md#f-apple-design-awards-relevant-to-iter)).
>
> **Draws on.** [#7](../research/design-audit/03-benchmarks.md#7-three-ranked-answers-not-raw-data), [E2](../research/opportunities/03-differentiation-options.md#e2--answer-first-progressive-disclosure), [E1](../research/opportunities/03-differentiation-options.md#e1--now-field-mode).

```text
+--------------------------------+
| NEXT  Mesa Arch                |
| Leave 5:31 . set up by 6:12    |
| Great light, 78   [ Go ]       |
|                  details >     |
+--------------------------------+
```

> **Recommendation.** A as the baseline everywhere, B one tap away on the spot page, C on trip stops and in Now mode. They combine: C's "78" is A's intent score, and B is its explanation. The positioning brief wants every stop card to lead with a decision and keep the reasoning one tap away ([positioning](../research/opportunities/04-positioning.md#recommendation)), and the system brief ranks the honest score as its top fix ([system §10](../research/design-audit/02-system-and-identity.md#10-the-changes-that-would-raise-perceived-quality-most)).

> **Case against.** Three presentations of one number can drift apart, which is the bug today (ring versus rows). Each needs the same window object behind it. And C's confident verdict leans on a forecast whose accuracy the briefs could not verify; a wrong "Go" costs more trust than a bare number.

---

## 6.5 Visual identity direction

**Problem today.** The palette is Airbnb's, rose means six things, and the UI is serif-led while every logo is a sans ([system §2](../research/design-audit/02-system-and-identity.md#2-typography), [§3](../research/design-audit/02-system-and-identity.md#3-colour), [§8](../research/design-audit/02-system-and-identity.md#8-identity-distinctive-or-generic)).

**Your direction so far.** After round two you chose the route idea: Waypoints / Switchback as the favourite, Contour second ("really cool too, but its too big/detailed"). You asked for a heavier face, serif options, and an i that joins the word. For colour: "For colors i like first light and alpine." Round three is being drawn now in `brand/iter/round-3/`, so **the mark is not final** and these options are about the system around it, not the logo. The reasoning behind each conflict is in [decision 2.2](02-decisions.md#22-design-direction-and-identity).

Palettes ([First Light](../../brand/iter/round-2/palettes.md#first-light-first-light), [Alpine](../../brand/iter/round-2/palettes.md#alpine-alpine)): First Light is ink `#2A1710`, paper `#FFF6EC`, accent `#E4572E` (dark: `#FFF1E3` on `#1C1210`, accent `#FF8A5C`). Alpine is ink `#0F2A20`, paper `#F1F3EC`, accent `#5E7F12` (dark: `#EEF2E8` on `#0A1A14`, accent `#B9D86B`). Neither accent passes 4.5:1 as text on its light paper (3.45:1 and 4.15:1).

> **Option 6.5-A · First Light leads.** Espresso ink on cream. Coral is the sun: the switchback's tittle and one brand moment per screen. The Light Index ramp runs from neutral to amber and never uses coral. Danger and warning get a separate hue plus an icon.
>
> **Cost.** Coral is a red-orange, close to the rose the audit retired because red "reads as alert". Its dark accent `#FF8A5C` is almost today's warning orange `#FF8A3D`. Thin coral strokes are weak at 16px.
>
> **Draws on.** [pattern #23](../research/design-audit/03-benchmarks.md#23-one-signature-moment-numbers-kept-plain-not-boring-weather) (one signature moment), [system §3](../research/design-audit/02-system-and-identity.md#3-colour).

```text
 Spot card (First Light)
+--------------------------------+   paper  cream #FFF6EC
| Delicate Arch                  |   ink    espresso #2A1710
| Sunset 6:48 . 82 Great  [####] |   ramp   neutral -> amber
| set up by 6:25                 |   coral  only the sun / tittle
|                       iter .   |          (never a score)
+--------------------------------+
```

> **Option 6.5-B · Alpine leads.** Spruce ink on stone. Lichen marks the route and the brand. The light data is the only warm colour on screen, so light stands out against a cool interface. Green is removed from the Light Index and from success states.
>
> **Cost.** Green reads as "good": a lichen route or pin next to today's green "Good" band (`#22C55E`) would be read as a rating. Lichen reads olive and can look dated. In the red Night mode the greens drop out, so the brand changes at night.
>
> **Draws on.** [system §3](../research/design-audit/02-system-and-identity.md#3-colour) (single-hue ramp, separate categorical set), [pattern #20](../research/design-audit/03-benchmarks.md#20-named-bands-for-a-composite-score) (a word beside every band colour).

```text
 Trip day (Alpine)
+--------------------------------+   paper  stone #F1F3EC
| Day 2 . Tue                    |   ink    spruce #0F2A20
| o Delicate Arch  Sunset . 82   |   lichen route line only
| |  42 min (lichen route)       |   amber  the light data,
| o Mesa Arch      Blue . 64     |          the only warmth
+--------------------------------+
```

> **Option 6.5-C · Both, with separate jobs.** Alpine for the land and the journey: ink, route lines, the switchback or contour mark. First Light's coral for the light: the brand light moment, and at most the top of the light ramp. The road is green; the light is warm.
>
> **Cost.** The most colour to keep disciplined: two accents, a light ramp, and a day and people set that must avoid both. It doubles the discipline the audit found missing today. It needs a written rule per colour on the Foundations page.
>
> **Draws on.** [system §8](../research/design-audit/02-system-and-identity.md#8-identity-distinctive-or-generic) ("make light the system"), [system §3](../research/design-audit/02-system-and-identity.md#3-colour).

```text
 Role map (option C)
 interface ink ....... spruce / stone (Alpine)
 route, connectors ... lichen line, switchback jog
 light moment ........ coral sun (First Light)
 Light Index ramp .... neutral -> amber (coral at most at top)
 status .............. own hues + icons, never green/coral
 Night mode .......... red, dim; greens remapped
```

**Type, alongside the colour.** Switchback was drawn in Geist 600; you asked for heavier faces and serif options, which round three is exploring. The system rule holds whatever wins: a serif may carry the wordmark and place names; data, times and decisions stay in a sans with tabular figures ([system §2](../research/design-audit/02-system-and-identity.md#2-typography)). On native, SF Pro for running text is a later decision.

> **Recommendation.** Your call; this is the most personal decision in the plan. My lean is C, tested against A, because it uses both palettes you like and gives each one a job the product already has: route and light. Judge it in Figma on three real screens (an Explore map full of pins, a spot page's light timeline, a trip day with a route), with round three's mark in place, in light, dark and Night modes.

> **Case against.** The audit's own pick, Meridian on Archivo with Gold Standard, is cheaper and has no semantic conflicts: gold is the light, ink is the interface ([system §8](../research/design-audit/02-system-and-identity.md#8-identity-distinctive-or-generic)). Your palettes each bring one (coral reads as alert, green reads as good), and C carries both. Switchback's kink "vanishes at 16px" and "can look like a drawing flaw" at large sizes ([switchback notes](../../brand/iter/round-2/waypoints/switchback/notes.json)), so the mark may still change in ways that move the colour decision.
