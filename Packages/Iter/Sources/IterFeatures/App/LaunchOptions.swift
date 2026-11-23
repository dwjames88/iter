import Foundation
import IterModel

/// The launch switches the shells read (ported from the old `AppLaunch`). Parsed once from the process arguments, which
/// is where `-Key value` pairs land (they also reach `UserDefaults`' argument domain, but this type never reads defaults,
/// so a stale preference can never switch a real launch into a test mode or back).
///
/// | Switch | Effect |
/// |---|---|
/// | `-IterInMemoryStore YES` | Opens an in-memory store. No file is read or written. |
/// | `-IterStorePath <path>` | Opens the store at this path (render and test copies only; ignored by the real app id). |
/// | `-IterSampleDataEnabled YES` | Conditions, Find and routing come from the built-in sample services, not the network. |
/// | `-IterLocation lat,lon` | A fixed location; no permission is ever asked. |
/// | `-IterSection find\|trips\|places\|trip` | The section to open on. |
/// | `-IterSeedTrip YES` | Adds the sample trip (and opens it with `-IterSection trip`). |
public struct LaunchOptions: Sendable, Equatable {
    public var inMemoryStore: Bool
    public var storePath: String?
    public var sampleData: Bool
    public var fixedLocation: Coordinate?
    public var section: String?
    public var seedTrip: Bool
    /// Every argument, for switches a shell adds of its own.
    public var arguments: [String]

    public init(inMemoryStore: Bool = false, storePath: String? = nil, sampleData: Bool = false, fixedLocation: Coordinate? = nil,
                section: String? = nil, seedTrip: Bool = false, arguments: [String] = []) {
        self.inMemoryStore = inMemoryStore
        self.storePath = storePath
        self.sampleData = sampleData
        self.fixedLocation = fixedLocation
        self.section = section
        self.seedTrip = seedTrip
        self.arguments = arguments
    }

    /// Parses `-Key value` pairs. Unknown switches are kept in `arguments` only.
    public init(arguments: [String]) {
        func value(_ key: String) -> String? {
            guard let i = arguments.firstIndex(of: key), i + 1 < arguments.count else { return nil }
            return arguments[i + 1]
        }
        func flag(_ key: String) -> Bool {
            guard let v = value(key)?.lowercased() else { return false }
            return ["yes", "true", "1"].contains(v)
        }
        self.init(inMemoryStore: flag("-IterInMemoryStore"), storePath: value("-IterStorePath"), sampleData: flag("-IterSampleDataEnabled"),
                  fixedLocation: value("-IterLocation").flatMap(LaunchOptions.coordinate(from:)), section: value("-IterSection"),
                  seedTrip: flag("-IterSeedTrip"), arguments: arguments)
    }

    /// The current process's switches.
    public static var current: LaunchOptions { LaunchOptions(arguments: ProcessInfo.processInfo.arguments) }

    static func coordinate(from text: String) -> Coordinate? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }
}
