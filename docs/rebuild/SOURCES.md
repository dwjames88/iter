# Iter rebuild: data sources

Status: research complete, 2026-11-22. Data-sources track of the rebuild. Every source marked **Verified** returned usable data to a live request made today from the command line. Everything else is marked as a failure, unverified, or inference. Probe scripts that re-run each check are under `scripts/probes/` (paths are given per source). All probes send the generic User-Agent `IterProbe/0.1 (data-source evaluation)`. No accounts were created and no keys were requested.

Test points: **W** = 36.5785, -118.2923 (Mount Whitney, US). **S** = 46.5586, 8.5610 (Swiss Alps, near the Gotthard).

How to read the origin labels:

| Label | Meaning |
|---|---|
| **MIL** | Produced and published by a US military / defence organisation. |
| **MIL→GOV** | Military-origin data or model, redistributed by a civilian agency (for example military airfield METARs served by NOAA). |
| **GOV** | Civilian government science agency (NOAA, NWS, NASA, USGS, MET Norway, ECMWF, EUMETSAT, EU JRC). |
| **ACAD** | University-run (for example Iowa Environmental Mesonet). |
| **OTHER** | Commercial, community or individual. |

Facts and inferences are kept apart. Anything that was not observed today or read on the provider's own page is marked *(inference)* or *(search result, not read on the provider's page)*.

---

## 1. Recommended stack

Order in each row: military-origin first, then government, then other free. Paid or keyed options appear only in the last column.

### 1.1 The big picture

* **The whole forecast core can be US government, public domain, keyless and worldwide**, through one small piece of code: a GRIB2 decoder for *simple packing* (template 5.0). NOAA's NOMADS "GRIB filter" cuts a small box out of HRRR (US, 3 km) or GFS (global, 0.25°) and **re-packs it as simple packing**. A box around a spot with low, mid and high cloud plus visibility is about 12 KB (verified for HRRR and GFS, and for HRRR smoke fields). A simple-packing decoder is roughly 150 lines of Swift, plus about 40 for HRRR's Lambert conformal grid *(estimate)*. This is the single most useful finding of this track.
* **Open-Meteo is the easiest source by far, but its free API is non-commercial.** Quote: "You may only use the free API services for non-commercial purposes." Apps with subscriptions or ads count as commercial. It suits a free build now. It does not suit a sold app without a paid plan (prices not published) or self-hosting.
* **MET Norway is the commercial-safe JSON fallback**: worldwide, low/mid/high cloud and a fog fraction, CC BY 4.0. It has no visibility, and its terms ask mobile apps to go through a proxy as traffic grows.
* **Genuinely military feeds that work are few.** They are useful but small: USNO for sun and moon, military airfield METARs (via NOAA), the World Magnetic Model (NGA/UK DGC, computed on device), the Space Force satellite catalogue (via CelesTrak), and MGRS (an NGA standard, computed on device). The defence weather and aerosol producers (FNMOC, NRL Monterey NAAPS, the Air Force 557th Weather Wing) are CAC-gated, blocked or offline to the public today. NAVGEM is mirrored by NOAA but carries no cloud fields.
* **The US gets a better tier** for: hourly 3 km forecasts with visibility and smoke (HRRR), alerts and observations (NWS), radar, 1 m elevation (3DEP), and smoke polygons (HMS). Outside the US the app falls back to GFS (coarser, 3-hourly), MET Norway or Open-Meteo, Meteosat imagery, and no free radar.

### 1.2 Table

| Need | Primary | Fallback | Optional extra (keyed / paid / licence-limited) | Why |
|---|---|---|---|---|
| **Sun, moon, twilight, moon phase** | Local `IterAstro` (source of truth) | **MIL** USNO AA API as a cross-check | – | Local maths is offline and instant. USNO is genuinely Navy and agreed with expectations at W and S. |
| **Place search (typed)** | Apple MapKit `MKLocalSearch` | **OTHER** Nominatim (user-triggered only) / Photon | – | MapKit needs no key or paid team. Nominatim forbids autocomplete and allows 1 request per second across all users. |
| **Spot discovery (viewpoints, peaks, waterfalls)** | MapKit POI categories + **OTHER** OSM Overpass | **GOV** USGS GNIS (US names); Wikipedia geosearch | NPS API (free key, US parks); Flickr (key, commercial terms) | Overpass worked at both points (70 and 304 features). Public Overpass is shared and was busy once; cache hard. |
| **Spot photos and descriptions** | **OTHER** Wikipedia + Wikimedia Commons geosearch (per-file licences) | Wikidata SPARQL (CC0; heavily rate-limited today) | Flickr (key) | Commons returned geotagged, licensed photos at both points. |
| **Dark-sky sites** | Dark Sky places list (unofficial WordPress feed, names only) geocoded once | OSM tags | – | No official feed with coordinates exists. |
| **"AI search"** | Apple Foundation Models on device, as ranker and extractor over the sources above | – | Reddit OAuth (approval needed); Brave (card needed) | No free, keyless web search API remains. Reddit's public JSON returns 403. Google Custom Search is closing. |
| **Hourly forecast, cloud by layer, ~10 days, US** | **GOV** NOAA HRRR (0–48 h) then GFS (to 16 days) via NOMADS filter | **GOV** MET Norway locationforecast | Open-Meteo (non-commercial free tier) | HRRR has LCDC/MCDC/HCDC, visibility and smoke at 3 km. GFS covers the rest of the range. Both are public domain. |
| **Same, outside the US** | **GOV** NOAA GFS via NOMADS filter (global 0.25°, 3-hourly) | **GOV** MET Norway (layers + fog, no visibility) | Open-Meteo for ECMWF/ICON/UKMO (non-commercial free tier) | GFS is the only free, commercial-safe global source with layers **and** visibility. |
| **Alerts, station obs (US)** | **GOV** NWS api.weather.gov | IEM ASOS (ACAD) | – | Free, public domain. NWS has no cloud layers, so it is not the forecast source. |
| **Current observations near a stop (worldwide)** | **MIL→GOV** METAR/TAF from aviationweather.gov, including military airfields | NWS observations (US) | – | Global, keyless, 100 requests per minute. Military bases abroad (Ramstein, Aviano) present. |
| **Nowcast 0–3 h** | **GOV** HRRR f00–f03 (US); METAR + satellite + radar trend | Open-Meteo `minutely_15` (US, model-based) | – | No free radar-extrapolation nowcast was found anywhere. MET Norway nowcast is Nordic-only. |
| **Satellite imagery** | **GOV** NASA GIBS WMTS tiles (GOES-East/West, Himawari) | **GOV** EUMETSAT view WMS (Meteosat, Europe/Africa); NOAA STAR sector JPEGs (US, fresher, 2.5–8 MB) | – | GIBS is tiled and keyless but runs 30–40 minutes behind. GIBS has no Meteosat layer, so Europe needs EUMETSAT. |
| **Radar** | **ACAD** IEM NEXRAD n0q tiles (US) | **GOV** NOAA MRMS map service (US, not tile-tested) | – | Nothing free and verified outside the US. |
| **Aerosol, haze, smoke** | **GOV** HRRR smoke and AOD fields via NOMADS filter (US); **GOV** HMS smoke polygons (North America) | Open-Meteo CAMS AOD (global, non-commercial free tier) | NASA FIRMS fires (free key) | HRRR smoke via the filter is simple packing, 12.5 KB (verified). **MIL** NRL NAAPS is not reachable. |
| **Aurora, space weather** | **GOV** NOAA SWPC JSON (OVATION, Kp, Kp forecast) | – | – | Public domain, keyless, global grid. Not military, although USAF magnetometer reports appear on SWPC. |
| **Light pollution / sky brightness** | **Gap.** Proposal: bundle a coarse grid derived from NASA Black Marble VIIRS (needs Earthdata login to download once) | GIBS VIIRS night-lights tile as a visual proxy | lightpollutionmap.info (key, terms unknown) | The Falchi 2016 atlas is CC BY-NC, so it cannot be shipped in a sold app. No free point service exists. |
| **Seeing / transparency** | **Gap.** Derive a transparency proxy from AOD + humidity + high cloud | – | 7Timer (non-commercial only) | No commercial-safe seeing source was found. |
| **Milky Way visibility** | Computed locally (galactic centre altitude, twilight, moon, cloud, sky brightness) | – | – | No feed exists. |
| **Satellite passes (ISS, Starlink)** | **MIL→OTHER** CelesTrak GP data (Space Force catalogue) + on-device SGP4 | – | Space-Track (free account) | CelesTrak blocks repeat downloads within 2 hours; cache. |
| **Elevation at a point** | **GOV** USGS 3DEP EPQS (US, 1 m) | AWS Terrain Tiles (Terrarium PNG, global, blends SRTM/GMTED = NASA/NGA, USGS/NGA) | – | Both verified to within a few metres of the summit. |
| **Terrain grid / horizon** | Terrarium tiles decoded on device; horizon computed on device | **GOV** 3DEP ImageServer float32 grid (US) | Copernicus DEM 30 m COG (licence to read) | PVGIS horizon works globally but gave an impossible profile at Whitney. |
| **Gazetteer** | Apple MapKit + OSM | **GOV** USGS GNIS (US) | GeoNames (free username) | **MIL** NGA GEOnet Names Server timed out from here. |
| **Magnetic declination** | **MIL→GOV** World Magnetic Model 2025 (NGA + UK DGC), computed on device | – | NOAA declination API (free key) | A 60-line Python port matched NOAA's live answer to 3 decimals. |
| **Coordinates / MGRS** | Computed on device (NGA grid standard) | – | – | No data needed. |
| **Routing / ETA** | Apple MapKit `MKDirections` | – | – | OSRM demo is non-commercial; OpenRouteService needs a key. No reason to leave MapKit was found. |

---

## 2. Verified matrix

Each entry: origin, endpoint and example, auth, limits, licence and distribution, coverage, resolution and cadence, latency, format and Swift effort, reliability, probe result, script.

Swift effort scale used below: **Easy** = JSON or PNG with system frameworks. **Moderate** = text, XML or KML parsing, or a small binary reader. **Hard** = a decoder of several hundred lines.

### 2.1 Military and military-origin

#### USNO Astronomical Applications API — Verified — MIL
* **Operator:** US Naval Observatory (Navy).
* **Endpoints:** `https://aa.usno.navy.mil/api/rstt/oneday?date=2026-11-22&coords=36.5785,-118.2923&tz=-8`; also `moon/phases/date`, `celnav` (instantaneous altitude/azimuth), `siderealtime` (needs `time`), `seasons`, `eclipses/solar/year`.
* **Auth:** none. Optional `ID` parameter (up to 8 characters).
* **Limits / licence:** neither stated on the API page. US government work, so public domain *(inference)*.
* **Coverage:** global. **Resolution:** event times to the minute. `rstt` returns local times; `moon/phases` returns UTC.
* **Format:** JSON. Easy.
* **Probe:** HTTP 200 at W and S. W: civil twilight 06:10, sunrise 06:38, transit 11:39, sunset 16:40, civil end 17:08. Moon rise 15:03, set 04:27, waxing gibbous 95%, full moon 24 Nov 06:53 local.
* **Use:** cross-check for `IterAstro` in tests, not a runtime dependency.
* **Scripts:** `scripts/probes/military/usno-api.sh`, `scripts/probes/sky/usno-oneday.sh`.

#### METAR / TAF including military airfields (aviationweather.gov) — Verified — MIL→GOV
* **Operator:** NOAA Aviation Weather Center. Military stations' observations are military data served by NOAA.
* **Endpoints:** `https://aviationweather.gov/api/data/metar?ids=KNID,KNFL,KEDW,KLSV,ETAR,LIPA&format=json`; `.../taf?ids=...&format=raw`; `.../stationinfo?ids=KNID&format=json`; `.../metar?bbox=36,-119,37,-117.5&format=raw`.
* **Auth:** none. **Limits:** 100 requests per minute; up to 400 entries per call; a custom User-Agent recommended; gzipped cache files refreshed each minute for bulk use.
* **Licence:** not stated on the page. US government, public domain *(inference)*.
* **Coverage:** global. **Cadence:** about hourly per station plus specials. **Latency:** minutes (ETAR 12:55Z observation available at 13:10Z).
* **Format:** JSON (Easy). Raw METAR/TAF text needs a parser (Moderate).
* **Probe:** HTTP 200. `METAR ETAR 221255Z AUTO 06008KT 9999 CLR 05/01 A2976`. TAFs for ETAR, KEDW, KNFL, LIPA. The nearest station to W was KO26 (not military); KNID, KNFL and KEDW are 50–200 km away.
* **Use:** the observed-sky input of the real-time Sky Index, for whichever stations are nearest.
* **Script:** `scripts/probes/military/avwx-military-metar.sh`.

#### World Magnetic Model 2025 — Verified — MIL→GOV
* **Operator:** NGA and the UK Defence Geographic Centre. Built by NOAA NCEI and the British Geological Survey; NCEI hosts it.
* **Download:** `https://www.ncei.noaa.gov/sites/default/files/2024-12/WMM2025COF.zip` (HTTP 200, 42,887 B) and `.../2025-01/WMM2025COF.zip` (HTTP 200, 90,017 B; a different package). Both contain `WMM.COF` (header `2025.0 WMM-2025 11/13/2024`). The often-quoted `ngdc.noaa.gov/geomag/WMM/data/WMM2025/WMM2025COF.zip` returns 404.
* **Licence (quoted from NCEI):** "The WMM source code is in the public domain and not licensed or under copyright. The information and software may be used freely by the public." Derived works must note the US Government material (17 U.S.C. 403).
* **Validity:** 2025.0 until the end of 2029.
* **Effort:** spherical harmonics, degree 12. About 150–200 lines of Swift with the coefficients embedded *(estimate)*.
* **Probe:** a 60-line Python port (`terrain/wmm-compute.py`) reproduced NOAA's published test values (1.281 vs 1.28; 68.775 vs 68.78) and gave declination 11.817° at W, matching NOAA's live API (11.81729). S: 3.623°.
* **Scripts:** `scripts/probes/terrain/wmm-coefficients.sh`, `terrain/wmm-compute.py`, `military/wmm-coefficients.sh`.

#### CelesTrak GP element sets — Verified — MIL→OTHER
* **Operator:** CelesTrak (individually run), republishing the US Space Force 18th SDS catalogue.
* **Endpoints:** `https://celestrak.org/NORAD/elements/gp.php?CATNR=25544&FORMAT=json`; `...?GROUP=stations&FORMAT=json`; `GROUP=starlink`.
* **Auth:** none. **Limits:** data refreshes every 2 hours. A repeat download before the next update gets HTTP 403. More than 50 errors in 2 hours can firewall the IP for 2 hours.
* **Licence:** "freely available" but no licence stated. The usage-policy page was not read.
* **Format:** JSON (OMM), Easy. Pass prediction needs SGP4 on device (Moderate, a few hundred lines).
* **Probe:** HTTP 200. `ISS (ZARYA)`, epoch 2026-11-22T04:07Z.
* **Scripts:** `scripts/probes/military/celestrak.sh`, `sky/celestrak-iss.sh`, `sky/celestrak-stations.sh`.

#### JTWC tropical cyclone feed — Verified (feed only) — MIL
* **Operator:** Joint Typhoon Warning Center (Navy/Air Force). Pacific and Indian Oceans only.
* **Endpoints:** `https://www.metoc.navy.mil/jtwc/rss/jtwc.rss`, `.../jtwc/products/abpwweb.txt`. The HTML page returns 403.
* **Auth:** none. Licence and limits not stated.
* **Probe:** HTTP 200, RSS built 13:28Z, "No Current Tropical Cyclone Warnings."
* **Use:** low relevance; optional storm context for Pacific trips.
* **Script:** `scripts/probes/military/jtwc.sh`.

#### NAVGEM (Navy global model) on NOMADS — Verified, not useful — MIL→GOV
* **Operator:** FNMOC model output mirrored by NOAA NOMADS. FNMOC's own public site is down to the public (503, "access remains for authorized users with a Common Access Card").
* **Endpoint:** `https://nomads.ncep.noaa.gov/pub/data/nccf/com/fnmoc/prod/navgem.YYYYMMDD/navgem_YYYYMMDDHHfFFF.grib2` (use HTTP/1.1).
* **Content:** 0.5° global, to 180 h. **No cloud-cover parameter** (no GRIB2 category 6 messages in the f024 file). No `.idx`, so no byte-range fetches; 20 MB per file.
* **Probe:** HTTP 200, 20.4 MB, 91 messages.
* **Verdict:** military-origin, but it cannot score a sunrise. Not recommended.
* **Script:** `scripts/probes/military/navgem-nomads.sh`.

### 2.2 Weather (government and others)

#### NOAA NOMADS GRIB filter: HRRR and GFS — Verified — GOV
* **Operator:** NOAA NCEP.
* **HRRR example:** `https://nomads.ncep.noaa.gov/cgi-bin/filter_hrrr_2d.pl?dir=%2Fhrrr.20261122%2Fconus&file=hrrr.t12z.wrfsfcf01.grib2&var_LCDC=on&var_MCDC=on&var_HCDC=on&var_TCDC=on&var_VIS=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_entire_atmosphere=on&lev_surface=on&subregion=&toplat=37&leftlon=-119&rightlon=-117.5&bottomlat=36`
* **GFS:** the same pattern with `filter_gfs_0p25.pl`; works anywhere on Earth.
* **Auth:** none. **Limits:** not published in what was read; NOMADS throttles heavy users *(inference)*. Requests should be per spot, per model run, and cached.
* **Licence:** US government, public domain. Fine for a sold app.
* **Coverage and cadence:** HRRR: CONUS 3 km, hourly runs, hourly steps to 18 h (48 h on 00/06/12/18Z). GFS: global 0.25°, 4 runs a day, to 16 days (hourly to 120 h, then 3-hourly *(from general knowledge, not re-checked)*).
* **Latency:** HRRR f01 for the 12Z run was available about 53 minutes after the run time.
* **Fields:** low, middle and high cloud layers, total cloud, visibility. HRRR also gives smoke (MASSDEN near-surface, COLMD column) and aerosol optical thickness (AOTK). No fog field (use visibility, humidity and low cloud).
* **Format:** GRIB2, **simple packing (template 5.0)** as returned by the filter, with grid template 3.30 (HRRR, Lambert conformal) or 3.0 (GFS, lat/lon).
* **Swift effort:** about 150 lines for simple unpacking plus about 40 lines for Lambert conformal *(estimate)*. One decoder serves forecast, visibility and smoke.
* **Reliability:** NOMADS has a history of outages and slow periods. The AWS mirror is the fallback but uses complex packing (see next entry).
* **Probes:** cloud box 200, 12,302 B, 5 messages, 2,392 points. GFS box 200, 2,060 B. HRRR smoke box (MASSDEN, COLMD, AOTK) 200, 12,524 B, all template 5.0 (lead re-test).
* **Scripts:** `scripts/probes/weather/nomads-hrrr-subset.sh` (cycle date is hard-coded; edit if not yet published), `scripts/probes/lead-retests.sh`, helper `weather/grib2_templates.py`.

#### NOAA HRRR and GFS on AWS Open Data — Verified — GOV
* **Endpoints:** `https://noaa-hrrr-bdp-pds.s3.amazonaws.com/hrrr.20261122/conus/hrrr.t12z.wrfsfcf01.grib2` plus `.idx`; `noaa-gfs-bdp-pds` likewise. Byte-range requests return HTTP 206.
* **Cost:** one whole-domain field is 0.4–0.9 MB (LCDC 912 KB). No server-side subsetting.
* **Packing:** **template 5.3** (complex packing with spatial differencing). About 400–600 lines of Swift; validate against wgrib2 *(estimate)*.
* **Use:** fallback when NOMADS is down, and a candidate for any future server-side relay.
* **Script:** `scripts/probes/weather/aws-hrrr-gfs-range.sh`, `scripts/probes/sky/hrrr-smoke-aws.sh`.

#### NWS api.weather.gov — Verified — GOV, US only
* **Endpoints:** `/points/36.5785,-118.2923` → office VEF grid 14,134; `/gridpoints/VEF/14,134`; `/stations/KBIH/observations/latest`; `/alerts/active?point=lat,lon`.
* **Auth:** none. A User-Agent is required and should carry a contact (owner decision). Rate limit unpublished; 429 means retry after about 5 s.
* **Licence:** "intended to be open data, free to use for any purpose."
* **Fields:** `skyCover` only (no layers). `visibility` is a single placeholder value. Has humidity, wind, precipitation probability and amount, `ceilingHeight`, `lowVisibilityOccurrenceRiskIndex`. About 7 days.
* **Probe:** 200 at W. 404 "Data Unavailable For Requested Point" at S. Grid response 307 KB.
* **Use:** alerts and US observations, not the cloud forecast.
* **Script:** `scripts/probes/weather/nws-gridpoint.sh`.

#### MET Norway locationforecast 2.0 — Verified — GOV (Norway), worldwide
* **Endpoint:** `https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=46.5586&lon=8.5610` (coordinates to at most 4 decimals; 5+ returns 403).
* **Auth:** none. User-Agent with an app name and contact required (owner decision). Under 20 requests per second **summed over all installs**. Honour `Expires`; use `If-Modified-Since`. "Mobile apps should not contact the API directly, but instead use a local proxy" (quoted).
* **Licence:** CC BY 4.0 (commercial use permitted with credit).
* **Fields:** `cloud_area_fraction` and `_low`, `_medium`, `_high`, `fog_area_fraction`, humidity, wind, precipitation. **No visibility.**
* **Coverage and range:** global, about 10 days (93 steps; hourly early, coarser later).
* **Probe:** 200 at W and S. W at 13Z: low 2.3, medium 20.3, high 35.2, fog 0.0. S: 96.1 / 91.4 / 85.9, fog 0.8. Re-confirmed 200 by the lead.
* **Nowcast 2.0:** 422, "only available for the Nordic area". Rejected.
* **Script:** `scripts/probes/weather/met-no-locationforecast.sh`.

#### Open-Meteo forecast — Verified — OTHER (licence-limited)
* **Endpoint:** `https://api.open-meteo.com/v1/forecast?latitude=36.5785&longitude=-118.2923&hourly=cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high,visibility&forecast_days=10&timezone=auto`; `models=` for `gfs_seamless`, `ncep_hrrr_conus`, `ecmwf_ifs025`, `icon_seamless`, `ukmo_seamless`, `meteofrance_seamless`, `gem_seamless`, `jma_seamless`.
* **Auth:** none on the free tier. **Limits:** under 10,000 calls a day, 5,000 an hour, 600 a minute.
* **Licence (quoted):** "You may only use the free API services for non-commercial purposes." "Apps and websites that have subscriptions or display advertisements count as commercial." Data CC BY 4.0. Paid plans exist; prices not published. Self-hosting the open-source server is allowed.
* **Fields:** cloud layers from every model tested. Visibility from GFS/HRRR, UKMO, and `best_match`; **None** from ECMWF, ICON, ICON-CH1, GEM, JMA and Météo-France. `minutely_15` for the US (model-derived *(inference)*).
* **Probe:** 200, 240 hourly values, 0.2 s. One earlier request timed out at 60 s and succeeded on retry. Lead re-test at S: UKMO visibility 58,520 m falling to 120 m overnight (fog); `best_match` 32,460 m; ECMWF None.
* **Scripts:** `scripts/probes/weather/open-meteo-layers.sh`, `scripts/probes/lead-retests.sh`.

#### ECMWF open data (IFS 0.25°) — Verified, not recommended direct — GOV (intergovernmental)
* **Endpoint:** `https://data.ecmwf.int/forecasts/20261122/06z/ifs/0p25/oper/20261122060000-3h-oper-fc.grib2` plus JSON `.index`; range fetch of `lcc` returned 206, 479 KB.
* **Fields:** `lcc`, `mcc`, `hcc`, `tcc`; **no visibility**. Whole-globe fields only.
* **Packing:** **template 5.42 (CCSDS/AEC)**, about 500+ lines of Swift and no system library *(estimate)*.
* **Licence:** CC BY 4.0 (stated in the brief; not re-read today).
* **Verdict:** use ECMWF only through Open-Meteo or a future relay.
* **Script:** `scripts/probes/weather/ecmwf-open-data.sh`.

#### NBM (National Blend of Models) — Partial — GOV
* AWS `noaa-nbm-grib2-pds` reachable; idx lists total cloud, ceiling, visibility and **visibility probability below thresholds** (useful for fog risk). No cloud layers. Not subset-tested. Optional.

#### NASA POWER — Verified, not useful — GOV
* Returned 200 with `-999` fill for recent days. Archive and climatology only. Script: `scripts/probes/weather/nasa-power-synoptic.sh`.

### 2.3 Satellite and radar

#### NASA GIBS WMTS — Verified — GOV
* **Example tile:** `https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/GOES-West_ABI_Band13_Clean_Infrared/default/2026-11-22T12:00:00Z/2km/4/4/5.png` → 200, 512×512 PNG, 237 KB, over the Sierra Nevada.
* **Layers (lead-checked in capabilities):** GOES-East and GOES-West GeoColor, Band 2 visible, Band 13 IR, Air Mass, Dust, FireTemp; Himawari AHI equivalents; VIIRS true colour and night lights. **No Meteosat layer.**
* **Auth:** none. Capabilities state Fees none, AccessConstraints none.
* **Cadence:** 10-minute time steps. **Latency:** about 30–40 minutes.
* **Caveats:** only some zoom levels are populated in a given tile matrix set (z3 and z5 returned 404 for the same spot). WMS `GetMap` returned blank transparent images; use WMTS. Capabilities is 5.3 MB, so do not fetch it on a phone; bake the layer list into the app.
* **Format:** PNG/JPEG tiles. Easy (MapKit overlay).
* **Script:** `scripts/probes/weather/satellite-gibs-goes.sh`.

#### EUMETSAT view WMS (Meteosat) — Verified by the lead — GOV (intergovernmental)
* **Example:** `https://view.eumetsat.int/geoserver/wms?service=WMS&version=1.3.0&request=GetMap&layers=msg_fes:ir108&styles=&crs=EPSG:4326&bbox=45,7,48,10&width=256&height=256&format=image/png` → 200, 256×256 PNG, 65 KB, 1.0 s, real IR cloud imagery over the Alps (checked visually).
* **Auth:** none. GetCapabilities is slow (43 s) — bake the layer list in.
* **Licence:** **not checked.** EUMETSAT's data policy for real-time imagery in commercial products must be read before release (owner decision).
* **Script:** `scripts/probes/lead-retests.sh`.

#### NOAA STAR GOES sector images — Verified — GOV
* `https://cdn.star.nesdis.noaa.gov/GOES18/ABI/SECTOR/psw/GEOCOLOR/latest.jpg` (2.26 MB), `.../GOES19/ABI/CONUS/GEOCOLOR/latest.jpg` (8.3 MB). Updated every 5–10 minutes *(inference from timestamps)*. Whole sectors only; crop on device. CC0 per image metadata. Too heavy for frequent refresh on cellular.

#### IEM NEXRAD tiles and ASOS — Verified — ACAD
* **Radar:** `https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/6/10/25.png` → 200, 6 KB, 0.3 s; `-m05m` variants for animation; scans about every 5 minutes.
* **Observations:** `api/1/currents.json?station=KBIH&network=CA_ASOS` → 200.
* **Licence:** IEM's terms not read. University service, no commercial guarantee.
* **Script:** `scripts/probes/weather/radar-iem-mrms-opengeo.sh`.

#### NOAA MRMS radar map service — Reachable, not tile-tested — GOV
* `https://mapservices.weather.noaa.gov/eventdriven/rest/services/radar/radar_base_reflectivity/MapServer?f=json` → 200 (MRMS 1 km). `opengeo.ncep.noaa.gov` WMS capabilities → 200. Raw MRMS GRIB2 at `mrms.ncep.noaa.gov/2D/...` reachable but heavy.

### 2.4 Sky, aerosol, space weather

#### NOAA SWPC — Verified — GOV
* **Endpoints:** `https://services.swpc.noaa.gov/json/ovation_aurora_latest.json` (919 KB; global 1° grid `[lon 0–359, lat, %]`), `json/planetary_k_index_1m.json`, `products/noaa-planetary-k-index-forecast.json`, `text/3-day-forecast.txt`, `products/noaa-scales.json`.
* **Auth/limits:** none stated. **Licence:** NOAA/NWS public domain; do not imply endorsement.
* **Cadence:** OVATION is a 30–90 minute nowcast (obs 13:13Z, forecast 14:19Z); Kp per minute; 3-hour Kp forecast for 3 days.
* **Probe:** 200. Kp 1 (`"kp":"1Z"`); forecast peaks Kp 4 on 23 Nov 12–15 UT.
* **Caveat:** the old solar-wind paths (`products/solar-wind/*.json`) now return 404; the new paths were not found.
* **Scripts:** `scripts/probes/sky/swpc-ovation.sh`, `swpc-kp1m.sh`, `swpc-kp-forecast.sh`, `swpc-3day.sh` (`swpc-solarwind.sh` is kept as evidence of the 404).

#### NOAA HMS smoke polygons — Verified — GOV
* `https://satepsanone.nesdis.noaa.gov/pub/FIRE/web/HMS/Smoke_Polygons/KML/2026/11/hms_smoke20261122.kml` → 200, 0 placemarks today (plausible in late November). KML via `XMLParser` plus point-in-polygon (Moderate). Daily analyst polygons, light/medium/heavy. No GeoJSON (404).
* **Script:** `scripts/probes/sky/hms-smoke-kml.sh` (`hms-smoke-geojson.sh` is kept as evidence of the 404).

#### Open-Meteo air quality (CAMS) — Verified — OTHER (licence-limited)
* `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=...&longitude=...&hourly=aerosol_optical_depth,dust,pm2_5,pm10&forecast_days=2` → 200 at W (AOD 0.06–0.07) and S (AOD 0.03–0.06).
* Same non-commercial rule as the forecast API; must credit CAMS and Open-Meteo. Global 0.4°, Europe 0.1°, about 5 days.
* **Scripts:** `scripts/probes/sky/openmeteo-aq-whitney.sh`, `openmeteo-aq-swiss.sh`.

#### NASA GEOS-CF via OPeNDAP — Verified, limited — GOV
* `https://opendap.nccs.nasa.gov/dods/gmao/geos-cf/fcast/aqc_tavg_1hr_g1440x721_v1.latest.ascii?pm25_rh35_gcc[0:2][0][506][247]` (use `curl -g`) → 200, PM2.5 ≈ 0.97. Only surface NO2, CO, O3, PM2.5, SO2 — **no AOD**. Index-based URLs are brittle. Not recommended.
* **Script:** `scripts/probes/sky/geos-cf-opendap.sh`.

#### NASA GIBS VIIRS night lights — Verified, proxy only — GOV
* `https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/VIIRS_Night_Lights/default/2016-01-01/500m/3/2/2.png` → 200. Only 2012 and 2016 composites; rendered colours, not radiance. A visual layer, not a sky-brightness number.
* **Script:** `scripts/probes/sky/gibs-night-lights.sh`.

#### 7Timer ASTRO — Verified — OTHER (non-commercial)
* `https://www.7timer.info/bin/astro.php?lon=-118.2923&lat=36.5785&ac=0&unit=metric&output=json&tzshift=0` → 200 at W and S. Seeing (1–8), transparency (1–8), cloud (1–9), 3-hourly for about 3 days, from GFS. Content type is `text/html`.
* **Licence (quoted):** free "as long as you are not using them for commercial purpose." Not usable in a sold app.
* **Scripts:** `scripts/probes/sky/7timer-astro-whitney.sh`, `7timer-astro-swiss.sh`.

### 2.5 Terrain and geo

| Source | Origin | Whitney (true ≈ 4,421 m) | Swiss (≈ 2,100 m) | Auth | Licence | Script (`scripts/probes/terrain/`) |
|---|---|---|---|---|---|---|
| USGS 3DEP EPQS `epqs.nationalmap.gov/v1/json?x=-118.2923&y=36.5785&units=Meters&wkid=4326` | GOV | 4416.2 (1 m) | fails (US only) | none | public domain, credit requested | `usgs-epqs.sh` |
| USGS 3DEP ImageServer `identify` / `exportImage` (float32 TIFF grid) | GOV | 4416.23; 21×21 grid min 3783 max 4410 | not tested | none | public domain | `usgs-3dep-imageserver.sh` |
| AWS Terrain Tiles `s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png` | blend incl. SRTM (NASA/NGA), GMTED (USGS/NGA), 3DEP | 4412.4 (z12) | 2107.0 (z12) | none | per-source credits (Tilezen list); some regional sources CC BY | `aws-terrarium.py` |
| Copernicus DEM GLO-30/90 COG on AWS | GOV (EU) | header read only | header read only | none | free; **commercial clause not confirmed** | `copernicus-cog.sh` |
| PVGIS horizon `re.jrc.ec.europa.eu/api/printhorizon?lat=&lon=&outputformat=json` | GOV (EU JRC) | 62° wall to the west — wrong | plausible 2–19° | none, 30/s per IP | not stated | `pvgis-horizon.sh` |
| USGS GNIS `carto.nationalmap.gov/arcgis/rest/services/geonames/MapServer/5/query` (envelope query) | GOV | 84 landform names in a 16 km box | US only | none | public domain | `usgs-gnis.sh`, `places/usgs_gnis.sh` |
| Open-Meteo elevation | OTHER | 4355 (90 m) | 2107 | none | non-commercial free tier | `open-meteo-elevation.sh` |
| OpenTopoData public | OTHER | 4403 / 4412 | 2110 | none | 1,000 calls/day | `opentopodata.sh` |
| Open-Elevation public | OTHER | 4369.5 | 2111.2 | none | unknown | `open-elevation.sh` |

Swift effort: Terrarium PNG via ImageIO, about 30 lines (Easy). 3DEP float32 uncompressed TIFF, 60–80 lines (Moderate). Copernicus COG with DEFLATE and float predictor, 250–400 lines (Hard). DTED would be simple binary but no public download was confirmed.

Horizon: compute on device from 4–9 Terrarium z12 tiles around the spot (about 30 m effective source resolution) by ray-marching each azimuth; use the 3DEP grid in the US for detail *(design inference)*. PVGIS is a sanity check only.

### 2.6 Place discovery

| Source | Origin | Endpoint (example) | Auth / limits | Licence for a sold app | Probe | Script (`scripts/probes/places/`) |
|---|---|---|---|---|---|---|
| OSM Overpass | OTHER | `POST https://overpass-api.de/api/interpreter` with `nwr[tourism=viewpoint](around:15000,LAT,LON)` etc. | none; ~10,000 requests/day, ~1 GB/day | ODbL with attribution. Usage page calls a non-mapper app relying on public instances a problem case; self-host for scale | W 200, 70 features (Mount Barnard 4266 m, Lower Picket Creek Falls). S first 502 "at capacity", retry 200, 304 (Dammastock 3630 m, Calmut viewpoint). Mirrors kumi.systems and private.coffee timed out | `overpass.sh` |
| Nominatim | OTHER | `/search?q=Mount+Whitney&format=jsonv2`, `/reverse` | none; 1 request/s across all users; cache; **no autocomplete** | ODbL | 200; Whitney at 36.5786,-118.2921; S reverse → Airolo | `nominatim_photon.sh` |
| Photon (komoot) | OTHER | `https://photon.komoot.io/api/?q=Grimsel+Pass` | none; terms not read | ODbL data | 200, "Grimsel Passhöhe" | `nominatim_photon.sh` |
| Wikipedia / Wikivoyage geosearch | OTHER | `en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=LAT|LON&gsradius=10000` | none; serial requests, descriptive UA | CC BY-SA text; link and credit | W: Mount Whitney, Mount Russell. S: Gotthard Pass, Lago di Lucendro | `wikimedia.sh` |
| Wikimedia Commons geosearch | OTHER | `commons.wikimedia.org/w/api.php?...list=geosearch&gsnamespace=6` + `extmetadata` | none | per-file (CC0, CC BY-SA 3.0/4.0 seen); attribute author | photos at both points | `wikimedia.sh` |
| Wikidata SPARQL | OTHER | `POST https://query.wikidata.org/sparql` with `wikibase:around` | none; strict; 429 today ("1 req / min" outage rule) | CC0 (images per-file) | W 200 (Mount Muir, LeConte, Mallory). S 429 twice | `wikidata.sh` |
| USGS GNIS | GOV | see 2.5 | none | public domain | W 84 names | `usgs_gnis.sh` |
| iNaturalist | OTHER | `api.inaturalist.org/v1/observations?lat=&lng=&radius=10&photos=true` | none; ~60/min (search result) | per-photo licences | 200, ~7,000 observations each | `inaturalist.sh` |
| NPS API | GOV | `developer.nps.gov/api/v1/parks?q=sequoia&api_key=...` | **free key**, 1,000/hour | terms page not read | 200 with public `DEMO_KEY` | `nps_ridb.sh` |
| Waymarked Trails | OTHER | `hiking.waymarkedtrails.org/api/v1/list/search?query=John+Muir+Trail` | none | ODbL data; service terms not read | 200 | `darksky_waymarked.sh` |
| Dark Sky places (WordPress REST) | OTHER | `darksky.org/wp-json/wp/v2/darksky_place?per_page=100&_fields=id,link,title` | none; unofficial | reuse terms unknown | 200, 301 places, names only, no coordinates | `darksky_waymarked.sh` |
| DuckDuckGo Instant Answer | OTHER | `api.duckduckgo.com/?q=Mount+Whitney&format=json` | none | terms not read | 200, entity abstract only | `search_engines.sh` |

Apple (read from Apple docs, not run): `MKLocalSearch` and `MKLocalPointsOfInterestRequest` (iOS 14+) need no key. Useful categories: `.nationalPark`, `.park`, `.beach`, `.campground` (iOS 13+), `.nationalMonument`, `.hiking` (iOS 18 / macOS 15+). Foundation Models on device: free, unlimited, 4K-token context. **Whether it runs on a free Personal Team build is not documented; test on device.** The new Private Cloud Compute route (iOS 27 / macOS 27, 32K context) requires App Store Small Business Program enrolment and a managed entitlement, so treat it as unavailable on a free team.

---

## 3. Rejected or unavailable (do not re-check without a reason)

| Source | Origin | Result today | Reason |
|---|---|---|---|
| FNMOC public web services | MIL | 503: "temporarily removed its public web services… authorized users with a Common Access Card" | CAC-gated. Only NAVGEM via NOMADS remains (no cloud fields). |
| USGODAE FNMOC FTP | MIL | 403 / 404 | Blocked. |
| NRL Monterey NAAPS aerosol | MIL | `nrlmry.navy.mil/aerosol/` 302 to generic page; `aerosol_web.cgi` 403 | No public feed. |
| NRL Tropical Cyclone Web | MIL | 200, single-page image app; no API | Image-only. |
| Air Force 557th Weather Wing | MIL | `weather.af.mil` redirects to CCE SSO login; `557weatherwing.af.mil`, `afwa.af.mil` do not resolve | CAC-gated. |
| NGA GEOnet Names Server | MIL | Connection timed out (HTTP 000) on every path, by researcher and lead; `www.nga.mil` reachable | Unreachable from this network. Reportedly excludes the US anyway *(search result)*. Re-test from another network if wanted. |
| NGA DTED | MIL | No public download confirmed | Level 1+ restricted; Level 0 availability unconfirmed. |
| Space-Track.org | MIL | 401 "You must be logged in" | Needs an account; CelesTrak covers it. |
| DMSP OLS night lights | MIL→GOV | NCEI download page 404; annual composites ended 2014 | Superseded by VIIRS. |
| NAVGEM | MIL→GOV | Works | No cloud cover; 0.5°; 20 MB files without index. |
| NOAA declination API | GOV | 400 without key | Needs a free key; local WMM is better. |
| NWS for cloud layers | GOV | No low/mid/high; visibility is a placeholder | Wrong tool for sky scoring (still used for alerts). |
| MET Norway nowcast | GOV | 422 "only available for the Nordic area" | Coverage. |
| ECMWF direct | GOV | Works | CCSDS packing, global files only, no visibility. Use via Open-Meteo or a relay. |
| GIBS WMS GetMap | GOV | 200 but blank images | Use WMTS. |
| NASA POWER | GOV | `-999` for recent days | Archive only. |
| NASA Black Marble via LAADS | GOV | File download 303 to login | Needs Earthdata login (owner sign-up); HDF5. Still the best candidate to build a bundled sky-brightness grid. |
| EOG (Mines) VIIRS composites | ACAD | Redirect to login | Needs registration; commercial terms unclear. |
| Falchi 2016 World Atlas | ACAD | Request form, 2.9 GB | **CC BY-NC 4.0** *(search result)* — not shippable in a sold app. |
| lightpollutionmap.info | OTHER | 200 "Please request a key" | Key and terms unknown. |
| djlorenz atlas | OTHER | PNG maps only | No licence; author asks maps not be presented as Bortle values. |
| NASA FIRMS | GOV | 400 "Invalid MAP_KEY"; public CSV header-only | Needs a free key. |
| Synoptic / MesoWest | OTHER | 401 "Invalid token" | Keyed. |
| AirNow | GOV | not probed | Keyed. |
| Clear Outside, Meteoblue, Astrospheric | OTHER | No API / paid / keyed | – |
| Environment Canada seeing | GOV | Page only; guessed data path 404 | No data endpoint found. |
| SWPC solar-wind JSON (old paths) | GOV | 404 | Moved; new paths not found. |
| Reddit public JSON | OTHER | 403 (researcher and lead, with and without a custom UA) | **Dead.** The current app's Reddit source no longer works. OAuth now needs approval *(search result)*. |
| Google Custom Search JSON API | OTHER | 403 | Closed to new customers, shutting down 2027-01-01 (Google's overview page). **The current app's Google source is a sunset item.** |
| Google Places API (New) | OTHER | 403 | Free monthly caps per SKU (5,000 Pro, 1,000 Enterprise) but a billing account is required *(not verified on Google's page)*. |
| Bing Web Search API | OTHER | DNS failure | Retired 2025-08-11. |
| Brave Search API | OTHER | 422 missing token | Free tier replaced by credits with a card *(search result)*. |
| Mojeek | OTHER | CAPTCHA | Paid, card required *(search result)*. |
| Flickr | OTHER | "Invalid API Key" | Key; a revenue-earning app is "commercial" and may carry fees. |
| Mapillary, Unsplash, Recreation.gov RIDB, GeoNames, OpenRouteService, OpenTopography | OTHER/GOV | 401/500/limit | Keys or usernames required. |
| 500px | OTHER | 302 to nothing | Dead. |
| Openverse | OTHER | Flaky; `bbox` ignored | No geo search. |
| Apple MapKit Server API | OTHER | not run | Needs a paid developer account *(search result)*. |
| OSRM public demo | OTHER | Works | "Reasonable, non-commercial use", 1 request/s. |
| Valhalla public | OTHER | Works | Policy not read; no reason to leave MapKit. |
| Open-Meteo elevation, OpenTopoData, Open-Elevation | OTHER | Work | Non-commercial or tight caps; Terrarium tiles do the job keylessly. |
| PVGIS horizon as primary | GOV | Works | Impossible 62° western horizon at Whitney; 7.5° steps. Cross-check only. |

---

## 4. Sky Index inputs

Scores remain "unknown is never guessed": a missing input drops its factor and adds a note, as today.

### 4.1 Window scores (forecast, per spot)

| Input | Sunrise / sunset (golden hour) | Blue hour | Night (stars, Milky Way, aurora) | Source (US / elsewhere) | Refresh |
|---|---|---|---|---|---|
| Sun altitude/azimuth, event times, twilight phases | ✓ | ✓ | ✓ (astronomical dark) | `IterAstro` (USNO in tests) | computed |
| **Terrain-adjusted** sunrise/sunset (when the sun actually clears the ridge) | ✓ | ✓ | – | Terrarium tiles / 3DEP grid + `IterAstro` | once per spot |
| Low cloud at the spot | ✓ (heavy penalty) | ✓ | ✓ | HRRR → GFS / GFS; MET Norway fallback | per model run (HRRR hourly, GFS 6-hourly) |
| Mid and high cloud at the spot | ✓ (bonus when broken, penalty when solid) | ✓ | ✓ (penalty) | same | same |
| Cloud **along the sun's azimuth**, 50–150 km out (is the horizon clear for light to reach the clouds?) | ✓ | – | – | same grid box, sampled toward the sun azimuth *(design inference; the 12 KB box already contains these points)* | same |
| Visibility | ✓ | ✓ | ✓ | HRRR/GFS VIS / GFS VIS (MET Norway has none) | same |
| Fog risk | ✓ (sunrise valley fog can be a bonus from above) | ✓ | ✓ | HRRR VIS + humidity + low cloud; MET Norway `fog_area_fraction`; NBM visibility probabilities (US, optional) | same |
| Precipitation probability / amount | ✓ | ✓ | ✓ | GFS/HRRR; NWS PoP (US) | same |
| Aerosol optical depth (colour boost when moderate, penalty when heavy) | ✓ | ✓ | ✓ (transparency) | HRRR AOTK / Open-Meteo CAMS (licence) | hourly / 12-hourly |
| Smoke (near-surface and column) | ✓ | ✓ | ✓ | HRRR MASSDEN + COLMD, HMS polygons / CAMS | hourly / daily |
| Humidity, wind (lens fog, long exposures) | minor | minor | ✓ | all forecast sources | per run |
| Moon altitude and illumination | – | ✓ (moonrise as a subject) | ✓ (penalty for brightness) | `IterAstro` | computed |
| Galactic centre altitude | – | – | ✓ | `IterAstro` | computed |
| Sky brightness (Bortle-like) | – | – | ✓ | **gap** — bundled VIIRS-derived grid proposed | static |
| Transparency | – | – | ✓ | proxy: AOD + humidity + high cloud *(design inference)* | per run |
| Aurora probability, Kp forecast | – | – | ✓ (high latitudes) | SWPC OVATION, Kp 3-day forecast | 30 min / 3 h |
| Satellite passes (ISS) | – | ✓ | ✓ | CelesTrak + SGP4 | every 2 h at most |

### 4.2 Real-time Sky Index (iOS trip mode, current position and next stop)

| Input | Source | Refresh | Notes |
|---|---|---|---|
| Observed cloud layers, visibility, weather at the nearest stations (including military airfields) | aviationweather.gov METAR (global) | every 5–10 min (obs about hourly + specials) | One `bbox` call covers the route corridor. |
| US station observations | NWS `/stations/{id}/observations/latest`, IEM ASOS 5-minute | 5–10 min | US only. |
| Short-range model for the next 0–3 h | HRRR f00–f03 via NOMADS filter (US); GFS (elsewhere) | hourly (HRRR), 6-hourly (GFS) | Same 12 KB box per stop. |
| Satellite cloud picture | GIBS WMTS GOES/Himawari tiles; EUMETSAT WMS (Europe); STAR sector JPEG (US, Wi-Fi only) | 10 min (GIBS ~30–40 min late) | Show the timestamp; it is not live. |
| Radar | IEM n0q tiles (US) | 5 min | None outside the US. |
| Aurora now | SWPC OVATION + Kp 1-minute | 5–30 min | 0.9 MB OVATION: fetch only when north/south of ~45° *(design inference)*. |
| Smoke now | HMS (daily) + HRRR f00 smoke | hourly | US/North America. |
| Sun/moon now | `IterAstro` | continuous | – |
| Drive time to the next stop | MapKit `MKDirections` | on movement | Combine with the window start time to give "leave by". |

Budget sketch *(inference)*: per stop per hour, one HRRR or GFS filter call (~12 KB), one METAR corridor call, a few tiles. Comfortably inside every published limit for one user; the shared-limit sources (Nominatim, MET Norway, Overpass, CelesTrak) are the ones to keep off the refresh loop.

---

## 5. Open decisions for the owner

1. **User-Agent contact.** NWS, MET Norway, Nominatim and Wikimedia ask for an app name and a contact (email or website) in the User-Agent; aviationweather.gov recommends a custom one. Probing used a generic string with no contact. Decide what the shipped app sends (a project web page is enough for most).
2. **Selling the app later.** Free tiers that forbid commercial use: **Open-Meteo** (forecast, air quality and elevation), **7Timer**, the **Falchi** light-pollution atlas, the **OSRM** demo. Recommendation: build on the public-domain NOAA path (NOMADS + one GRIB decoder) and MET Norway now, and keep Open-Meteo optional, so selling never forces a rewrite. If Open-Meteo is used while the app is free, note that ads or subscriptions would make it commercial.
3. **MET Norway proxy.** Their terms ask mobile apps to use a proxy and cap total traffic across all installs at 20 requests per second. Fine at small scale; needs a relay if the app grows.
4. **Public OSM servers.** Overpass and Nominatim are shared volunteer services; their policies discourage apps that rely on them at scale. Caching is required; self-hosting is the long-term answer.
5. **Drop dead discovery sources.** Reddit's public JSON returns 403 and Google Custom Search is shutting down on 2027-01-01. Decide whether to remove both or replace Reddit with an approved OAuth app (needs sign-up and Reddit's review; commercial use needs an agreement).
6. **Keys that would add value (all need the owner to sign up; none was requested):**
   * NPS API (free, US park data).
   * NASA Earthdata login (to download Black Marble once and build a bundled sky-brightness grid).
   * NASA FIRMS MAP_KEY (active fires).
   * GeoNames username (global gazetteer, CC BY, commercial allowed).
   * lightpollutionmap.info key (only if their terms allow commercial use).
   * Not needed: NOAA declination key (WMM runs locally), Space-Track (CelesTrak), OpenRouteService (MapKit).
7. **Licences to read before release:** EUMETSAT imagery policy for real-time Meteosat in an app; CelesTrak usage policy; Copernicus DEM licence (only if the COG route is chosen); IEM terms for radar tiles; Komoot Photon terms; Dark Sky places reuse.
8. **Light pollution.** There is no free, commercial-safe point source. Options: build a coarse grid from NASA VIIRS (CC0 per a third party; needs Earthdata login once), or ship without a sky-brightness number and show the GIBS night-lights layer as a picture.
9. **Foundation Models on a free team.** Apple's docs do not say whether on-device Foundation Models needs a paid team. Test on device before the "Ask" flow depends on it.

---

## Appendix: probe scripts

```
scripts/probes/lead-retests.sh            WMM zips, GNS, HRRR smoke via filter, EUMETSAT WMS, Swiss visibility by model
scripts/probes/military/                  usno-api, avwx-military-metar, celestrak, jtwc, fnmoc-navgem, nrl-naaps,
                                          afweather-557, nga-gns, spacetrack, dmsp-viirs, noaa-geomag (reads $NOAA_GEOMAG_KEY)
scripts/probes/weather/                   nws-gridpoint, nomads-hrrr-subset, aws-hrrr-gfs-range, ecmwf-open-data,
                                          open-meteo-layers, met-no-locationforecast, satellite-gibs-goes,
                                          radar-iem-mrms-opengeo, nasa-power-synoptic, grib2_templates.py
scripts/probes/sky/                       swpc-*, 7timer-astro-*, openmeteo-aq-*, hrrr-smoke-aws, hms-smoke-kml,
                                          geos-cf-opendap, gibs-night-lights, celestrak-*, usno-oneday
                                          (failure evidence: hms-smoke-geojson, swpc-solarwind, lpmap-query, firms-*,
                                          laads-blackmarble, eog-viirs-annual, nrl-naaps)
scripts/probes/terrain/                   usgs-epqs, usgs-3dep-imageserver, aws-terrarium.py, copernicus-cog,
                                          pvgis-horizon, usgs-gnis, wmm-coefficients, wmm-compute.py,
                                          noaa-declination, open-meteo-elevation, opentopodata, open-elevation, other-endpoints
scripts/probes/places/                    overpass, nominatim_photon, wikimedia, wikidata, reddit, inaturalist, usgs_gnis,
                                          nps_ridb, darksky_waymarked, search_engines, openverse, flickr_mapillary_unsplash
```

Several scripts hard-code today's date or model cycle; edit the date before re-running. Downloads default to `${TMPDIR:-/tmp}/iter-probes/` (override with `OUT=`).
