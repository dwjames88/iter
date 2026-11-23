import Foundation
import Testing
import IterModel
import IterSources
import IterStore
import IterSourcesLive
@testable import IterFeatures

@MainActor
@Suite("Own spots")
struct OwnSpotTests {
    let here = Coordinate(latitude: 38.3884, longitude: -109.8680)
    let there = Coordinate(latitude: 38.4000, longitude: -109.8000)

    private func mine(_ rig: Rig) -> PlaceRecord {
        rig.act { rig.library.places.createUserSpot(name: "Pond", coordinate: here, timeZoneIdentifier: "America/Denver") }
    }

    @Test func droppingAPinNamesItFromTheReverseLookup() async throws {
        let rig = try Rig()
        rig.model.spots.beginAdding()
        #expect(rig.model.spots.isAdding)
        let dropped = try #require(await rig.model.dropPin(at: here))
        #expect(dropped.place.name == "Dropped Place" && dropped.place.locality == "Canyonlands National Park, UT")
        #expect(dropped.place.timeZoneIdentifier == "America/Denver" && !dropped.timeZoneIsEstimate)
        #expect(dropped.place.origin == .user && dropped.place.coordinate == here)
        #expect(!rig.model.spots.isAdding)
        #expect(rig.model.card?.kind == .own && rig.model.card?.verification == .userPlaced)
        #expect(rig.model.card?.verificationLabel == "Placed by you")
        #expect(rig.model.mapContent.pins.contains { $0.kind == .own && $0.coordinate == here })
        #expect(rig.library.places.savedValues().map(\.name) == ["Dropped Place"])
    }

    @Test func aFailedLookupStillCreatesTheSpotWithAnEstimatedZone() async throws {
        let rig = try Rig(geocoder: FindFixtures.FixtureGeocoder(failsReverse: true))
        let dropped = try #require(await rig.model.dropPin(at: here))
        #expect(dropped.place.name == "Dropped Pin" && dropped.place.locality.isEmpty)
        #expect(dropped.timeZoneIsEstimate && !dropped.nameFromLookup)
        // -109.868 / 15 = -7.3, so seven hours behind UTC (Etc/GMT+7 in POSIX sign).
        #expect(dropped.place.timeZoneIdentifier == "Etc/GMT+7")
        #expect(TimeZone(identifier: dropped.place.timeZoneIdentifier) != nil)
    }

    @Test func timeZoneEstimateCoversBothHemispheres() {
        #expect(OwnSpotEditor.estimatedTimeZone(at: Coordinate(latitude: 0, longitude: 0)) == "Etc/GMT")
        #expect(OwnSpotEditor.estimatedTimeZone(at: Coordinate(latitude: 51, longitude: 30)) == "Etc/GMT-2")
        #expect(OwnSpotEditor.estimatedTimeZone(at: Coordinate(latitude: -33, longitude: 151)) == "Etc/GMT-10")
    }

    @Test func aNewerDropSupersedesAnOlderOne() async throws {
        struct Slow: IterSources.Geocoder {
            var descriptor = FindFixtures.descriptor(.appleGeocoder, "Apple Maps", kinds: [.geocode])
            func geocode(_ text: String, near region: GeoRegion?) async throws -> [GeocodeResult] { [] }
            func reverse(_ c: Coordinate) async throws -> GeocodeResult {
                if c.latitude > 40 { try await Task.sleep(for: .milliseconds(150)) }
                return GeocodeResult(name: c.latitude > 40 ? "First" : "Second", coordinate: c)
            }
            func boundary(of name: String, near coordinate: Coordinate?) async throws -> GeoPolygon? { nil }
        }
        let rig = try Rig(geocoder: Slow())
        let editor = rig.model.spots
        async let first = editor.drop(at: Coordinate(latitude: 41, longitude: -110))
        try await Task.sleep(for: .milliseconds(20))
        let second = await editor.drop(at: here)
        #expect(second?.place.name == "Second")
        #expect(await first == nil)
        #expect(rig.library.places.savedValues().map(\.name) == ["Second"])
    }

    @Test func movingASpotIsOneNamedUndoStepAndKeepsTheCoordinateExactly() throws {
        let rig = try Rig(undoable: true)
        let spot = mine(rig)
        rig.undo.removeAllActions()
        #expect(rig.act { rig.model.spots.move(spot.id, to: there) })
        #expect(spot.coordinate == there)
        #expect(rig.undo.undoActionName == "moveSpot")
        rig.undo.undo()
        #expect(spot.coordinate == here)
        #expect(!rig.undo.canUndo, "one step only")
        rig.undo.redo()
        #expect(spot.coordinate == there)
    }

    @Test func onlyYourOwnSpotsMove() throws {
        let rig = try Rig()
        let curated = CuratedSpots.spot(id: "mesa-arch")!
        rig.library.places.setSaved(curated, true)
        let record = try #require(rig.library.places.savedPlaces().first { $0.origin == .curated })
        #expect(!rig.model.spots.canMove(record.id))
        #expect(!rig.model.spots.move(record.id, to: there))
        #expect(!rig.model.spots.beginDrag(record.id))
        #expect(!rig.model.spots.move(UUID(), to: there))
    }

    @Test func draggingShowsTheDragCoordinateAndWritesOnlyOnDrop() throws {
        let rig = try Rig(undoable: true)
        let spot = mine(rig)
        let editor = rig.model.spots
        #expect(editor.beginDrag(spot.id))
        editor.drag(to: there)
        #expect(editor.displayCoordinate(for: spot.id, stored: here) == there)
        #expect(spot.coordinate == here)
        rig.act { editor.endDrag(commit: false) }
        #expect(spot.coordinate == here && editor.dragging == nil)
        #expect(editor.beginDrag(spot.id))
        editor.drag(to: there)
        rig.act { editor.endDrag(commit: true) }
        #expect(spot.coordinate == there)
    }

    @Test func adjustLocationCommitMovesAndCancelRestoresTheOriginal() throws {
        let rig = try Rig(undoable: true)
        let spot = mine(rig)
        let editor = rig.model.spots
        rig.undo.removeAllActions()
        let revision = rig.library.revision
        #expect(editor.beginAdjusting(spot.id))
        #expect(!editor.beginDrag(spot.id), "no drag while adjusting")
        editor.adjustCenterChanged(there)
        #expect(editor.displayCoordinate(for: spot.id, stored: here) == there)
        rig.act { editor.finishAdjusting(commit: false) }
        #expect(spot.coordinate == here && editor.adjusting == nil)
        #expect(editor.displayCoordinate(for: spot.id, stored: here) == here)
        #expect(rig.library.revision == revision)
        #expect(editor.beginAdjusting(spot.id))
        editor.adjustCenterChanged(there)
        rig.act { editor.finishAdjusting(commit: true) }
        #expect(spot.coordinate == there)
        rig.undo.undo()
        #expect(spot.coordinate == here)
    }

    @Test func pasteCoordinatesReadsEveryFormat() {
        let samples: [(String, Coordinate)] = [
            ("38.5, -109.5", Coordinate(latitude: 38.5, longitude: -109.5)),
            ("38.5 -109.5", Coordinate(latitude: 38.5, longitude: -109.5)),
            ("38.5°N 109.5°W", Coordinate(latitude: 38.5, longitude: -109.5)),
            ("N 38.5 W 109.5", Coordinate(latitude: 38.5, longitude: -109.5)),
            ("38°30′00″N 109°30′00″W", Coordinate(latitude: 38.5, longitude: -109.5)),
            ("https://maps.apple.com/?ll=38.5,-109.5&q=Spot", Coordinate(latitude: 38.5, longitude: -109.5)),
            ("https://maps.apple.com/place?coordinate=38.5,-109.5", Coordinate(latitude: 38.5, longitude: -109.5)),
        ]
        for (text, expected) in samples {
            var f = CoordinateFields(Coordinate(latitude: 0, longitude: 0))
            let ok = f.paste(text)
            #expect(ok, "\(text)")
            #expect(f.coordinate == expected, "\(text)")
        }
        var f = CoordinateFields(Coordinate(latitude: 1, longitude: 2))
        let bad = f.paste("not a coordinate")
        #expect(!bad && f.pasteFailed)
        #expect(f.coordinate == Coordinate(latitude: 1, longitude: 2))
        let range = f.paste("95, 10")
        #expect(!range, "out of range")
        f.latitudeText = "91"
        #expect(f.latitudeProblem != nil && f.longitudeProblem == nil && f.coordinate == nil)
        #expect(CoordinateFields.format(-109.549412) == "-109.549412" && CoordinateFields.format(38.5) == "38.5")
    }

    @Test func fieldsMoveTheSpotWhenApplied() throws {
        let rig = try Rig(undoable: true)
        let spot = mine(rig)
        let editor = rig.model.spots
        editor.editFields(for: spot.id)
        #expect(editor.fields.latitudeText == "38.3884")
        #expect(editor.pasteCoordinates("38.4, -109.8"))
        #expect(rig.act { editor.applyFields() })
        #expect(spot.coordinate == Coordinate(latitude: 38.4, longitude: -109.8))
        editor.fields.longitudeText = "x"
        #expect(!editor.applyFields())
    }

    @Test func readoutGivesLatLonMGRSAndDeclinationWithProvenance() throws {
        let rig = try Rig()
        let r = rig.model.spots.readout(for: here, elevationMeters: 1800)
        #expect(r.latitudeText == "38.3884°N" && r.longitudeText == "109.8680°W")
        let mgrs = try #require(r.mgrs)
        #expect(mgrs.hasPrefix("12S "), "\(mgrs)")
        #expect(mgrs.split(separator: " ").count == 4)
        #expect(r.mgrsSource?.contains("Military Grid Reference System") == true)
        #expect(r.mgrsSource?.contains("computed on device") == true)
        let declination = try #require(r.declinationText)
        #expect(declination.hasSuffix("E"), "Utah's declination is east: \(declination)")
        let degrees = try #require(Double(declination.split(separator: "°")[0]))
        #expect((6.0...12.0).contains(degrees), "\(degrees)")
        #expect(r.declinationSource?.contains("World Magnetic Model 2025") == true)
        #expect(r.declinationSource?.contains("Military-origin") == true)
        #expect(r.declinationNote == nil)
    }

    @Test func readoutSaysWhenTheCompassCannotBeTrusted() throws {
        let rig = try Rig()
        let r = rig.model.spots.readout(for: Coordinate(latitude: 86, longitude: -100))
        #expect(r.declinationNote != nil)
    }

    @Test func mgrsSpacingGroupsTheDigits() {
        #expect(OwnSpotEditor.spaced("12SWC1234567890") == "12S WC 12345 67890")
        #expect(OwnSpotEditor.spaced("12S WC 12345 67890") == "12S WC 12345 67890")
    }
}
