# 1 · Where Iter stands

A frank read of the prototype, drawn from the flow briefs, the competitor teardowns, the opportunity briefs and the design audit. Each point links to the brief that found it.

## The short version

Iter has a real idea that nobody else ships: a light forecast attached to each stop of a dated, multi-day drive. The research could not find a competitor doing it ([landscape, "Where nobody is"](../research/competitors/00-landscape.md#where-nobody-is)). The engineering under the prototype is better than most prototypes. But today the product undermines its own idea in three ways. The headline score misleads. The main screen is broken on phones. And the look is borrowed from Airbnb, while Iter's own visual ideas sit below the fold.

None of this is expensive to fix. The order of fixing matters more than the size of any one fix, and that order is the plan in [section 4](04-phases.md).

## What is strong, and should be protected

1. **The idea and the bones of it.** Per-stop light sessions, "Be set up by" times, drive times between stops and a 7-day score already exist ([differentiation options, "Where the prototype stands"](../research/opportunities/03-differentiation-options.md#where-the-prototype-stands)). The light-first promise "exists in code but not in the experience" ([positioning, Direction 1](../research/opportunities/04-positioning.md#direction-1--light-first-road-trips-recommended)).
2. **Light as a visual language.** Four things are genuinely Iter's: the sky-gradient timeline, the sun-and-moon arc with "Your frame", the gold light moment, and the plain-language window reasons, "the best copy in the product" ([system and identity §8](../research/design-audit/02-system-and-identity.md#8-identity-distinctive-or-generic)).
3. **The system's engineering.** Two clean token layers, no drift between `tokens.ts` and `index.css`, nearly token-clean components, and a living styleguide with stable ids. That styleguide is what made the Figma import scripts possible ([system and identity, verdict](../research/design-audit/02-system-and-identity.md#verdict-in-one-paragraph), [§4](../research/design-audit/02-system-and-identity.md#4-components)).
4. **Sharing with no account wall.** "Iter's no-accounts sharing is a real advantage. Keep it when accounts arrive" ([gaps and openings §4](../research/competitors/gaps-and-openings.md#4-the-ux-failures-common-across-the-category); benchmark [#24](../research/design-audit/03-benchmarks.md#24-guests-never-hit-an-account-wall)).
5. **A free core, no paywall yet.** The best-rated products in the category keep the core free; the worst-reviewed cap it ([pricing, "What this suggests"](../research/competitors/pricing-and-models.md#what-this-suggests-for-iter)).
6. **The landing hero and the editorial serif.** The hero is "the strongest piece of visual design in the product" ([audit §1](../research/design-audit/01-screen-by-screen-audit.md#1-landing-)), and Roboto Serif at large sizes "is the most characterful thing in the product" ([system and identity §2](../research/design-audit/02-system-and-identity.md#2-typography)). Section 2 argues for narrowing the serif's job, not for losing what it does well.

## The most serious problems

Ordered by how much they damage the core job: knowing when and where the light is good.

| # | Problem | Severity | Found in |
|---|---|---|---|
| 1 | **The Light Index answers the wrong question.** The day score is 70% of the best window plus 30% of the average, and in clear weather the best window is usually the night sky. About 14 of 16 pins read "Epic". A rainy Tuesday shows "87 · Great light" while both golden hours are "Thick overcast · 38". The date strip ranks days on the same score. | critical | [Audit X1](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first); [system §5](../research/design-audit/02-system-and-identity.md#5-the-data-visualisation-system-the-products-core) |
| 2 | **On phones the Explore map is blank.** `tw()` does not resolve the position group, so `relative` beats `absolute inset-0` and the map collapses to zero height. The same clash misplaces the scout's submit button. | critical | [Audit X0](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first); [system §4](../research/design-audit/02-system-and-identity.md#4-components) |
| 3 | **Unknown is shown as good.** A failed or out-of-range forecast scores every window 58, so the spot reads a confident green "Good". The verdict says "no forecast yet" even when the request failed. | major | [Audit X2](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first); [flow 05, "When the forecast fails"](../flows/05-spot-detail.md#when-the-forecast-fails) |
| 4 | **It looks like Airbnb.** `#FF385C` and four Airbnb greys, white cards, black pills. Rose means Epic, danger, Day 1, member 1, "Now" and "you" at once. The light scale fails 3:1 for four of five bands and collapses Epic vs Good for deuteranopes. | major | [Audit X3](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first); [system §3](../research/design-audit/02-system-and-identity.md#3-colour) |
| 5 | **"When to go" is buried.** On the phone spot page the first viewport is photo, tags and a serif pull-quote. Five light views use five scales and never highlight the same window. | major | [Audit X4](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first) |
| 6 | **The light-first promise is invisible in the builder.** Sessions are optional chips; warnings fire only when both stops have one, and effectively never across days. | major (audit row 7 covers the stop card) | [Flow 07, "Not as it looks"](../flows/07-trip-builder.md#not-as-it-looks); [audit table row 7](../research/design-audit/01-screen-by-screen-audit.md#the-most-important-screen-level-findings) |
| 7 | **Trip editing lags the bar.** No drag, no undo, the header "Add stop" always targets Day 1, and the add-stop list is unsorted. Wanderlog sets the bar. | — (table stakes) | [Gaps §1](../research/competitors/gaps-and-openings.md#1-table-stakes-iter-lacks), [§5](../research/competitors/gaps-and-openings.md#5-where-a-competitor-does-it-better-than-iter-today) |
| 8 | **Unfinished edges reach users.** "Vantage" across the UI, developer copy in the scout fallback, React Router's "Hey developer" 404, the trip owner shown to friends as "You". | major | [Audit X5](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first) |
| 9 | **Phone and desktop feel like two products,** and basic accessibility is missing: a 1.24:1 focus ring, about 60 controls under 44px, modals that do not trap focus. | major | [Audit X6, X8](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first) |
| 10 | **Two data sources cannot be used commercially.** Open-Meteo's free tier and the OSRM demo server are non-commercial. | launch blocker | [Differentiation options, "Where the prototype stands"](../research/opportunities/03-differentiation-options.md#where-the-prototype-stands) |
| 11 | **No offline, no notifications, trips on one device only.** All three are table stakes in the category. | — (table stakes) | [Gaps §1](../research/competitors/gaps-and-openings.md#1-table-stakes-iter-lacks) |

The full, de-duplicated list of every design problem is in [section 5](05-critique-digest.md).

## Where the competition is

- **Locationscout is the closest threat.** 233,000+ spots, an Along Route planner, routing with travel times and sun and moon lines, all shipped in 2026. "A day-by-day planner is a small step for it" ([landscape, threats](../research/competitors/00-landscape.md#where-the-direct-threat-is)).
- **PhotoScout names Iter's exact job,** "the spots, the times, and the route". It is unproven, web only, and covers Europe and Asia ([landscape, threats](../research/competitors/00-landscape.md#where-the-direct-threat-is)).
- **Wanderlog is the bar for trip editing:** free, collaborative, times between every stop, drag to reorder ([gaps §5](../research/competitors/gaps-and-openings.md#5-where-a-competitor-does-it-better-than-iter-today)).
- **Alpenglow makes the forecast find you** (widgets, Watch, Live Activities, alerts), and **Sunsethue is more honest** (uncertainty, rarity, a method page) ([gaps §5](../research/competitors/gaps-and-openings.md#5-where-a-competitor-does-it-better-than-iter-today)).

Neither Locationscout nor PhotoScout could be tested by hand, so "nobody does this" is strong but not proof ([landscape, limits](../research/competitors/00-landscape.md#limits-of-this-research)).

## What this means

Iter does not need a new idea. It needs to stop contradicting the one it has. The score must mean what a photographer thinks it means. The plan must carry the light. And the look must come from light, not from a booking site. Everything in this plan follows from those three sentences.
