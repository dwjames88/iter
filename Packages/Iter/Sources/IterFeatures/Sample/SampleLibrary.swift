import Foundation
import IterModel
import IterStore

/// The sample library: what `-IterSeedTrip YES`, the Debug menu's "Add Sample Trip" and the snapshots fill a scratch store
/// with. Never run against the owner's real store (the composition root refuses; the shell's menu is Debug-only).
@MainActor
public enum SampleLibrary {
    /// Names, so tests and screens can find the sample rows.
    public static let tripName = "Canyon Country"
    public static let scoutingTripName = "Moab Recon"
    public static let springTripName = "Eastern Sierra Autumn"
    public static let tripFolderName = "Scouting"
    public static let placeFolderName = "Desert Favourites"

    /// What a seed added, for callers that want to open it.
    public struct Seeded: Equatable {
        public var canyonCountryID: UUID
        public var tripIDs: [UUID]
        public var tripFolderID: UUID
        public var placeFolderID: UUID
        public var placeIDs: [UUID]
    }

    /// Adds the four-day Canyon Country trip (six light stops, two lodging stops, a fuel waypoint, an evening-before
    /// transfer, drive notes), two more trips (one filed in a folder), saved places filed in a folder and a pinned trip and
    /// place. `now` fixes the start day (tomorrow, in Mountain time) so a snapshot is the same on every run.
    @discardableResult
    public static func seed(into library: LibraryStore, now: Date) -> Seeded {
        let utah = TimeZone(identifier: "America/Denver") ?? .current
        let tomorrow = LocalDay(now, in: utah).adding(days: 1)
        let trips = library.trips
        let places = library.places
        let folders = library.folders

        // The headline trip.
        let canyon = trips.create(from: TripTemplates.canyonCountry(), startDay: tomorrow)
        trips.rename(canyon, to: tripName)
        trips.setNotes(canyon, to: "Four days through canyon country: Horseshoe Bend, Monument Valley, Moab and the San Rafael Swell.")
        addLodging(named: "Lodging in Page", at: Coordinate(latitude: 36.9147, longitude: -111.4558), zone: "America/Phoenix",
                   day: 0, arrival: LocalTime(hour: 21, minute: 0), to: canyon, library: library)
        addLodging(named: "Lodging in Moab", at: Coordinate(latitude: 38.5733, longitude: -109.5498), zone: "America/Denver",
                   day: 1, arrival: LocalTime(hour: 21, minute: 30), to: canyon, library: library)
        if let hanksville = places.createUserSpot(name: "Fuel in Hanksville", locality: "Hanksville, UT",
                                                  coordinate: Coordinate(latitude: 38.3736, longitude: -110.7132),
                                                  timeZoneIdentifier: "America/Denver", category: .street).value() as Place? {
            let stop = trips.addStop(hanksville, to: canyon, day: 3, session: .goldenMorning, at: 0)
            trips.setKind(stop, to: .waypoint)
            trips.setDwell(stop, minutes: 20)
        }
        trips.setTransferTiming(canyon, intoDay: 2, to: .eveningBefore)
        let notes: [Int: String] = [1: "About 2 hours 40 minutes from Page; leave before dawn.", 2: "Moab is under 2 hours from Monument Valley's north exit; the evening before is easier.",
                                    3: "Highway 24 through Hanksville; fuel there."]
        for day in notes.keys.sorted() {
            if let first = canyon.orderedStops(onDay: day).first(where: { $0.kind == .light }) { trips.setDriveNote(first, to: notes[day] ?? "") }
        }
        trips.setPinned(canyon, true)

        // A trip in a folder, and one more unfiled.
        let scouting = folders.create(name: tripFolderName, kind: .trips)
        let recon = trips.create(name: scoutingTripName, startDay: tomorrow.adding(days: 20), dayCount: 2)
        folders.moveTrips([recon], to: scouting, index: nil)
        let sierra = trips.create(from: TripTemplates.easternSierra(), startDay: tomorrow.adding(days: 45))
        trips.rename(sierra, to: springTripName)

        // Saved places: two filed, one pinned, one loose.
        let desert = folders.create(name: placeFolderName, kind: .locations)
        for slug in ["mesa-arch", "delicate-arch", "horseshoe-bend", "goblin-valley"] {
            if let spot = CuratedSpots.spot(id: slug) { places.setSaved(spot, true) }
        }
        if let loose = CuratedSpots.spot(id: "tunnel-view") { places.setSaved(loose, true) }
        let saved = places.savedPlaces()
        let inFolder = saved.filter { ["mesa-arch", "delicate-arch", "horseshoe-bend"].contains($0.curatedID ?? "") }
        folders.movePlaces(inFolder, to: desert, index: nil)
        if let arch = saved.first(where: { $0.curatedID == "mesa-arch" }) { places.setPinned(arch, true) }

        library.flush()
        return Seeded(canyonCountryID: canyon.id, tripIDs: [canyon.id, recon.id, sierra.id], tripFolderID: scouting.id,
                      placeFolderID: desert.id, placeIDs: saved.map(\.id))
    }

    private static func addLodging(named name: String, at coordinate: Coordinate, zone: String, day: Int, arrival: LocalTime,
                                   to trip: TripRecord, library: LibraryStore) {
        let record = library.places.createUserSpot(name: name, locality: name.replacingOccurrences(of: "Lodging in ", with: "") + ", UT",
                                                    coordinate: coordinate, timeZoneIdentifier: zone, category: .urban)
        let stop = library.trips.addStop(record.value(), to: trip, day: day, session: .night)
        library.trips.setKind(stop, to: .lodging)
        library.trips.setFixedArrival(stop, to: arrival)
    }
}

extension TripTemplates {
    @MainActor static func canyonCountry() -> TripTemplate { template(id: "canyon-country")! }
    @MainActor static func easternSierra() -> TripTemplate { template(id: "eastern-sierra")! }
}
