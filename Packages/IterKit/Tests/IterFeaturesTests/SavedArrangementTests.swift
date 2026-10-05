import Foundation
import Testing
import IterCore
import IterData
@testable import IterFeatures

@Suite struct SavedArrangementTests {
    private func item(_ id: String, score: Int?, origin: SpotOrigin = .curated, name: String? = nil, category: SpotCategory? = nil) -> SavedItem {
        var spot = CuratedSpots.spot(id: id)!
        spot.origin = origin
        if let name { spot.name = name }
        if let category { spot.category = category }
        return SavedItem(id: UUID(), spot: spot, todayScore: score)
    }

    private var items: [SavedItem] {
        [item("mesa-arch", score: 40), item("tunnel-view", score: 72),
         item("tunnel-view", score: nil, origin: .user, name: "Back field")]
    }

    @Test func sortsByLightWithUnscoredLast() {
        let out = SavedArranger.arrange(items, query: "", filter: .all, sort: .lightToday)
        #expect(out.map(\.todayScore) == [72, 40, nil])
    }

    @Test func sortsByName() {
        let out = SavedArranger.arrange(items, query: "", filter: .all, sort: .name)
        #expect(out.map(\.spot.name) == out.map(\.spot.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func sortsByKindThenName() {
        let mixed = [item("mesa-arch", score: 1, category: .urban), item("tunnel-view", score: 1, category: .landscape)]
        let out = SavedArranger.arrange(mixed, query: "", filter: .all, sort: .kind)
        #expect(out.map(\.spot.category) == [.landscape, .urban])
    }

    @Test func filtersByOrigin() {
        #expect(SavedArranger.arrange(items, query: "", filter: .addedByYou, sort: .name).count == 1)
        #expect(SavedArranger.arrange(items, query: "", filter: .curated, sort: .name).count == 2)
        #expect(SavedArranger.arrange(items, query: "", filter: .appleMaps, sort: .name).isEmpty)
    }

    @Test func searchMatchesNameAndLocalityIgnoringCase() {
        #expect(SavedArranger.arrange(items, query: "BACK", filter: .all, sort: .name).count == 1)
        #expect(SavedArranger.arrange(items, query: "zzzz", filter: .all, sort: .name).isEmpty)
        let locality = items[0].spot.locality
        #expect(!SavedArranger.arrange(items, query: locality.lowercased(), filter: .all, sort: .name).isEmpty)
    }
}
