import Foundation
import SwiftData
import IterCore
@testable import IterData

/// A photographer's library built through the OLD public API, exactly as the app calls it.
@MainActor
func buildRealistic(at url: URL, exportedAt: Date) throws -> [(name: String, plan: TripPlan)] {
    let container = try IterSchema.makeContainer(url: url)
    let store = IterStore(container: container)
    func curated(_ id: String) -> Spot { CuratedSpots.spot(id: id)! }
    func day(_ iso: String) -> LocalDay { LocalDay(iso: iso)! }

    // Own places.
    let mobius = store.createUserSpot(name: "Mobius Arch pullout", locality: "Lone Pine, CA", coordinate: Coordinate(latitude: 36.6128, longitude: -118.1264),
                                      timeZoneIdentifier: "America/Los_Angeles", category: .astro, bestLight: [.night, .sunrise],
                                      notes: "Dark sky, Bortle 2. Flat gravel, room for the star tracker.", walkInMinutes: 3)
    let reine = store.createUserSpot(name: "Reine rorbu \u{1F3D4}\u{FE0F}", locality: "Reine, Lofoten, Norge", coordinate: Coordinate(latitude: 67.9323, longitude: 13.0887),
                                     timeZoneIdentifier: "Europe/Oslo", category: .coast, bestLight: [.blueHour, .sunrise], notes: "Fiskerhytte \u{2014} bakeri 200 m. \u{00C5}pent kl. 7.")
    let hamnoy = store.createUserSpot(name: "Hamn\u{00F8}y bridge \u{2728}", locality: "Hamn\u{00F8}y, Lofoten", coordinate: Coordinate(latitude: 67.9439, longitude: 13.1326),
                                      timeZoneIdentifier: "Europe/Oslo", category: .coast, bestLight: [.sunset, .night], notes: "\u{5317}\u{6975}\u{5149} chance in Sept\u{2013}Mar. Wind!", walkInMinutes: 10)
    let pullout = store.createUserSpot(name: "Unnamed pullout", coordinate: Coordinate(latitude: 36.1, longitude: -117.2), timeZoneIdentifier: "America/Los_Angeles")

    // Apple Maps results: non-UUID ids become externalID.
    let deli = Spot(id: "I5D9F0B2A7C3E1648", name: "Whoa Nellie Deli", locality: "Lee Vining, CA", coordinate: Coordinate(latitude: 37.9366, longitude: -119.1214),
                    timeZoneIdentifier: "America/Los_Angeles", category: .street, popularity: 50, origin: .appleMaps)
    let hotel = Spot(id: "IC1A07E3B94D2F865", name: "Hotel Fj\u{00E6}re & Br\u{00F8}d", locality: "Reine", coordinate: Coordinate(latitude: 67.9331, longitude: 13.0902),
                     timeZoneIdentifier: "Europe/Oslo", category: .urban, origin: .appleMaps)

    // Trip A: five days, the Eastern Sierra.
    let a = store.createTrip(name: "Eastern Sierra Autumn \u{1F342}", startDay: day("2026-10-14"), dayCount: 5)
    store.setNotes(a, to: "Aspens peak around Oct 18. Chains in the car after Nov 1.\nGas in Lee Vining.")
    let a1 = store.addStop(curated("alabama-hills"), to: a, day: 0, session: .goldenEvening)
    store.setBuffer(a1, minutes: 30); store.setNote(a1, to: "Mobius Arch first, then the Whitney view")
    let a2 = store.addStop(mobius.spot, to: a, day: 0, session: .night)
    store.setBuffer(a2, minutes: 45); store.setNote(a2, to: "Star tracker; 2 min subs"); store.setDriveNote(a2, to: "Gravel road, 4 minutes. Drive slow.")
    let a3 = store.addStop(curated("convict-lake"), to: a, day: 1, session: .blueMorning)
    store.setBuffer(a3, minutes: 35); store.setNote(a3, to: "Aspen grove on the north shore"); store.setDriveNote(a3, to: "Highway 395 north from Lone Pine, about 2 h")
    let a4 = store.addStop(curated("lake-sabrina"), to: a, day: 1, session: .goldenMorning)
    store.setBuffer(a4, minutes: 10); store.setDriveNote(a4, to: "Twisty road to the lake; park at the dam")
    let a5 = store.addStop(deli, to: a, day: 1, session: .goldenEvening)
    store.setNote(a5, to: "Fish tacos before sunset")
    let a6 = store.addStop(curated("mono-lake-south-tufa"), to: a, day: 1, session: .blueEvening)
    store.setBuffer(a6, minutes: 0)
    let a7 = store.addStop(curated("bodie"), to: a, day: 2, session: .goldenEvening)
    store.setBuffer(a7, minutes: 60); store.setNote(a7, to: "Gate closes at 6; check the hours"); store.setDriveNote(a7, to: "Dirt road for the last 3 miles")
    let a8 = store.addStop(curated("ancient-bristlecone-forest"), to: a, day: 3, session: .goldenMorning)
    store.setBuffer(a8, minutes: 25); store.setDriveNote(a8, to: "White Mountain Road, 40 min of switchbacks")
    let a9 = store.addStop(curated("fossil-falls"), to: a, day: 4, session: .goldenEvening)
    store.setNote(a9, to: "Last light on the way home")
    store.setTransferTiming(a, intoDay: 1, to: .eveningBefore)
    store.setTransferTiming(a, intoDay: 3, to: .eveningBefore)

    // Trip B: Death Valley long weekend.
    let b = store.createTrip(name: "Death Valley long weekend", startDay: day("2026-12-04"), dayCount: 3)
    let b1 = store.addStop(curated("zabriskie-point"), to: b, day: 0, session: .goldenMorning); store.setBuffer(b1, minutes: 15)
    let b2 = store.addStop(curated("mesquite-flat-dunes"), to: b, day: 0, session: .goldenEvening); store.setNote(b2, to: "Walk 1 mile out; footprints fade by sunrise")
    let b3 = store.addStop(curated("badwater-basin"), to: b, day: 1, session: .blueMorning); store.setDriveNote(b3, to: "From Furnace Creek 30 min")
    let b4 = store.addStop(pullout.spot, to: b, day: 2, session: .night)
    _ = b4
    store.setTransferTiming(b, intoDay: 2, to: .eveningBefore)

    // Trip C: Lofoten.
    let c = store.createTrip(name: "Lofoten \u{2728} Reine & Hamn\u{00F8}y \u{5317}\u{6975}", startDay: day("2027-02-20"), dayCount: 4)
    store.setNotes(c, to: "Aurora window Feb 21\u{2013}24. Crampons for the ice. \u{1F9E4}")
    let c1 = store.addStop(reine.spot, to: c, day: 0, session: .blueMorning); store.setNote(c1, to: "Reflection in the harbour if calm")
    let c2 = store.addStop(hamnoy.spot, to: c, day: 0, session: .night); store.setBuffer(c2, minutes: 60)
    store.setDriveNote(c2, to: "E10 south then the Hamn\u{00F8}y turnoff, 15 min")
    let c3 = store.addStop(hotel, to: c, day: 1, session: .goldenEvening)
    store.setNote(c3, to: "Dinner stop \u{2014} the Fj\u{00E6}re & Br\u{00F8}d")
    let c4 = store.addStop(hamnoy.spot, to: c, day: 2, session: .goldenMorning); store.setBuffer(c4, minutes: 5)

    // Trip D: one day, a name with characters a file name cannot hold.
    let d = store.createTrip(name: "Utah / Arches: Day trip?", startDay: day("2026-11-21"), dayCount: 1)
    let d1 = store.addStop(curated("delicate-arch"), to: d, day: 0, session: .goldenEvening)
    store.setBuffer(d1, minutes: 50); store.setNote(d1, to: "1.5 mile hike up the slickrock")

    // Saved curated spots.
    for id in ["alabama-hills", "mono-lake-south-tufa", "delicate-arch", "bodie", "zabriskie-point", "lake-sabrina", "horseshoe-bend"] {
        store.setSaved(curated(id), true)
    }
    store.setSaved(deli, true)
    // One unsaved after saving: a saved-then-removed curated spot that no stop uses is pruned by the store.
    store.setSaved(curated("the-wave"), true); store.setSaved(curated("the-wave"), false)

    // The user's edits to a curated spot (name and notes only; the catalogue's facts stay).
    if let rec = store.editableRecord(for: curated("delicate-arch")) {
        var edit = PlaceEdit(rec)
        edit.name = "Delicate Arch \u{2014} golden hour \u{1F305}"
        edit.notes = "Hike starts at the Wolfe Ranch lot.\nBring a headlamp for the walk down."
        store.editPlace(rec, edit)
    }

    // Folders, filing, pins.
    let road = store.createFolder(name: "2026 Road Trips \u{1F698}", kind: .trips)
    _ = store.createFolder(name: "Wishlist", kind: .trips)
    store.moveTrips([a], to: road, index: nil)
    store.moveTrips([c], to: road, index: 0)
    store.setPinned(b, true)
    store.setPinned(road, true)

    let sierra = store.createFolder(name: "Sierra shoots", kind: .locations)
    let night = store.createFolder(name: "Night sky \u{1F30C}", kind: .locations)
    store.movePlaces([store.editableRecord(for: curated("mono-lake-south-tufa"))!, store.editableRecord(for: curated("alabama-hills"))!,
                      store.editableRecord(for: curated("bodie"))!], to: sierra, index: nil)
    store.movePlaces([mobius, hamnoy], to: night, index: nil)
    if let rec = store.editableRecord(for: curated("delicate-arch")) { store.setPinned(rec, true) }
    store.setPinned(night, true)
    store.setPinned(mobius, true)

    return store.trips().map { ($0.name, $0.plan) }
}
