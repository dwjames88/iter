import Foundation
import IterModel
import SwiftData
import Testing
@testable import IterStore

/// A clock that moves one second on every read, so every stamp is distinct and ordered, and tests are deterministic.
final class TickingClock: @unchecked Sendable {
    private(set) var now: Date
    init(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { now = start }

    func read() -> Date {
        defer { now = now.addingTimeInterval(1) }
        return now
    }

    /// Jumps forward without a read.
    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
struct StoreFixture {
    let store: LibraryStore
    let undo = UndoManager()
    let clock = TickingClock()
    let day = LocalDay(year: 2026, month: 10, day: 10)

    /// With `undoable`, every store call must be inside `act` (no run loop here to open and close groups).
    init(undoable: Bool = false) throws {
        let clock = self.clock
        store = LibraryStore(container: try IterStoreSchema.makeInMemoryContainer(), clock: { clock.read() })
        undo.groupsByEvent = false
        if undoable { store.undoManager = undo }
    }

    /// One user action = one undo group (the app gets this from the run loop).
    func act<T>(_ body: () -> T) -> T {
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        return body()
    }

    func spot(_ id: String) -> Place { CuratedSpots.spot(id: id)! }

    func count<M: PersistentModel>(_ type: M.Type) -> Int {
        ((try? store.context.fetch(FetchDescriptor<M>())) ?? []).count
    }

    func trip3() -> TripRecord {
        let trip = store.trips.create(name: "T", startDay: day, dayCount: 3)
        store.trips.addStop(spot("mesa-arch"), to: trip, day: 0)
        store.trips.addStop(spot("delicate-arch"), to: trip, day: 0)
        store.trips.addStop(spot("horseshoe-bend"), to: trip, day: 1)
        store.trips.addStop(spot("monument-valley"), to: trip, day: 2)
        return trip
    }

    /// An own place at a fixed spot.
    func ownPlace(_ name: String) -> PlaceRecord {
        store.places.createUserSpot(name: name, coordinate: Coordinate(latitude: 38, longitude: -109),
                                    timeZoneIdentifier: "America/Denver")
    }

    func ownTrip(_ name: String) -> TripRecord { store.trips.create(name: name, startDay: day, dayCount: 1) }

    /// An Apple Maps place; each call is a different value for the same MapKit identifier.
    func mapsPlace(external: String = "I63803AE6A1C5C9A1") -> Place {
        Place(externalID: external, name: "Overlook", locality: "UT", coordinate: Coordinate(latitude: 38, longitude: -110),
              timeZoneIdentifier: "America/Denver", category: .landscape, origin: .appleMaps)
    }
}
