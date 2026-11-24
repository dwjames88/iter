# Data providers

Every place Iter gets data from, as built on this branch. The research behind the choices is in [docs/rebuild/SOURCES.md](rebuild/SOURCES.md). The code that defines each source is `Packages/Iter/Sources/IterSources/Registry/SourceCatalogue.swift` (tiers, rates, cache lifetimes, licence keys) and `Attribution.swift` (the credit text). If this page and that code disagree, the code is right and this page needs fixing.

## The rules Iter follows

- **Free to run.** No source needs a key or an account. Settings has a Keys tab, but it says no source needs one.
- **Order of trust.** When two sources can answer the same question, the more trusted one is asked first. The tiers, best first, are: military, government, open data, user key, device. A source that fails is skipped and named in the app; it never fails the whole search.
- **Every number carries where it came from.** Each datum keeps its source, its model, when it was issued and fetched, its licence and its origin. The screens show a short source line with the data, and Settings ▸ Sources & Credits shows the full credits.
- **Missing is missing.** If no source supplies something, Iter says so. It never fills a gap with a guess that looks like data.
- **Polite to every host.** Each source has a minimum gap between requests, a cap on requests in flight, a timeout and a retry limit. A `Retry-After` header wins over our own backoff. Results are cached, and an old cached result is shown with its age, never as fresh.
- **User-Agent.** Every request says only the app name and version, for example `Iter/0.2.0` (`UserAgent` in `IterSources/HTTP/HTTPClient.swift`). There is a single place a contact address could be added, and it is empty. No name, email or username is ever sent.
- **Licence limits are honoured.** A source whose terms forbid keeping data on disk is marked "memory only" below. Apple Maps results are also memory only.

## What "military-origin" means here

The code has an origin tier for each source: military, government, open data, user key or device. "Military-origin" means the data was produced by a military organisation, even when a civil agency serves it. Three things in Iter are military-origin:

- **METAR and TAF reports from military airfields**, served by the civil NOAA Aviation Weather Center. The feed is NOAA's. The reports from civil airports are government data. Each report is labelled by its own station: Iter marks a station military if it is on a built-in list of airfields or its name has a military marker (AFB, NAS, "air base" and so on). This is a best effort. A military field that is on neither list is shown as civil. In the catalogue the METAR source is listed at the military tier because it can supply military-origin reports.
- **World Magnetic Model 2025**, made for the US National Geospatial-Intelligence Agency (NGA) and the UK Defence Geographic Centre. Iter computes it on the device.
- **MGRS grid references**, an NGA standard, computed on the device.

Everything else is civil government, an open-data community, a university, or Apple. The Navy's USNO sun and moon service was tested but is not used at run time (decision D10): Iter's own astronomy code runs on the device.

## The table

Rates are from the catalogue. "Spacing" is the minimum gap between request starts to one host. "In flight" is the most requests at once. A blank per-minute cap means none beyond the spacing. "On by default" is whether a fresh install uses it.

### Weather and sky

| Source | Provides | Operator | Origin tier (as coded) | Licence and credit text | Key | Rates and limits | On by default |
|---|---|---|---|---|---|---|---|
| NOAA HRRR and GFS (`noaa.nomads`) | Hourly forecast by cloud layer, visibility; nowcast steps. HRRR in the US (3 km, to 48 h), GFS worldwide (0.25 degrees, to 16 days), through the NOMADS GRIB filter, decoded on the device | NOAA NCEP | Government. Civil, not military | US government work, public domain. "Data: NOAA/NCEP" | None | Spacing 600 ms, 2 in flight, 50 per minute, timeout 30 s, 2 retries, first backoff 5 s. Cache 1 h | Yes |
| NOAA HRRR smoke (`noaa.nomads.hrrr-smoke`) | Near-surface smoke, column smoke, aerosol optical thickness. Continental US only | NOAA NCEP | Government | Same as above | None | Same host policy as HRRR and GFS. Cache 1 h | Yes |
| MET Norway Locationforecast (`metno.locationforecast`) | Worldwide fallback forecast: cloud layers and fog, no visibility | Norwegian Meteorological Institute | Government | CC BY 4.0. "Data from MET Norway (CC BY 4.0)" | None | Spacing 1 s, 1 in flight, timeout 20 s, 2 retries. Honours the `Expires` header and sends `If-Modified-Since`. Cache 1 h | Yes |
| Aviation weather reports (`noaa.awc.metar`) | Current observations: METAR and TAF from the nearest stations worldwide, the real-time sky input | NOAA Aviation Weather Center | Military in the catalogue (it can supply military-origin reports); each report is labelled military or government by its station. See above | US government work, public domain. "Data: NOAA Aviation Weather Center". The full text says it includes military airfields | None | Spacing 1 s, 2 in flight, 60 per minute (the host's published limit is 100), timeout 15 s, 2 retries. Cache 10 min | Yes |
| National Weather Service (`noaa.nws.api`) | Official alerts and station observations. US only | NOAA National Weather Service | Government | US government work, public domain. "Data: NOAA/National Weather Service" | None | Spacing 1 s, 2 in flight, timeout 15 s, 2 retries, first backoff 5 s. Cache 5 min | Yes |
| NOAA Space Weather (`noaa.swpc`) | Aurora probability and geomagnetic data (Kp) | NOAA SWPC | Government | US government work, public domain. "Data: NOAA Space Weather Prediction Center" | None | Spacing 1 s, 1 in flight, timeout 30 s, 2 retries. Cache 15 min | Yes |
| NOAA Hazard Mapping System (`noaa.nesdis.hms`) | Smoke plume outlines. North America | NOAA NESDIS | Government | US government work, public domain. "Data: NOAA Hazard Mapping System" | None | Spacing 1 s, 1 in flight, timeout 30 s, 2 retries. Cache 1 h | Yes |
| Sky brightness (`iter.none.sky-brightness`) | Nothing. A "no provider" stub: it always answers "no source" | none | Device (placeholder) | "No source" | None | None | Yes (it only reports that nothing exists) |
| Seeing and transparency (`iter.none.seeing`) | Nothing. A "no provider" stub, same as above | none | Device (placeholder) | "No source" | None | None | Yes (same) |

Why the two stubs exist: no commercial-safe light-pollution or seeing source was found (SOURCES.md section 1.2). The Falchi atlas is non-commercial, and no free point service exists. The sky index leaves those factors out and says so, instead of guessing. See [ROADMAP.md](ROADMAP.md) for the light-pollution plan.

### Terrain and elevation

| Source | Provides | Operator | Origin tier | Licence and credit text | Key | Rates and limits | On by default |
|---|---|---|---|---|---|---|---|
| Terrain Tiles, Terrarium (`aws.terrain-tiles`) | Elevation tiles, decoded on the device into a 72-azimuth horizon profile per place (used for terrain-aware sunrise and sunset) | Tilezen on AWS Open Data. Underlying data from USGS, NASA/NGA (SRTM) and national mapping agencies | Government | Mixed public-domain and open government licences. The credit is the Tilezen list, in full, in Settings. Short form: "Terrain: Tilezen Terrain Tiles; USGS, NASA/NGA, and national agencies" | None | Spacing 100 ms, 4 in flight, timeout 20 s, 2 retries. Cache 90 days | Yes |
| USGS 3DEP point elevation (`usgs.epqs`) | Elevation at a point, US only | USGS The National Map | Government | US government work, public domain, credit requested. "Data: USGS" | None | Spacing 500 ms, 2 in flight, timeout 15 s, 2 retries. Cache 30 days | Yes in the catalogue. Not used by the app yet: see "Built but not used" |

### Imagery

| Source | Provides | Operator | Origin tier | Licence and credit text | Key | Rates and limits | On by default |
|---|---|---|---|---|---|---|---|
| NASA GIBS (`nasa.gibs`) | Satellite cloud imagery tiles from GOES and Himawari | NASA ESDIS | Government (data from NOAA and JMA) | "Imagery: NASA GIBS / NOAA GOES / JMA Himawari" | None | Spacing 100 ms, 4 in flight, timeout 20 s, 1 retry. Cache 10 min | Yes in the catalogue. Not shown in the app: see "Built but not used" |
| EUMETSAT Meteosat (`eumetsat.view`) | Meteosat imagery for Europe and Africa | EUMETSAT | Government | "Contains EUMETSAT data". Memory only, never stored on disk | None | Spacing 250 ms, 2 in flight, timeout 20 s, 1 retry. Cache 15 min | **No.** The licence for real-time imagery in an app has not been read. The user can switch it on in Settings |
| IEM NEXRAD radar (`iem.nexrad`) | US radar tiles | Iowa Environmental Mesonet (Iowa State University), from NOAA NWS NEXRAD data | Open data (the data itself is government) | "Radar tiles: Iowa Environmental Mesonet (NEXRAD)". Memory only | None | Spacing 100 ms, 4 in flight, timeout 15 s, 1 retry. Cache 5 min | **No.** The service's terms have not been fully read. The user can switch it on in Settings |

### Discovery (Find)

| Source | Provides | Operator | Origin tier | Licence and credit text | Key | Rates and limits | On by default |
|---|---|---|---|---|---|---|---|
| OpenStreetMap, Overpass (`osm.overpass`) | Named features (peaks, waterfalls, viewpoints, lakes, arches) and the real outlines of parks and protected areas | OpenStreetMap contributors | Open data | ODbL 1.0. "(c) OpenStreetMap contributors (ODbL)" | None | Spacing 2 s, 1 in flight, timeout 60 s (longer than the 25 s query limit we send, so the server answers first), 2 retries, first backoff 10 s. Cache 7 days | Yes |
| USGS Geographic Names (`usgs.gnis`) | US place names | USGS The National Map | Government | Public domain, credit requested. "Data: USGS" | None | Spacing 1 s, 1 in flight, timeout 30 s, 2 retries. Cache 30 days | Yes |
| Wikipedia (`wikipedia.geosearch`) | Article text and coordinates near a point, as evidence that a place is notable | Wikimedia Foundation | Open data | CC BY-SA 4.0. "Text from Wikipedia (CC BY-SA 4.0)". Links to each article | None | Spacing 1 s, 1 in flight, timeout 15 s, 2 retries. Cache 7 days | Yes |
| Wikivoyage (`wikivoyage.geosearch`) | Travel-guide text, with See and Do sections that name photo spots | Wikimedia Foundation | Open data | CC BY-SA 4.0. "Text from Wikivoyage (CC BY-SA 4.0)" | None | Same as Wikipedia | Yes |
| Wikimedia Commons (`wikimedia.commons`) | Geotagged, licensed photos as evidence | Wikimedia Foundation | Open data | Each photo has its own licence (CC0, CC BY, CC BY-SA and others). "Photos from Wikimedia Commons; licence per photo" | None | Spacing 1 s, 1 in flight, timeout 15 s, 2 retries. Cache 7 days | Yes |

### Apple

All five are MapKit. None needs a key or a paid team. Results are kept in memory only (`mayStore` is false); a place you save is your own data, not a cache.

| Source | Provides | Operator | Origin tier | Credit text | Rates and limits | On by default |
|---|---|---|---|---|---|---|
| Apple Maps search (`apple.mapkit.search`) | Typed place search | Apple | Open data (as coded) | "Apple Maps" | Spacing 250 ms, 2 in flight, 50 per minute, timeout 20 s, 1 retry. Cache 1 day | Yes |
| Apple Maps points of interest (`apple.mapkit.poi`) | Nearby points of interest by category | Apple | Open data (as coded) | "Apple Maps" | Same | Yes |
| Apple Maps geocoder (`apple.mapkit.geocoder`) | Name to coordinate, coordinate to name | Apple | Open data (as coded) | "Apple Maps" | Same | Yes |
| Apple Maps directions (`apple.mapkit.directions`) | Routes and travel times (drive legs, leave-by times, live ETA in Go) | Apple | Open data (as coded) | "Apple Maps" | Same. Cache 10 min | Yes |
| Apple Look Around (`apple.lookaround`) | Street-level imagery where Apple has it | Apple | Open data (as coded) | "Apple Maps" | Same. Cache 7 days | Yes |

Apple is a company, not an open-data project. The code puts it in the open-data tier because it is a free, keyless service and is not military or government. Treat that as a label for ordering, not a claim about Apple's licence.

### On device (no network)

| Source | Provides | Operator | Origin tier | Licence and credit text | On by default |
|---|---|---|---|---|---|
| World Magnetic Model 2025 (`nga.wmm2025`) | Magnetic declination for any place | NGA and the UK Defence Geographic Centre, built by NOAA NCEI and the British Geological Survey | **Military**, computed on the device | US government work, public domain. "World Magnetic Model 2025, NGA and UK DGC (US Government work)". Valid to the end of 2029 | Yes |
| Military Grid Reference System (`nga.mgrs`) | MGRS grid references for any place | NGA | **Military** standard, computed on the device | "MGRS (NGA standard)" | Yes |

Sun, moon, twilight and Milky Way positions are also computed on the device by the Iter astronomy code. They are not network sources and have no catalogue entry.

## Sources that are not in the app

| Source | State | Why |
|---|---|---|
| Reddit | **Off, not built.** Find shows it as "unavailable" with the reason | Reddit's open JSON no longer works for apps. The only free route needs the owner's own Reddit app credentials (OAuth). The code has an extension point for it (a text-evidence provider with the id `reddit.api`). See [ROADMAP.md](ROADMAP.md) |
| Google Custom Search | **Off, not built.** Shown as "unavailable" | Google is closing the product to new users. The old optional key is left where it was and nothing reads it |
| Light pollution, sky brightness | **No provider** (stub) | No commercial-safe free source. See the table above and the roadmap |
| Seeing and transparency | **No provider** (stub) | No commercial-safe free source |
| OpenWeather, Windy, WeatherKit | **Not carried over** | OpenWeather and Windy needed a key. WeatherKit needs a paid developer team (decision D1). The old keys stay in the Keychain where they were. Nothing reads them |
| Open-Meteo | Not built | Its free tier is for non-commercial use only |
| USNO sun and moon, CelesTrak satellites, JTWC cyclones, NAVGEM | Not built | Tested in the research. USNO would only be a test cross-check. The others are not needed for the flow, or carry no cloud data (NAVGEM) |

## Built but not used

Four sources have code and tests but nothing in the apps shows or calls them yet. They are listed in Settings ▸ Sources & Credits so the credits cover everything the app can show.

- **NASA GIBS imagery.** There is a verified true-colour layer descriptor (Web Mercator) and a URL helper, and a real tile was fetched to check it. The cloud-imagery overlay is left out because SwiftUI's `Map` has no tile-overlay content. It needs an `MKMapView`-based map or a future MapKit API. The "show cloud imagery" preference was removed.
- **EUMETSAT** and **IEM radar.** Off by default as above, and not drawn anywhere, for the same map reason.
- **USGS 3DEP point elevation.** Terrain Tiles supply elevation worldwide, so the US-only point service is not called.

## Keys

Nothing needs a key today. The key vault (`IterSources/KeyVault`) is kept so a keyed source can be added later. It stores keys in the Keychain under the service `com.dwjames.iter.keys`, one item per source id. At launch, for the real process only, the vault copies the old app's items (OpenWeather, Windy, Google) into that layout once (`migrateLegacyItems`). It never overwrites a new item, leaves the old ones in place, and a marker makes later launches do nothing. The copied keys are not used by anything today.

## Adding or changing a source

1. Add its `SourceID` and `SourceDescriptor` to `SourceCatalogue.swift`, and its licence text to `Attribution.swift`. This is the only place tiers, rates and cache lifetimes live.
2. Write the adapter in `Packages/Iter/Sources/IterSourcesLive/<operator>/`, with a pure `Mapping` file and fixture tests in `IterSourcesLiveTests`.
3. Wire it in `AppContainer+Live.swift` (the only place concrete adapters are built).
4. If its terms are not read, set `enabledByDefault: false` and `mayStore: false` until they are.
5. Update this page.
