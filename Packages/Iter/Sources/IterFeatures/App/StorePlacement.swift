import Foundation

/// Where the library store lives for this process. This is the one place that can return the owner's real store, and it
/// does so only for the real app's bundle id, outside any test host, with no test switch. Everything else (the render copy
/// `com.dwjames.iter.render`, test bundles, previews, `swift test`) gets an in-memory store or an explicit path that is
/// refused if it points into the real store's folder. Structural, not a convention: a render or test configuration cannot
/// name the real path even by mistake.
public enum StorePlacement: Sendable, Equatable {
    case inMemory
    case file(URL)

    /// The real app's bundle id on this platform: the only id allowed to open the real store. The iPhone app keeps
    /// `com.dwjames.iter.ios` (the owner's phone has its library under it); the Mac app is `com.dwjames.iter`.
#if os(iOS)
    public static let realBundleID = "com.dwjames.iter.ios"
#else
    public static let realBundleID = "com.dwjames.iter"
#endif

    public enum Refusal: Error, Equatable, Sendable {
        /// A non-real process asked for a path inside the real store's folder.
        case pathInsideRealStoreFolder(String)
    }

    /// True only for the real app's bundle id outside any test host. The one definition of "the real app": the store
    /// placement, the preferences suite and the Keychain all key off it.
    public static func isRealProcess(bundleID: String?, environment: [String: String]) -> Bool {
        let underTest = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
        return bundleID == realBundleID && !underTest
    }

    /// Decides the placement.
    /// - Parameters:
    ///   - bundleID: `Bundle.main.bundleIdentifier`.
    ///   - options: the parsed launch switches.
    ///   - environment: the process environment (test hosts are detected by `XCTestConfigurationFilePath`,
    ///     `XCTestBundlePath` or `XCTestSessionIdentifier`).
    ///   - realStoreURL: the owner's store (`StoreLocation.directStoreURL()` on the Mac).
    public static func resolve(bundleID: String?, options: LaunchOptions, environment: [String: String],
                               realStoreURL: URL) throws -> StorePlacement {
        let isReal = isRealProcess(bundleID: bundleID, environment: environment)
        if isReal {
            // The real app ignores -IterStorePath (it can never be pointed elsewhere by an argument) but honours the
            // in-memory switch, which only ever makes it safer.
            return options.inMemoryStore ? .inMemory : .file(realStoreURL)
        }
        guard !options.inMemoryStore, let path = options.storePath, !path.isEmpty else { return .inMemory }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.resolvingSymlinksInPath()
        let realFolder = realStoreURL.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        if url.path == realFolder || url.path.hasPrefix(realFolder + "/") { throw Refusal.pathInsideRealStoreFolder(url.path) }
        return .file(url)
    }
}
