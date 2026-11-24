# Roadmap

What is next, in rough order, and why. Items marked **owner** need something only the owner can do (a login, a decision, a device). The rebuild itself is described in [docs/rebuild/BLUEPRINT.md](rebuild/BLUEPRINT.md) and what is built is in [ARCHITECTURE.md](ARCHITECTURE.md).

## Do first: check the rebuild on real devices

- **The first-look checklist** in [TESTING.md](../TESTING.md) and [TESTING-iOS.md](../TESTING-iOS.md). No headless run could check glass, map pins, drag and drop, menus, the Live Activity, background location, Lock Screen notification actions, real network sources, Apple Intelligence or the first real-store launch. Anything found goes here as a fix.
- **A dry run of the iPhone store migration on a copy.** The cut-over plan tries the Mac store on a copy before the real launch. A copy of the iPhone store has not been tried by anything in this documentation. **Owner:** make an iPhone backup (Xcode ▸ Devices and Simulators ▸ Download Container) so a copy can be opened and the trips compared.

## Data

- **Light pollution from NASA Black Marble.** Today there is no light-pollution source, and the sky index leaves Bortle out and says so. The plan is a coarse grid made from NASA Black Marble night-lights data, bundled in the app. Downloading it needs a free NASA Earthdata login, once. **Owner:** create the login. This also enables the Bortle factor for night scores. The Falchi atlas cannot be used because its licence is non-commercial.
- **A seeing and transparency proxy.** No free commercial-safe seeing source exists. A rough proxy from aerosol, humidity and high cloud could fill the seeing factor. Lower priority than light pollution.
- **Reddit through OAuth.** Reddit no longer allows keyless use. If the owner applies for free Reddit API credentials, Reddit can return as a text source. The extension point exists (Find already lists Reddit as unavailable and says why). **Owner:** apply for credentials, and decide where the key lives (Settings ▸ Keys, in the Keychain).
- **Read the EUMETSAT and IEM licences.** Both imagery sources are built but off by default, and never stored on disk, until their terms are read. EUMETSAT covers Meteosat imagery for Europe and Africa. IEM covers US radar. If the terms allow it for this app, turn them on by default. **Owner:** read or approve.
- **Draw the imagery.** NASA GIBS cloud imagery, EUMETSAT and IEM radar have adapters, and a GIBS true-colour descriptor was checked with a real tile, but nothing draws them. The cloud imagery layer needs an `MKMapView`-based map or a future MapKit API, because SwiftUI's `Map` has no tile-overlay content.
- **Old keys.** The key vault copies the old OpenWeather, Windy and Google keys at launch (real process only), but no source uses them. Delete the old items and this code if no keyed source is planned.
- **Satellite passes (ISS, Starlink).** Researched with CelesTrak, not built. A fun extra for night windows. CelesTrak blocks repeat downloads within two hours, so it must cache.
- **Recheck the feeds.** Fixtures were recorded on one day in November 2026. Feed formats and limits change, so rerun the live suite (`ITER_LIVE=1`, see TESTING.md) before relying on a source, and after any NOAA change.

## The sky index

- **Calibrate the new score factors against real shoots.** Every factor added in the rebuild (precipitation, visibility, moon, aerosol and smoke, terrain, humidity, wind, Milky Way core) is a first guess. They need real shoots with a note of how the light was, to adjust the points. A "How did it go?" check-in after a stop would collect that.
- **Aurora thresholds.** The Kp-by-latitude table is rough. Replace it with a better geomagnetic latitude model if aurora matters.

## Sync and sharing

- **Bonjour peer sync (blueprint phase 10b).** **Not built.** The `IterSync` target is a placeholder. File-based sync works today: **Send to iPhone** and **Send Library**, with a merge by id. Peer sync would add a Mac advertising on the local network, a six-digit pairing code, a pre-shared key in each Keychain, and change sets since the last sync. It needs the local-network and Bonjour keys in the iOS Info.plist and a runtime prompt. Build it when passing files around gets tiresome.
- **Move the merge into `IterSync`, or delete the target.** The merge lives in `IterStore` today. When peer sync is built, `IterSync` becomes real. If it is not going to be, remove the placeholder.
- **A share extension** (send a link or a place to Iter from Safari or Maps). Listed as later in the blueprint. Optional.
- **No iCloud sync.** It needs CloudKit, which a free team does not have. See the paid-membership item below.

## Look and use

- **A red night mode.** A dim red palette for use in the field at night. It was planned as a token mode from the start. The design tokens already separate colour from use, so this is mostly a palette and a setting.
- **Calendar and GPX export** of a trip's sessions, and spots along the drive.
- **A Mac widget.** Judged low value in the blueprint.
- **Offline base map.** Still not possible: MapKit has no way to download tiles. Pinned and active trips already keep their conditions, drive times and images.
- **CarPlay: not planned.** No CarPlay category fits. The Live Activity reaches the CarPlay Dashboard by itself.

## If the developer team is paid (decision D1)

Every provisioning profile on this Mac showed a 365-day life, which is unusual for a free Personal Team. **Owner:** check developer.apple.com ▸ Membership. If the membership is paid, these become possible:

- **WeatherKit** as one more forecast provider (the provider protocols already allow it).
- **Push updates for the Live Activity**, so Go can update while Iter is suspended.
- **Time-sensitive notifications** that break through a Focus.
- **CloudKit sync** between the Mac and the iPhone.

If the team is free, none of these are possible and the app is already designed for that.

## Housekeeping

- **Release notes and version.** The rebuild has not been given a version number or released. Cut it with `scripts/release.sh` ([DISTRIBUTION.md](DISTRIBUTION.md)) once the first-look checklist is done.
