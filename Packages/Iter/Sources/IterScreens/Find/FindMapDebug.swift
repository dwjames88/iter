import Foundation
import IterFeatures
import IterModel

/// Screenshot switches for the Find map, honoured only with `-IterInMemoryStore YES` so a real library's launch can never
/// be steered by a stray argument:
///
/// | Switch | Effect |
/// |---|---|
/// | `-IterMapCamera lat,lon,span` | Starts the map on this centre, `span` degrees of latitude tall (zoomed out to see the terminator). |
/// | `-IterMapTime 2026-06-21T18:00:00Z` | Draws the night side for this instant instead of now. |
struct FindMapDebug: Equatable {
    var region: GeoRegion?
    var time: Date?

    static let current = FindMapDebug(options: .current)

    init(options: LaunchOptions) {
        guard options.inMemoryStore else { return }
        func value(_ key: String) -> String? {
            guard let i = options.arguments.firstIndex(of: key), i + 1 < options.arguments.count else { return nil }
            return options.arguments[i + 1]
        }
        if let text = value("-IterMapCamera") {
            let parts = text.split(separator: ",").compactMap { Double($0) }
            if parts.count == 3 {
                region = GeoRegion(center: Coordinate(latitude: parts[0], longitude: parts[1]), latitudeDelta: parts[2], longitudeDelta: parts[2])
            }
        }
        if let text = value("-IterMapTime") { time = ISO8601DateFormatter().date(from: text) }
    }
}
