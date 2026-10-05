# 03 · Differentiation options for Iter

This is a catalogue of ways Iter (code-named Vantage; a road-trip planner for photographers, a web prototype heading to native Mac and iOS on MapKit) could set itself apart. Each option is written so you can accept it, reshape it or reject it. The first audience assumed throughout is the serious hobbyist landscape or travel photographer on a multi-day driving trip, one to four trips a year, often with a non-photographer companion, iPhone-first, paying roughly $10 to $60 for tools.

**How to read the ratings.** Each is 1 to 5. *Value* is how much the first audience needs it. *Distinct* is how few competitors do it well (5 means nobody found). *Feasible* is data, platform and design effort combined (5 means easy). Effort is S, M or L. **Evidence tags:** "Confirmed" means a source was opened and the link is given. "Inferred" means reasoning from the sources, not a fact. Anything marked "unconfirmed" could not be verified. Counts of how often a need came up are small samples, so read them as direction, not proof. Reddit was mostly unreachable during research, so most user voice comes from App Store reviews, Trustpilot, blogs and forums. **Quoted text inside "What it is" and "Design notes" is example UI copy written for this brief, not something a user said.** User quotes always carry a link.

---

## At a glance

| ID | Name | One-line pitch | V/D/F | Effort |
|---|---|---|---|---|
| A1 | Explainable Light Index | Say why a sky is rated as it is, how sure we are, and own up when we only have geometry | 5/4/5 | M |
| A2 | Sun-side horizon cloud | Judge the cloud where the sun will be, not overhead | 4/3/3 | M |
| A3 | Second-opinion sky score | Buy a sunset-quality score from Sunsethue's API instead of building one | 3/2/5 | S |
| A4 | Terrain-aware sun times | "Sun leaves the valley at 6:41", written into the itinerary | 5/3/3 | M |
| A5 | Conditions layer | Fog, aurora, Milky Way and moon, Bortle, smoke as optional layers | 4/2-3/3 | L |
| A6 | Seasonal | Fall colour, bloom, snow line | 3/4/2 | L |
| A7 | Tides | Tide times for coastal spots | 3/2/4 | S |
| B1 | Light-first itinerary | "Plan my days around the light" | 5/5/3 | L |
| B2 | Backward schedule | "Leave 5:31, park 6:02, walk 12 min, set up by 6:12" | 5/4/4 | M |
| B3 | Weather swap (Plan B) | When a session turns grey, offer a better nearby spot or day | 5/5/3 | L |
| B4 | Access facts | Parking, walk-in, 4x4, permits, closures, drone link-out | 4/3/3 | M |
| B5 | Crowd timing | Seasonal crowd prior per spot | 3/3/2 | M |
| B6 | Composition preview | Sun and moon lines, Look Around, 3D terrain on the spot | 4/2/4 | S |
| C1 | "Tonight" Live Activity | A countdown for each session on Lock Screen, Watch, CarPlay Dashboard | 5/4/4 | M |
| C2 | Offline trip packs | The whole trip works with no signal, never paywalled | 5/3/3 | L |
| C3 | Photos-library memory | "You shot here in 2023", learned on-device | 4/5/4 | M |
| C4 | WeatherKit backbone | Replace non-commercial Open-Meteo (enabler) | 4/1/5 | S |
| C5 | On-device AI | Private scout summaries and why-text | 3/3/4 | M |
| C6 | Real collaboration | CloudKit sharing, App Clip invite, companion view | 4/3/3 | L |
| C7 | Widgets, Watch, Siri | Glance and ask without opening the app | 3/2/4 | M |
| C8 | AR sun path | Set aside, see section 5 | 3/1/3 | M |
| D1 | Private-by-default spots | Sensitive flag that shares only an area | 3/4/5 | S |
| D2 | Verified, dated spot facts | "Last checked" and contributor credit | 4/3/2 | L |
| D3 | Photographer-authored guides | Clone an expert's trip into yours | 4/4/3 | L |
| D4 | Companion mode | A view for the non-photographer | 3/5/4 | S |
| E1 | "Now" field mode | One screen with only the next three hours | 5/4/4 | M |
| E2 | Answer-first design | Lead with the decision, details on demand | 5/4/4 | M |
| E3 | Night mode | Red, dim UI for pre-dawn and astro | 4/3/5 | S |
| E4 | One-handed, glove-friendly controls | Big targets, compass caveats | 3/2/5 | S |
| E5 | Honest pricing | No stop caps, offline never paywalled | 4/3/5 | S |

### Strongest eight

In priority order. D1 follows as a stance rather than a feature.

1. **B1 Light-first itinerary.** No product found combines an itinerary with light windows, and it is the promise the name implies.
2. **B3 Weather swap.** Several working photographers advise keeping a Plan A and a Plan B (Kelby, Mezeul, Chesebrough; see [02](02-unmet-needs.md)), and none of the sources describes a tool that proposes one.
3. **A1 Explainable Light Index.** Cheap to ship on the rules already in the code, and it answers the loudest forecast complaint: no reason given.
4. **E1 + E2 Now mode and answer-first design (one bet).** Together they answer the complexity complaint that came up most often (six sources) and a direct user request for a three-hour view.
5. **C1 "Tonight" Live Activity.** It brings the plan to the Lock Screen, Watch and CarPlay Dashboard without a CarPlay entitlement.
6. **C2 Offline trip packs.** Offline fails at the worst moment, and we found no MapKit API that lets third-party apps download maps (unconfirmed absence; Apple Maps itself has offline maps).
7. **A4 Terrain-aware sun times.** The best single user story in the research is a hill that cost 15 minutes of sun.
8. **C3 Photos-library memory.** Nobody found does it, it is private by design, and it makes the app feel personal.
9. **D1 (stance).** Private by default fits the ethics debate and the open map platforms do not offer it.

---

## Where the prototype stands

Blunt, so the options below land on the right starting point.

- **The Light Index is hand-tuned rules on overhead cloud at the spot.** It has no sun-side horizon cloud, no terrain horizon and no confidence value. Beyond seven days every window gets a flat 58 "geometry only" (`src/lib/light.ts:53`). A failed forecast does the same, so a broken request looks like a real "Good" rating (brief 05, "When the forecast fails").
- **The "light-first" promise is mostly invisible.** Session chips are optional, and arrive-by hints and warnings fire only when both stops have a chip (`src/pages/TripBuilder.tsx:286-306`, brief 07). Warnings compare absolute times, so across days they effectively never fire.
- **There is no offline at all.** Data lives in localStorage or in-memory caches, and the app map lists "No global offline or API-failure indicator" as a missing state (`00-app-map.md`, Tweak points). Sun and moon maths run locally, but the map, routing, forecast and photos need a connection.
- **Launch blocker: Open-Meteo.** The free tier is non-commercial; the terms count "Operating websites or apps that have subscriptions or display advertisements" as commercial ([terms](https://open-meteo.com/en/terms)). The forecast call is at `src/lib/weather.ts:13`.
- **Launch blocker: OSRM.** The public demo is "restricted to reasonable, non-commercial use-cases", one request per second, no uptime guarantee ([OSRM wiki](https://github.com/Project-OSRM/osrm-backend/wiki/Demo-server)). It is called from `src/lib/routing.ts:19`, with a straight-line fallback at 80 km/h that the footnote describes inaccurately.
- **Two licence traps ahead.** If WeatherKit replaces Open-Meteo, Iter's Light Index counts as a "value-added" product, which requires attributing the data to "Weather" with "a notice that the data provided by Apple has been modified" ([WeatherKit](https://developer.apple.com/weatherkit/get-started/)). If a Bortle layer is built later, the Falchi atlas is CC BY-NC 4.0 and must not ship in a paid app ([record](https://b2find.eudat.eu/dataset/df8cd562-df6a-51bf-ad64-7421cf8c8623)).
- **Spots are fragile and public by default.** Custom spots cannot be edited or deleted, there is no private or sensitive notion, and a shared trip is the only sharing.
- **No accounts.** Identity is a random id plus a display name in localStorage; trip sync to Cloudflare KV is last-write-wins, with a 90-day TTL (`worker/trips.ts:38`, `src/lib/sync.ts`).

What already works and is worth keeping: local sun, moon and light-window maths (brief 05), a seven-day date strip, a per-stop session with a "Be set up by" time, drive-time chips between stops, shareable trips, and an AI scout on Explore.

---

# A · Light and sky

### A1 · Explainable Light Index

**What it is.** Under the score ring, the card says in plain words what helps and what hurts, per layer: "Thin high cloud at 40% will catch colour. Low cloud on the sun side is 10%, so the horizon should stay open." A confidence chip drops with lead time ("Forecast 6 days out: treat as a guess") and the card says so honestly when only geometry is available, instead of showing a calm "Good". After the trip, a one-tap "How did it go?" lets the user rate the light, which later calibrates the rules.

**The need behind it.** Forecast distrust and missing reasons came up in four sources. An Alpenglow reviewer says [it "doesn't tell you why they will be poor, fair, good"](https://justuseapp.com/en/app/978589174/alpenglow-sunset-forecasts/reviews); another says [it "simply isn't at all accurate"](https://justuseapp.com/en/app/978589174/alpenglow-sunset-forecasts/reviews) and describes a ["20-30% predictor"](https://justuseapp.com/en/app/978589174/alpenglow-sunset-forecasts/reviews) that misses. A blogger who tested Skyfire found it [accurate "just over 50% of the time"](https://www.jmpeltier.com/review-skyfire-sunsetwx-predicting-sunrise-sunset/) and objected to a bare percentage: ["what kind of rain? And how much?"](https://www.jmpeltier.com/review-skyfire-sunsetwx-predicting-sunrise-sunset/). That is one blogger's subjective test, so it is directional only.

**Why it's distinctive.** [Sunsethue](https://sunsethue.com) shows a 0-100% score plus an uncertainty metric, up to three days ahead (confirmed on its site), but a score is not a reason. [Alpenglow](https://apps.apple.com/us/app/alpenglow-sunset-forecasts/id978589174) offers quality forecasts to four days on Pro with threshold notifications; reviewers say it does not explain itself. Iter already stores a reason string per window (brief 05), so explanation is a presentation change on top of existing logic. The check-in loop is not seen anywhere in the research (unconfirmed absence).

**What it takes.** No new data. Surface the existing reason strings by layer, add a lead-time confidence rule (for example full confidence inside 48 hours, falling to "geometry only" past the forecast horizon), and one stored rating per past session. Design effort is the main cost: a confidence chip, an honest empty state, and a two-tap check-in. Calibration needs many ratings before it means anything.

**Risks.**
- Explaining a wrong forecast makes the error more visible. The honest state has to feel calm, not apologetic.
- A check-in with few responses calibrates nothing; treat it as a trust ritual first, a data source later.
- Confidence thresholds are a judgment call without a verification study to anchor them (none was found).

**Rating.** Value 5/5 · Distinct 4/5 · Feasible 5/5 · Effort M

**Design notes.**
- Lead with one sentence ("Evening gold looks strong, fairly sure"), put layers behind a tap.
- Replace the neutral 58 with a visibly different "No forecast" state (dashed ring, no colour band); do not let it share a colour with real scores.
- Show forecast age ("updated 2 h ago") wherever a score appears.

### A2 · Sun-side horizon cloud

**What it is.** Instead of one reading of cloud over the spot, the app samples low cloud along the direction of the sun, say 20 to 200 km out, and says "A bank of low cloud 80 km west may block the last 10 minutes of sun." The ring still shows one score; the reason text names the sun-side gap.

**The need behind it.** The sunset factors in the research are consistent: high thin cloud lights up as a screen and thick low cloud blocks the horizon ([PSU on SunsetWx](https://www.psu.edu/news/academics/story/sunrise-sunset-forecasting-tool-sunsetwx-partners-weather-channel)). Iter's current rule (20-65% mid and high, little low) matches that but reads only overhead cloud. Moving to the sun side is an inference from the sources, not something a user asked for in those words.

**Why it's distinctive.** Sunsethue describes a "ray-based model" and says colour depends on whether the sun can [reflect off the clouds](https://sunsethue.com/guide). [Viewfindr](https://www.viewfindr.net/) says its "Burning red sky" forecast is "Based on 3D cloud, rain and sun position". So competitors claim it; Iter's difference would be showing it on the itinerary, not the method itself. Method quality of either competitor is unverified.

**What it takes.** Several forecast points per window along the sun azimuth, from Open-Meteo (low, mid, high cover; commercial plan needed, price not retrieved) or [WeatherKit](https://developer.apple.com/weatherkit/get-started/) (500,000 calls a month included; whether one request for several datasets counts as one call is unverified). Met Norway offers free low, medium and high fractions with CC BY 4.0 credit ([terms](https://api.met.no/doc/TermsOfService)). Call volume grows five to ten times per window per stop, so cache by grid cell.

**Risks.**
- No verification study exists, and the one test found shows about 50% hit rate for existing tools. More geometry does not fix weather-model error.
- Call volume and cost on a paid weather plan.
- Over-precise claims ("blocked at 7:42") the data cannot back.

**Rating.** Value 4/5 · Distinct 3/5 · Feasible 3/5 · Effort M

**Design notes.**
- Show it as a small strip along the sun direction (open, patchy, blocked), not a number.
- Fall back silently to overhead cloud when the sun-side data is missing, but say which was used.

### A3 · Second-opinion sky score via Sunsethue API

**What it is.** Beside Iter's own score, a small "Sunsethue says 72%" line, or a blended score, for sunrise and sunset windows. Buy the sunset-quality model instead of building it.

**The need behind it.** Same as A1 and A2: the user wants a sunset forecast they can trust, and two independent views are more convincing than one.

**Why it's distinctive.** It is not; any competitor could license the same API. The value is speed to a credible sky score and a cheap sanity check on Iter's rules. The only documented sunset-quality API with commercial terms found is [Sunsethue's](https://sunsethue.com/dev-api).

**What it takes.** Free tier: 1,000 credits a day, "No commercial use". Pay as you go: "€1 per 10,000 credits (~2,000 sunsets)", 30,000 free credits a month, "Commercial use allowed", updates every six hours, cacheable per grid cell. That works out to about five credits per sunset (Inferred), so a ten-stop trip is cheap. Small Worker proxy and a cache; no Apple-side work.

**Risks.**
- Dependency on one indie vendor; availability and long-term terms unconfirmed.
- Two scores that disagree confuse users unless one is clearly primary.
- Attribution requirements were not retrieved.

**Rating.** Value 3/5 · Distinct 2/5 · Feasible 5/5 · Effort S

**Design notes.**
- Show it only when the two sources disagree by a lot, with a plain "Sources differ" line.
- Keep Iter's score primary so there is one answer on the card.

### A4 · Terrain-aware sun times

**What it is.** The stop card and schedule use the real horizon. Instead of "Sunrise 6:47" it says "Sun clears the eastern ridge at 7:12, 25 min after listed sunrise", and instead of "Sunset 7:41" it says "Sun drops behind the western ridge at 6:56, 45 min before listed sunset". Light windows and "Be set up by" times shift to match.

**The need behind it.** This is the strongest single story in the research. A TPE reviewer wrote that [they drove to a sunset spot "only to find the sun was setting behind a hill, 15 minutes earlier than I expected"](https://apps.apple.com/us/app/the-photographers-ephemeris/id366195670) and has used the app "religiously" since. Another reviewer praised seeing the sun against the ["elevation and 'Flow' of the land"](https://apps.apple.com/us/app/the-photographers-ephemeris/id366195670). One source, but vivid; frequency is low.

**Why it's distinctive.** [The Photographer's Ephemeris](https://www.photoephemeris.com/en/) ships TPE 3D with realistic directional light and shadows, and PlanIt has a photorealistic VR viewfinder (both confirmed). Neither is shown to carry terrain-adjusted times into a multi-day itinerary. Iter's difference is the number appearing in the trip plan, not a separate 3D view. That absence is based on thin evidence.

**What it takes.** An elevation model: [Copernicus GLO-30](https://registry.opendata.aws/copernicus-dem/) (free with an attribution string; it is a surface model, so trees and buildings are included), SRTM 1 arc-second (public domain), USGS 3DEP for the US (free, no use restrictions) or AWS Terrain Tiles. Method (Inferred): ray-march the DEM along each azimuth to get a horizon-angle profile, then delay sunrise or sunset until the sun clears it. Precompute a small horizon profile per curated spot; this also makes the feature work offline (see C2). Custom pins can be computed on a server on first use.

**Risks.**
- Surface-model horizons count trees as ridges. Present times as approximate ("about").
- 30 m data misses nearby small obstacles, and users shoot from specific spots on a slope.
- If it looks like TPE 3D, the story becomes "me too". Keep it to times, not a 3D scene.

**Rating.** Value 5/5 · Distinct 3/5 · Feasible 3/5 · Effort M

**Design notes.**
- Show the delta, not just the new time: "6:41 (listed sunset 6:56)" in the same row.
- Let the user override a spot's horizon ("trees block it") and remember it.

### A5 · Conditions layer

**What it is.** Optional layers that appear only when relevant to a stop: fog or a cloud-sea inversion ("valley fog likely at dawn"), aurora ("Kp 5 tonight, but 80% cloud"), Milky Way core and moon ("core rises after moonset at 1:10"), a Bortle class, and smoke or haze. Each is a single chip on the stop card.

**The need behind it.** Strongest for the astro-curious expansion audience. [Eric Brown, maker of MilkyWayPlanner.com (he sells a tool)](https://ericbrown.com/milky-way-planning/), writes: "I'd check the moon phase, pick a date that looked good, drive an hour or two to a dark location, and then watch clouds roll in." The same author notes ["Multi-night photography trips add complexity. You need to know conditions at multiple locations across multiple dates."](https://ericbrown.com/milkyway-planner-night-sky-photography-planning-tool/) Moon, cloud and dark site co-planning appeared in five sources. A tour operator says [fog and visibility radars "can mean the difference between wasting your time and making the most of your shoot"](https://iceland-photo-tours.com/articles/landscape-and-nature-photography/how-to-plan-for-a-successful-landscape-photography-shoot).

**Why it's distinctive.** Many tools cover single layers: Clear Outside (hourly cloud layers, Bortle), Astrospheric (cloud, smoke, aurora), PlanIt Live (aurora, tides), Viewfindr (fog layer height; confirmed on its site). None are shown combining them with a drive itinerary. Distinctness depends on which layers: fog and Milky Way are contested, whereas a trip-level combination is not.

**What it takes.** Pick layers one at a time. Fog: Met Norway `fog_area_fraction` and dew point, free with CC BY 4.0 credit; inversion detection would compare pressure-level temperatures (no validated method found, all heuristics Inferred). Aurora: NOAA SWPC OVATION and Kp JSON, free ([SWPC](https://www.spaceweather.gov/content/data-access)). Milky Way and moon: [Astronomy Engine](https://github.com/cosinekitty/astronomy) (MIT) and SunCalc (BSD-2, already used). Bortle: build from NASA Black Marble VIIRS radiance, not Falchi (CC BY-NC); radiance is not sky brightness, so accuracy needs its own model. Smoke: Open-Meteo air quality (aerosol optical depth, CAMS credit). The smoke "sweet spot" for good colour is not quantified in anything retrieved.

**Risks.**
- Scope creep into an astro app; this competes with PhotoPills where it is strongest.
- Unvalidated heuristics for fog and smoke produce confident wrong answers.
- Open-Meteo layers inherit the commercial-licence issue.

**Rating.** Value 4/5 · Distinct 2-3/5 · Feasible 3/5 · Effort L

**Design notes.**
- Chips appear only when they would change a decision; nothing on a quiet day.
- Ship Milky Way plus moon first: pure maths, no data licence, and the clearest user story.

### A6 · Seasonal: fall colour, bloom, snow line

**What it is.** A spot card says "Peak colour usually early Oct; this year looks 5 days late" or "Snow line near 1,800 m this week". A trip builder note warns "Poppies usually peak in late March".

**The need behind it.** Demand evidence here is indirect. The research found crowd damage at bloom events ([Walker Canyon in 2019, snippet only](https://www.cbsnews.com/amp/losangeles/news/officials-prepare-for-super-bloom-chaos-in-lake-elsinore)) but no user asking for a bloom forecast. Treat the need as plausible, unconfirmed.

**Why it's distinctive.** No product confirmed doing this for photographers. The data is the problem, which is also why it is distinctive.

**What it takes.** Data is weak. SmokyMountains.com sells foliage map data only on request. USA-NPN Spring Index is free but covers spring onset in the contiguous US, not autumn colour. NOHRSC SNODAS gives US snow depth, free with a required citation, but needs server-side raster processing. The USDA Forest Service page has no feed. State foliage and wildflower feeds were not researched. A cheap start (Inferred): editorial "best months" per curated spot.

**Risks.**
- Confident dates that are wrong damage trust more than no date.
- Regional only; likely US-first.
- Feeds and licences unverified.

**Rating.** Value 3/5 · Distinct 4/5 · Feasible 2/5 · Effort L

**Design notes.**
- Label editorial month ranges as "typical", not a forecast.
- Let users add their own "peaked on" note after a visit; it builds local knowledge over time.

### A7 · Tides

**What it is.** For coastal spots the stop card adds "Low tide 6:12, pools exposed until 7:30" and warns if the shoot window falls at high water.

**The need behind it.** One road-trip guide says [to "Check tide tables if you are going to be shooting along the coast"](https://fstoppers.com/originals/photographers-ultimate-road-trip-guide-333953). Tides appear in two sources of about twenty, so this is a minor need for most users and a big one for coast-heavy trips.

**Why it's distinctive.** [PlanIt](https://planitphoto.com) lists tides (confirmed). Low distinctness; included for completeness.

**What it takes.** [NOAA CO-OPS](https://api.tidesandcurrents.noaa.gov/api/prod/) is free for US coasts (key requirement not verified). [WorldTides](https://www.worldtides.info/developer) covers 8,000+ locations globally from $4.99 a month, with caching limited to the requesting user. UK Admiralty: the free Discovery tier prohibits caching, and Foundation costs GBP 120 a year ex VAT (snippet only). Stormglass's free tier is non-commercial.

**Risks.**
- Station to spot mismatch; the nearest station may be a bay away.
- Per-user caching limits fight offline packs (C2).

**Rating.** Value 3/5 · Distinct 2/5 · Feasible 4/5 · Effort S

**Design notes.**
- Show tide only on spots tagged coastal, never as a global panel.
- Say which station it comes from.

---

# B · Planning

### B1 · Light-first itinerary

**What it is.** The user adds spots and sessions ("Mesa Arch, sunrise" and "Delicate Arch, sunset") and taps "Plan my days around the light." Iter proposes an order and timing that fits each session's light window plus drive time, shows two alternatives, and explains the trade ("Day 2: moved Delicate Arch to sunset because the road is 2 h 10 m and sunrise is the only dawn window left"). Sessions become time windows the plan has to respect.

**The need behind it.** Photographers describe doing this by hand. A road-trip guide puts the failure and the manual fix in two sentences: ["I've been that guy in his car freaking out as I watch the sunset explode and I'm stuck on a highway. Start with the locations you want to photograph, now that you know when the light is best for each plan your route for the maximum efficiency."](https://fstoppers.com/originals/photographers-ultimate-road-trip-guide-333953) One writer called seeing everything on one map ["a huge breakthrough and sigh of relief"](https://fstoppers.com/originals/one-best-tools-use-when-planning-your-next-photography-trip-246448) after struggling with ["wrapping my head around where everything was"](https://fstoppers.com/originals/one-best-tools-use-when-planning-your-next-photography-trip-246448). Juggling several apps for where, when and weather came up in four sources, and the planning-around-companions constraint in two ([PictureCorrect](https://www.picturecorrect.com/landscape-photography-trip-planning-tips/): "The challenge is to maintain a balance between family and photography.").

**Why it's distinctive.** [Roadtrippers](https://www.roadtrippers.com), [Wanderlog](https://wanderlog.com) and [Furkot](https://trips.furkot.com/) route multi-stop trips with drive times; none confirmed light windows. [Locationscout](https://apps.apple.com/us/app/locationscout-photo-spots/id1474484447) has "Along Route" ("Just enter your start and destination to instantly discover the best spots along your journey") and crowd and sun info, but it finds spots, it does not schedule them. No competitor found does this; absence rests on thin evidence.

**What it takes.** A time matrix per day from a routing engine, then a solver with time windows. [VROOM](https://github.com/VROOM-Project/vroom) is BSD-2-Clause, does time windows and service durations, and works with OSRM, Openrouteservice or Valhalla matrices. A photographer day has three to ten stops, so a hand-written insertion plus 2-opt heuristic in Swift is likely enough on-device (Inferred). Apple `MKDirections` gives ETAs but no multi-stop optimisation and throttles per device. OR-Tools shows no iOS or WASM support. Replace the OSRM demo before launch. Design work is substantial: the proposal UI, locks, and explanations.

**Risks.**
- Plans that churn with each forecast refresh. Mitigation: plan with geometry, re-plan with weather only inside about 72 hours.
- It is hard to show in a screenshot.
- Optimising against a forecast that is right roughly half the time can mislead.

**Rating.** Value 5/5 · Distinct 5/5 · Feasible 3/5 · Effort L

**Design notes.**
- Propose, never rewrite: a preview diff the user accepts, with a one-tap undo (the prototype has none today).
- Pinned stops and "must be here at sunrise" stay locked; the planner moves everything else.
- Make session chips default-on so the planner has the inputs it needs.

### B2 · Backward schedule

**What it is.** Each session expands into a countdown the user can follow: "Leave hotel 5:31 → park 6:02 → walk 12 min → set up by 6:12 → sun clears ridge 6:41." The user can set an alarm for the leave time and edit the walk-in time, which is remembered for that spot.

**The need behind it.** The prototype already computes a "Be set up by" time (sunrise and sunset anchored 45 minutes before the window end; golden morning and blue hour 15 minutes before the start; night 30 minutes; `tripUtils.ts:98-104`). What is missing is the walk. Photographers weigh access first: [Mezeul asks "How close will the road take me to this area I'm interested in and then how far of a hike?"](https://www.naturettl.com/?p=19400), and a Reddit post on [Marlboro Point](https://www.reddit.com/r/landscapephotography/comments/1mjkn58/) says it needs a 4x4 or about a three-mile hike from the nearest paved road. Early starts are a recurring friction, but the sources hold no direct request for a leave-time alarm.

**Why it's distinctive.** No competitor found offers a backward schedule. Flighty-style countdown thinking (Apple praised it for "a beautifully designed app experience") is the model. PhotoPills and TPE answer when the light is, not when to leave.

**What it takes.** Drive time from `MKDirections` (iOS 7+; traffic-aware ETA), walk-in time from MapKit walking directions or user entry, parking from OSM or user notes. Alarm via time-sensitive notifications (iOS 15+; user can disable; entitlement need not verified). A "Leave by" value feeds C1 directly.

**Risks.**
- False precision on trail walks; estimates often miss slope and gear.
- A missed alarm costs the sunrise; alarms need a clear opt-in and fallback.

**Rating.** Value 5/5 · Distinct 4/5 · Feasible 4/5 · Effort M

**Design notes.**
- Write times as a short vertical list with the one decision on top: "Leave 5:31."
- Add a buffer slider (5, 10 or 15 minutes) so users tune their own caution.

### B3 · Weather swap (Plan B)

**What it is.** When a session's score drops, a card appears on the trip: "Tomorrow's sunrise at Delicate Arch looks grey (low cloud 85%). Mesa Arch, 40 min away, looks clearer. Swap, or swap days?" Accepting rewrites the day; declining dismisses it for that session.

**The need behind it.** The most repeated planning advice in the research is a Plan B. Chesebrough: ["No matter how good your plan, always be prepared to throw it out the window."](https://www.digitalphotomentor.com/?p=73913) Mezeul: ["I recommend having a Plan A and B."](https://www.naturettl.com/?p=19400) A Reddit post says ["don't fix your route"](https://www.reddit.com/r/landscapephotography/comments/1jvx37y/) because booking hotels in advance leaves you stuck in bad light or rain. A forum user writes ["No point diving miles for grey skies"](https://www.talkphotography.co.uk/threads/sunset-sunrise-tracking.662410/). An elopement photographer says [more than half of her shoots "don't go to plan"](https://rangefinderonline.com/wedding-portrait/weddings/what-does-it-really-take-to-photograph-adventure-elopements/). Plan B appeared in five or more sources, always as manual advice; no source described a tool that does it.

**Why it's distinctive.** No confirmed precedent for automatic weather-driven alternate-spot suggestions was found (absence of evidence only). This is also the feature most likely to feel magic or annoying.

**What it takes.** The ingredients exist: a spot catalogue with `bestLight`, per-spot forecasts, and the score. Method (Inferred): when a session scores under a threshold inside the confident forecast range, search spots within a drive-time radius with a better score for the same window, then check that the swap does not break the next leg. Needs forecast data for many spots (call volume, see C4) and a dense catalogue; PhotoHound reviewers already complain of thin coverage outside tourist areas ([PhotoHound reviews](https://apps.apple.com/us/app/id1539761940)).

**Risks.**
- Alerts that cry wolf; with a roughly 50% hit rate on sunset forecasts, noisy swaps would train users to ignore it.
- Thin catalogues produce no alternatives, and an empty Plan B feels broken.
- Hidden gems recommended to strangers collide with D1.

**Rating.** Value 5/5 · Distinct 5/5 · Feasible 3/5 · Effort L

**Design notes.**
- Appear at one moment only (the evening before, and again at wake-up), as a single calm card, not a notification storm.
- Show the evidence in one line ("Cloud 85% vs 25%") and a map of the move.
- Never auto-apply. Always keep the original reachable with one tap.

### B4 · Access facts

**What it is.** Each spot shows what decides whether you can get there: parking, walk-in distance, 4x4, timed entry or permits, current closures, and for drones a link-out to the right authority ("Drones: not allowed in national parks. Check B4UFLY partners").

**The need behind it.** Julian Elliott advises to ["Consider potential obstacles like roadworks or limited parking."](https://www.julianelliottphotography.com/blog/7-tips-to-plan-a-landscape-and-travel-photography-trip/) Elopement photographers report that ["Early- or late-season snowfalls unexpectedly close roads all the time. Floods and forest fires close national parks without warning."](https://rangefinderonline.com/wedding-portrait/weddings/what-does-it-really-take-to-photograph-adventure-elopements/) Drone pilots repeatedly say a green airspace result says nothing about park rules (six or more threads and explainers; see [02](02-unmet-needs.md), need 10). No review text about spot access in photo-spot apps was found, so demand is partly Inferred.

**Why it's distinctive.** Locationscout reportedly carries parking markers (search snippet, unconfirmed); [PhotoHound](https://www.photohound.co) spot pages carry accessibility and difficulty fields. No planner confirmed combining permits and closures with a light itinerary.

**What it takes.** [Recreation.gov RIDB](https://www.recreation.gov/use-our-data) (free, credit encouraged), the [NPS Data API](https://www.nps.gov/subjects/developer/guides.htm) (free key, 1,000 requests an hour, includes alerts), InciWeb for fires (API terms unconfirmed). OSM via Overpass for parking and paths: the public instance bars commercial use, and ODbL share-alike may apply to a merged database (legal advice needed). NPS policy memorandum 14-05 has superintendents "prohibit the launching, landing, or operation of unmanned aircraft" ([NPS](https://www.nps.gov/articles/unmanned-aircraft-in-the-national-parks.htm)). Cache alerts in KV.

**Risks.**
- Stale data presented as fact is worse than none; show "last checked".
- Closure and permit scope is large; start with the US national parks.
- Drone rules are a legal liability if Iter states them (see section 5): link out, never assert.

**Rating.** Value 4/5 · Distinct 3/5 · Feasible 3/5 · Effort M

**Design notes.**
- Put one status line on the stop card ("Timed entry required, 2 alerts") and the detail one tap away.
- Color only for problems; "no known issues" stays quiet and says when it was checked.

### B5 · Crowd timing

**What it is.** A spot shows a crowd note: "Busiest Jun to Aug, expect 100+ at sunrise; quieter on weekdays." It informs the itinerary but does not predict live numbers.

**The need behind it.** PetaPixel reported that by 7am [over 200 people were there "taking photos or watching the sunrise, walking into framed shots"](https://petapixel.com/2017/09/15/photographers-ruining-photography-photographers/). Adorama says [popular spots "often have big crowds"](https://www.adorama.com/alc/best-digital-tools-for-scouting-locations/). Four sources raise crowding or geotag spoilage, but none asks for a crowd forecast; evidence of demand is indirect.

**Why it's distinctive.** Locationscout's App Store text lists "crowd levels, best visiting times, and sunrise/sunset info" and a per-spot crowd factor (confirmed). Iter would need a different angle, such as tying crowds to the chosen session and day.

**What it takes.** NPS monthly visitation for 406 units, free; [BestTime](https://besttime.app/) is the only legitimate hourly foot-traffic API found, from $29 minimum with venue-based pricing, and it fits venues, not trailheads. Google has no confirmed popular-times API. A user-reported "how busy was it?" in the post-session check-in (A1) is the cheapest honest source.

**Risks.**
- Weak data for remote trailheads.
- Publishing crowd numbers can send people to quiet places; coordinate with D1.

**Rating.** Value 3/5 · Distinct 3/5 · Feasible 2/5 · Effort M

**Design notes.**
- Express as a range and a season, not a live count.
- Show only on spots where the data exists; blank otherwise.

### B6 · Composition preview

**What it is.** On the spot page, sun and moon rise and set lines on the map, an optional Look Around preview from the pullout, and a realistic-elevation 3D view that shows where the sun will come up relative to the ridge.

**The need behind it.** Table stakes. A PlanIt reviewer wrote ["went to the spot and was spot on. Confirmed point with phone's compass."](https://apps.apple.com/us/app/id898876435) The prototype already draws a sky arc with a "Your frame" wedge (brief 05).

**Why it's distinctive.** Barely. [PhotoPills](https://apps.apple.com/us/app/photopills/id596026805), TPE, Sun Surveyor and PeakFinder all have AR or map overlays, and Locationscout has sun and moon direction lines with a toggle. The point is to match the standard, not to lead.

**What it takes.** MapKit: `MapStyle.imagery(elevation: .realistic)` (iOS 17, macOS 14), Look Around via `MKLookAroundSceneRequest` (iOS 16, macOS 13; coverage not confirmed, so handle nil). No cost found.

**Risks.**
- Look Around gaps in remote areas, where the app matters most.
- Feature parity work that does not move the first audience's decision.

**Rating.** Value 4/5 · Distinct 2/5 · Feasible 4/5 · Effort S

**Design notes.**
- Keep it behind one tap on the spot page; do not put it on the trip screen.
- Reuse the same sun-direction line in A4 so terrain times and the picture agree.

---

# C · Apple platform

### C1 · "Tonight" Live Activity

**What it is.** A Live Activity scheduled for each session. On the Lock Screen and in the Dynamic Island: "Sunset at Mesa Arch · leave in 42 min · set up by 6:12 · Great". The same activity reaches the Apple Watch Smart Stack, CarPlay Dashboard and the Mac menu bar with no extra work.

**The need behind it.** Early starts and tight windows are the job, and the TPE reviewer's "Dummy mode: only display what can be used in the 3 hours" request ([TPE reviews](https://apps.apple.com/us/app/the-photographers-ephemeris/id366195670)) is the same need. A countdown glance is easier than opening an app with gloves on. No reviewer asked for a Live Activity by name.

**Why it's distinctive.** Alpenglow has threshold notifications, interactive widgets and Watch complications ([App Store](https://apps.apple.com/us/app/alpenglow-sunset-forecasts/id978589174)); PhotoPills has widgets. No photography planner was confirmed using Live Activities, which Apple highlighted when it praised Flighty's integration of them ([Apple Newsroom 2023](https://www.apple.com/newsroom/2023/06/apple-announces-winners-of-the-2023-apple-design-awards/)). Absence is unconfirmed.

**What it takes.** [ActivityKit](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities): active up to eight hours, 4 KB payload, and the activity "can't access the network or receive location updates", so updates come from the app or push. Schedule with `startDate`. WWDC26 session 223 says activities appear on Lock Screen, Dynamic Island (new landscape style in iOS 27), StandBy, Watch Smart Stack, macOS menu bar and CarPlay Dashboard ([session](https://developer.apple.com/videos/play/wwdc2026/223/)). CarPlay supports Live Activities and widgets from any app ([session 212](https://developer.apple.com/videos/play/wwdc2026/212/)), so no CarPlay entitlement is needed. Push updates need the Push Notifications capability and a Worker to send them. Needs a "leave by" value from B2.

**Risks.**
- Stale content if the forecast changes and no push arrives.
- Limits on simultaneous activities; plan for one at a time.
- iOS only: nothing for the web prototype.

**Rating.** Value 5/5 · Distinct 4/5 · Feasible 4/5 · Effort M

**Design notes.**
- One verb and one time: "Leave 5:31" is the headline, the score a small chip.
- Dim and high contrast for pre-dawn; no animation that draws attention in the dark.

### C2 · Offline trip packs

**What it is.** "Download this trip" fetches everything the trip needs: map area, route legs, precomputed light windows and horizon profiles for each stop and day, access notes, and the last forecast snapshot with its age ("forecast from 6 pm Tue"). Offline is never paywalled.

**The need behind it.** Offline came up in five sources. Martin writes that he would ["load up a route on hotel Wi-Fi, get halfway to my next destination, and discover the preloaded route vanished"](https://fstoppers.com/apps/ten-essential-travel-apps-nomadic-photographers-236282); a reader added ["If your signal is bad google maps is useless"](https://fstoppers.com/apps/ten-essential-travel-apps-nomadic-photographers-236282). A review of Wanderlog says offline sits behind Pro, [and those are "the features you reach for mid trip"](https://www.endlesstravelplans.com/guides/planning-tools/wanderlog-review). A Roadtrippers reviewer: ["you can't see where you are on the map or points of interest without data service"](https://justuseapp.com/en/app/944060491/roadtrippers-trip-planner/reviews). TPE 3D needs data for elevation ([Peltier](https://www.jmpeltier.com/five-essential-outdoor-photo-apps/)).

**Why it's distinctive.** [PlanIt Pro](https://apps.apple.com/us/app/planit-pro-photo-planner/id898876435) works fully offline if you preload elevation and mbtiles, [PeakFinder](https://www.peakfinder.com/mobile) is fully offline, Wanderlog and Roadtrippers offer it on paid tiers. A trip pack that includes the light plan, not just the map, is not seen in the research. The offline gating by price is the opening.

**What it takes.** Apple provides no MapKit offline API for third parties that was found (consumer Apple Maps offline from iOS 17 only; absence of an API is unconfirmed). So: your own cached tiles or vector data with a licence that allows storage (CARTO and OSM terms to check), offline routing (Valhalla is MIT and runs on iOS), cached horizon profiles from A4, and a forecast snapshot with an age stamp. Storage budgeting, update rules and expiry. This is the largest engineering item here.

**Risks.**
- Tile licence and storage size across a multi-state trip.
- Stale snapshots shown as current; the age stamp has to be unmissable.
- A new baseline expectation: users will ask why live weather fails offline.

**Rating.** Value 5/5 · Distinct 3/5 · Feasible 3/5 · Effort L

**Design notes.**
- Show a single "Ready offline · 340 MB · updated Tue 6 pm" state per trip.
- Make everything degrade visibly: a quiet "Offline" tag, not an error.

### C3 · Photos-library memory

**What it is.** With permission, Iter reads the location and date of the user's own photos, on-device. A spot page then says "You shot here in 2023, mostly at 7 am" and the trip builder can suggest "You haven't been to X yet." The user can also import camera-card photos to cover shots a phone never took.

**The need behind it.** Photographers want to remember where a picture was taken. Martin notes ["My Canon 5D Mark III doesn't have onboard geotagging"](https://fstoppers.com/apps/ten-essential-travel-apps-nomadic-photographers-236282) and recommends GeotagPhotos. Locationscout's App Store text offers manual "Mark spots as visited… Filter by visited" (confirmed). A Locationscout reviewer wrote: ["I've shown my pictures and everyone wants to know where they are and how I found them."](https://apps.apple.com/us/app/id1474484447) Demand is a hypothesis built on weak evidence.

**Why it's distinctive.** Nothing confirmed does this; the nearest is Locationscout's manual "visited" flag. It is also private by design, which supports the "private atlas" stance (D1).

**What it takes.** PhotoKit `PHAsset.location` and `creationDate` (iOS 8+), limited-library mode (iOS 14+, handle `presentLimitedLibraryPicker`), and ImageIO for camera EXIF GPS (`kCGImagePropertyGPSDictionary`). Photos permission. No server and no licence cost. Many photographers strip geotags or shoot on cameras, so phone Photos sees only part of their history (Inferred).

**Risks.**
- Permission fatigue; ask late and explain plainly.
- Limited library shows partial history, which looks like a bug.
- Privacy perception; nothing may leave the device.

**Rating.** Value 4/5 · Distinct 5/5 · Feasible 4/5 · Effort M

**Design notes.**
- Ask for access at the moment of value ("Show where you've shot near here?"), not at launch.
- Present a map of past visits as a quiet layer, not a feed.

### C4 · WeatherKit as data backbone

**What it is.** An enabler: swap Open-Meteo for Apple WeatherKit as the forecast source in the native app. Users see no new feature, but the Light Index keeps working and Iter becomes legally launchable.

**The need behind it.** Open-Meteo's free tier is non-commercial and the prototype is a commercial product in waiting (Inferred; see "Where the prototype stands").

**Why it's distinctive.** It is not; any Apple-platform app can do it. Included because it is the practical path to a legal launch and gets a feature (cloud by layer) the Light Index already uses.

**What it takes.** [WeatherKit](https://developer.apple.com/weatherkit/get-started/): 500,000 calls a month included with the Developer Program, 1M for US$49.99 a month, unused calls do not roll over. Hourly data exposes cloud cover by altitude (low, mid, high; property names to verify), visibility and precipitation chance, with a ten-day hourly horizon. Must show the Apple Weather mark and a legal link. Because Iter's Light Index is a value-added product, attribute the data to "Weather" with a notice that the data has been modified. WeatherKit iOS 16, macOS 13. Minute precipitation and alerts are only in select regions; no aerosol or AQI field was found. Cloud base was not seen.

**Risks.**
- The web prototype needs the REST API or another source.
- Calls multiply with B3 and A2; whether a combined request counts once is unverified.
- Horizon past ten days stays geometry-only.

**Rating.** Value 4/5 · Distinct 1/5 · Feasible 5/5 · Effort S

**Design notes.**
- Put the Apple Weather mark and modified-data notice in a small, consistent "Data" row on the Light Index card.
- Keep a model-agnostic score layer so a second source (A3) can plug in.

### C5 · On-device AI for summaries and why-text

**What it is.** A short, private summary of a spot or a day written on the phone: "Quiet pullout, 8-minute walk, sun clears the ridge late, low cloud may block the horizon." It could also phrase the why-text in A1. It works offline and costs no per-call server fee.

**The need behind it.** It serves A1 (explanation), and the prototype's AI scout ("Ask Vantage") currently runs on Cloudflare Workers AI. No user asked for AI summaries; this is a cost and privacy argument, not a user request.

**Why it's distinctive.** Modest. Any iOS 26+ app can call it. The difference is private summaries grounded in the user's own trip data.

**What it takes.** Foundation Models framework (iOS and macOS 26+): on-device context of 8,192 tokens, a Private Cloud Compute model with 32,000, image input new at WWDC26, free for developers under 2 million first-time downloads ([session 241](https://developer.apple.com/videos/play/wwdc2026/241/), checked on the session page). Requires a device and region that support Apple Intelligence.

**Risks.**
- Invented facts about places. Feed it structured data only and have it phrase, not discover.
- Unavailable on older devices; the app must work without it.

**Rating.** Value 3/5 · Distinct 3/5 · Feasible 4/5 · Effort M

**Design notes.**
- Build the rule-based why-text first (A1); let the model only rephrase.
- Mark generated text subtly so users know what is rule-derived and what is written.

### C6 · Real collaboration

**What it is.** Share a trip through the system share sheet. Companions join from a link, an App Clip opens a read-only view with no install, and Apple-account users edit together in real time. A web view stays as fallback.

**The need behind it.** Collaboration is a medium need (three sources). Wanderlog users report sharing failures, and a reviewer says live editing offers ["no decision structure"](https://www.endlesstravelplans.com/guides/planning-tools/wanderlog-review). The prototype shares by link and its sync is last-write-wins with a name-only identity.

**Why it's distinctive.** Roadtrippers and Wanderlog both collaborate; the difference would be fit to a photo trip, such as showing whose session it is, and the companion view (D4).

**What it takes.** CloudKit sharing with `CKShare` (iOS 13+; Apple-account only, so keep the invite link for web and Android), App Clips (10 MB, up to 100 MB on iOS 17+ under conditions), optional SharePlay (iOS 15+). Replaces the KV store and name-only identity. Sign in with Apple may be needed; rules not verified. Conflict handling replaces last-write-wins.

**Risks.**
- Apple-only sharing excludes Android friends.
- Migration of existing web trips.
- Real accounts and conflict UI are a large step up in complexity.

**Rating.** Value 4/5 · Distinct 3/5 · Feasible 3/5 · Effort L

**Design notes.**
- Make the first shared experience read-only and zero-install; editing comes second.
- Show "who changed what" on a stop, quietly.

### C7 · Widgets, Watch, Siri

**What it is.** A "Tonight's best spot" widget with the score; a Watch complication counting down to blue hour; and Siri asked "When do I leave for Mesa Arch?" through App Intents.

**The need behind it.** A PhotoPills reviewer asked for an [Apple Watch app with complications](https://apps.apple.com/us/app/photopills/id596026805?see-all=reviews) and for customisable ordering (extractor's wording). A ready-made beneficiary of C1.

**Why it's distinctive.** Alpenglow ships widgets and Watch complications, PhotoPills ships widgets (both confirmed). Parity, with a small edge from trip-aware content.

**What it takes.** WidgetKit (iOS 14+; about 40 to 70 refreshes a day for a frequently viewed widget), Live Activities reach the Watch automatically, App Intents (new Siri and Spotlight items in iOS 27). No entitlement found.

**Risks.**
- Refresh budgets make "live" scores stale.
- Time spent here is time not spent on B1 and B3.

**Rating.** Value 3/5 · Distinct 2/5 · Feasible 4/5 · Effort M

**Design notes.**
- Show one decision per widget, not a mini dashboard.
- Show the data age, since widgets lag.

*C8, AR sun path, is set aside; see section 5.*

---

# D · Community and ethics

### D1 · Private-by-default spots with a "sensitive" flag

**What it is.** Every spot a user adds is private. A "Sensitive" toggle changes how it shares: a shared trip shows only the area ("near Kanab"), never exact coordinates. When publishing to any community list, a "thoughtful pause" prompt suggests waiting before posting.

**The need behind it.** The ethics debate is live and the sources split three ways: withhold, share one-to-one, share freely for resilient places. Nature First Principle 4 is "Use discretion if sharing locations", with ["Keeping natural areas off the radar is the best way to protect them"](https://naturefirst.org/principles/) and a suggested "thoughtful pause". On the other side Matt Payne writes that withholding [coordinates "reeks of entitlement"](https://www.onlandscape.co.uk/2024/12/geotagging-gatekeeping-location-sharing/) yet concludes ["it deserves respect"](https://www.onlandscape.co.uk/2024/12/geotagging-gatekeeping-location-sharing/) as a personal choice. Dave Koch: ["Where and how they shot an image can be the shooters equivalent of a trade secret."](https://petapixel.com/2020/05/19/where-did-you-shoot-that/) Horseshoe Bend draws up to two million visitors a year, and a Glen Canyon spokeswoman said ["Most people believe it's caused by Instagram."](https://www.kunc.org/news/2019-04-29/popular-river-overlook-in-arizona-now-has-parking-fee) Counts are small (three blog authors plus the Nature First principles).

**Why it's distinctive.** Locationscout is open with exact positions. [PhotoHound](https://www.photohound.co/articles/?p=13651) is curated with a "Shoot Freely" tag. Neither offers a private-by-default personal model that shares an area (as far as we could confirm). Iter's difference is a stance built into the data model, not a policy page.

**What it takes.** A `visibility` field on spots, coordinate fuzzing to an area on share, and a publish-time prompt. No third-party data. Fixes the prototype's missing edit and delete for custom spots as a prerequisite. Leave No Trace's "tag a general area" guidance supports the area-only approach, though lnt.org itself was not reachable (the wording came via Roadtrippers).

**Risks.**
- A sensitive flag cannot stop a recipient from re-sharing.
- Fuzzed areas can still point at a place; use a generous radius and say so.
- Users who prefer open sharing may find the default paternalistic.

**Rating.** Value 3/5 · Distinct 4/5 · Feasible 5/5 · Effort S

**Design notes.**
- Phrase it as a choice, not a lecture; one line explains what "Sensitive" does.
- Preview exactly what a recipient will see before sharing.

### D2 · Verified, dated spot facts

**What it is.** Each curated spot carries "Last checked Sep 2026 by [name]" for parking, access and conditions, with a one-tap "Report a change" and credit to contributors.

**The need behind it.** Stale data was raised in four sources: Roadtrippers [shows "businesses so old that they were gone before I even moved to this city 10 years ago"](https://justuseapp.com/en/app/944060491/roadtrippers-trip-planner/reviews), a Locationscout reviewer says [they haven't tested the GPS coordinates](https://justuseapp.com/en/app/1474484447/locationscout-photo-spots/reviews), and Adorama says to ["check how recent images are"](https://www.adorama.com/alc/best-digital-tools-for-scouting-locations/). Contributors want credit: a Locationscout user says [it became a "sales vehicle" for his photos](https://apps.apple.com/au/app/id1474484447).

**Why it's distinctive.** PhotoHound reviews each submission within 24 hours ([article](https://www.photohound.co/articles/?p=12337)). Dated verification and credit per fact are not seen elsewhere (unconfirmed).

**What it takes.** An editorial or community process, a moderation queue and credit display. No API cost; the cost is people. Fits the "thin coverage outside famous areas" complaint only if enough contributors exist.

**Risks.**
- Bootstrapping: no contributors, no coverage.
- Moderation burden and liability for wrong access info.

**Rating.** Value 4/5 · Distinct 3/5 · Feasible 2/5 · Effort L

**Design notes.**
- Date stamp on every fact, in plain words ("checked 3 weeks ago").
- Make "Report a change" one tap and work offline (queued).

### D3 · Photographer-authored trip guides

**What it is.** A paid or free editorial collection, such as "Eastern Sierra, 5 days, autumn", written by a named photographer. One tap clones it into the user's trips, with sessions, drive times and notes in place.

**The need behind it.** Elopement photographers hand clients a ["30- to 80-page custom document"](https://rangefinderonline.com/wedding-portrait/weddings/what-does-it-really-take-to-photograph-adventure-elopements/) after more than 20 hours of research, so structured, expert trips have value. Hobbyists ask strangers for routes on Reddit, for example a [Charleston to Austin road trip](https://www.reddit.com/r/landscapephotography/comments/1hodt4h/). Inferred: a ready trip beats a blank page.

**Why it's distinctive.** Guidebooks and ebooks exist; Iter's difference is a guide that is executable, with times that adapt to the dates and the forecast.

**What it takes.** An authoring tool, editorial relationships, and a pricing model (none researched). Reuses the trip schema. Contributors' credit and income expectations are a real design area.

**Risks.**
- Content supply depends on partnerships.
- Guides send readers to the same spots, in tension with D1.

**Rating.** Value 4/5 · Distinct 4/5 · Feasible 3/5 · Effort L

**Design notes.**
- Clone, then personalise: show which stops were moved by the dates.
- Credit the author on every stop they added.

### D4 · Companion mode

**What it is.** A calm view of the shared trip for the non-photographer: meals, rest stops, and "why we're up at 4:50" in one sentence per day. No scores, no sun-angle tools.

**The need behind it.** Photographers plan around companions: [Adorama](https://www.adorama.com/alc/how-to-plan-a-photography-road-trip) suggests that "if sunset conflicts with dinner time, think about eating early or packing along a picnic", and PictureCorrect says [you can't allocate the major portion of your time to photography](https://www.picturecorrect.com/landscape-photography-trip-planning-tips/). Two sources, so a hypothesis.

**Why it's distinctive.** No product found has a companion view; Roadtrippers and Wanderlog are generic itineraries.

**What it takes.** A read-only rendering of the existing shared trip with a simplified layout; the share link already exists. No new data.

**Risks.**
- May stay unused if the photographer does not forward it.
- Needs per-day plain-language reasons (reuse A1 copy).

**Rating.** Value 3/5 · Distinct 5/5 · Feasible 4/5 · Effort S

**Design notes.**
- Lead with "Today": the one early start and the one place.
- Avoid jargon (no "golden hour"); say "sunrise light, best around 6:50".

---

# E · Experience qualities

### E1 · "Now" field mode

**What it is.** A single screen with only what matters in the next three hours: where to be, when to leave, the light now and at the end of the window, one next action. Everything else is a swipe away.

**The need behind it.** A direct user request: a TPE reviewer asked for a ["Dummy mode: only display what can be used in the 3 hours"](https://apps.apple.com/us/app/the-photographers-ephemeris/id366195670) and said TPE ["has gotten a little busy over the years with all the features"](https://apps.apple.com/us/app/the-photographers-ephemeris/id366195670). Complexity complaints run through six sources.

**Why it's distinctive.** No competitor confirmed a time-boxed mode. Apple Design Award praise for Flighty and Halide Mark II centres on glanceable, uncluttered design: Halide ["focuses on the essentials"](https://www.apple.com/newsroom/2022/06/apple-announces-winners-of-the-2022-apple-design-awards/).

**What it takes.** No new data. A view over the next session, B2's schedule and the live forecast. Design work: what to leave out.

**Risks.**
- Users may expect it to cover astro or drives that do not fit three hours.
- Too sparse and it loses the hobbyist who wants detail.

**Rating.** Value 5/5 · Distinct 4/5 · Feasible 4/5 · Effort M

**Design notes.**
- Show one big thing: "Sunset in 1 h 12 m · leave 5:31".
- Make it the home screen when a session is within three hours.

### E2 · Answer-first, progressive disclosure

**What it is.** Every screen leads with a decision ("Go to Mesa Arch, leave 5:31") and puts timelines, hourly weather, sun arcs and facts behind a tap. The anti-PhotoPills.

**The need behind it.** The most repeated photo-app complaint (six sources). PhotoPills reviewers: ["The user interface is befuddling"](https://justuseapp.com/en/app/596026805/photopills/reviews), ["having the users watch a video to be able to understand PhotoPills is a UX failure"](https://justuseapp.com/en/app/596026805/photopills/reviews). A blogger: ["you may find it overwhelming"](https://www.jmpeltier.com/photopills-vs-tpe/) and ["TPE is by far easier to learn because it's a much simpler app"](https://www.jmpeltier.com/photopills-vs-tpe/). The complaints are about discoverability and onboarding, not capability. Even fans agree.

**Why it's distinctive.** PhotoPills wins on depth; Iter would win on trip-level clarity. Bundled rival content stays reachable but not up front.

**What it takes.** Design discipline, not data. A hierarchy per screen: one decision, one reason, one action. Prototype today lists many sections in sequence on the spot page (date strip, timeline, index, sky arc, hourly weather, nearby); the reorder is the work.

**Risks.**
- Experts feel hidden features are missing; make "More" discoverable.
- A "simple" app that lacks depth loses to PhotoPills at the point of purchase.

**Rating.** Value 5/5 · Distinct 4/5 · Feasible 4/5 · Effort M

**Design notes.**
- Every card gets a verb headline. Details are labelled by what they answer, not by data type.
- Test discoverability explicitly; one reader had to be told a calendar feature sat under "More" ([Fstoppers](https://fstoppers.com/apps/apps-you-need-plan-photos-461374)).

### E3 · Night mode

**What it is.** A red, dim theme for pre-dawn and astro use, switchable from a control and automatic after a set hour or in "Now" mode, that keeps text readable and protects night vision.

**The need behind it.** Sky at Night says ["A smartphones bright light will ruin your night vision"](https://skyatnightmagazine.com/advice/how-to-turn-your-iphone-screen-red-for-astronomy) and gives the iOS colour-filter workaround. Stellarium has a built-in night mode (snippet). Red modes in PhotoPills and TPE could not be confirmed (not proof they lack one).

**Why it's distinctive.** Mildly. An in-app red theme means users do not rely on the system filter, which is easy to forget.

**What it takes.** A theme with a red palette and brightness cap; check contrast. No data. Mac and iOS native theming.

**Risks.**
- Even a dim red screen can hurt dark adaptation (forum snippet, unconfirmed).
- Maps and photos are hard to tint without losing legibility.

**Rating.** Value 4/5 · Distinct 3/5 · Feasible 5/5 · Effort S

**Design notes.**
- Pure red on near-black, no blue or white anywhere, including the map and splash.
- Offer a "dim extra" step, and keep touch targets large.

### E4 · One-handed, glove-friendly controls

**What it is.** Large hit areas, bottom-reachable primary actions, and no precision gestures on the field screens. A note where the compass is used: magnetic gloves disturb it.

**The need behind it.** Martin warns that [AR mode relies on the compass, so fingerless gloves with magnets "like my Vallerret photography gloves"](https://fstoppers.com/apps/ten-essential-travel-apps-nomadic-photographers-236282) must come off. No photographer quote on cold, gloves or one-handed use was retrieved; treat this as a gap, not evidence of absence. The need is Inferred.

**Why it's distinctive.** Barely. It is a quality bar rather than a feature.

**What it takes.** Design and QA only. Targets of 44 pt or larger, reachable primary actions, and a test with real gloves. The prototype's stop-card icon buttons drop to 60% opacity on desktop and are small, a hint of what to fix (`StopCard.tsx:95-98`).

**Risks.**
- Without evidence, effort may go unused.

**Rating.** Value 3/5 · Distinct 2/5 · Feasible 5/5 · Effort S

**Design notes.**
- Put the main action in the bottom third; confirm destructive actions with undo, not dialogs.
- Test in cold conditions early; touchscreens under gloves are unreliable.

### E5 · Honest pricing

**What it is.** No caps on stops or trips, no feature hostage-taking, offline never paywalled, and billing that says what it will charge and when.

**The need behind it.** Price and billing anger dominates the generic trip apps (five sources). Roadtrippers reviewers on Trustpilot report ["Without my consent, they autopay upped my level to Premium $59.99"](https://au.trustpilot.com/review/www.roadtrippers.com) and ["They bill without sending any notices for renewals"](https://au.trustpilot.com/review/www.roadtrippers.com); another says ["I can only have 5 waypoints"](https://justuseapp.com/en/app/944060491/roadtrippers-trip-planner/reviews). On Wanderlog: ["Says it is free, but it is not. Cannot plan trip unless you sign up for the $39,99 per year cost."](https://trustpilot.com/review/wanderlog.com) Photo apps draw only mild grumbling ("not so happy when there was a fee to use LS.. but I get it").

**Why it's distinctive.** Price anchors from App Store pages: [PhotoPills](https://apps.apple.com/us/app/photopills/id596026805) $10.99 one-off, [PlanIt Pro](https://apps.apple.com/us/app/planit-pro-photo-planner/id898876435) $9.99, [Locationscout](https://apps.apple.com/us/app/locationscout-photo-spots/id1474484447) Premium $9.99 a month or $59.99 a year, [Alpenglow](https://apps.apple.com/us/app/alpenglow-sunset-forecasts/id978589174) Pro $14.99 to $19.99 a year. Few state a no-caps promise.

**What it takes.** A pricing decision, not engineering. Server and data costs (WeatherKit calls, routing, maps) must be sustainable; budget by user and trip.

**Risks.**
- Offline packs cost real storage and data; "never paywalled" must be affordable.
- Pricing below the $10 to $60 band for a segment that tolerates around $10 once may signal low quality.

**Rating.** Value 4/5 · Distinct 3/5 · Feasible 5/5 · Effort S

**Design notes.**
- Plain price page, one screen; show renewal date and a one-tap cancel.
- If there is a subscription, say what stops working if it lapses (nothing already downloaded should).

---

## Options we considered and set aside

- **C8 · AR sun path.** Table stakes: PhotoPills, TPE, Sun Surveyor and PeakFinder already have it. ARKit geotracking works only outdoors, in specific areas in over 20 countries, so remote parks are likely uncovered (Inferred). It relies on the compass, which magnetic gloves disturb. Low priority; B6's map lines and Look Around cover the need. **CarPlay app:** no listed category fits a trip planner (navigation and driving task need Apple approval, and eligibility is unconfirmed). Use the C1 Live Activity, which reaches the CarPlay Dashboard from any app.
- **Drone-rules engine.** Rules vary by land manager, and the research shows pilots misread a green airspace result as permission ([drone rules explainer](https://dronesgator.com/can-you-fly-a-drone-in-a-park): green "tells you only one thing: the airspace is uncontrolled"). A wrong answer is a legal and safety liability. Offer a link-out to NPS policy and an FAA B4UFLY supplier instead (B4), and say Iter does not give legal advice. Drone data licensing is also awkward: OpenAIP is CC BY-NC.
- **Creator content calendars.** Evidence is thin and the fit weak. Creators plan by video list and calendar ([Little Grey Box](https://littlegreybox.net/travel-vlogging-guide-for-beginners-7-essential-tips/)), not by light, and willingness to pay is low (Inferred). A shot list per stop may cover the useful part later.
- **A social feed.** It invites the crowd damage the research documents, needs moderation, and conflicts with D1. The community split on sharing is real; Iter can stay out of the feed and still support private sharing.

---

## Open questions to test with users

1. When a sunrise looks grey the night before, what do you do now, and what would you need to see to accept a suggested swap (B3)? Would you want a spot or a day moved?
2. How would you want to see forecast uncertainty: a number, a word, or a range? Does a reason ("low cloud on the sun side") raise or lower your trust (A1, A2)?
3. If you only had three hours of information on screen, what would be on it? What must never be hidden (E1, E2)?
4. How do you currently handle the walk-in and parking part of an early start, and would a backward schedule with an alarm feel helpful or pushy (B2, C1)?
5. What would make you share a spot's exact location, or refuse to? Would an area-only share of a "sensitive" spot be useful to you (D1)?
6. Would you let an app read your Photos library to show where you have shot before? What would you want it to never do (C3)?
7. What do you pay for photography planning tools today, and what would feel unfair about offline being included or locked (E5, C2)? How does a non-photographer on the trip actually see the plan (D4)?
