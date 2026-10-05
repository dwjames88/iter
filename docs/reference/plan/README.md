# Iter improvement plan

A proposal for you to react to and reshape. Nothing in it is being built yet. It is the last part of your brief: "show me your plan to improve this." It draws only on the research already done: the [flow briefs](../flows/README.md), the [competitor teardowns](../research/competitors/README.md), the [opportunity briefs](../research/opportunities/README.md), the [design audit](../research/design-audit/README.md) and the [logo rounds](../../brand/iter/round-2/logo-options-round-2.html). Every recommendation links to the brief and section it rests on. Where the briefs say "unverified" or "Inferred", so does this plan.

Written 2026-10-04.

## The plan on one page

**Where Iter stands.** Iter has an idea nobody else ships: a light forecast attached to each stop of a dated, multi-day drive. Today the product undercuts it. The headline score says "Epic" on days when the golden hours are grey, because the night sky lifts it. The Explore map is blank on phones. And the look is close to a copy of Airbnb's, while Iter's own visual ideas (the sky-gradient timeline, the sun-and-moon arc, the gold light moment) sit below the fold. All of it is fixable, and the engineering underneath is sound. [Section 1](01-where-iter-stands.md).

**The recommended decisions.** [Section 2](02-decisions.md).
- **Position:** light-first road trips for the serious hobbyist landscape and travel photographer. "Be in the right place when the light is right." Built to the calm standard of a field companion, private by default.
- **Identity:** make light the system. Retire Airbnb rose, give every colour one job, keep data colours out of the brand. Your stated direction is the route idea (Waypoints / Switchback, with Contour second) and the First Light and Alpine palettes; the mark is still being refined in round three. The plan lays out three ways to use the two palettes, each with a conflict to manage (coral can read as alert, green as "good"), and leans toward Alpine for the land and the route, coral for the light.
- **Light Index:** the score for what you are shooting (sunrise, sunset, blue hour, night), with the window always named ("Sunset · 38"), a real "No forecast" state, visible uncertainty, and the reasons one tap away.
- **First native release:** plan and field. The redesigned core plus the explained Light Index, a backward schedule, light-first ordering as a suggestion, offline trip packs and the "Tonight" Live Activity. Weather swap follows.
- **Business model:** free core with trips of any size and sharing. One paid tier for things that cost money to run. Offline never paywalled.
- **Data:** an Apple-native stack (WeatherKit, MapKit) for the paid app, because Open-Meteo's free tier and the OSRM demo are non-commercial.

**How you control the design.** Figma becomes the source of truth for every visual decision. Components arrive through a local plugin (about 30 minutes of your time). Screens arrive by capture. Token changes flow back to code as DTCG JSON through one export and a reviewed diff. Screens you mark "Ready for build" are the spec. Machines move what already exists; you decide anything a user will notice. [Section 3](03-design-control.md).

**The phases, in order.** [Section 4](04-phases.md).
1. **Stop misleading, stop breaking.** Phone map, honest no-forecast state, a score that names its window, developer copy gone, undo, plain status, focus and targets. Behaviour and copy only, so no design decision is taken from you.
2. **Everything in Figma, and the foundation.** Import, capture, token round trip, identity (round three and the First Light / Alpine split), light ramp, dark and Night modes, component clean-up.
3. **Redesign the core flows.** One shell, Explore map and sheet, a spot page that leads with when to go, the Light Index presentation, trip builder editing, sharing, AI scout, landing, Saved and your own spots.
4. **The differentiators.** Backward schedule, light-first itinerary, explained Light Index, weather swap, Now and Night modes, along-the-drive spots, handoff and export, private by default.
5. **Go native.** Licensed data, the native shell, offline trip packs, the Live Activity, trips on every device, a fair paywall.

**What you need to decide first.** Positioning; that "Iter" replaces "Vantage" in the UI; the Light Index rule; how to get the screens into Figma; the identity direction, once round three is in. The full list, in blocking order, is in [section 7](07-decisions-and-unknowns.md).

**Where the briefs disagreed,** and which side this plan takes:
- **Offline packs, paid or free.** The pricing brief would charge for them; the differentiation brief says never. This plan says free ([2.5](02-decisions.md#25-business-model-in-outline)).
- **Merge duplicate components before or after the Figma import.** The audit says before; the tool-path brief says run the ready scripts now. This plan imports now and merges in Figma, where the decision is yours ([3.3](03-design-control.md#33-how-the-file-is-organised)).
- **Which identity.** The audit recommended Meridian with Archivo and Gold Standard; round two paired R-leg with Geist and Blue Hour. Both are superseded by your own direction after round two (Switchback and Contour; First Light and Alpine). The plan keeps the audit's gold route only as the case against ([2.2](02-decisions.md#22-design-direction-and-identity)).
- **Gold for text.** The audit calls the deepened gold fit for "text and graphics"; the palette study measures it at 3.40:1, graphics only. This plan follows the measurement ([6.5](06-design-options.md#65-visual-identity-direction)).
- Smaller conflicts between the flow briefs and the audit are listed in [section 5](05-critique-digest.md).

## Contents

| Section | What it answers |
|---|---|
| [1 · Where Iter stands](01-where-iter-stands.md) | What is strong, what is most wrong, who the threats are |
| [2 · The decisions that shape everything else](02-decisions.md) | Positioning, identity, Light Index, native scope, business model, data providers: options, recommendation, case against |
| [3 · How you control the design](03-design-control.md) | Figma as source of truth, the import route and your time, how changes come back into code, where Paper fits |
| [4 · The plan, in phases](04-phases.md) | Every item with why, done-when, size, dependencies and decisions; the dependency diagram |
| [5 · Design critique digest](05-critique-digest.md) | Every design problem found, de-duplicated, by severity, with its fix and phase |
| [6 · Design options to weigh](06-design-options.md) | Navigation, map and sheet, trip builder, Light Index presentation, identity: sketched alternatives |
| [7 · Decisions and unknowns](07-decisions-and-unknowns.md) | What you need to decide, in blocking order; the research gaps and how to close them |
| [8 · What we are not doing](08-not-doing.md) | Deliberate omissions, with reasons |

`iter-improvement-plan.html` in this folder is a reading view of the same content, generated from these files.

## Conventions

- **Severity** follows the design audit: critical (misleads about the core job or blocks it), major, minor, polish.
- **Size** is relative: S, M, L. There are no calendar dates.
- **Option IDs** (A1, B3, E1 …) are from the [differentiation options brief](../research/opportunities/03-differentiation-options.md#at-a-glance), with its value / distinct / feasible ratings out of 5.
- **Pattern #N** is a benchmark in the [benchmarks brief](../research/design-audit/03-benchmarks.md), numbered by its section headings.
- **Assumption:** marks anything this plan needed that the briefs do not establish.
