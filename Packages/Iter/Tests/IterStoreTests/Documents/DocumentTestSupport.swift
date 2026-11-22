import Foundation
import IterModel

enum DocFixtures {
    static var documentsFolder: URL? {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)?.appendingPathComponent("documents", isDirectory: true)
    }

    /// Every `.iter` file directly in `folder` (relative to `documents/`), sorted by name.
    static func files(in subfolder: String? = nil) -> [URL] {
        guard var folder = documentsFolder else { return [] }
        if let subfolder { folder.appendPathComponent(subfolder, isDirectory: true) }
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "iter" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// A counter-backed id source, so tests are deterministic.
final class IDSequence: @unchecked Sendable {
    private var next: UInt8
    init(start: UInt8 = 1) { next = start }
    func make() -> UUID {
        defer { next &+= 1 }
        return UUID(uuid: (0xA0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, next))
    }
}

func uuid(_ n: UInt8) -> UUID { UUID(uuid: (0xB0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, n)) }
func at(_ seconds: Int) -> Date { Date(timeIntervalSince1970: 1_800_000_000 + TimeInterval(seconds)) }

func samplePlace(_ n: UInt8, updated: Int = 0, name: String = "Place") -> Place {
    Place(id: uuid(n), name: "\(name) \(n)", coordinate: Coordinate(latitude: 38.5, longitude: -109.5),
          timeZoneIdentifier: "America/Denver", category: .desert, origin: .user, isSaved: true, createdAt: at(0),
          updatedAt: at(updated))
}

func sampleTrip(_ n: UInt8, updated: Int = 0, name: String = "Trip", places: [Place] = []) -> Trip {
    let stops = places.enumerated().map { i, p in
        Stop(id: uuid(100 &+ n &* 10 &+ UInt8(i)), place: p, dayIndex: 0, session: .goldenEvening)
    }
    return Trip(id: uuid(n), name: "\(name) \(n)", startDay: LocalDay(year: 2026, month: 11, day: 21), dayCount: 2,
                stops: stops, createdAt: at(0), updatedAt: at(updated))
}
