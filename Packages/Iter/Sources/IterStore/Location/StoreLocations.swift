import Foundation

/// Where the store and its backups live. Everything takes an injected directory or home, so tests never touch the
/// user's real folders. The Mac's direct-download location and the one-time sandbox move are in `StoreLocation`.
public enum StoreLocations {
    /// iOS: the EXPLICIT URL `<Application Support>/default.store`, which is what SwiftData's default resolved to in the
    /// old iOS app, so a later change of SwiftData's default cannot move the store. There is no App Group.
    /// `applicationSupportDirectory` is injected (the app passes `FileManager.url(for: .applicationSupportDirectory...)`).
    public static func iOSStoreURL(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appending(path: "default.store", directoryHint: .notDirectory)
    }

    /// `<Application Support>/Iter/Backups/`, on both platforms.
    public static func backupsDirectory(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appending(path: "Iter/Backups", directoryHint: .isDirectory)
    }

#if os(macOS)
    /// Mac: `~/Library/Application Support/Iter/Backups/`.
    public static func backupsDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        backupsDirectory(applicationSupportDirectory: home.appending(path: "Library/Application Support", directoryHint: .isDirectory))
    }
#endif
}
