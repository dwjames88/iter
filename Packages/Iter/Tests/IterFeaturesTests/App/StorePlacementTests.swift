import Foundation
import Testing
@testable import IterFeatures

@Suite struct StorePlacementTests {
    private let real = URL(fileURLWithPath: "/Users/someone/Library/Application Support/Iter/Iter.store")

    @Test func realAppOpensRealStore() throws {
        let p = try StorePlacement.resolve(bundleID: "com.dwjames.iter", options: LaunchOptions(), environment: [:], realStoreURL: real)
        #expect(p == .file(real))
    }

    @Test func realAppIgnoresStorePath() throws {
        let p = try StorePlacement.resolve(bundleID: "com.dwjames.iter", options: LaunchOptions(storePath: "/tmp/x.store"),
                                           environment: [:], realStoreURL: real)
        #expect(p == .file(real))
    }

    @Test func renderCopyNeverReachesRealStore() throws {
        #expect(try StorePlacement.resolve(bundleID: "com.dwjames.iter.render", options: LaunchOptions(), environment: [:],
                                           realStoreURL: real) == .inMemory)
        #expect(throws: StorePlacement.Refusal.self) {
            try StorePlacement.resolve(bundleID: "com.dwjames.iter.render", options: LaunchOptions(storePath: real.path),
                                       environment: [:], realStoreURL: real)
        }
        let scratch = URL(fileURLWithPath: "/tmp/iter-scratch/Iter.store")
        #expect(try StorePlacement.resolve(bundleID: "com.dwjames.iter.render", options: LaunchOptions(storePath: scratch.path),
                                           environment: [:], realStoreURL: real) == .file(scratch.standardizedFileURL.resolvingSymlinksInPath()))
    }

    @Test func testHostWithRealIDStaysInMemory() throws {
        let p = try StorePlacement.resolve(bundleID: "com.dwjames.iter", options: LaunchOptions(),
                                           environment: ["XCTestConfigurationFilePath": "/x"], realStoreURL: real)
        #expect(p == .inMemory)
    }

    @Test func swiftTestHasNoBundleID() throws {
        #expect(try StorePlacement.resolve(bundleID: nil, options: LaunchOptions(), environment: [:], realStoreURL: real) == .inMemory)
    }

    @Test func parsesLaunchSwitches() {
        let o = LaunchOptions(arguments: ["Iter", "-IterInMemoryStore", "YES", "-IterLocation", "37.77,-122.42", "-IterSection", "trip"])
        #expect(o.inMemoryStore)
        #expect(o.fixedLocation?.latitude == 37.77)
        #expect(o.section == "trip")
        #expect(LaunchOptions(arguments: ["-IterLocation", "200,0"]).fixedLocation == nil)
    }
}
