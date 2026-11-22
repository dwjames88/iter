import Foundation
import Testing
@testable import IterModel

@Suite struct LocalDayTests {
    @Test func roundTripsISO() {
        let d = LocalDay(iso: "2026-10-05")!
        #expect(d.iso == "2026-10-05")
        #expect(d.adding(days: 30).iso == "2026-11-04")
        #expect(d.days(until: LocalDay(iso: "2027-01-01")!) == 88)
    }

    @Test func dayIsLocalToTheZone() {

        #expect(LightIntent.allCases.filter { $0.windows.contains(.night) } == [.night])
    }
}

@Suite struct GeoTests {
    @Test func distanceIsReasonable() {
        let portland = Coordinate(latitude: 45.5152, longitude: -122.6784)
        let seattle = Coordinate(latitude: 47.6062, longitude: -122.3321)
        #expect(abs(portland.distance(to: seattle) - 233_500) < 2_000)
        #expect(compassPoint(for: 100) == "E")
    }
}
