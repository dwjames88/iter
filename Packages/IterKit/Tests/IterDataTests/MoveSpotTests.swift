import Foundation
import Testing
import IterCore
@testable import IterData

@MainActor
@Suite struct MoveSpotTests {
    private let here = Coordinate(latitude: 37.0, longitude: -118.0)
    private let there = Coordinate(latitude: 37.01, longitude: -118.02)

    @Test func movingASpotStoresExactlyTheGivenCoordinateAndUndoes() throws {
        let f = try Fixture(undoable: true)
        f.store.actionName = { $0.rawValue }
        let mine = f.act { f.store.createUserSpot(name: "Pond", coordinate: here, timeZoneIdentifier: "America/Los_Angeles") }
        f.act { f.store.moveSpot(mine, to: there) }
        #expect(mine.coordinate == there)
        #expect(f.undo.undoActionName == "moveSpot")
        f.undo.undo()
        #expect(mine.coordinate == here)
        f.undo.redo()
        #expect(mine.coordinate == there)
    }

    @Test func movingBySpotIDOnlyMovesYourOwn() throws {
        let f = try Fixture()
        let mine = f.store.createUserSpot(name: "Pond", coordinate: here, timeZoneIdentifier: "America/Los_Angeles")
        #expect(f.store.moveSpot(id: mine.spot.id, to: there))
        #expect(mine.coordinate == there)
        #expect(!f.store.moveSpot(id: "mesa-arch", to: there))
        #expect(!f.store.moveSpot(id: UUID().uuidString, to: there))
        let saved = f.store.setSaved(f.spot("mesa-arch"), true)
        _ = saved
        let curated = try #require(f.store.savedPlaces().first)
        f.store.moveSpot(curated, to: there)
        #expect(curated.coordinate != there)
    }

    @Test func movingToTheSamePlaceIsNotAnEdit() throws {
        let f = try Fixture(undoable: true)
        let mine = f.act { f.store.createUserSpot(name: "Pond", coordinate: here, timeZoneIdentifier: "America/Los_Angeles") }
        let revision = f.store.revision
        f.act { f.store.moveSpot(mine, to: here) }
        #expect(f.store.revision == revision)
    }
}
