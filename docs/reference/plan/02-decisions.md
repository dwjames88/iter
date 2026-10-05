# 2 · The decisions that shape everything else

Six decisions sit upstream of the rest of the plan. Each one lists the options, a recommendation, and the strongest case against that recommendation. None of them is made yet. The order you need to answer them in is in [section 7](07-decisions-and-unknowns.md).

---

## 2.1 Positioning and first audience

> **Decision 2.1 · What is Iter's first story, and who is it for?**
> It decides what the home screen leads with, what the App Store screenshots show, and what gets cut when time runs short ([positioning](../research/opportunities/04-positioning.md)).

> **Option 2.1-A · Light-first road trips.** For serious hobbyist landscape and travel photographers on multi-day drives, one to four trips a year, often with a companion who does not shoot. Promise: "Be in the right place when the light is right." Proven by B1 light-first itinerary, B3 weather swap and C1 "Tonight" Live Activity ([Direction 1](../research/opportunities/04-positioning.md#direction-1--light-first-road-trips-recommended)).

> **Option 2.1-B · The calm field companion.** Anyone in the field before dawn. Proven by E1 "Now" mode, E3 Night mode, C2 offline plus C1. Calm is a quality, not a capability: "easy to claim and easy to copy" ([Direction 2](../research/opportunities/04-positioning.md#direction-2--the-calm-field-companion)).

> **Option 2.1-C · The honest sky forecaster.** Condition chasers. The most crowded and cheapest lane; forecast skill is bounded by weather models ([Direction 3](../research/opportunities/04-positioning.md#direction-3--the-honest-sky-forecaster)).

> **Option 2.1-D · The private atlas.** Your places, your history, shared on your terms. The least crowded lane, but "a new user with no history sees an empty map" ([Direction 4](../research/opportunities/04-positioning.md#direction-4--the-private-atlas)).

> **Recommendation.** A, built to the standard of B, with D's ethics underneath from day one (private by default, sensitive spots), exactly as the positioning brief recommends ([Recommendation](../research/opportunities/04-positioning.md#recommendation)). First audience: the serious hobbyist landscape and travel photographer ([audience, 5.1](../research/opportunities/01-photographers-and-jobs.md#51-the-decision)). It is the only direction that builds strongly on what exists, sits in a lane where nothing was found, and shows value on the first trip. Design consequences: the trip, not the map, is the home of the app; every stop leads with a decision; sessions stop being optional.

> **Case against.** Locationscout is already moving here, and adding "plan around sunset" is a smaller step for it than building a spot database is for Iter. An itinerary that reshuffles itself on a forecast that is right "just over 50% of the time" can feel flaky. The segment is small and price-sensitive (Inferred). And "Iter orders your stops by light" does not screenshot as well as a glowing sunset map ([the argument against](../research/opportunities/04-positioning.md#the-argument-against)). If testing shows people do not want the app to reorder their trip, B1 shrinks to "suggest an order" ([what would change this](../research/opportunities/04-positioning.md#what-would-change-this-recommendation)).

---

## 2.2 Design direction and identity

> **Decision 2.2 · How does Iter stop looking like Airbnb, and make light the organising idea of the system?**
> This also settles the logo, the typeface and the palette, which the audit says should be decided together ("Decide with the logo, not after it", [system §2](../research/design-audit/02-system-and-identity.md#2-typography)).

**The principle is settled by the research.** Retire rose. Keep ink and paper for the interface. Draw the data colours from the sky (night navy, blue-hour indigo, golden amber, day white). Spend the brand accent on one moment, not on data ([system §3](../research/design-audit/02-system-and-identity.md#3-colour), [§8](../research/design-audit/02-system-and-identity.md#8-identity-distinctive-or-generic)).

**Your stated direction.** After round two you said: "I love switchback, but the mark needs to be improved, and the i feels too different from the word. Maybe flip the I horizontal so it looks like it joins the word, and make the dot of the i in line with the top of the t. Maybe explore a heavier typeface." You also said "give me some options from a serif font too" and "Contour is really cool too, but its too big/detailed." On colour: "For colors i like first light and alpine." So the live identity is the **route idea**: Waypoints / Switchback is the favourite and Waypoints / Contour is the second ([round two, waypoints](../../brand/iter/round-2/logo-options-round-2.html)). Meridian is no longer the lead. **The logo is not final.** Round three is refining both, with heavier faces, serif options and a simpler contour, in `brand/iter/round-3/`. This plan does not choose a mark. It works out what your two palettes mean for the product.

**The two palettes** ([palettes](../../brand/iter/round-2/palettes.md#first-light-first-light)):

| | First Light | Alpine |
|---|---|---|
| Idea | Warm sunrise: espresso on cream, a coral sun | Forest at altitude: spruce on stone, lichen green |
| Light ground | ink `#2A1710`, paper `#FFF6EC`, accent `#E4572E` | ink `#0F2A20`, paper `#F1F3EC`, accent `#5E7F12` |
| Dark ground | ink `#FFF1E3`, paper `#1C1210`, accent `#FF8A5C` | ink `#EEF2E8`, paper `#0A1A14`, accent `#B9D86B` |
| Accent on light paper | 3.45:1: graphics only, fails text | 4.15:1: graphics only, fails text |
| Accent on dark paper | 7.91:1 | 11.19:1 |
| The palette study's weak spot | Thin coral strokes are weak at 16px; a coral app icon fails contrast | Reads olive, can look dated beside cool UI greys |

**What they imply for the product's visual language.** This is my reading of how the palettes meet the audit's findings. The hex comparisons are mine; the ratios are the palette study's.

1. **Coral sits close to the red the audit asked to retire.** The audit's problem with `#FF385C` was not only that it is Airbnb's. Red also "reads as alert", and one hue meant six things ([system §3](../research/design-audit/02-system-and-identity.md#3-colour)). First Light's `#E4572E` is a warmer red-orange, so a map of coral pins could read as warnings again. Its dark accent `#FF8A5C` is also almost the same as today's warning orange `#FF8A3D`. If coral is the brand, danger and warning need their own hue and an icon, and coral never marks data.
2. **Green reads as "good".** Today's "Good" light band is green `#22C55E`, and status colours will add a success green ([system §1](../research/design-audit/02-system-and-identity.md#1-tokens)). An Alpine lichen route or pin will be read as "good light" or "done". If Alpine leads, green leaves the Light Index entirely (the single-hue ramp already does this) and success uses ink with a check icon, not green.
3. **The gold light moment has to find a new home.** Switchback's tittle is "the gold destination" ([switchback notes](../../brand/iter/round-2/waypoints/switchback/notes.json)). In First Light the natural light moment is the coral sun itself, which fits the idea well. In Alpine there is no warm colour at all, so the light data (amber ramp) becomes the only warmth in the interface. That could make light stand out more, not less.
4. **Neither accent works as text on light paper.** Both need a darker text-safe variant, exactly as the audit asks for every accent ([system §3](../research/design-audit/02-system-and-identity.md#3-colour), recommendation 4). Both are strong on dark grounds.
5. **Night mode is red and dim** ([E3](../research/opportunities/03-differentiation-options.md#e3--night-mode)). First Light's warm family carries over into it naturally. Alpine's greens would be dropped or remapped in Night mode, so the brand looks different at 5 a.m. That is acceptable, but it should be designed on purpose.
6. **Both papers are tinted** (cream, stone), not white. That is a real change from today's white UI. It suits the warm photographs, but every surface, shadow and the map style has to be retuned for it, and photos must be checked against a tinted ground.
7. **The route idea becomes a UI device.** The switchback's jog or the contour's meander can draw route lines, the connectors between trip stops and section rules, the way the audit suggested Meridian's horizon line could ([system §8](../research/design-audit/02-system-and-identity.md#8-identity-distinctive-or-generic)). This gives the trip builder a signature of its own. Contour's "too big/detailed" note applies here too: keep the device to a single line.

> **Option 2.2-A · First Light leads.** Espresso and cream for the interface; coral is the sun, used for the brand moment (the tittle) and nowhere in data. The Light Index ramp runs neutral to amber below coral, and danger becomes a distinct hue with an icon. Warmest and most "photographic light".

> **Option 2.2-B · Alpine leads.** Spruce and stone for the interface; lichen for the route and the brand. Light data is the only warm colour on screen. Green is removed from the Light Index and from success states. Calm and outdoors, with the clearest separation between "route" and "light".

> **Option 2.2-C · Both, with separate jobs.** Alpine for the land and the journey (interface ink, route lines, the switchback mark); First Light's coral for the light (the brand light moment and, at most, the top of the light ramp). It matches the product's idea: the road is green, the light is warm. It is also the hardest to keep disciplined: two accents plus a light ramp plus day colours can turn busy, and the categorical day and people set must avoid both accents.

> **Recommendation.** No pick yet; this is yours. My lean is C, tested against A, because it uses both palettes you like and gives each one a job the product already has. Decide it with round three's mark in front of you, in Figma, on three real screens: an Explore map full of pins, a spot page's light timeline, and a trip day with a route. Whatever you choose: drop the italic-serif accent from the UI. If round three's serif wordmark wins, keep the serif for the wordmark and place names only, and run the interface in a sans (typography option A, [system §2](../research/design-audit/02-system-and-identity.md#2-typography)). On native, SF Pro for running text is a later decision (typography option C).

> **Case against.** The audit's own recommendation was Meridian on the Archivo family with Gold Standard. It is the cheapest path, because the UI already runs on Archivo, and it keeps gold as the light moment with no red or green conflicts ([system §8](../research/design-audit/02-system-and-identity.md#8-identity-distinctive-or-generic)). Switchback was drawn in Geist 600, and its kink "vanishes at 16px" and "can look like a drawing flaw" at large sizes ([switchback notes](../../brand/iter/round-2/waypoints/switchback/notes.json)). Both of your palettes bring a semantic conflict that the gold route avoids: coral reads as alert, green reads as good. Option C doubles the colour discipline the audit found missing today.

Sketches of each direction are in [section 6.5](06-design-options.md#65-visual-identity-direction).

---

## 2.3 What the Light Index is, and how it earns trust

> **Decision 2.3 · What does the headline number mean?**
> Today it is "70% of the best window plus 30% of the average", which makes most spots Epic and lets a night sky rescue a grey sunset ([flow 05, Light Index](../flows/05-spot-detail.md#light-index-plain-language); [audit X1](../research/design-audit/01-screen-by-screen-audit.md#cross-cutting-findings-read-these-first)).

> **Option 2.3-A · Intent-based score.** The user picks what they shoot (Sunrise, Sunset, Blue hour, Night), defaulting to the spot's "best at", and every pin, card, strip and stop shows the score for that intent ([system §5](../research/design-audit/02-system-and-identity.md#5-the-data-visualisation-system-the-products-core), fix A).

> **Option 2.3-B · Name the window.** Keep the best-window score, but never show a bare number: "Night sky · 93" ([system §5](../research/design-audit/02-system-and-identity.md#5-the-data-visualisation-system-the-products-core), fix B).

> **Option 2.3-C · Both.** The intent sets the default; the window name is always printed beside the number.

> **Recommendation.** C, as the audit recommends, and then check that "Epic" is rare in a normal week. Add, in this order: a distinct "No forecast" state (hollow ring, dashed arc, no colour band); forecast age wherever a score appears; a confidence marker that falls with lead time; the reasons by layer one tap away; and later a "How did it go?" check-in (A1, [option A1](../research/opportunities/03-differentiation-options.md#a1--explainable-light-index)). Uncertainty and explanation are what nobody does well ([gaps §3](../research/competitors/gaps-and-openings.md#3-things-nobody-does-well)); this is opening 2 in the competitor ranking ([gaps §6](../research/competitors/gaps-and-openings.md#2-the-most-trustworthy-light-score-in-the-category)). Say plainly in the product that past about three days a trip is planned on geometry and season, and inside 72 hours on weather ([positioning, recommendation](../research/opportunities/04-positioning.md#recommendation)).

> **Case against.** An intent picker adds a control to every surface, and a user browsing without intent still needs a single answer; the spot's "best at" default carries that weight and may be wrong for a given user. Explaining a wrong forecast makes the error more visible. Confidence thresholds are a judgement call with no verification study behind them ([A1 risks](../research/opportunities/03-differentiation-options.md#a1--explainable-light-index)).

---

## 2.4 Scope of the first native release

> **Decision 2.4 · What does the first MapKit app ship with?**

> **Option 2.4-A · Plan and field.** The redesigned core (explore, spot, trip builder, sharing) plus the explained Light Index (A1), the backward schedule (B2), light-first ordering as a suggestion (B1), offline trip packs (C2) and the "Tonight" Live Activity (C1).

> **Option 2.4-B · Parity first.** Port the redesigned web prototype to native as is, then add differentiators release by release.

> **Option 2.4-C · Field companion only.** Plan on the web; the native app is Now mode, offline packs and the Live Activity.

> **Recommendation.** A, with weather swap (B3) in the release after, once the confidence model has been tested. The positioning brief makes offline packs plus the Live Activity the native app's first milestone, "the two moments competitors fail in the field" ([positioning, recommendation](../research/opportunities/04-positioning.md#recommendation)). Parity alone would ship an Iter with no reason to switch; a field-only app would leave the planning half, the thing nobody else does, on the web.

> **Case against.** A is large. C2 is "the largest engineering item here" ([C2](../research/opportunities/03-differentiation-options.md#c2--offline-trip-packs)), and B1 is effort L. No MapKit API for third-party offline maps was found (unconfirmed absence), so offline means Iter's own tiles and routing. A smaller first release (B) would reach users sooner and teach more.

---

## 2.5 Business model, in outline

> **Decision 2.5 · What is free, what is paid, and how is it priced?**
> Not needed until the native release, but it shapes design now: the paywall has to be designed as carefully as the product ([pricing, "What this suggests"](../research/competitors/pricing-and-models.md#what-this-suggests-for-iter)).

> **Option 2.5-A · Free core, one paid tier.** Free: discover, score, trips of any size, sharing by link. Paid: things that cost money to run or save real effort, such as threshold alerts, unlimited AI trip generation, exports and later terrain checks. One tier near the $35–60 a year band, plus a lifetime option ([pricing](../research/competitors/pricing-and-models.md#what-this-suggests-for-iter); [opening 7](../research/competitors/gaps-and-openings.md#7-a-free-core-and-a-fair-paywall)).

> **Option 2.5-B · One-time purchase.** About $10, matching PhotoPills ($10.99) and PlanIt Pro ($9.99) ([positioning, the competitive field](../research/opportunities/04-positioning.md#the-competitive-field-in-one-paragraph)). Simple, but it does not pay for forecasts, AI or offline data that cost money every month.

> **Option 2.5-C · Free with stop or trip caps.** The Roadtrippers and PhotoHound shape. The briefs are clear that this is the shape the category punishes ([gaps §4](../research/competitors/gaps-and-openings.md#4-the-ux-failures-common-across-the-category)).

> **Recommendation.** A, with one change to the pricing brief's list: **offline trip packs stay free.** The two research streams disagree here. The pricing brief and opening 7 list offline packs as a paid item ([pricing](../research/competitors/pricing-and-models.md#what-this-suggests-for-iter); [opening 7](../research/competitors/gaps-and-openings.md#7-a-free-core-and-a-fair-paywall)); the differentiation brief says offline is "never paywalled" ([C2](../research/opportunities/03-differentiation-options.md#c2--offline-trip-packs), [E5](../research/opportunities/03-differentiation-options.md#e5--honest-pricing)). I side with free. Offline is table stakes, a reviewer of Wanderlog singles out paywalled offline as "the features you reach for mid trip", and a trip that goes blank on a mountain road is a safety and trust failure, not an upsell moment. Show the price before any trial, show the renewal date, offer one-tap cancel, and never lock a built trip.

> **Case against.** Willingness to pay is the thinnest evidence in the research: "one-time $10 tolerated, subscription trip apps punished" (Inferred, [audience 5.1](../research/opportunities/01-photographers-and-jobs.md#51-the-decision)). Hobbyists take one to four trips a year, so a subscription has to earn its keep between trips. Free offline also gives away the one feature competitors prove people pay for, and its tile and storage costs are not yet known.

---

## 2.6 Data providers licensed for commercial use

> **Decision 2.6 · Which forecast, routing and map sources can Iter launch on?**
> Today two of them cannot be used in a paid product (details below). This does not block design work. It blocks any public launch.

| Job | Today | Problem | Licensed option in the briefs | Status in the briefs |
|---|---|---|---|---|
| Forecast | Open-Meteo free tier (`src/lib/weather.ts:13`) | Non-commercial: the terms count "apps that have subscriptions or display advertisements" as commercial | **WeatherKit** (C4): 500,000 calls a month with the Developer Program, ten-day hourly horizon, cloud by altitude. Requires the Apple Weather mark, a legal link, and, because the Light Index is "value-added", a notice that the data has been modified. Open-Meteo's own commercial plan exists, price not retrieved. Met Norway cloud layers are free with CC BY 4.0 credit | Cloud-by-altitude property names "to verify"; whether a combined request counts once is unverified |
| Routing | OSRM public demo (`src/lib/routing.ts:19`) | "Restricted to reasonable, non-commercial use-cases", one request a second, no uptime guarantee | Natively, `MKDirections` for drive and walk ETAs (B2). For offline, Valhalla (MIT) runs on iOS (C2) | — |
| Map tiles | CARTO Positron via MapLibre, no key | Licence for commercial use and for offline storage not checked | Natively, MapKit. For offline packs, own cached tiles or vector data "with a licence that allows storage (CARTO and OSM terms to check)" | Terms not retrieved. No MapKit offline API for third parties was found (unconfirmed absence) |
| Second-opinion sky score | — | — | Sunsethue API pay-as-you-go allows commercial use (A3) | Long-term terms and attribution not retrieved |
| Place search, photos, AI | Nominatim, Wikipedia and Wikimedia Commons, Cloudflare Workers AI | No brief states their commercial terms | — | **Gap in the research** |

Sources: [where the prototype stands](../research/opportunities/03-differentiation-options.md#where-the-prototype-stands), [C4](../research/opportunities/03-differentiation-options.md#c4--weatherkit-as-data-backbone), [A2](../research/opportunities/03-differentiation-options.md#a2--sun-side-horizon-cloud), [A3](../research/opportunities/03-differentiation-options.md#a3--second-opinion-sky-score-via-sunsethue-api), [B2](../research/opportunities/03-differentiation-options.md#b2--backward-schedule), [C2](../research/opportunities/03-differentiation-options.md#c2--offline-trip-packs), [app map, data at a glance](../flows/00-app-map.md#data-at-a-glance).

> **Option 2.6-A · Apple-native stack.** WeatherKit, MapKit and `MKDirections` in the native app; own tiles and Valhalla only for offline packs. The web prototype stays on its current sources as a non-commercial design tool.

> **Option 2.6-B · Paid open stack.** Open-Meteo's commercial plan, a hosted or self-run OSRM or Valhalla, and a commercial tile provider, so the web and native apps share one data path.

> **Recommendation.** A. It fits the native target, WeatherKit's included calls are generous, and the positioning leans on Apple-only features anyway. Keep the score layer model-agnostic so a second source (A3 Sunsethue, Met Norway) can plug in later ([C4 design notes](../research/opportunities/03-differentiation-options.md#c4--weatherkit-as-data-backbone)). Before launch, close the gap on search, photos and AI terms, which no brief covered.

> **Case against.** If the web app is ever sold or carries a subscription, it needs B anyway, and two data paths can give two different scores for the same sunset. WeatherKit calls multiply with weather swap (B3) and sun-side cloud (A2), and Open-Meteo's commercial price was never retrieved, so the cost comparison is incomplete.
