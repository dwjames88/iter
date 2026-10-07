import Foundation

/// Which base map the user wants: Standard, Satellite (imagery) or Hybrid (imagery with labels). One choice for every
/// map in the app (Explore, Locations and the trip route maps, Mac and iOS), stored under `storageKey` (`@AppStorage`).
public enum MapStyleChoice: String, CaseIterable, Identifiable, Sendable {
    case standard, satellite, hybrid

    /// The one `UserDefaults` / `@AppStorage` key every map and the View menu read.
    public static let storageKey = "iter.map.style"
    public static let `default` = MapStyleChoice.standard

    public var id: String { rawValue }

    /// The choice stored as `raw`; anything missing or unknown is Standard.
    public init(stored raw: String?) {
        self = raw.flatMap(MapStyleChoice.init(rawValue:)) ?? .default
    }

    /// The saved choice in `defaults`.
    public static func current(in defaults: UserDefaults = .standard) -> MapStyleChoice {
        MapStyleChoice(stored: defaults.string(forKey: storageKey))
    }

    public func save(in defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.storageKey) }
}
