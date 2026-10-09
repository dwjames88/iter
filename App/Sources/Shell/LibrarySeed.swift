import Foundation
import IterCore
import IterData
import IterFeatures

/// `-IterSeedLibrary YES` (with `-IterInMemoryStore YES`): fills the throwaway store with a small library so the sidebar
/// and Locations can be photographed. Never runs against real data.
@MainActor
enum LibrarySeed {
    static func run(_ model: AppModel) {
        let store = model.store
        let tomorrow = model.today(in: .current).adding(days: 1)

        // Trips: the sample trip, pinned (it downloads like any pinned trip); a folder with a subfolder (pinned); one unfiled trip.
        let sample = store.seedSampleTrip(startDay: tomorrow)
        model.offline.pin(sample)
        let utah = store.createFolder(name: "Utah 2027", kind: .trips)
        let scouting = store.createFolder(name: "Scouting", kind: .trips, parent: utah)
        if let canyon = TripTemplates.template(id: "canyon-country") {
            let trip = store.createTrip(from: canyon, startDay: tomorrow.adding(days: 30))
            store.renameTrip(trip, to: "Canyon Country in Spring")
            store.moveTrips([trip], to: utah, index: nil)
        }
        let moab = store.createTrip(name: "Moab Recon", startDay: tomorrow.adding(days: 20), dayCount: 2)
        store.moveTrips([moab], to: scouting, index: nil)
        store.createTrip(name: "Weekend Away", startDay: tomorrow.adding(days: 9), dayCount: 2)

        // Locations: two folders of saved curated spots, plus one unfiled.
        let coast = store.createFolder(name: "Coast", kind: .locations)
        let desert = store.createFolder(name: "Desert", kind: .locations)
        file(["haystack-rock", "bixby-bridge", "point-reyes-lighthouse"], in: coast, store: store)
        file(["mesa-arch", "delicate-arch"], in: desert, store: store)
        if let spot = CuratedSpots.spot(id: "tunnel-view") { store.setSaved(spot, true) }

        // Pinned to the sidebar: a trip folder, a location folder, a location.
        store.setPinned(utah, true)
        store.setPinned(desert, true)
        if let arch = store.savedPlaces().first(where: { $0.curatedID == "mesa-arch" }) { store.setPinned(arch, true) }
    }

    private static func file(_ ids: [String], in folder: FolderRecord, store: IterStore) {
        for id in ids {
            guard let spot = CuratedSpots.spot(id: id) else { continue }
            store.setSaved(spot, true)
        }
        let records = store.savedPlaces().filter { $0.curatedID.map(ids.contains) ?? false }
        store.movePlaces(records, to: folder, index: nil)
    }
}
