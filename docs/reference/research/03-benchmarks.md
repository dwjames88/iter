# 03 · Best-in-class benchmarks

These are the design patterns Iter should measure itself against, taken from the strongest products in and around its space. Each pattern gives what it is, where to see it, why it works, how Iter could apply it, and what not to copy. Patterns are grouped by the Iter surface they matter for, and each carries a **When** tag: **Now** (web prototype), **Native** (the Mac/iOS build) or **Later**.

Research date: 2026-10-04. Every link is in [sources.md](sources.md). Some claims could only be confirmed from a search snippet or general knowledge rather than a primary page; these are marked **[unverified]**. No screenshots of other products are embedded. Open the links to see them.

**How to read this alongside the audit.** The audit in [01](01-screen-by-screen-audit.md) and [02](02-system-and-identity.md) says what is wrong with Iter today. This file sets the bar. The table directly below maps each benchmark to the Iter screen it should change.

## At a glance

| # | Pattern | Benchmark | Iter surface | When |
|---|---|---|---|---|
| 1 | Detented sheet over a live map | Apple Maps, HIG Sheets | Explore (phone) | Now |
| 2 | Glass for controls, solid for content | Apple Maps iOS 26, HIG Materials | Explore, Trip map | Native |
| 3 | Map chrome that moves with the sheet | HIG Maps | Explore, Trip builder | Now |
| 4 | Pins labelled with the decision variable, with a pin budget | Airbnb | Explore map | Now |
| 5 | One selection drives map, list and sheet | Airbnb, Apple Maps | Explore | Now |
| 6 | Place card with one primary action at the top | Apple Maps iOS 26 | Spot detail | Now |
| 7 | Three ranked answers, not raw data | Citymapper | Explore, Spot detail | Now |
| 8 | Feasibility connectors between stops | Wanderlog, Roadtrippers | Trip builder | Now |
| 9 | Draggable day boundaries with live totals | komoot multi-day | Trip builder | Later |
| 10 | Direct-manipulation reorder with recompute and undo | Roadtrippers, Wanderlog | Trip builder | Now |
| 11 | "Add to trip" everywhere, plus an along-route filter | Roadtrippers | Explore, Spot, Trip | Now |
| 12 | Now / next / later day-of mode, Live Activity | Flighty, HIG Live Activities | Trip (day of) | Native |
| 13 | Offline trips with freshness stamps | AllTrails, Wanderlog | Trip, Spot | Later |
| 14 | Tab bar that becomes a sidebar | HIG Tab bars, Sidebars | App shell | Native |
| 15 | Sheets become panels and popovers on large screens | HIG Sheets | Explore, Spot (desktop) | Now |
| 16 | The time series as the hero, with a scrubber | Tide Guide (ADA 2026) | Spot light timeline | Now |
| 17 | A single-purpose sky instrument | Moonlitt (ADA 2026) | Sky arc, moon | Native |
| 18 | Cloud layers split low / mid / high | Clear Outside, Sunsethue, Alpenglow | Spot detail | Now |
| 19 | One map overlay with one scrubber, not twenty toggles | PhotoPills, TPE | Spot detail | Later |
| 20 | Named bands for a composite score | Oura Readiness, Sunsethue | Light Index everywhere | Now |
| 21 | Contributors under the number | Oura | Light Index card | Now |
| 22 | Visible forecast uncertainty and horizon | Sunsethue | Date strip, Light Index | Now |
| 23 | One signature moment, numbers kept plain | (Not Boring) Weather | Sky arc | Native |
| 24 | Guests never hit an account wall | Apple Invites, Partiful | Join | Now |
| 25 | Identity later, at a moment of value | Apple Invites, iCloud | Trips, Join | Native |
| 26 | Host controls what guests see | Apple Invites | Invite modal | Now |
| 27 | Edit link vs suggest link | Wanderlog, Tripsy | Invite, Join | Later |
| 28 | Visible attribution and activity | Google Maps lists | Trip builder | Now |
| 29 | AI answers land as editable map objects | Google Ask Maps, Mindtrip | AI scout | Now |
| 30 | Checkable confidence on AI suggestions | (gap in the market) | AI scout | Now |

---

## A. Map and bottom sheet

### 1. Detented sheet over a live map
- **What it is.** A sheet that rests at fixed heights (Apple's HIG names *medium*, about half, and *large*; custom detents are allowed), with a grabber that shows it can be resized and that cycles detents when tapped. A nonmodal sheet lets people keep using the map behind it.
- **Where.** Apple Maps search and place cards. [HIG: Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets).
- **Why it works.** Progressive disclosure without losing the map. Fixed resting heights make the gesture predictable, and the grabber works with VoiceOver.
- **Iter.** The Explore phone sheet already has three snaps (peek 140px, half, full). Make them a documented contract: *peek* shows the search pill, the date and one summary line ("14 spots · best light 6:40 pm"); *half* shows the list; *full* shows the list with sort. Give the handle a button role so it can be operated by keyboard and VoiceOver (it is pointer-only today, see [02](02-system-and-identity.md)). On iOS this becomes `presentationDetents` with background interaction enabled [API name unverified].
- **Watch-outs.** One sheet at a time (the HIG says so). Never dim the map behind the Explore sheet. Today a selected marker *replaces* the sheet with a floating card, so the list context is lost (brief 02); a detent change is the better model.
- **When.** Now.

### 2. Glass for controls, solid for content
- **What it is.** In the current Apple design language, Liquid Glass "forms a distinct functional layer for controls and navigation elements" that floats above content, and the HIG says "Don't use Liquid Glass in the content layer." iOS 26 Maps uses a translucent search bar and floating controls set in from the screen edges.
- **Where.** [HIG: Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [MacRumors iOS 26 Maps guide](https://www.macrumors.com/guide/ios-26-maps).
- **Why it works.** The hierarchy is carried by the layer, not by borders, so content stays dominant.
- **Iter.** Floating map buttons, the search pill and the tab bar go glass; spot cards, the Light Index and timelines stay opaque white. This fits the white-surface direction well, and the token set needs a *material* layer that it does not have today.
- **Watch-outs.** No glass behind dense data such as hourly weather. Provide a solid fallback for Reduce Transparency.
- **When.** Native (on the web, keep today's `backdrop-blur` on the floating layer only).

### 3. Map chrome that respects the sheet
- **What it is.** The HIG asks apps to keep the Apple logo and legal link "10 points above the lowest resting position" of a bottom card, and not to cover the map with non-interactive elements. Map padding follows the sheet so the selected pin is never hidden.
- **Where.** [HIG: Maps](https://developer.apple.com/design/human-interface-guidelines/maps).
- **Why it works.** The primary action and the selection always stay visible and within thumb reach.
- **Iter.** Pan the map so a selected spot sits in the visible area above the sheet (selecting a marker does not pan today, brief 02). Set the map's camera padding to the sheet height at every detent. Keep the locate and layer buttons above the peek height.
- **Watch-outs.** Plan for MapKit's attribution rules now so they are not retrofitted later.
- **When.** Now.

### 4. Pins that carry the decision variable, with a pin budget
- **What it is.** Airbnb's map pins show the price, the number people decide on. Airbnb has written about limiting the map to the most relevant pins and showing smaller "mini pins" for the rest (secondary summary; the original Airbnb Tech post was not fetched [unverified]).
- **Where.** Airbnb search; [summary of Airbnb's map-ranking work](https://techscoop.substack.com/p/how-airbnb-made-map-search-smarter).
- **Why it works.** People can scan the map without opening anything.
- **Iter.** Iter's pins already show a Light Index number, which is the right instinct. Go further: label the pin with the *best window* for the chosen day ("82 · 6:40p"), show the top N by score in the viewport as pills, and the rest as dots. Re-label the pins when the date changes. Always show spots that are already in a trip.
- **Watch-outs.** "Where did my spot go?": show "+12 more" rather than silently dropping pins. Don't encode the score by colour alone (see 20 and [02](02-system-and-identity.md)).
- **When.** Now.

### 5. One selection drives map, list and sheet
- **What it is.** In Airbnb and Apple Maps, the list card, the pin and the sheet are three views of one selected object: hover or tap one and the others respond.
- **Where.** Airbnb search (desktop split view); Apple Maps.
- **Why it works.** People move between "which" (list) and "where" (map) without re-orienting.
- **Iter.** The desktop list sets a hovered id but the list ignores marker hover (brief 02). Make the coupling two-way and keyboard-reachable (focus as well as hover), and keep the selected card scrolled into view.
- **Watch-outs.** Keep filter and sort state shared between the two views, and preserve it in the URL so Back does not reset it (brief 02).
- **When.** Now.

### 6. Place card with one primary action at the top
- **What it is.** iOS 26 place cards put the main action buttons "more prominently listed at the top", before hours and details.
- **Where.** [MacRumors iOS 26 Maps guide](https://www.macrumors.com/guide/ios-26-maps); [HIG: Maps](https://developer.apple.com/design/human-interface-guidelines/maps) (place card styles).
- **Why it works.** The two or three things people do most are one tap away, above the fold.
- **Iter.** Spot detail: name, distance, the Light Index for the chosen day, then a single primary black pill (**Add to trip**) and two secondary actions (Directions, Share). Then the timeline, sun and moon, weather and nearby spots.
- **Watch-outs.** Only one primary. Don't show data you can't keep fresh (closures, permits) without a "last checked" date.
- **When.** Now.

### 7. Three ranked answers, not raw data
- **What it is.** Citymapper compares options for you and offers a few ranked choices with time and live status; a design critique praises the live status but flags its buried "Leave: Now" time control.
- **Where.** [Pratt IxD critique of Citymapper](https://ixd.prattsi.org/2026/02/design-critique-citymapper-ios-app/).
- **Why it works.** People choose between three good options instead of parsing a map or a chart.
- **Iter.** "When should I shoot here?" as three cards on spot detail: *Tonight 7:12 pm · 82*, *Tomorrow 6:48 am · 74*, *Sat 7:10 pm · 61*, each with a one-line reason and an arrive-by time. The date control must be a prominent pill, not a buried one.
- **Watch-outs.** An opinionated ranking needs a visible reason ("thin high cloud, clear horizon").
- **When.** Now.

### 8. Offline downloads with freshness stamps
- **What it is.** AllTrails offers offline maps and trail conditions on the trail card (search snippet only [unverified]); Wanderlog advertises offline access.
- **Where.** [AllTrails membership help](https://support.alltrails.com/hc/en-us/articles/43589223010708-The-benefits-of-AllTrails-premium-membership), [Wanderlog](https://wanderlog.com/plan-a-trip).
- **Why it works.** Photographers are often out of signal at the exact moment they need the plan.
- **Iter.** "Save for offline" on a trip: cache tiles, spot data and the computed light forecast for the trip dates, stamped "Forecast as of 4:12 pm".
- **Watch-outs.** A stale forecast shown as live is worse than none. Always show its age.
- **When.** Later (it is also a native strength).

## B. Itinerary builders

### 9. Feasibility connectors between stops
- **What it is.** Wanderlog shows distance and time between consecutive places and colours the map by day.
- **Where.** [Wanderlog](https://wanderlog.com/plan-a-trip), [iMore review](https://www.imore.com/apps/travel-apps/wanderlog-iphone-travel-app-trip-planning).
- **Why it works.** The list is the plan and the map is the sanity check; the connector makes feasibility visible.
- **Iter.** Iter already computes drive times and arrive-by hints. This is Iter's chance to beat Wanderlog: make the connector the *conflict signal*, e.g. "42 min drive · leave by 5:58 pm to make golden hour", turning amber when the drive eats the light window.
- **Watch-outs.** Wanderlog is dense and paywalls route optimisation. Stay calmer.
- **When.** Now.

### 10. Draggable day boundaries (komoot multi-day)
- **What it is.** komoot's multi-day planner splits one route into days and shows per-day distance, elevation and time (from search snippets [unverified]).
- **Where.** [komoot Premium](https://www.komoot.com/premium), [komoot newsroom](https://newsroom.komoot.com/182344-go-further-with-komoot-premium/).
- **Why it works.** The day boundary is something you can move, and you see at once what moving it costs.
- **Iter.** Per-day totals in the day header (drive time, number of stops, "sunset at last stop 7:42 pm"), and later a draggable boundary between days.
- **Watch-outs.** Never auto-split without an override.
- **When.** Later.

### 11. Direct-manipulation reorder with recompute and undo
- **What it is.** Roadtrippers and Wanderlog reorder stops by drag and drop (Roadtrippers help page returned 403; snippet only [unverified]).
- **Where.** [Roadtrippers help](https://support.roadtrippers.com/hc/en-us/articles/200632079-Planning-a-Trip-on-Our-Website).
- **Why it works.** The order *is* the model; arrows that move one step at a time are not.
- **Iter.** Replace the up/down/trash trio (three 36px buttons with no gap between them, see [01](01-screen-by-screen-audit.md)) with a drag handle, drag across days, a recompute shimmer on drive times, and an undo toast. On iOS: `List` with `onMove`, swipe to delete.
- **Watch-outs.** Dragging inside a scrolling sheet conflicts with the sheet's own drag; use a dedicated handle.
- **When.** Now.

### 12. "Add to trip" everywhere, plus an along-route filter
- **What it is.** Roadtrippers offers Add to Trip from search, from the map and from category browsing (snippet [unverified]).
- **Where.** [Roadtrippers get started](https://roadtrippers.com/get-started/).
- **Why it works.** People plan in two modes: "I know the place" and "show me what's near my route".
- **Iter.** Curated spots can't be added to a trip from Explore at all today (brief 02). Put Add to trip on every card, pin and detail. Then add Iter's own twist, which no competitor has: **"Along this day's route, sorted by the light when you'd arrive."**
- **Watch-outs.** Roadtrippers is POI-heavy (food, fuel, hotels); Iter should stay photographic.
- **When.** Now.

### 13. Now / next / later, and Live Activities (Flighty)
- **What it is.** Flighty, the 2023 Apple Design Award winner for Interaction, starts a Live Activity hours before departure and shows one status at a glance on the Lock Screen and in the Dynamic Island, escalating only when something changes. The HIG says Live Activities suit tasks "that have a defined beginning and end" and should "focus on important information that people need to see at a glance".
- **Where.** [2023 ADA winners](https://www.apple.com/newsroom/2023/06/apple-announces-winners-of-the-2023-apple-design-awards/), [9to5Mac on Flighty's Live Activities](https://9to5mac.com/2022/10/24/flighty-dynamic-island-iphone-live-activities/), [HIG: Live Activities](https://developer.apple.com/design/human-interface-guidelines/live-activities).
- **Why it works.** One decision per glance, started at the moment of need.
- **Iter.** A day-of mode in the trip: one card, "Next: Mesa Arch · leave by 5:20 am · golden hour 6:02–6:34 · 78". Natively, a "shoot window" Live Activity: compact = sun glyph + minutes to golden hour; expanded = spot, leave-by, Light Index; it ends after sunset. On the web, a sticky "Now" bar.
- **Watch-outs.** A whole multi-day trip is not a Live Activity. Escalate only on a meaningful change (the score drops a band, the drive grows by 15 minutes or more).
- **When.** Native (the web "Now" bar can come sooner).

### 14. Tab bar that becomes a sidebar
- **What it is.** In iOS 26 the tab bar floats on glass and can minimise on scroll with an accessory; on iPad it can become a sidebar. Sidebars allow "no more than two levels of hierarchy".
- **Where.** [HIG: Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [HIG: Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars).
- **Why it works.** One information architecture reflows across sizes, so people keep their place.
- **Iter.** Explore, Trips, Saved as tabs on iPhone; a sidebar on iPad and Mac with trips listed underneath. The "next stop" can be the tab bar accessory. Today the web app gives desktop a top bar and phone a tab bar with different content (no logo, no profile on phone; see [01](01-screen-by-screen-audit.md)).
- **Watch-outs.** Invite is an action, not a tab.
- **When.** Native (fix the web parity issues now).

### 15. Sheets become panels on large screens
- **What it is.** The HIG says that on iPad and Mac, sheets present as form or page sheets over a dimmed background, and detents are an iPhone idiom.
- **Where.** [HIG: Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets).
- **Iter.** On desktop, Explore's list becomes a floating panel over a full-bleed map (the Apple Maps Mac layout) rather than a 46% column, and spot detail can push inside that panel. Add to trip becomes a popover.
- **Watch-outs.** Don't scale the phone sheet up to desktop and call it done.
- **When.** Now (desktop web) and Native.

## C. Light, weather and the score

### 16. The time series as the hero, with a scrubber (Tide Guide)
- **What it is.** Tide Guide won the 2026 Apple Design Award for Visuals and Graphics for "hour-by-hour forecasts and crisp weather data presentation" with custom animation. It was also a 2023 Interaction finalist.
- **Where.** [2026 ADA winners](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/).
- **Why it works.** One chart carries the whole story, and scrubbing is a native gesture.
- **Iter.** The 24-hour light timeline is Iter's most ownable visual. Make it the hero of spot detail: draw golden and blue hour as labelled *bands* (today they are a continuous gradient read from tick marks, see [02](02-system-and-identity.md)), overlay the window scores, and add a scrub handle that moves the sun on the sky arc and updates the readout.
- **Watch-outs.** Animation must never delay reading. Respect Reduce Motion.
- **When.** Now.

### 17. A single-purpose sky instrument (Moonlitt)
- **What it is.** Moonlitt won the 2026 Apple Design Award for Interaction; Apple describes "an elegant interface for tracking celestial events, planning photography, and exploring lunar phenomena".
- **Where.** [2026 ADA winners](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/).
- **Why it works.** It is the closest awarded analogue to Iter's sky arc and moon card, and it shows that a narrow sky tool can win on interaction.
- **Iter.** Use Moonlitt as the interaction bar for the sky arc and moon card; review it hands-on before the native build (its interaction details beyond Apple's text are [unverified]).
- **When.** Native.

### 18. Cloud layers split low / mid / high
- **What it is.** Photographer forecasts separate cloud by altitude because that decides colour: Sunsethue's model looks at cloud along the sun's direction; Alpenglow describes favouring mid and high cloud with gaps (snippet); Clear Outside shows low/mid/high hourly [unverified].
- **Where.** [Sunsethue whitepaper](https://sunsethue.com/whitepaper), [Sunsethue FAQ](https://sunsethue.com/faq), [Alpenglow explainer](https://alpenglowapp.com/will-sunset-be-good-tonight).
- **Why it works.** It explains a score in photographers' terms.
- **Iter.** Iter already fetches these layers and uses them in the score. Show them: three short labelled bars under the Light Index ("Low 10% · Mid 35% · High 50%") with one plain sentence ("Thin high cloud, clear horizon: expect colour").
- **Watch-outs.** Grids of numbers read as jargon. Three bars and a sentence, no more.
- **When.** Now.

### 19. One overlay, one scrubber (what to take from PhotoPills and TPE)
- **What it is.** PhotoPills' planner and The Photographer's Ephemeris put sun and moon bearings on a map with a time bar. PhotoPills is powerful but reviewers note "a bit of a learning curve".
- **Where.** [The Photographer's Ephemeris](https://photoephemeris.com), [PhotoPills review](https://expertphotography.com/photopills-review).
- **Why it works.** Photographers think in bearings and times; a line on a map shows both.
- **Iter.** An optional "light direction" layer on spot detail: a sun azimuth line for the scrubbed time. Off by default.
- **Watch-outs.** This is where Iter wins by restraint. Don't ship PhotoPills' panel of toggles, jargon or dense numerals as the default surface.
- **When.** Later.

### 20. Named bands for a composite score
- **What it is.** Oura's Readiness score uses named bands (85–100 Optimal, 70–84 Good, 60–69 Fair, 0–59 Pay attention). Sunsethue states its own quality bands.
- **Where.** [Oura Readiness help](https://support.ouraring.com/hc/en-us/articles/360025589793), [Sunsethue FAQ](https://sunsethue.com/faq).
- **Why it works.** The word anchors the number, and the top band stays rare enough to mean something.
- **Iter.** Iter has bands (Epic / Great / Good / Fair / Poor at 88/74/58/40) but shows the word inconsistently and keeps the legend only on the landing page. Put number + word together wherever there is room, put a one-line legend in Explore and Spot, and check that "Epic" is actually rare.
- **Watch-outs.** The current colours make Epic and Good nearly indistinguishable for deuteranopes, and the fallback score with no forecast is 58, the bottom of "Good" (see [02](02-system-and-identity.md)).
- **When.** Now.

### 21. Contributors under the number
- **What it is.** Oura breaks Readiness into contributors and shows which ones pull the score down.
- **Where.** [Oura contributors help](https://support.ouraring.com/hc/en-us/articles/360057791533).
- **Why it works.** It turns "why 62?" into an answer.
- **Iter.** Tapping the Light Index opens a short list: sun angle, low / mid / high cloud, rain, visibility, moon, each with a +/− effect and one headline sentence. The scoring code already produces these reasons.
- **Watch-outs.** The weights are heuristics, so say "estimated from forecast data".
- **When.** Now.

### 22. Visible uncertainty and horizon
- **What it is.** Sunsethue limits forecasts to three days, says cloud forecasts "can be wrong sometimes", and computes an uncertainty metric from forecast horizon and variance.
- **Where.** [Sunsethue FAQ](https://sunsethue.com/faq), [Sunsethue whitepaper](https://sunsethue.com/whitepaper).
- **Why it works.** Admitting limits makes the confident days believable.
- **Iter.** On the 7-day date strip, hatch or fade days 4–7 and show a range ("55–75") instead of a point. Put "Updated 2:00 pm" on every score. When there is no forecast, show a hollow ring and "No forecast" rather than a green 58.
- **Watch-outs.** How Sunsethue draws uncertainty in its UI was not found; design and test this yourself.
- **When.** Now.

### 23. One signature moment, numbers kept plain ((Not Boring) Weather)
- **What it is.** (Not Boring) Weather uses "gaming industry tech like 3D modeling and lighting effects" (App Store) while keeping the forecast readable. Its sibling, (Not Boring) Habits, won an ADA in 2022; whether Weather itself was recognised is [unverified]. (Not Boring) Camera is a 2026 ADA finalist.
- **Where.** [App Store: (Not Boring) Weather](https://apps.apple.com/us/app/id1531063436), [2026 ADA finalists](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/).
- **Why it works.** Personality turns a utility into somewhere people want to go.
- **Iter.** Spend the personality budget on one moment, for example a sky arc lit to match the real sun angle at the scrubbed time. Keep the Light Index and times plain.
- **Watch-outs.** Skins and mini-games are scope creep.
- **When.** Native.

## D. Onboarding without accounts, sharing and collaboration

### 24. Guests never hit an account wall
- **What it is.** Apple Invites needs iCloud+ to *create*, but "anyone can RSVP, regardless of whether they have an Apple Account or Apple device". Partiful guests reply from a text link without installing anything (secondary source [unverified]). Splitwise, by contrast, makes people create an account to join a group (secondary source).
- **Where.** [Apple Invites announcement](https://www.apple.com/newsroom/2025/02/introducing-apple-invites-a-new-app-that-brings-people-together/), [Partiful review](https://party.pro/Partiful), [Splitwise join](https://robots.net/fintech/how-to-join-a-group-in-splitwise/).
- **Why it works.** The host carries the setup cost; the guest gets straight to the thing.
- **Iter.** Iter's no-account join is a real advantage; protect it. Make `/join/CODE` feel like an invitation, not an app screen: take it out of the app shell (the tab bar competes with the one call to action, brief 09), lead with the trip's photo, dates and who's going, and ask only for a name.
- **When.** Now.

### 25. Identity later, at a moment of value
- **What it is.** Convert people to a persistent identity when they have something to lose (a third saved spot, a shared trip), not at launch. Natively, iCloud is the account, with no sign-up form. (A general practice; no single source.)
- **Iter.** On the web: "This trip lives on this device. Save a recovery link." Natively: turn on iCloud sync. Fix the default name "You", which leaks to collaborators (brief 09), by asking for a name the first time someone shares.
- **When.** Native (the name fix is Now).

### 26. Host controls what guests see
- **What it is.** Apple Invites hosts choose what appears in the invitation and guests control their own visibility.
- **Where.** [Apple Invites announcement](https://www.apple.com/newsroom/2025/02/introducing-apple-invites-a-new-app-that-brings-people-together/).
- **Iter.** Photographers guard their spots. Offer "Hide exact locations from viewers" on the invite, plus "Reset link" (the link is a bearer token today, with no way to revoke it, brief 08).
- **When.** Now.

### 27. Edit link vs suggest link
- **What it is.** Wanderlog offers one link for suggesters and another for full editors (search summary [unverified]); Tripsy distinguishes Collaborator and View-only guests (help snippet).
- **Where.** [Wanderlog listing](https://www.iculture.nl/app/1476732439), [Tripsy sharing help](https://tripsy.helpscoutdocs.com/article/11-share-my-trip-plan-with-family-or-friends-on-tripsy).
- **Iter.** Roles are shown and editable in the Invite modal but never enforced (brief 08). Either enforce them or remove them; a "suggest" role whose additions appear as ghost cards is the ambitious version.
- **When.** Later.

### 28. Visible attribution and activity
- **What it is.** In Google Maps shared lists, viewers see who joined and who added or edited each place.
- **Where.** [Google Maps help: shared lists](https://support.google.com/maps/answer/7280933).
- **Why it works.** Authorship keeps disagreements friendly and makes changes trustworthy.
- **Iter.** "Added by Sam" on each stop, in Sam's colour with initials, and a toast when a pull changes the itinerary ("Sam moved Mesa Arch to Day 2 · Undo"). Today a pull silently replaces the trip (brief 08).
- **When.** Now.

## E. AI-assisted discovery

### 29. AI answers land as editable map objects
- **What it is.** Google's Ask Maps answers plain-language questions with suggestions on a map (coverage via search snippets [unverified]); Mindtrip turns chat into an editable itinerary (snippet [unverified]).
- **Where.** [Search Engine Journal on Ask Maps](https://www.searchenginejournal.com/google-maps-launches-ai-conversational-search-with-ask-maps/), [PhocusWire on Mindtrip](https://www.phocuswire.com/mindtrip-ai-trip-planner-travel-startup).
- **Why it works.** The answer can be checked against the map, and nothing is trapped in a chat bubble.
- **Iter.** The scout already returns cards and gold pins, which is the right shape. Add: the prompt as an editable chip at the top for re-running; "Add all to Day 2"; a per-card Dismiss; a cancel button while it runs (up to about a minute today with no stop control, brief 03); and a detail view before saving.
- **When.** Now.

### 30. Checkable confidence on AI suggestions (a gap)
- **What it is.** No source found shows a major travel app giving per-suggestion confidence. Iter can fill that gap.
- **Iter.** A "match" indicator derived from checkable facts (how many prompt constraints the spot meets, whether it has a Wikipedia or OSM record, whether access is known), plus a "Needs checking: access, permits" line. Never let the model grade itself.
- **When.** Now.

## F. Apple Design Awards relevant to Iter

| Year | App | Award | Why it matters to Iter | Source |
|---|---|---|---|---|
| 2026 | Moonlitt | Winner, Interaction | Sky and moon planning for photographers; the bar for the sky arc | [Apple Newsroom](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/) |
| 2026 | Tide Guide | Winner, Visuals and Graphics | Hour-by-hour charts as the hero; the bar for the light timeline | same |
| 2026 | (Not Boring) Camera, Structured | Finalists | Personality with restraint; a day timeline (Structured) | same |
| 2025 | Watch Duty | Winner, Social Impact | Live map data that people trust under stress | [Apple Newsroom](https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/) |
| 2025 | Lumy | Finalist, Delight and Fun | Sun and light-times app (Apple gives no description; details [unverified]) | same |
| 2024 | Crouton, Gentler Streak | Winners (Interaction; Social Impact) | Calm list UI; a score that is not judgemental, a model for how to word a low Light Index | [Apple Newsroom](https://www.apple.com/newsroom/2024/06/apple-announces-winners-of-the-2024-apple-design-awards/) |
| 2023 | Flighty | Winner, Interaction | Glanceable time-critical status; Live Activities | [Apple Newsroom](https://www.apple.com/newsroom/2023/06/apple-announces-winners-of-the-2023-apple-design-awards/) |
| 2023 | Tide Guide | Finalist, Interaction | (see above) | same |

## What the best products share that Iter lacks today

1. **One selected object that drives everything.** Pin, card and sheet react together (Apple Maps, Airbnb). In Iter they are partly wired and partly not.
2. **Detent discipline.** Named resting heights, a grabber anyone can operate, and map padding that follows the sheet.
3. **An answer, not just data.** Citymapper and Oura turn data into "go / wait / skip". Iter computes the Light Index but doesn't yet say *when to go*.
4. **Honest uncertainty.** Sunsethue limits its horizon and admits error; Iter shows a confident green 58 when it knows nothing.
5. **Feasibility as the headline.** Drive time against the light window should be the trip builder's main signal, and it is Iter's unique angle.
6. **A day-of mode.** Flighty guides you on the day; Iter only plans.
7. **Trustworthy sharing.** Roles that mean something, attribution, a revocable link, and no account wall for guests (Iter already has the last one).
8. **Restraint, with one signature moment.** Weather apps that win awards keep their numbers plain and spend their personality in one place.

## Anti-patterns to avoid

- **Jargon and density as the default surface** (PhotoPills' learning curve). Azimuths and elevations belong behind a tap.
- **A forecast presented as certain.** No bare "92" for day 7.
- **A score with no explanation.**
- **An account wall before the shared object.**
- **Colour-only bands.** Every band colour needs its word or a glyph beside it.
- **Personality that hides the data.**
- **AI results that are only text,** or that can't be cancelled, edited or dismissed.
- **Silent edits in shared trips.**
