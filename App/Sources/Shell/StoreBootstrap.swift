#if os(macOS)  // Mac only: the direct-download build's updater and store location (the iOS app excludes these)
import Foundation
import SwiftData
import OSLog
import IterData

/// Opens the app's store. The direct (unsandboxed) build keeps it at `StoreLocation.directStoreURL()` and, once,
/// copies the old App Sandbox container's data there first; see `StoreLocation`. A sandboxed build (for example an
/// App Store build with the sandbox entitlement restored) keeps SwiftData's default location.
enum StoreBootstrap {
    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        // A test run never touches a real store: unsandboxed, SwiftData's default would be the file every other
        // unsandboxed app shares (`~/Library/Application Support/default.store`).
        if inMemory || AppLaunch.isRunningTests { return try IterSchema.makeContainer(inMemory: true) }
        if StoreLocation.isSandboxed() { return try IterSchema.makeContainer(inMemory: false) }

        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.dwjames.iter"
        // A throw here leaves no store at the new location, so the caller falls back to memory for this run and
        // the next launch tries again (an empty store created now would hide the old data for good).
        let moved = try StoreLocation.migrateFromSandboxContainer(bundleIdentifier: bundleIdentifier)
        if moved.didMigrate {
            AppLaunch.log.info("Copied data from the sandbox container: store \(moved.storeItems.joined(separator: ", "), privacy: .public); folders \(moved.supportItems.joined(separator: ", "), privacy: .public)")
        }
        let keys = StoreLocation.migratePreferencesFromSandboxContainer(bundleIdentifier: bundleIdentifier)
        if keys > 0 { AppLaunch.log.info("Copied \(keys) preferences from the sandbox container") }
        return try IterSchema.makeContainer(url: StoreLocation.directStoreURL())
    }
}

#endif
