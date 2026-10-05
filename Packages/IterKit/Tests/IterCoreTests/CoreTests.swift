import Foundation
import Testing
@testable import IterCore

@Suite struct LocalDayTests {
    @Test func roundTripsISO() {
        let d = LocalDay(iso: "2026-10-05")!
        #expect(d.iso == "2026-10-05")
        #expect(d.adding(days: 30).iso == "2026-11-04")
        #expect(d.days(until: LocalDay(iso: "2027-01-01")!) == 88)
    }

    @Test func dayIsLocalToTheZone() {
        // 2026-10-05 03:00 UTC is still 4 October in Denver.
        let instant = Date(timeIntervalSince1970: 1_791_169_200)
        #expect(LocalDay(instant, in: TimeZone(identifier: "America/Denver")!).iso == "2026-10-04")
        #expect(LocalDay(instant, in: TimeZone(identifier: "UTC")!).iso == "2026-10-05")
    }
}

@Suite struct LightRuleTests {
    @Test func bandThresholds() {
        #expect(LightBand(score: 87) == .great)
        #expect(LightBand(score: 88) == .epic)
        #expect(LightBand(score: 57) == .fair)
    }

    @Test func nightNeverAnswersSunset() {
        #expect(!LightIntent.sunset.windows.contains(.night))
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
