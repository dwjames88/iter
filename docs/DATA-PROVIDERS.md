# Data providers

Where Iter's forecasts come from, what each source can and cannot give the Light Index, and what each one costs, permits and requires. Provider facts were read from the providers' own pages and checked 5 October 2026. Prices and terms change; check the linked pages before relying on them.

Iter has three forecast providers (plus Sample Data, which is for testing only). The user chooses a primary in Settings ▸ Weather and, optionally, a fallback ("If it fails, try"). `WeatherRouter` tries them in order. If the primary fails and the fallback answers, the forecast records which source failed, and every screen says so ("OpenWeather (Apple Weather unavailable)"; the reason is not claimed beyond that). If all fail, the primary's error is shown.

> **Note, 2026-10-06: attribution lives in Settings.** At the owner's instruction ("Take off the attribution, put that in settings."), provider attribution (the Apple Weather mark and legal link, "Weather data © OpenWeather", Windy's "Contains data from the Windy database" and windy.com link, and "Light Index modified from forecast data") is shown only in Settings ▸ Weather ("Data Sources and Attribution") and Settings ▸ About, no longer beside forecasts on Explore, Trip builder, Saved, Scout or the spot page. Screens keep a plain source line ("OpenWeather · updated 06:29"). The provider terms as documented below (OpenWeather's licence, Apple's WeatherKit rules and Windy's API terms) ask for attribution where the data is shown. The owner chose Settings-only for this test build. **This must be revisited before any release.**

## What the Light Index needs

The Light Index scores five windows a day from hourly data: cloud cover (total, and low, mid and high layers where known), precipitation, visibility, and the sun and moon from Iter's own astronomy. Each provider fills some of these and leaves the rest unknown. Unknown is never guessed. A missing input drops its factor and adds a note to the score (`ScoreNote`), and some lower confidence.

| | Apple Weather | OpenWeather One Call 3.0 | Windy Point Forecast v2 |
|---|---|---|---|
| Cloud layers (low, mid, high) | Yes (cloud cover by altitude) | No | Yes |
| Total cloud | Yes | Yes (the only cloud field) | No: derived from the layers |
| Precipitation chance | Yes | Yes (`pop`) | No |
| Precipitation amount | Yes | Yes (mm/h, rain and snow) | Yes (3-hour accumulation) |
| Visibility | Yes | Capped at 10 km | Yes |
| Hourly steps | Hourly | Hourly for 48 h, then daily | The model's own step (3-hourly for GFS), interpolated to hours |
| Reach | About ten days | 48 h hourly, then 8 days of daily summaries | Per model run (GFS reaches furthest) |
| Needs | Paid Developer Program team (WeatherKit) | User's API key | User's API key (Professional for real scores) |

Apple Weather's column is from the app's own notes (`docs/ARCHITECTURE.md`, `AppleWeatherService`). This page is mostly about the two key-based providers.

## Apple Weather

* The best fit for the Light Index: cloud by altitude, visibility and precipitation chance, hourly.
* Works only for an app signed by a paid Apple Developer Program team with WeatherKit on its App ID. See [TESTING.md](../TESTING.md).
* Attribution: the Apple Weather mark and its legal page, required wherever its forecasts appear. This is WeatherKit's rule (currently shown in Settings only, see the 2026-10-06 note above).
* Cache: `CachedWeatherService`, an actor keyed by rounded coordinate.

## OpenWeather One Call 3.0

Source: <https://openweathermap.org/api/one-call-3>

Request: `GET https://api.openweathermap.org/data/3.0/onecall` with `lat`, `lon`, `exclude=current,minutely,alerts`, `units=metric` and `appid`. One call returns everything for a spot.

**What it gives.** Hourly data for 48 hours (cloud %, visibility, wind and gust, probability of precipitation, rain and snow mm/h, temperature, humidity, a condition code) and daily data for 8 days.

**What it cannot give, and what Iter does about it.**

* **Total cloud only.** There is no cloud by height. Iter scores golden hour and blue hour from total cloud with a lower ceiling than it allows with layers, adds the note "no cloud layers", and lowers confidence one step for those windows. Reasons talk about cloud cover, not "high cloud" or "low cloud".
* **48 hours of hourly data.** After that, Iter fills the hours from the daily summaries (cloud, probability, wind and humidity from the day, temperature interpolated through the day). These hours are marked `dailySummary`. Any window that uses one is scored with low confidence and carries the note "daily summary only".
* **Visibility is capped at 10 km.** The Light Index gives a small bonus above 12 km (up to 2 points at 20 km). OpenWeather can never earn it. A clear day still scores normally; it just cannot go past what 10 km earns.
* **No visibility at all** in the daily summaries. Those hours drop the visibility factor and add the note "no visibility".
* **Sunrise, sunset and moon phase.** The daily data has them. Iter keeps them as a cross-check and does not display them. All times and moon figures in the app come from Iter's own astronomy (`IterAstro`).
* **Rain and snow** are optional in the response. Absent means none.

**Condition symbols.** The `weather[0].id` code is mapped to Iter's condition names and SF Symbols (`WeatherConditionMapping`). An icon ending in `n` is night.

**Why some days score 5.** A score is a baseline of 60 plus signed points per factor, clamped to 5...100, and a golden-hour window with heavy low cloud falls below 5 on its own: 80% low cloud costs about 50 points, rain chance and short visibility cost another 10 to 35, and thick mid and high cloud about 10. The clamp then shows 5, and "Why this score" lists the raw factors (low cloud first, then precipitation, visibility), so their points can add up to more than the 55 lost. This is the intended floor, not a missing-data default. Missing data never lowers a score: a missing factor is dropped and noted ("no cloud layers", "no visibility", "daily summary only") with lower confidence, and days beyond the hourly range are filled from the daily summary. The sample data cycles through six sky regimes (clear, high cloud evening, overcast, rain, morning fog, partly cloudy), and overcast, rain and fog-at-sunrise days carry 78 to 100% low cloud, so they score 5 beside 66 to 87 for the others. OpenWeather has no cloud layers, so a real overcast day scores from total cloud: about 40 at 100% cloud before rain and visibility, and 5 only with heavy rain on top.

### Limits, licence and attribution (checked 5 October 2026)

* **Plan:** "One Call by Call". 1,000 calls a day are free. Calls over that cost 0.0015 USD each. Price page: <https://openweathermap.org/price>.
* **Daily cap:** set on the "Billing plan" tab of your OpenWeather account. Set it to 1,000 or below so the free allowance cannot be exceeded.
* **Licence:** ODbL. Commercial use is allowed. Visible attribution is required wherever the data appears. OpenWeather's recommended line is "Weather data © OpenWeather". Licence page: <https://openweathermap.org/full-price#licenses>. Iter shows that line, linking openweathermap.org, in Settings ▸ Weather and About (see the 2026-10-06 note above). The ODbL also allows Iter to keep the data, so the cache persists on disk.
* **One Call 4.0.** OpenWeather now recommends One Call 4.0 for new integrations. Its FAQ describes 4.0 with a default cap of 2,000 calls a day. Iter uses 3.0 because that is the version whose pages and schema were read for this work. Moving to 4.0 is on the [roadmap](ROADMAP.md).
* **Payment card: not confirmed.** Whether a payment card is needed for the free 3.0 allowance was not confirmed from the pages read. The price page says "Complete the billing form and confirm payment" for subscriptions. Check at sign-up before assuming it is free of card details.
* **Keys take up to two hours to activate** after creation. A 401 in that time is normal.

### Errors

HTTP 401 and 403 mean the key was rejected (wrong key, or no "One Call by Call" subscription). 429 means a limit was reached, and is shown like Iter's own cap. Any other status is shown as a provider failure with OpenWeather's own `message` (up to 200 characters, with the key removed). The same mapping applies to Windy.

## Windy Point Forecast v2

Source: <https://api.windy.com/point-forecast/docs>

Request: `POST https://api.windy.com/api/point-forecast/v2` with JSON `{lat, lon, model, parameters, levels: ["surface"], key}`. Parameters used: `temp`, `dewpoint`, `precip`, `wind`, `windGust`, `lclouds`, `mclouds`, `hclouds`, `rh`, `cbase`, `visibility`, `ptype`.

**What it gives.** A model forecast at a point, with cloud in three layers. This is the only key-based provider with cloud by height, so it is the one that matches Apple Weather for golden hour.

**What it cannot give, and what Iter does about it.**

* **No total cloud.** Iter derives it: total = 1 − (1 − low)(1 − mid)(1 − high), which assumes the layers overlap at random. It is an estimate, and it is said to be one. If a layer is null for an hour, the total uses the layers present (a lower bound) and the missing layer stays unknown for that hour.
* **No precipitation probability.** Windy gives `past3hprecip`, the accumulation over the preceding three hours. Iter spreads it evenly (value ÷ 3 mm for each of those hours). The Light Index then scores precipitation from the amount and adds the note "precipitation from amount".
* **3-hourly steps.** GFS reports every three hours; other models may step more finely. Iter reads the step from each response's timestamps and interpolates linearly to hourly. It never extrapolates: an hour needs both neighbours. These hours are marked `interpolated`; the high-confidence limit falls from 36 hours to 24, and the score carries the note "three-hourly steps".
* **No ECMWF.** The Point Forecast API does not offer it, although the Windy map does. Iter says "GFS" or "ICON-EU", never "Windy's ECMWF".
* **Condition symbols** are derived, because Windy has no condition code: precipitation of 0.1 mm/h or more (drizzle under 0.5 mm/h, otherwise rain, or snow for precipitation types 5, 7 and 8), then visibility under 1,000 m foggy and under 5,000 m haze, then the sky from cloud cover.
* **Units** come from the response's `units` object and are converted by name (`K`, `m*s-1`, `%`, `m`), never assumed. A field with an unknown unit is dropped. A missing field is unknown, not zero.

### Models and region

Settings ▸ Weather has "Best for the spot" (default) and "GFS".

| Where | Model | Box (approximate) |
|---|---|---|
| Europe | ICON-EU | 29.5–70.5 °N, 23.5 °W–62.5 °E |
| Contiguous United States | NAM CONUS | 24–50 °N, 125–66 °W |
| Everywhere else | GFS | global |

If a regional model answers 204 (no data) or 400, or has no cloud layers, Iter retries once with GFS. That retry is a second call and counts against the budget. The model that answered is stored on the forecast and shown ("Windy · ICON-EU").

### Limits, licence and attribution (checked 5 October 2026)

* **Testing tier:** free, 500 requests a day, "randomly shuffled and slightly modified data", for development only. The API terms say a trial key returns "forecasts for random coordinates" and may not be integrated into a production app.
* **Professional:** 990 € a year, 10,000 requests a day. Pricing: <https://api.windy.com/point-forecast/pricing>.
* **Terms** (effective 1 September 2023): <https://account.windy.com/agreements/windy-api-map-and-point-forecast-terms-of-use>.
  * You may not store or extract the weather data, or build databases from it. Hence Iter's Windy cache is memory only and is gone on quit.
  * Attribution: the Windy logo, unscaled and clickable to windy.com, plus "Contains data from the Windy database". Iter shows the text and a link to windy.com. **The logo asset is not shipped yet. That is a gap to close before any release** (see the [roadmap](ROADMAP.md)).
* **Testing keys are not used for scores.** In Settings you declare the key type (Testing is the default). With a Testing key, or if the response carries a top-level `warning`, Iter makes the call, reads it, and then refuses it with "Testing key: data is shuffled, not used for scores". Nothing is cached, so each request with a testing key costs one call.

## The Windy map

Iter does not embed the Windy map.

* The embeddable widget is "not allowed to be used by weather apps and other commercial websites" (windy.com Terms of Use, section "Windy and Webcam embeddable widget").
* The Map Forecast API trial is for development only, and its keys are bound to web domains, which a native app does not have.

Instead the spot page (a "Windy" section after Hour by hour, button **Open in Windy**) and Explore (a **Windy** toolbar button) open windy.com in the browser: at the spot (`https://www.windy.com/?LAT,LON,ZOOM`, coordinates to 3 decimal places, zoom 9) or at the map's centre (zoom from the visible latitude span, about log2(360 / span), clamped to 3...11). `WindyLink` builds the URLs. An in-app map would need a Map Forecast Professional licence that permits a native app. It is on the roadmap as a question, not a plan.

## Cache policy

Both key-based providers use `ProviderCache`, one per provider, keyed by the coordinate rounded to two decimal places (about 1 km) and the UTC hour in which the forecast was fetched. Concurrent requests for one spot share one fetch. Errors are not cached.

| | OpenWeather | Windy |
|---|---|---|
| Valid for | Through the end of the next clock hour: a forecast fetched at 14:05 is served until 16:00 (so 1 to 2 hours) | 3 hours from the fetch (GFS runs four times a day) |
| Kept | On disk as JSON under `Application Support/Iter/ForecastCache/openweather/`, so a relaunch does not refetch | Memory only. The terms forbid storing the data |
| Old entries | Pruned as the hours pass | Gone on quit |

## Call budget

`CallBudget` counts calls per UTC day, per provider, and refuses at a cap. It is checked before the network call, and a cache hit never reaches it. At the cap the provider throws "Daily cap reached (800)" without calling.

| | Default cap | Free allowance |
|---|---|---|
| OpenWeather | 800 | 1,000 a day |
| Windy | 400 | 500 a day (Testing tier) |

Counts are kept in UserDefaults (they are counts, not secrets). The caps are adjustable. Settings shows "Calls today 12 / 800".

### Expected daily calls

Forecasts are not polled. A forecast for a place is held in memory for the session and is requested again only on launch, on a settings change (provider, key, model, cap), by Refresh Forecasts (⌘R), which retries places whose forecast failed, or by Retry on a spot page. The cache then answers any request made in the same or the next clock hour.

For OpenWeather:

* Opening Explore with the 45 curated spots costs at most 45 calls, once in an hour. Opening it again in that hour, or the next, costs none.
* A day of normal use (Explore a few times, some spot pages, a trip with several stops) is roughly 50 to 200 calls.
* The cap stops it at 800 whatever happens, below the 1,000 free.

These are estimates from how the app asks for forecasts, not measurements. The live calls have not been exercised yet (see [TESTING.md](../TESTING.md)).

For Windy, a spot in an uncovered region costs two calls (regional model, then GFS), and a Testing key is never cached. The 400 cap sits below the 500 Testing allowance.

## Keys

Keys are never in the repo, in UserDefaults or in logs. Order of lookup: environment variable (`ITER_OPENWEATHER_KEY`, `ITER_WINDY_KEY`), then launch argument (`-ITER_OPENWEATHER_KEY <key>`), then the login Keychain (service `com.dwjames.iter.weather`, account `openWeather` or `windy`). Settings says where the key in use came from ("From environment (ITER_WINDY_KEY)" or "From launch argument") and then shows no key field. See [TESTING.md](../TESTING.md) for steps.

## Fixtures

The weather fixtures in `Packages/IterKit/Tests/IterServicesTests/Fixtures/` are **documented-schema, not recorded**. No live call was made to produce them. Each is built from the provider's published documentation, with synthetic values, and the file names say "documented". `Fixtures/README.md` lists each file and what is invented.

To record real ones, with a key set (environment, launch argument or Keychain):

```
cd Packages/IterKit && ITER_LIVE=1 swift test --filter "Weather live"
```

The live tests call the real providers and check basic shape. Save the raw response bodies as new fixtures, replace the "documented" files, and update `Fixtures/README.md`. A Windy Testing key will answer with shuffled data, so record Windy only with a Professional key.
