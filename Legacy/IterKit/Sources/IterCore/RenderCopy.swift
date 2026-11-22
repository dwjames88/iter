import Foundation

/// A render or test copy of the Mac app is built with a different bundle id (`scripts/render.sh`, `scripts/snapshots.sh`
/// set `ITER_BUNDLE_ID=com.dwjames.iter.render`). Such a copy is ad-hoc signed and runs next to the user's real app, so it
/// must never touch the user's Keychain, Application Support/Iter, caches or the old sandbox container.
public enum RenderCopy {
    /// The shipped app's bundle id. Anything else is a render or test copy.
    public static let shippedBundleID = "com.dwjames.iter"

    /// True when `bundleID` is not the shipped app's. A process with no bundle id (a bare tool) counts as the shipped app,
    /// so only a real, differently named app bundle is isolated.
    public static func isRenderCopy(bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return bundleID != shippedBundleID
    }

    /// Whether this process is a render copy.
    public static var isCurrent: Bool { isRenderCopy(bundleID: Bundle.main.bundleIdentifier) }

    /// A fresh throwaway folder for anything a render copy would otherwise write under the user's folders.
    public static func scratchDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "IterRender-\(name)-\(getpid())", directoryHint: .isDirectory)
    }
}
