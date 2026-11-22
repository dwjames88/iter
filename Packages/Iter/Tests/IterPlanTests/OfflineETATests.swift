import Foundation
import Testing
import IterModel
@testable import IterPlan

private func c(_ lat: Double, _ lon: Double = -110) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }

/// A 22 km line due north in two segments, planned at 20 minutes and 20 km.
private let routeLeg = Leg(from: c(40), to: c(40.2), seconds: 1200, meters: 20_000, isEstimate: false, path: [c(40), c(40.1), c(40.2)])
private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Suite struct OfflineETATests {
    @Test func startOfTheLineLeavesTheWholeLeg() throws {
        let e = try #require(OfflineETA.estimate(from: c(40), along: routeLeg))
        #expect(abs(e.fractionRemaining - 1) < 1e-9)
        #expect(abs(e.seconds - 1200) < 1e-6)
        #expect(abs(e.meters - 20_000) < 1e-6)
        #expect(e.crossTrackMeters < 1)
        #expect(e.isAlongRoute)
    }

    @Test func middleOfTheLineLeavesHalf() throws {
        let e = try #require(OfflineETA.estimate(from: c(40.1), along: routeLeg))
        #expect(abs(e.fractionRemaining - 0.5) < 1e-6)
        #expect(abs(e.seconds - 600) < 1e-3)
        #expect(abs(e.meters - 10_000) < 1e-2)
    }

    @Test func endOfTheLineLeavesNothing() throws {
        let e = try #require(OfflineETA.estimate(from: c(40.2), along: routeLeg))
        #expect(e.fractionRemaining < 1e-9)
        #expect(e.seconds < 1e-6)
    }

    @Test func beforeStartAndPastEndClamp() throws {
        let before = try #require(OfflineETA.estimate(from: c(39.999), along: routeLeg))
        #expect(before.fractionRemaining == 1)
        let past = try #require(OfflineETA.estimate(from: c(40.2005), along: routeLeg))
        #expect(past.fractionRemaining == 0)
        #expect(past.crossTrackMeters > 0)
    }

    @Test func nearbyOffsetCountsAsOnRouteWithCrossTrack() throws {
        let e = try #require(OfflineETA.estimate(from: c(40.05, -109.995), along: routeLeg))   // about 425 m east
        #expect(e.crossTrackMeters > 300 && e.crossTrackMeters < 500)
        #expect(abs(e.fractionRemaining - 0.75) < 1e-3)
    }

    @Test func offRouteIsNil() {
        #expect(OfflineETA.estimate(from: c(40.05, -109.9), along: routeLeg) == nil)     // about 8.5 km east
    }

    @Test func degeneratePathsAreNil() {
        var leg = routeLeg
        leg.path = [c(40)]
        #expect(OfflineETA.estimate(from: c(40), along: leg) == nil)
        leg.path = []
        #expect(OfflineETA.estimate(from: c(40), along: leg) == nil)
        leg.path = [c(40), c(40)]
        #expect(OfflineETA.estimate(from: c(40), along: leg) == nil)
    }

    @Test func etaUsesTheRouteWhenOnIt() {
        let r = OfflineETA.eta(from: c(40.1), to: c(40.2), plannedLeg: routeLeg, now: t0)
        #expect(r.isAlongRoute)
        #expect(abs(r.eta.seconds - 600) < 1e-3)
        #expect(r.eta.departing == t0)
        #expect(r.eta.arrival == t0.addingTimeInterval(r.eta.seconds))
    }

    @Test func etaFallsBackToTheStraightLine() {
        let straight = Leg.estimate(from: c(40.05, -109.9), to: c(40.2)).seconds
        let off = OfflineETA.eta(from: c(40.05, -109.9), to: c(40.2), plannedLeg: routeLeg, now: t0)
        #expect(!off.isAlongRoute)
        #expect(off.eta.seconds == straight)
        let none = OfflineETA.eta(from: c(40.05, -109.9), to: c(40.2), plannedLeg: nil, now: t0)
        #expect(!none.isAlongRoute)
        #expect(none.eta.seconds == straight)
        #expect(none.eta.arrival == t0.addingTimeInterval(straight))
    }

    @Test func estimateRoundTripsThroughCodable() throws {
        let e = try #require(OfflineETA.estimate(from: c(40.1), along: routeLeg))
        let back = try JSONDecoder().decode(OfflineEstimate.self, from: JSONEncoder().encode(e))
        #expect(back == e)
    }
}
