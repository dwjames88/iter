# Testing Iter (milestone 1)

**The app:** `build/Iter.app` in this folder. `scripts/run.sh` builds it and opens it, and `scripts/test.sh` runs every test. Iter needs macOS 26 or later; this Mac runs 27.

## Before you start

**Weather is off until you give Iter a forecast source, and that is expected.** Iter has three: Apple Weather (WeatherKit), OpenWeather and Windy. WeatherKit only works for an app signed by a **paid** Apple Developer Program team that has WeatherKit switched on for the app's ID. This Mac signs with "a free Personal Team", which is free, and Xcode has no Apple ID signed in. OpenWeather and Windy need only an API key, so they work with a free team (see "Turning on forecasts without WeatherKit" below). With none of the three working, every screen shows **"No forecast"** with the specific reason ("Weather isn't enabled for this build…", "Needs an API key"), along with the real sun and moon times. That honest state is part of what you are testing.

To see scores now, turn on **Debug ▸ Use Sample Weather**. The scores then come from made-up weather, and the screens are labelled "Sample data".

**To turn real weather on** (once you have a paid membership):
1. In Xcode, open **Settings ▸ Accounts**, click **+** and sign in with the Apple ID of the paid Developer Program team.
2. At developer.apple.com, go to **Account ▸ Certificates, Identifiers & Profiles ▸ Identifiers**. Click **+**, choose **App IDs ▸ App**, enter the description "Iter" and the explicit Bundle ID `com.dwjames.iter`.
3. On that App ID, tick **WeatherKit** on the **Capabilities** tab and again on the **App Services** tab, then click **Save**. Allow up to 30 minutes for it to take effect.
4. In `project.yml`, change `DEVELOPMENT_TEAM: VF945J28YU` to your paid team's ID (shown in the top right of the developer site).
5. Run `scripts/run.sh --weatherkit`. This adds the WeatherKit entitlement and lets Xcode create the provisioning profile.
6. Iter ▸ Settings ▸ Weather should now show "Working · last update …" under Apple Weather.

## Turning on forecasts without WeatherKit

Details, limits and licences for each provider are in [docs/DATA-PROVIDERS.md](docs/DATA-PROVIDERS.md).

**OpenWeather** (scores with total cloud only):
1. Sign up at https://home.openweathermap.org/users/sign_up.
2. Subscribe to **One Call by Call** from the One Call 3.0 page or the pricing page. 1,000 calls a day are free. Whether a payment card is needed for that was not confirmed, so read what the sign-up asks for.
3. On the **Billing plan** tab of your account, set the daily limit to 1,000 or below, so you are never charged.
4. Copy your key from https://home.openweathermap.org/api_keys. A new key can take up to 2 hours to activate; "Key rejected" in that time is normal.

**Windy** (scores with low, mid and high cloud):
1. Go to https://api.windy.com/keys and create a **Point Forecast** key.
2. A Testing key is accepted, but Iter will not score from it, because Windy shuffles its data. Settings says "Testing key: Windy's data is shuffled, so Iter won't score from it". Elsewhere the reason reads "Windy's testing key returns shuffled data, so Iter won't score from it." You need a Professional key for real scores.

**Paste the key into Iter.** Open **Iter ▸ Settings ▸ Weather**. Under **Forecast source**, set the picker labelled **Use** to "OpenWeather" (or "Windy"). Optionally set **If it fails, try** to another provider (the default is "None"). In that provider's own section, paste the key into the **API key** field ("Paste your key") and click **Save** (or press Return). Its status line should read "Working · last update 19:40" (your time); until then it reads "Needs an API key" or "Checking…". Once a key is saved the field says "Saved in Keychain. Paste to replace" and a **Remove** button appears. Windy's section also has **Key type** (Testing, Professional) and **Model** ("Best for the spot", "GFS everywhere"). Each key provider shows "Calls today 0 of 800" (400 for Windy) with a stepper for the daily cap, and a **Get a key** link. The key goes to your login Keychain (service "com.dwjames.iter.weather"). It is never written to the repo, to defaults or to a log.

**What to expect.**
* Every screen that shows a forecast or a score names its source ("OpenWeather · updated 19:40"; in lists without the time, for example "Windy · GFS"), with the provider's attribution. A fallback is named too: "OpenWeather (Apple Weather unavailable)". Expanding a window on the spot page lists footnotes for what the provider could not supply.
* OpenWeather gives total cloud only. Reasons talk about cloud cover, and confidence is one step lower for golden hour and blue hour.
* OpenWeather has hourly data for 48 hours. Beyond that, scores come from daily summaries and carry low confidence.
* Windy is 3-hourly, interpolated to hours, so confidence drops sooner (24 hours rather than 36 for "high"). Windy has no rain probability; Iter uses the rain amount and says so.
* Iter never makes more than 800 OpenWeather or 400 Windy calls in a UTC day. Settings shows the count. At the cap the status line reads "Daily cap reached (800 of 800)" and screens say "Iter's daily limit for OpenWeather is reached, to stay inside the free allowance. Forecasts resume tomorrow or raise the cap in Settings."

**Development switches.** Instead of Settings you can supply a key for one run with an environment variable (`ITER_OPENWEATHER_KEY`, `ITER_WINDY_KEY`) or a launch argument:

```
open build/Iter.app --args -ITER_OPENWEATHER_KEY <your key>
```

`open` does not pass environment variables to the app, so use the launch argument with `open`. Either one overrides the Keychain, and Settings replaces the key field with a read-only row saying where the key in use came from: "From environment (ITER_OPENWEATHER_KEY)" or "From launch argument".

**When a change takes effect.** Changing anything in Settings ▸ Weather (either picker, key type, model, a cap, saving or removing a key) drops every loaded forecast, and every open screen fetches again with the new setup; saving a key also checks that provider. **Light ▸ Refresh Forecasts (⌘R)** is narrower: it re-requests only the forecasts that failed (no key, key rejected, cap reached, offline), and leaves the ones that loaded alone. The ⌥⌘R Retry on a spot page does the same for that spot.

Apple Intelligence (the Scout and "Explain") needs Apple Intelligence switched on in **System Settings ▸ Apple Intelligence & Siri**. It is on and working on this Mac.

## A guided tour (about 20 minutes)

1. **Open the app.** Run `scripts/run.sh`, or double-click `build/Iter.app`. You land on **All Trips**. The trip comes first because the plan makes the trip the home of the app. With no trips you see one **New Trip** button with three templates directly under it.
2. **Start from a template.** Click **Canyon Country**. A 4-day trip opens in the builder, with its days and stops on the left and the route on the right.
3. **Read a stop.** Each stop's headline is a backward schedule: "Leave 05:54 · park 06:50 · set up by 07:00". Under it you'll find the session (one control: Sunrise, Sunset, the blue hours or Night), the walk-in time ("walk-in unknown" where Iter doesn't know it), the set-up time, and the light for that window. With weather off, the light reads "No forecast" and gives the reason, but every time on the page is still exact.
4. **Watch the connectors.** Between two stops you see the MapKit drive time and distance. If a drive cannot fit between one stop's light and the next, the connector turns violet and says how short you are ("Drive doesn't fit: 2 hr, 58 min short"). An **Overnight** divider separates the days.
5. **Break the order, then accept the suggestion.** Drag a sunrise stop below a sunset stop on the same day. The row warns "Out of order", and a banner offers **Reorder by light**. Click **Apply** to accept, or **Dismiss** to ignore it. Iter never reorders on its own.
6. **Undo everything.** Press ⌘Z. Every move, removal, rename, date change and delete can be undone; the Edit menu names the action ("Undo Move Stop"), and ⇧⌘Z redoes it.
7. **Move a stop to another day.** Drag it onto another day's header, or right-click it and choose **Move to Day ▸**. The drive times and schedule recalculate, with a small spinner while MapKit answers.
8. **Change the dates.** Choose **⋯ ▸ Change Dates…** and shorten the trip. Iter warns how many stops will move to the last day before it does anything.
9. **Turn on sample weather.** Choose **Debug ▸ Use Sample Weather**. Scores appear on every stop and the sidebar shows a "Sample data" banner. Note that a score always names its window ("Sunset · 73") and shows its confidence bars.
10. **Explore.** Press ⌘2. The map and the list show the 45 curated spots, each with the score for its best light on the chosen date. Pick a date with ⌘[ and ⌘], and choose what you shoot (Sunrise, Sunset, Blue hour, Night) from the toolbar or the **Light** menu. Filter and sort from the list header menu. The toolbar's **Windy** button opens windy.com in your browser at the map area you are looking at. Selecting a row selects its pin, and the other way round.
11. **Search Apple Maps.** Press ⌘F, type "Antelope Canyon" and press Return. Apple Maps results appear in their own section, labelled "Apple Maps", and can be saved or added to a trip like any spot.
12. **Add your own spot.** Press ⇧⌘N (or the Add Spot toolbar toggle), then click the map. A sheet opens with the pin on a small map, which you can drag to adjust. Iter fills in the place name and time zone. Pick a category and any best light, then save.
13. **Open a spot page.** Double-click Mesa Arch. The page leads with **When to go**: the best sunrise in the next 10 days, with its confidence and range ("Likely 72–100"). Below that are the 10-day outlook (fainter further out), the five windows of the day with their reasons (open a row to see each factor and its effect), the light timeline (hover to read any hour), the sun and moon arc with the classic view's direction, hour-by-hour weather with the source line ("Windy · GFS · updated 09:00") and the provider's attribution, a **Windy** section with **Open in Windy** (the map opens in your browser, because Windy's terms do not allow its map inside an app like this), and **Look Around** where Apple has imagery.
14. **Ask for an explanation.** On a scored window, click **Explain**. Apple Intelligence writes two or three plain sentences from the listed factors only, and it is labelled as written by Apple Intelligence.
15. **Add to a trip from the spot.** Use **Add to Trip ▸ Canyon Country ▸**. Each day in the menu shows that day's light at this spot, so the choice of day is a light decision.
16. **Scout with Apple Intelligence.** Press ⌘4 and try "Waterfalls near Portland, Oregon". You see real stages ("Searching near Portland, Oregon…"), elapsed time and **Cancel**. Every result is a real place from Apple Maps or Iter's curated list. The model's reason is labelled "Scout's note", and the Light Index (not the model) scores the light.
17. **Saved.** Press ⌘3. Saved curated spots and your own spots are in one list, with your own spots tagged "Added by you". Right-click to edit or delete your spot (undoable).
18. **Share a trip.** Back in the trip, use **Share** in the toolbar, or **Export…** to save a `.iter` file. Import it with **File ▸ Import Trip…** (⌘O) or by double-clicking the file; it arrives as a new trip.
19. **Settings.** Press ⌘, to set the default light, the temperature unit and the default set-up time. The Weather tab has the **Use** and **If it fails, try** pickers, then a section each for Apple Weather, OpenWeather and Windy with a status line, a key field (OpenWeather and Windy), the calls used today and a **Get a key** link. The Apple Intelligence tab shows its status.
20. **Light and dark.** Switch the Mac's appearance. Every screen follows it.

## The Debug menu

| Item | What it does |
|---|---|
| Use Sample Weather | Replaces Apple Weather with made-up but plausible weather (all six sky types over any 10 days) so scores can be tested. **Off by default.** While it is on, the sidebar says "Sample data" on every screen, and Settings ▸ Weather says so too. |
| Seed Sample Trip | Adds the Canyon Country trip starting tomorrow and opens it. |
| Reset All Data… | Deletes every trip and spot after asking. This cannot be undone. |

For screenshots, launch with `-IterSection explore|saved|scout|trips|trip` (`trip` = first trip) to open on that section (overriding the restored one) and `-IterAppearance light|dark` to force the appearance. Also `-IterSettingsTab general|weather|intelligence|about` to open the Settings window on that tab at launch, and `-IterSpot <curated spot id>` (for example `-IterSpot mesa-arch`) to open that curated spot's page. To supply a key for one run, see "Development switches" above.

## Keyboard

⌘N New Trip · ⇧⌘N Add Spot on Map · ⌘O Import Trip · ⌘F Find Spots · ⌘1 Trips · ⌘2 Explore · ⌘3 Saved · ⌘4 Scout · ⌘R Refresh Forecasts · ⌘[ / ⌘] previous / next day (Explore) · ⌘D Save spot · ⌘E Edit your spot · ⌘Z / ⇧⌘Z Undo / Redo · Delete removes the selected stop or spot · ⌘, Settings.

## Known gaps and rough edges

Most important first.

1. **No live weather call has been exercised.** WeatherKit needs a paid team (see above). The OpenWeather and Windy services were built and tested against fixtures that follow each provider's documented schema; none is a recorded response (`Packages/IterKit/Tests/IterServicesTests/Fixtures/README.md`). The WeatherKit mapping is written against the SDK and has not seen a real response either. Everything weather-related was tested with sample data, fixtures and the "not enabled" state. Real behaviour may differ in details such as null fields and units.
2. **Windy's logo is not shipped.** Windy's terms require its logo, unscaled and linked to windy.com, wherever its data appears. Iter shows the required text and a link only. This must be fixed before any release, and a Windy Testing key cannot be used for scores in any case.
3. **Whether OpenWeather's free allowance needs a payment card was not confirmed** from the pages read.
4. **The Scout is only as good as Apple Maps text search and the small on-device model.** Every place it returns is real (that is enforced), but it sometimes returns weak matches, such as a town called Forest Grove for "forest", or a suburban park. Its notes are now limited to what the place data says, so they can be bland. A request typically takes 12–25 seconds, occasionally longer.
5. **Not tested by hand:** drag and drop, map clicks (Add Spot), hover on the map, Look Around and Open in Maps were built and compiled but could not be exercised without using the screen. Please try them first.
6. **Times follow your Mac's clock format.** On a 24-hour Mac you will see "17:25" rather than "5:25 PM".
7. **Light Index weights are heuristics** ("estimated from forecast data"), and confidence thresholds have no verification study behind them yet. A score past about three days out is shown with a range and low confidence.
8. **Today's passed windows** show "This window has passed" rather than jumping to tomorrow on Explore. Saved rows do switch to tomorrow, labelled "Tomorrow".
9. **No spot photos.** The prototype's Wikipedia photos are gone (they are not licensed for a paid app). Look Around stands in where Apple has imagery.
10. **Not in this milestone** (see `docs/ROADMAP.md`): iCloud sync and shared trips, offline trip packs, weather swap, Now mode, Night (red) mode, widgets, the iPhone app and its Live Activity, calendar and GPX export, the paywall.

## Tests

- `scripts/test.sh` runs the package tests (`swift test`: domain, light engine, astronomy against USNO, JPL and Meeus reference values, store and undo, services, view models) and the app's hosted tests (`xcodebuild test`).
- `ITER_LIVE=1` (MapKit and WeatherKit) and `ITER_LIVE_AI=1` (Scout and explainer) run the live checks: `cd Packages/IterKit && ITER_LIVE=1 ITER_LIVE_AI=1 swift test`. With `ITER_LIVE=1` and an OpenWeather or Windy key (environment, launch argument or Keychain), the live provider checks run too (`--filter "Weather live"`); without a key they are skipped. They spend real calls from your daily allowance. The provider mapping, cache, budget and router tests use fixtures and fakes and need no key; the fixtures follow each provider's documented schema and are not recorded responses.
- `scripts/snapshots.sh` renders every screen and state to `Design/snapshots/` in light and dark at two sizes. Nothing appears on screen while it runs.
