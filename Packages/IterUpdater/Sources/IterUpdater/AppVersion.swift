import Foundation

/// The marketing version plus the build number. Two builds of the same marketing version still order.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public var version: SemanticVersion
    public var build: Int

    public init(version: SemanticVersion, build: Int) {
        self.version = version
        self.build = build
    }

    /// CFBundleShortVersionString and CFBundleVersion; a missing or non-integer build counts as 0.
    public init?(bundle: Bundle) {
        guard let info = bundle.infoDictionary else { return nil }
        self.init(infoDictionary: info)
    }

    /// Reads `<bundle>/Contents/Info.plist` straight from disk. `Bundle(url:)` caches, and a bundle that was
    /// just replaced must be read fresh.
    public init?(infoPlistAt bundleURL: URL) {
        guard let info = Self.readInfoDictionary(ofBundleAt: bundleURL) else { return nil }
        self.init(infoDictionary: info)
    }

    public var description: String { "\(version) (\(build))" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.version != rhs.version { return lhs.version < rhs.version }
        return lhs.build < rhs.build
    }

    init?(infoDictionary info: [String: Any]) {
        guard let short = info["CFBundleShortVersionString"] as? String, let version = SemanticVersion(short) else {
            return nil
        }
        let build: Int
        if let string = info["CFBundleVersion"] as? String {
            build = Int(string.trimmingCharacters(in: .whitespaces)) ?? 0
        } else if let number = info["CFBundleVersion"] as? Int {
            build = number
        } else {
            build = 0
        }
        self.init(version: version, build: build)
    }

    static func readInfoDictionary(ofBundleAt bundleURL: URL) -> [String: Any]? {
        let plist = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = object as? [String: Any] else { return nil }
        return info
    }
}
