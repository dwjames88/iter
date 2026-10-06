# Weather fixtures: provenance

**No live call was made to produce any file here. None is a recorded response.** Iter has no OpenWeather or Windy key
(and signing up for one is outside this task). Every fixture is built from the provider's published documentation, and
the file names say so ("documented").

| File | What it is |
| --- | --- |
| `openweather-onecall3-documented.json` | OpenWeather One Call 3.0 response. The documented example from https://openweathermap.org/api/one-call-3 (fetched 2026-10-05): `lat 40.12, lon -96.66, America/Chicago, timezone_offset -18000`, its `current` block, `hourly[0]` and `daily[0]` with the documented values. **Temperatures were converted from the example's Kelvin to °C** because Iter requests `units=metric`. The example is abbreviated with "..."; the rest (47 more hourly entries for 48 in total, 7 more daily for 8) is **synthetic**, written to the documented field list and types (including optional `wind_gust`, `rain.1h`, daily `moonrise`, `moonset`, `moon_phase`, `summary`). `minutely` and `alerts` are omitted because Iter excludes them. |
| `openweather-missing-fields-documented-schema.json` | Documented-schema response with fields absent: no `visibility`, no `pop`, no `rain`, no `daily`, one hour without `clouds` and one without `dt` (both must be dropped, not invented). |
| `openweather-error-401.json` | The documented error body shape `{cod, message}` (message text as shown in OpenWeather's FAQ for error 401). |
| `windy-gfs-documented-schema.json` | Windy Point Forecast v2 response written strictly to the documented schema (https://api.windy.com/point-forecast/docs): `ts` in milliseconds, 3-hourly (81 steps), a `units` object (`K`, `m*s-1`, `%`, `m`, `mm`), keys of the form `"lclouds-surface"`, `"wind_u-surface"`, `"past3hprecip-surface"`, with `null` in `cbase-surface` (no cloud base when clear) and in the first `past3hprecip-surface` step (no preceding accumulation). Values are **synthetic**. |
| `windy-null-layers-documented-schema.json` | Nine steps with null cloud layers at some steps, no `rh-surface` (humidity must come from temperature and dew point) and all-null visibility. |
| `windy-testing-warning-documented-schema.json` | The GFS fixture plus a top-level `"warning"` string, the shape the lead's spec says a testing-tier response may carry. The warning TEXT is invented; only its presence is relied on. |
| `windy-error-400.json` | A `{message}` body for a 400. |

Tests that need a different sky (overcast golden hour, bright clear night) edit these JSON files in code before mapping.
When a key exists, the opt-in live tests (`ITER_LIVE=1`) can be used to record real responses and replace these files.
