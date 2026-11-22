# Source fixtures

Real, complete responses recorded for the format decoders and adapters. Nothing is truncated or edited.
Other fixtures in this folder belong to other workers: `GRIB2/README.md` (NOMADS GRIB2) and `Geomag/` (WMM coefficients, MGRS reference).
`record.sh` re-records everything below (not GRIB2/ or Geomag/) and rewrites `manifest.tsv`; `Terrarium/make-reference.py` writes `Terrarium/reference.json`.

Test points: W = 36.5785,-118.2923 (Mount Whitney, US), S = 46.5586,8.5610 (Swiss Alps near the Gotthard).
Every request used `User-Agent: IterProbe/0.1 (data-source evaluation)`, no API key, no cookies. Times are UTC, 2026-11-22.
Sizes are bytes on disk. Request bodies for POST are form-encoded as `data=<query>`. The listed query string is the Overpass QL text.

## Fixtures

| File | Request | Fetched (UTC) | HTTP | Bytes | Licence / attribution |
|---|---|---|---|---|---|
| `MetNo/locationforecast-W.json` | `GET https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=36.5785&lon=-118.2923` | 2026-11-22T13:44:46Z | 200 | 65122 | CC BY 4.0 (also NLOD). Credit: "Data from MET Norway". |
| `MetNo/locationforecast-S.json` | `GET https://api.met.no/weatherapi/locationforecast/2.0/complete?lat=46.5586&lon=8.5610` | 2026-11-22T13:44:50Z | 200 | 64165 | CC BY 4.0 (also NLOD). Credit: "Data from MET Norway". |
| `AviationWeather/metar-W.json` | `GET https://aviationweather.gov/api/data/metar?ids=KO26,KBIH,KNID,KEDW&format=json` | 2026-11-22T13:44:54Z | 200 | 1610 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/metar-W.txt` | `GET https://aviationweather.gov/api/data/metar?ids=KO26,KBIH,KNID,KEDW&format=raw` | 2026-11-22T13:44:58Z | 200 | 278 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/taf-W.json` | `GET https://aviationweather.gov/api/data/taf?ids=KO26,KBIH,KNID,KEDW&format=json` | 2026-11-22T13:45:01Z | 200 | 4871 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/taf-W.txt` | `GET https://aviationweather.gov/api/data/taf?ids=KO26,KBIH,KNID,KEDW&format=raw` | 2026-11-22T13:45:05Z | 200 | 571 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/stationinfo-W.json` | `GET https://aviationweather.gov/api/data/stationinfo?ids=KO26,KBIH,KNID,KEDW&format=json` | 2026-11-22T13:45:08Z | 200 | 816 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/metar-S.json` | `GET https://aviationweather.gov/api/data/metar?ids=LSMM,LSMA,LSZC,LSZA,LSZL,LSME,LSZH,LIMC&format=json` | 2026-11-22T13:45:12Z | 200 | 3706 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/metar-S.txt` | `GET https://aviationweather.gov/api/data/metar?ids=LSMM,LSMA,LSZC,LSZA,LSZL,LSME,LSZH,LIMC&format=raw` | 2026-11-22T13:45:20Z | 200 | 590 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/taf-S.json` | `GET https://aviationweather.gov/api/data/taf?ids=LSMM,LSMA,LSZC,LSZA,LSZL,LSME,LSZH,LIMC&format=json` | 2026-11-22T13:45:24Z | 200 | 14200 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/taf-S.txt` | `GET https://aviationweather.gov/api/data/taf?ids=LSMM,LSMA,LSZC,LSZA,LSZL,LSME,LSZH,LIMC&format=raw` | 2026-11-22T13:45:27Z | 200 | 1284 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/stationinfo-S.json` | `GET https://aviationweather.gov/api/data/stationinfo?ids=LSMM,LSMA,LSZC,LSZA,LSZL,LSME,LSZH,LIMC&format=json` | 2026-11-22T13:45:31Z | 200 | 1599 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `AviationWeather/metar-bbox-W.json` | `GET https://aviationweather.gov/api/data/metar?bbox=36,-119,37,-117.5&format=json` | 2026-11-22T13:45:34Z | 200 | 409 | US government work, public domain. NOAA/NWS Aviation Weather Center; no endorsement by NOAA is implied. |
| `NWS/points-W.json` | `GET https://api.weather.gov/points/36.5785,-118.2923`; header `Accept: application/geo+json` | 2026-11-22T13:45:40Z | 200 | 3949 | US government work, public domain. National Weather Service; no endorsement by NOAA/NWS is implied. |
| `NWS/alerts-active-W.json` | `GET https://api.weather.gov/alerts/active?point=36.5785,-118.2923`; header `Accept: application/geo+json` | 2026-11-22T13:45:43Z | 200 | 234 | US government work, public domain. National Weather Service; no endorsement by NOAA/NWS is implied. |
| `NWS/stations-KBIH-observations-latest.json` | `GET https://api.weather.gov/stations/KBIH/observations/latest`; header `Accept: application/geo+json` | 2026-11-22T13:45:47Z | 200 | 4666 | US government work, public domain. National Weather Service; no endorsement by NOAA/NWS is implied. |
| `SWPC/ovation_aurora_latest.json` | `GET https://services.swpc.noaa.gov/json/ovation_aurora_latest.json` | 2026-11-22T13:45:50Z | 200 | 918526 | US government work, public domain. NOAA Space Weather Prediction Center; no endorsement implied. |
| `SWPC/planetary_k_index_1m.json` | `GET https://services.swpc.noaa.gov/json/planetary_k_index_1m.json` | 2026-11-22T13:45:54Z | 200 | 27925 | US government work, public domain. NOAA Space Weather Prediction Center; no endorsement implied. |
| `SWPC/noaa-planetary-k-index-forecast.json` | `GET https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json` | 2026-11-22T13:45:57Z | 200 | 6907 | US government work, public domain. NOAA Space Weather Prediction Center; no endorsement implied. |
| `USNO/oneday-W.json` | `GET https://aa.usno.navy.mil/api/rstt/oneday?date=2026-11-22&coords=36.5785,-118.2923&tz=-8` | 2026-11-22T13:46:00Z | 200 | 1269 | US government work, public domain. U.S. Naval Observatory; no endorsement implied. |
| `USNO/oneday-S.json` | `GET https://aa.usno.navy.mil/api/rstt/oneday?date=2026-11-22&coords=46.5586,8.5610&tz=1` | 2026-11-22T13:46:04Z | 200 | 1264 | US government work, public domain. U.S. Naval Observatory; no endorsement implied. |
| `USGS/epqs-W.json` | `GET https://epqs.nationalmap.gov/v1/json?x=-118.2923&y=36.5785&units=Meters&wkid=4326` | 2026-11-22T13:46:08Z | 200 | 164 | US government work, public domain. USGS 3DEP via The National Map; credit requested; no endorsement implied. |
| `Terrarium/terrarium-12-702-1600-W.png` | `GET https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/702/1600.png` | 2026-11-22T13:46:12Z | 200 | 142602 | Terrain Tiles, see "Terrarium attribution" below. |
| `Terrarium/terrarium-12-2145-1448-S.png` | `GET https://s3.amazonaws.com/elevation-tiles-prod/terrarium/12/2145/1448.png` | 2026-11-22T13:46:16Z | 200 | 135638 | Terrain Tiles, see "Terrarium attribution" below. |
| `Wikimedia/wikipedia-geosearch-W.json` | `GET https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=36.5785%7C-118.2923&gsradius=10000&gslimit=10&format=json` | 2026-11-22T13:47:47Z | 200 | 1269 | Wikipedia text CC BY-SA 4.0 (link and credit authors); titles and coordinates are facts. |
| `Wikimedia/commons-geosearch-W.json` | `GET https://commons.wikimedia.org/w/api.php?action=query&list=geosearch&gscoord=36.5785%7C-118.2923&gsradius=10000&gsnamespace=6&gslimit=10&format=json` | 2026-11-22T13:47:51Z | 200 | 1687 | Commons file titles and coordinates; each file has its own licence (see imageinfo). |
| `Wikimedia/commons-imageinfo-W.json` | `GET https://commons.wikimedia.org/w/api.php?action=query&generator=geosearch&ggscoord=36.5785%7C-118.2923&ggsradius=10000&ggsnamespace=6&ggslimit=3&prop=imageinfo&iiprop=url%7Cextmetadata&format=json` | 2026-11-22T13:47:55Z | 200 | 12614 | Per-file licences in the response (here CC0, CC BY-SA 3.0/4.0, CC BY 3.0); credit the per-file author. |
| `Wikimedia/wikipedia-geosearch-S.json` | `GET https://en.wikipedia.org/w/api.php?action=query&list=geosearch&gscoord=46.5586%7C8.5610&gsradius=10000&gslimit=10&format=json` | 2026-11-22T13:47:59Z | 200 | 1242 | Wikipedia text CC BY-SA 4.0 (link and credit authors); titles and coordinates are facts. |
| `Wikimedia/commons-geosearch-S.json` | `GET https://commons.wikimedia.org/w/api.php?action=query&list=geosearch&gscoord=46.5586%7C8.5610&gsradius=10000&gsnamespace=6&gslimit=10&format=json` | 2026-11-22T13:48:02Z | 200 | 1434 | Commons file titles and coordinates; each file has its own licence (see imageinfo). |
| `Wikimedia/commons-imageinfo-S.json` | `GET https://commons.wikimedia.org/w/api.php?action=query&generator=geosearch&ggscoord=46.5586%7C8.5610&ggsradius=10000&ggsnamespace=6&ggslimit=3&prop=imageinfo&iiprop=url%7Cextmetadata&format=json` | 2026-11-22T13:48:06Z | 200 | 25728 | Per-file licences in the response (here CC0, CC BY-SA 3.0/4.0, CC BY 3.0); credit the per-file author. |
| `Overpass/overpass-W.json` | `POST https://overpass-api.de/api/interpreter` body `data=[out:json][timeout:25];(nwr[tourism=viewpoint](around:6000,36.5785,-118.2923);node[natural=peak][name](around:6000,36.5785,-118.2923);node[waterway=waterfall](around:6000,36.5785,-118.2923););out center;` | 2026-11-22T13:48:57Z | 200 | 8610 | ODbL 1.0. (c) OpenStreetMap contributors. |
| `Overpass/overpass-S.json` | `POST https://overpass-api.de/api/interpreter` body `data=[out:json][timeout:25];(nwr[tourism=viewpoint](around:6000,46.5586,8.5610);node[natural=peak][name](around:6000,46.5586,8.5610);node[waterway=waterfall](around:6000,46.5586,8.5610););out center;` | 2026-11-22T13:49:41Z | 200 | 9079 | ODbL 1.0. (c) OpenStreetMap contributors. |

Also recorded:

| File | What |
|---|---|
| `MetNo/locationforecast-W.headers.txt`, `-S.headers.txt` | Response headers of the MET Norway calls (`Expires`, `Last-Modified`, `Date`, `Content-Type`). Same request and time as the JSON beside them. |
| `Terrarium/reference.json` | Pixel values and elevations at 20 positions per tile plus a whole-tile FNV-1a 64 checksum, from a pure-Python PNG decoder (`Terrarium/make-reference.py`, run with `python3 -I`). No network. |
| `manifest.tsv` | One row per request: file, fetch time, status, bytes, method, URL, body, headers. Tests check every row is HTTP 200 and matches the file size. |

The 307 KB NWS gridpoint forecast was deliberately not recorded. `SWPC/ovation_aurora_latest.json` is the real full file (918,526 bytes, global 1 degree grid), recorded whole.

## Terrarium attribution

The tiles are the Tilezen/Mapzen "joerd" terrain tile set on AWS Open Data. Its `docs/attribution.md` (fetched 2026-11-22 from the tilezen/joerd repository) lists the required credit; responsibility for following each provider's licence stays with the app:

```
* ArcticDEM terrain data DEM(s) were created from DigitalGlobe, Inc., imagery and funded under National Science Foundation awards 1043681, 1559691, and 1542736;
* Australia terrain data (c) Commonwealth of Australia (Geoscience Australia) 2017;
* Austria terrain data (c) offene Daten Oesterreichs - Digitales Gelaendemodell (DGM) Oesterreich;
* Canada terrain data contains information licensed under the Open Government Licence - Canada;
* Europe terrain data produced using Copernicus data and information funded by the European Union - EU-DEM layers;
* Global ETOPO1 terrain data U.S. National Oceanic and Atmospheric Administration
* Mexico terrain data source: INEGI, Continental relief, 2016;
* New Zealand terrain data Copyright 2011 Crown copyright (c) Land Information New Zealand and the New Zealand Government (All rights reserved);
* Norway terrain data (c) Kartverket;
* United Kingdom terrain data (c) Environment Agency copyright and/or database right 2015. All rights reserved;
* United States 3DEP (formerly NED) and global GMTED2010 and SRTM terrain data courtesy of the U.S. Geological Survey.
```

The two tiles here cover the US (3DEP/SRTM/GMTED: USGS credit) and the Swiss Alps (EU-DEM/SRTM/GMTED); an app that shows tiles anywhere should carry the whole list.

## Terrarium result

Decoded (ImageIO and pure Python, byte-identical): W pixel (nearest) 4412.371 m, bilinear 4412.951 m; S pixel 2106.957 m, bilinear 2106.750 m. USGS EPQS at W (1 m DEM): 4416.234 m. Terrarium z12 nearest minus EPQS = -3.863 m (a z12 pixel is about 30 m wide and smooths the summit; Whitney's published height is about 4421 m).

## Changes since SOURCES.md

- Overpass: 6 km radius (not 15 km) gives 36 features at W and 47 at S (SOURCES.md: 70 at W with 15 km). The first record run returned HTTP 502 for W twice (an initial try and one retry 30 s later); a re-run of only that folder (`ONLY=Overpass ./record.sh`) succeeded. S succeeded first time (SOURCES.md saw the 502 on S).
- aviationweather.gov: all eight requested Swiss and Italian stations reported (LSMM, LSMA, LSZC, LSZA, LSZL, LSME, LSZH, LIMC); KO26 reported a newer observation (13:35Z) than KBIH, KEDW, KNID (12:55-12:56Z). KNID's METAR had no wind or sky groups (`AUTO A3006 RMK AO2 SLPNO PWINO`), a real partial report worth a parser test. The TAF set is smaller than the METAR set at W: KO26 has no TAF (TAF list: KBIH, KEDW, KNID); KEDW's and KNID's TAFs are older amendments/corrections (issued 21 and 20 Nov). The `bbox=36,-119,37,-117.5` query (same box as SOURCES.md) returns only KO26; KBIH (37.37 N) lies outside the box.
- aviationweather.gov raw (`format=raw`) responses have no trailing newline after the last line.
- NWS: `/points` returned 200 with grid VEF/14,134 and `observationStations` as a URL (the nearest stations are not inline). KBIH was used for the latest observation (timestamp 12:56Z). No active alerts at W (empty `features`).
- SWPC: all three paths still work with the same shape (`ovation_aurora_latest.json` 918,526 bytes, was 919 KB).
- MET Norway: HTTP 200 as before; `Expires` is about 9 minutes after the fetch, and the file is about 65 KB per point.
- USNO: HTTP 200, same shape as before.
- USGS EPQS: 4416.2339 m, unchanged from SOURCES.md (4416.2).
- Terrarium z12: tile 702/1600 (W) and 2145/1448 (S); elevations 4412.4 and 2107.0 m as in SOURCES.md.
- Wikipedia/Commons: no changes seen; titles at W start with Smithsonian Institution Shelter, Whitney Classic, Mount Whitney; at S with Swiss Alps, Gotthard Pass, Lago di Lucendro.
