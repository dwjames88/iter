import Foundation
import Testing
import IterCore
@testable import IterFeatures

@Suite struct SavedSpotDraftTests {
    private func draft() -> SpotDraft { SpotDraft(coordinate: Coordinate(latitude: 38.5, longitude: -109.5)) }

    @Test func nameIsRequired() {
        var d = draft()
        #expect(d.problems == [.nameRequired])
        d.name = "  \n"
        #expect(!d.isValid)
        d.name = " Back field "
        #expect(d.isValid)
        #expect(d.trimmedName == "Back field")
    }

    @Test func walkInIsOptionalAndValidated() {
        var d = draft()
        d.name = "x"
        #expect(d.walkInMinutes == .some(nil))
        d.walkInText = "15"
        #expect(d.walkInMinutes == .some(15))
        d.walkInText = "abc"
        #expect(d.problems == [.walkInInvalid])
        d.walkInText = "-3"
        #expect(!d.isValid)
        d.walkInText = "601"
        #expect(!d.isValid)
        d.walkInText = "0"
        #expect(d.isValid)
    }

    @Test func bestLightKeepsCanonicalOrder() {
        var d = draft()
        d.bestLight = [.night, .sunrise, .midday]
        #expect(d.orderedBestLight == [.sunrise, .night, .midday])
    }

    @Test func lookupFillsOnlyUntouchedFieldsAndTakesTheZone() {
        var d = draft()
        d.name = "Mine"
        let result = PlaceResult(id: "1", name: "Arches", locality: "Moab, UT", coordinate: d.coordinate,
                                 timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
        d.apply(lookup: result, fillName: false, fillLocality: true)
        #expect(d.name == "Mine")
        #expect(d.locality == "Moab, UT")
        #expect(d.timeZoneIdentifier == "America/Denver")
        #expect(!d.timeZoneIsFallback)
    }

    @Test func lookupWithoutZoneKeepsTheFallbackFlag() {
        var d = draft()
        let result = PlaceResult(id: "1", name: "Arches", locality: "", coordinate: d.coordinate,
                                 timeZoneIdentifier: nil, pointOfInterestCategory: nil)
        d.apply(lookup: result, fillName: true, fillLocality: true)
        #expect(d.name == "Arches")
        #expect(d.timeZoneIsFallback)
    }
}
