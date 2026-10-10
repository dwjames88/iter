#if canImport(AppKit)
import AppKit
#endif
import Foundation
import SwiftUI
import OSLog
import IterCore
import IterDesign
import IterData
import IterServices
import IterFeatures

/// Launch-time switches. `-IterInMemoryStore YES` runs on a throwaway store; `-IterSmokeTest YES` walks the main
/// view models once and logs what it found (used by the background smoke test; no UI interaction needed).
/// `-IterSection explore|locations|trips|trip` (`trip` = the first pinned trip, else the most recent; `saved` is the old name of Locations, `scout` of Explore) opens the main window on that sidebar section, overriding the restored
/// selection; `-IterAppearance light|dark` forces the app's appearance. Both exist for screenshot testing.
/// `-IterSettingsTab general|weather|intelligence|search|about|licence` opens the Settings window on that tab at launch, and
/// `-IterSpot <curated spot id>` (for example `mesa-arch`) opens Explore with that spot's page pushed. Also for screenshots.
/// `-IterSeedTrip conflict` and `-IterTripDay <n>` are described on their properties.
/// `-IterShowLicensing YES` shows Settings ▸ Licence (and makes `-IterSettingsTab licence` work). Without it nothing about licensing is visible.
/// `-IterAsk <text>` makes Explore run an Ask with that text at launch (the field holds the text, the Ask section answers it).
/// `-IterScoutStub unavailable|results` replaces the Apple Intelligence scout with a stub, for screenshots only and honoured only with
/// `-IterInMemoryStore YES` (see `makeScout`): `unavailable` reports Apple Intelligence as turned off, `results` answers with three real
/// curated spots near the asked-about map region and canned notes.
/// `-IterDiscoveryStub results|off` (with `-IterInMemoryStore YES`) replaces Discovery for screenshots: `results` answers from canned
/// places with their sources (see `StubDiscovery`; Glacier, Moab and Yosemite areas, Reddit reported unavailable), `off` runs without it.
/// `-IterSearchHere YES` runs Search Here once, when the map's first camera has settled. With `-IterScoutStub results` the stub also
/// proposes a few real landmark names inside the visible region, so Search Here shows Ask rows.
/// `-IterShowLayoutGrid YES` draws the 8 pt layout grid and lane guides over lists and cards (Debug ▸ Show Layout Grid).
/// `-IterOnboarding show|skip`: `show` opens the first-run guide at launch even if it was seen; `skip` never opens it. Without
/// the flag the guide opens once on a first launch (not under tests, a smoke run or `-IterInMemoryStore YES`).
/// `-IterWindowSize WxH` (for example `1280x820`, `960x652`, or `min` for the window minimum) sets the main window's
/// content size once at launch; absent, the window opens as usual. Sizes below the minimum are raised to it.
/// `-IterMapCamera lat,lon,distanceKm` (for example `20,10,14000` for the whole globe) puts the Explore map's camera there
/// and keeps it there (the model's fit requests are ignored), for screenshots of the globe. `-IterDaylightDate <ISO 8601>`
/// (for example `2026-03-20T12:00:00Z`) shades day and night for that moment instead of now.
/// `-IterDragScript spot-to-folder|stop-reorder` (with `-IterInMemoryStore YES`) runs the drop handlers a drag calls, in process,
/// logging the model before and after to stdout (`spot-to-folder` needs `-IterSeedLibrary YES -IterSection locations`,
/// `stop-reorder` needs `-IterSeedTrip YES -IterSection trip`). `-IterResizeScript lo,hi` steps the window width from lo to hi and
/// back every 16 ms, then holds at 1100/1280/1440/1600/1800 (inside the range). `-IterCaptureWindow <dir>` writes PNGs of the
/// window (`cacheDisplay`, so MapKit may be blank) at each script milestone. `-IterScriptKeepOpen YES` keeps the app open after.
enum AppLaunch {
    static let log = Logger(subsystem: "com.dwjames.iter", category: "app")

    static var inMemoryStore: Bool { UserDefaults.standard.bool(forKey: "IterInMemoryStore") }
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil }
    /// Opens the first-run guide per `-IterOnboarding` and the rules above. Call once the window has appeared.
    @MainActor static func presentOnboardingIfWanted(_ model: AppModel) {
        guard !isRunningTests, !smokeTest else { return }
        switch UserDefaults.standard.string(forKey: "IterOnboarding")?.lowercased() {
        case "show": model.onboarding.present(at: .welcome)
        case "skip": break
        default: if !inMemoryStore { model.onboarding.presentIfNeeded() }
        }
    }
    static var smokeTest: Bool { UserDefaults.standard.bool(forKey: "IterSmokeTest") }

    static var sectionName: String? { UserDefaults.standard.string(forKey: "IterSection") }
    static var section: SidebarItem? {
        switch sectionName {
        case "explore": .explore
        case "locations", "saved": .locations   // `saved` is the old name of Locations
        case "scout": .explore   // the Scout screen is part of Explore now
        case "trips": .trips
        default: nil
        }
    }
    /// `-IterSeedLibrary YES`: a pinned trip, trip folders, location folders and saved spots, for
    /// screenshots of the sidebar and Locations (see `LibrarySeed`). Honoured only with `-IterInMemoryStore YES`.
    static var seedLibrary: Bool { inMemoryStore && UserDefaults.standard.bool(forKey: "IterSeedLibrary") }
    /// `-IterTripFolder <name>`: opens the All Trips page on the trip folder with that name. For screenshots.
    static var tripFolderName: String? { UserDefaults.standard.string(forKey: "IterTripFolder") }
    /// `-IterNewFolderPrompt YES`: All Trips opens its New Folder prompt at launch. For screenshots.
    static var newFolderPrompt: Bool { UserDefaults.standard.bool(forKey: "IterNewFolderPrompt") }
    /// `-IterLocationFolder <name>`: selects the location folder with that name at launch.
    static var locationFolderName: String? { UserDefaults.standard.string(forKey: "IterLocationFolder") }
    static var settingsTab: SettingsTab? {
        switch UserDefaults.standard.string(forKey: "IterSettingsTab") {
        case "general": .general
        case "weather": .weather
        case "intelligence": .intelligence
        case "search": .search
        case "about": .about
        case "licence" where showLicensing: .licence
        default: nil
        }
    }
    /// `-IterShowLicensing YES`: Settings shows the Licence tab (Mac) or row (iPhone, iPad). Off by default: this build is free.
    static var showLicensing: Bool { UserDefaults.standard.bool(forKey: "IterShowLicensing") }
    static var spot: Spot? { UserDefaults.standard.string(forKey: "IterSpot").flatMap { CuratedSpots.spot(id: $0) } }
    /// `-IterSelectRow <spot id>` (for example `mesa-arch`): Explore selects that row, scrolls it into view once when it
    /// is first built, and so opens its place panel. For screenshots.
    static var selectRowID: String? { UserDefaults.standard.string(forKey: "IterSelectRow") }
    /// `-IterSearch <text>`: Explore runs that Apple Maps search at launch (screenshots of search results).
    static var searchText: String? { UserDefaults.standard.string(forKey: "IterSearch") }
    /// `-IterAddSpot "lat,lon,Name"`: Explore adds your own spot there at launch, through the same path as the spot
    /// editor's Save, and selects it. Honoured only with `-IterInMemoryStore YES`, so it never touches real data.
    static var addSpot: (coordinate: Coordinate, name: String)? {
        guard inMemoryStore, let raw = UserDefaults.standard.string(forKey: "IterAddSpot") else { return nil }
        let parts = raw.split(separator: ",", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        return (Coordinate(latitude: lat, longitude: lon), parts[2])
    }
    /// `-IterAsk <text>`: Explore puts that text to the ask engine at launch (screenshots of the Ask section).
    static var askText: String? { UserDefaults.standard.string(forKey: "IterAsk") }
    /// `-IterSearchHere YES`: Explore runs Search Here once, as soon as the map's first camera has settled. For screenshots.
    static var searchHere: Bool { UserDefaults.standard.bool(forKey: "IterSearchHere") }
    /// `-IterPanelScrolled YES`: the place panel opens already scrolled to its lower half (When to go at the top). For screenshots.
    static var panelScrolled: Bool { UserDefaults.standard.bool(forKey: "IterPanelScrolled") }
    /// Open today in the outlook when the panel's model is built (`-IterOutlookOpen YES`). Debug and snapshot aid.
    static var outlookOpen: Bool { UserDefaults.standard.bool(forKey: "IterOutlookOpen") }
    /// `-IterSeedTrip YES|conflict`: seeds the sample trip (see `IterApp`); `conflict` also reverses day 2.
    enum TripSeed { case sample, conflict }
    static var seedTrip: TripSeed? {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "IterSeedTrip")?.lowercased() == "conflict" { return .conflict }
        return defaults.bool(forKey: "IterSeedTrip") ? .sample : nil
    }
    /// `-IterTripDay <n>` (1-based): the trip builder opens with that day selected. For screenshots.
    static var tripDay: Int? {
        guard let day = Int(UserDefaults.standard.string(forKey: "IterTripDay") ?? ""), day >= 1 else { return nil }
        return day - 1
    }
    /// `-IterMapCamera lat,lon,distanceKm`: see the type's comment.
    static var mapCamera: (coordinate: Coordinate, distanceMetres: Double)? {
        guard let raw = UserDefaults.standard.string(forKey: "IterMapCamera") else { return nil }
        let p = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 3, p[2] > 0 else { return nil }
        return (Coordinate(latitude: p[0], longitude: p[1]), p[2] * 1000)
    }
    /// `-IterDaylightDate <ISO 8601>`: the moment the maps shade as night and day. Absent, now.
    static var daylightDate: Date? {
        UserDefaults.standard.string(forKey: "IterDaylightDate").flatMap { try? Date($0, strategy: .iso8601) }
    }
    /// `-IterShowLayoutGrid YES`: the layout grid overlay is on (same key as Debug ▸ Show Layout Grid). For screenshots.
    static var showLayoutGrid: Bool { UserDefaults.standard.bool(forKey: "IterShowLayoutGrid") }
    static var appearanceName: String? { UserDefaults.standard.string(forKey: "IterAppearance") }

    /// The `-IterWindowSize` request in points, or nil. `min` is the window minimum.
    static var windowSize: CGSize? {
        guard let raw = UserDefaults.standard.string(forKey: "IterWindowSize") else { return nil }
        if raw == "min" { return CGSize(width: IterSize.mainWindowMinWidth, height: IterSize.windowMinHeight) }
        let parts = raw.lowercased().split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
    }


    /// The Apple Intelligence scout over MapKit and the curated set. It reports its own availability at run time.
    ///
    /// For screenshots only: with `-IterInMemoryStore YES`, `-IterScoutStub unavailable` returns a stub that reports
    /// `.appleIntelligenceNotEnabled`, and `-IterScoutStub results` returns a stub that answers every request with three
    /// real curated spots nearest the map region and canned notes. Never used with the real store.
    static func makeDiscovery() -> AppModel.DiscoveryChoice {
        guard inMemoryStore, let stub = UserDefaults.standard.string(forKey: "IterDiscoveryStub") else { return .live }
        switch stub {
        case "results": return .stub(StubDiscovery())
        case "off": return .off
        default: return .live
        }
    }

    static func makeScout() -> (any Scouting)? {
        if inMemoryStore, let stub = UserDefaults.standard.string(forKey: "IterScoutStub") {
            switch stub {
            case "unavailable": return StubScout(answers: false)
            case "results": return StubScout(answers: true)
            default: break
            }
        }
        return AppleIntelligenceScout(search: MapKitPlaceSearch(), geocoder: MapKitGeocoder(), drives: MapKitDriveTimes(),
                               curated: CuratedSpots.all)
    }
}

#if os(macOS)
/// Reaches the hosting window to enforce the content minimum (so no resize can clip a column) and to apply
/// `-IterWindowSize` once.
struct MainWindowConfigurator: NSViewRepresentable {
    let minSize: CGSize
    /// The window's content width, kept current as the window resizes.
    @Binding var contentWidth: CGFloat

    final class Coordinator {
        var appliedLaunchSize = false
        var observer: NSObjectProtocol?
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let minSize = minSize
        let contentWidth = $contentWidth
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.contentMinSize = minSize
            if coordinator.observer == nil {
                let publish: @MainActor () -> Void = { [weak window] in
                    guard let window else { return }
                    let width = window.contentLayoutRect.width
                    if abs(width - contentWidth.wrappedValue) > 0.5 { contentWidth.wrappedValue = width }
                }
                coordinator.observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
                    MainActor.assumeIsolated { publish() }
                }
                publish()
            }
            guard !coordinator.appliedLaunchSize, let size = AppLaunch.windowSize else { return }
            coordinator.appliedLaunchSize = true
            window.setContentSize(CGSize(width: max(size.width, minSize.width), height: max(size.height, minSize.height)))
        }
    }
}
#endif

/// The screenshot scout behind `-IterScoutStub` (see `AppLaunch.makeScout`). Not a model: canned notes on real spots.
private struct StubScout: Scouting {
    let answers: Bool

    func availability() -> ScoutAvailability { answers ? .available : .appleIntelligenceNotEnabled }

    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] {
        try await scout(request, near: nil, progress: progress)
    }

    /// Search Here: a few real landmark names inside the region (Search Here confirms each with the place search).
    func proposePlaces(in region: GeoRegion, areaName: String?) async throws -> [RegionProposal] {
        guard answers else { throw ScoutError.unavailable(.appleIntelligenceNotEnabled) }
        try await Task.sleep(for: .milliseconds(300))
        return StubPlaces.proposals(in: region)
    }

    func scout(_ request: String, near area: GeoRegion?, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] {
        guard answers else { throw ScoutError.unavailable(.appleIntelligenceNotEnabled) }
        let centre = area?.center
        let nearest = CuratedSpots.all
            .sorted { a, b in
                guard let centre else { return a.name < b.name }
                return centre.distance(to: a.coordinate) < centre.distance(to: b.coordinate)
            }
            .prefix(3)
        progress(.understanding)
        try await Task.sleep(for: .milliseconds(300))
        progress(.searching("the map"))
        try await Task.sleep(for: .milliseconds(300))
        progress(.writing)
        let notes = [
            "Open view toward the horizon, so the first and last light reach the whole scene.",
            "A classic frame for this kind of request; the light skims the foreground at the edges of the day.",
            "Quieter than the headline spots nearby, with room to work and several angles.",
        ]
        return nearest.enumerated().map { index, spot in
            ScoutSuggestion(id: spot.id, spot: spot, provenance: .curated, why: notes[index % notes.count],
                            suggestedWindow: nil, driveSeconds: TimeInterval(1800 + index * 1500))
        }
    }
}

