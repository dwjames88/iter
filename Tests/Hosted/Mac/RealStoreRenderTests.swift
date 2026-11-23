import AppKit
import Foundation
import SwiftUI
import Testing
import IterFeatures
import IterModel
import IterScreens
@testable import Iter

/// Renders the Mac app's screens over an explicit store file (for the cut-over dry run: the owner's store, migrated, as a
/// COPY). Skipped unless both are set; the test runner's environment comes from `TEST_RUNNER_`-prefixed variables:
///
///     TEST_RUNNER_ITER_RENDER_STORE_PATH=<path to Iter.store>   TEST_RUNNER_ITER_RENDER_OUT=<folder for the PNGs>
///     [TEST_RUNNER_ITER_RENDER_TRIP=<trip name>]                (default: the trip with the most stops)
///     ITER_DD=<derived data> scripts/test-mac.sh --only RealStoreRenderTests
///
/// Why this cannot reach the owner's real library: the store comes from `AppContainer.live` through `StorePlacement.resolve`.
/// `-IterStorePath` (here `LaunchOptions.storePath`) is honoured only when `isRealProcess` is false, that is, for any bundle id
/// but `com.dwjames.iter`, and for the real id only outside a test host. This host is the render copy
/// `com.dwjames.iter.render` (`Snapshot.requireRenderHost` refuses anything else), and `resolve` throws for a path inside the
/// real store's folder. Sample services replace every network adapter (`sampleData: true`), the location is fixed (no
/// permission), keys and preferences are in memory.
///
/// Output: light mode, window-sized (1280 x 820 pt at 2x), `all-trips.png`, `trip-builder.png`, `saved-places.png` in
/// `ITER_RENDER_OUT` only (never Design/). Offscreen, glass and maps do not draw (see Snapshot.swift).
@MainActor
@Suite(.enabled(if: RealStoreRenderEnvironment.isSet, "set ITER_RENDER_STORE_PATH and ITER_RENDER_OUT to run"))
struct RealStoreRenderTests {
    static let window = CGSize(width: 1280, height: 820)

    @Test func rendersAllTripsTripBuilderAndSavedPlaces() async throws {
        try Snapshot.requireRenderHost()
        let env = ProcessInfo.processInfo.environment
        let storePath = try #require(env["ITER_RENDER_STORE_PATH"])
        let out = URL(fileURLWithPath: try #require(env["ITER_RENDER_OUT"]), isDirectory: true)
        #expect(!out.standardizedFileURL.path.contains("/Design/"), "renders of a real library never go into Design/")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // The shell's composition, pointed at that store: a render bundle id, sample services, a fixed location.
        let options = LaunchOptions(storePath: storePath, sampleData: true, fixedLocation: Coordinate(latitude: 38.39, longitude: -109.87))
        let container = try AppContainer.live(options: options, bundleID: Bundle.main.bundleIdentifier, environment: env)
        let expected = URL(fileURLWithPath: storePath).standardizedFileURL.resolvingSymlinksInPath()
        #expect(container.store.placement == .file(expected), "the container must open the store it was given")
        #expect(container.dataMode == .sample)
        #expect(container.store.recovered == nil, "the store opened without falling back to recovery")

        let defaults = UserDefaults(suiteName: "iter.render.real.\(UUID().uuidString)")!
        let updates = UpdateController(updater: nil, defaults: defaults, presentsWindow: false)
        let shell = AppShell(container: container, smoke: SmokeSwitches(arguments: []), updates: updates)

        let trips = shell.library.trips
        #expect(!trips.isEmpty, "the store has no trips to render")
        let wanted = env["ITER_RENDER_TRIP"].flatMap { name in
            trips.first { $0.name == name } ?? trips.first { $0.name.localizedCaseInsensitiveContains(name) }
        }
        let trip = try #require(wanted ?? trips.max { $0.stopCount < $1.stopCount }, "no trip matches ITER_RENDER_TRIP")

        let screens: [(String, AppRoute)] = [("all-trips", .allTrips), ("trip-builder", .trip(trip.id)), ("saved-places", .savedPlaces)]
        for (name, route) in screens {
            let image = try await Snapshot.renderImage(MainWindow(shell: shell, route: route), appearance: .light, size: Self.window,
                                                       settle: .milliseconds(400), chrome: .titled)
            let pixels = try #require(Pixels(image))
            #expect(pixels.stats(x: 0, y: 0, w: image.width / 2, h: image.height / 2).hasContent, "\(name) looks blank")
            let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try data.write(to: out.appending(path: "\(name).png"))
        }
        // Counts only: no names in the log.
        print("rendered 3 screens; \(trips.count) trips, rendered trip has \(trip.stopCount) stops, \(shell.library.savedPlaces.count) saved places")
    }
}

enum RealStoreRenderEnvironment {
    static var isSet: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["ITER_RENDER_STORE_PATH"] != nil && env["ITER_RENDER_OUT"] != nil
    }
}
