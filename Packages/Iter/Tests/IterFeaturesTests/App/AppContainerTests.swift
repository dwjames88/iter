import Foundation
import Testing
import IterModel
import IterSources
import IterStore
import IterDiscovery
@testable import IterFeatures

private func scratch(_ label: String = "iter-features") throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(label)-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
@Suite("Composition root") struct AppContainerTests {
    static let render = "com.dwjames.iter.render"

    @Test func inMemoryLiveContainerBuildsWithoutTouchingDisk() throws {
        let fakeReal = try scratch().appending(path: "Real/Iter.store")
        let c = try AppContainer.live(options: LaunchOptions(inMemoryStore: true), bundleID: Self.render, environment: [:], realStoreURL: fakeReal)
        #expect(c.store.placement == .inMemory)
        #expect(c.store.activeURL == nil)
        #expect(c.dataMode == .live)
        #expect(c.location is InertLocationProvider)
        #expect(!FileManager.default.fileExists(atPath: fakeReal.deletingLastPathComponent().path))
        // The live adapters are registered, none of them has been asked for anything.
        let ids = Set(c.sources.map(\.id))
        #expect(ids.isSuperset(of: [.noaaNOMADS, .aviationWeather, .osmOverpass, .appleSearch, .worldMagneticModel, .mgrs, .nasaGIBS]))
        #expect(c.discovery.providers.gazetteers.map(\.descriptor.id).contains(.osmOverpass))
        #expect(c.streetLevel != nil)
    }

    @Test func nonRealCompositionNeverUsesTheSystemKeychainOrStandardDefaults() throws {
        let a = try AppContainer.live(options: LaunchOptions(inMemoryStore: true), bundleID: Self.render, environment: [:])
        let b = try AppContainer.live(options: LaunchOptions(inMemoryStore: true), bundleID: nil, environment: [:])
        try a.keyVault.setKey("secret-for-a", for: "test.key")
        #expect(a.keyVault.key(for: "test.key") == "secret-for-a")
        #expect(b.keyVault.key(for: "test.key") == nil)   // separate in-memory keychains, not a shared system one
        a.preferences.preferenceText = "waterfalls"
        #expect(UserDefaults.standard.string(forKey: Preferences.Keys.preferenceText) != "waterfalls")
        #expect(b.preferences.preferenceText == "")
    }

    @Test func realBundleIDInsideATestHostIsNotReal() throws {
        let fakeReal = try scratch().appending(path: "Real/Iter.store")
        let c = try AppContainer.live(options: LaunchOptions(), bundleID: StorePlacement.realBundleID,
                                      environment: ["XCTestConfigurationFilePath": "/x"], realStoreURL: fakeReal)
        #expect(c.store.placement == .inMemory)
        #expect(c.location is InertLocationProvider)
        #expect(!FileManager.default.fileExists(atPath: fakeReal.deletingLastPathComponent().path))
    }

    @Test func aPathInsideTheRealFolderIsRefused() throws {
        let realFolder = try scratch()
        let fakeReal = realFolder.appending(path: "Iter.store")
        let options = LaunchOptions(storePath: realFolder.appending(path: "copy.store").path)
        #expect(throws: AppContainerError.self) {
            try AppContainer.live(options: options, bundleID: Self.render, environment: [:], realStoreURL: fakeReal)
        }
        #expect(!FileManager.default.fileExists(atPath: fakeReal.path))
    }

    @Test func aScratchFilePlacementOpensThereWithBackupsBesideIt() throws {
        let fakeReal = try scratch().appending(path: "Real/Iter.store")
        let dir = try scratch()
        let url = dir.appending(path: "Scratch.store")
        let c = try AppContainer.live(options: LaunchOptions(storePath: url.path), bundleID: Self.render, environment: [:], realStoreURL: fakeReal)
        #expect(c.store.placement == .file(url.standardizedFileURL.resolvingSymlinksInPath()))
        #expect(c.store.activeURL?.lastPathComponent == "Scratch.store")
        #expect(c.store.activeURL != fakeReal)
        #expect(c.store.recovered == nil)
        #expect(c.library.trips.all().isEmpty)
        c.library.trips.create(name: "Scratch", startDay: LocalDay(year: 2027, month: 1, day: 1), dayCount: 1)
        c.library.flush()
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "Scratch.store").path))
        #expect(!FileManager.default.fileExists(atPath: fakeReal.deletingLastPathComponent().path))
    }

    @Test func fixedLocationAndSampleDataSwitches() throws {
        let c = try AppContainer.live(options: LaunchOptions(arguments: ["-IterInMemoryStore", "YES", "-IterLocation", "38.5,-109.5", "-IterSampleDataEnabled", "YES"]),
                                      bundleID: Self.render, environment: [:])
        #expect(c.dataMode == .sample)
        #expect(c.location is FixedLocationProvider)
        #expect(c.location.current == Coordinate(latitude: 38.5, longitude: -109.5))
        #expect(c.sources.contains { $0.id == SampleConditions.sourceID })
    }

    @Test func seedTripAddsTheSampleLibraryToAScratchStore() throws {
        let c = try AppContainer.live(options: LaunchOptions(arguments: ["-IterInMemoryStore", "YES", "-IterSeedTrip", "YES"]),
                                      bundleID: Self.render, environment: [:])
        #expect(c.library.trips.values().contains { $0.name == SampleLibrary.tripName })
    }

    @Test func recoveryNoticeIsANoOpInMemory() throws {
        let c = try AppContainer.test()
        c.markRecoveryNoticeShown()
        #expect(c.store.recovered == nil)
    }

    @Test func debugActionsRefuseTheRealStore() throws {
        let c = try AppContainer.test(seed: true)
        c.store.placement = .file(AppContainer.defaultRealStoreURL)
        #expect(throws: DebugActionError.refusedOnRealStore) { try c.resetLibrary() }
        #expect(throws: DebugActionError.refusedOnRealStore) { try c.seedSampleTrip() }
        #expect(!c.library.trips.all().isEmpty)   // untouched
    }

    @Test func resetLibraryEmptiesAScratchStore() throws {
        let c = try AppContainer.test(seed: true)
        #expect(!c.library.trips.all().isEmpty)
        try c.resetLibrary()
        #expect(c.library.trips.all().isEmpty && c.library.places.savedPlaces().isEmpty)
        #expect(c.library.folders.list(kind: .trips).isEmpty && c.library.folders.list(kind: .locations).isEmpty)
        try c.seedSampleTrip()
        #expect(c.library.trips.all().count == 3)
    }

    @Test func discoveryReflectsASourceToggleOnTheNextRead() throws {
        let c = try AppContainer.live(options: LaunchOptions(inMemoryStore: true), bundleID: Self.render, environment: [:])
        #expect(c.discovery.providers.gazetteers.map(\.descriptor.id).contains(.osmOverpass))
        c.preferences.disabledSources.insert(.osmOverpass)
        #expect(!c.discovery.providers.gazetteers.map(\.descriptor.id).contains(.osmOverpass))
        #expect(!c.discovery.providers.boundaries.map(\.descriptor.id).contains(.osmOverpass))
        c.preferences.disabledSources.remove(.osmOverpass)
        #expect(c.discovery.providers.gazetteers.map(\.descriptor.id).contains(.osmOverpass))
    }
}
