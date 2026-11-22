# Discovery fixtures: provenance

Recorded on 2026-10-09 with `curl` and the Iter User-Agent (`Iter/dev (photography trip planner; https://github.com/dwjames88)`).
No keys, cookies or account details were used or are present. Overpass data is OpenStreetMap, ODbL; Wikipedia and Wikivoyage text is CC BY-SA.

| File | What it is |
| --- | --- |
| `overpass-peaks-glacier.json` | **Real** Overpass reply for `node[natural~"^(peak\|volcano)$"][name]` in bbox 48.2,-114.5,49.0,-113.2 with `out center tags`, **trimmed** from 274 elements to 33 (the four named in the tests, four west and three east of the park, and a spread of others), plus **one synthetic element** appended (`Fixture Ridge (synthetic ele test)`, `ele=10,466 ft`) to cover a feet-with-comma elevation. |
| `overpass-waterfalls-yosemite.json` | **Real**, untrimmed: named `waterway=waterfall` nodes and ways in bbox 37.70,-119.70,37.76,-119.50, `out center tags` (15 elements: Yosemite Falls upper and lower, Bridalveil Fall, Vernal Fall, Nevada Fall and others, some without `ele`). |
| `overpass-boundary-glacier.json` | **Real** relation 1242641 (Glacier National Park, `boundary=protected_area`) from `out geom`, with each of the nine outer ways **decimated** from 2,089 vertices to 198 (about every 8th to 40th point, endpoints kept so the ways still join into one closed ring). Not survey-grade: edges are straightened by up to a few hundred metres. |
| `wikipedia-geosearch-glacier.json` | **Real** `list=geosearch` reply around Logan Pass (48.6966,-113.7184, 10 km, `gslimit=50`), **trimmed** to the nearest 25 results. |
| `wikipedia-extracts-glacier.json` | **Real** `prop=extracts\|coordinates\|pageprops` reply for three page ids (Logan Pass, Clements Mountain, Mount Oberlin), untrimmed. |
| `wikivoyage-glacier-see.json` | **Real** `action=parse&prop=wikitext` reply for "Glacier National Park (Montana)", **trimmed** to the "See" section. |
| `reddit-search-glacier.json` | **Hand-built**, not recorded: Reddit refused unauthenticated requests from `curl` (HTTP 403 and a block page). It follows Reddit's documented listing shape (`kind: Listing`, `data.children[].kind: t3`, `data` with `title`, `selftext`, `score`, `over_18`, `permalink`). Titles and text are invented for the tests; place names are real. One child is `over_18` and must be ignored. |
| `google-customsearch-glacier.json`, `google-customsearch-error.json` | **Hand-built** from the Custom Search JSON API's documented response shape. No key was used. The engine id is the placeholder `EXAMPLE_ENGINE_ID`. |
