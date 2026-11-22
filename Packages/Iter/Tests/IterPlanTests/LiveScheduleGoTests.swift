import Foundation
import Testing
import IterModel
@testable import IterPlan

private func at(_ hour: Double, day: Int = 0) -> Date {
    StandardDay.at(LocalDay(year: 2026, month: 10, day: 12 + day), hour)
}
private func minutes(_ m: Double) -> TimeInterval { m * 60 }
private func eta(_ m: Double, from now: Date) -> ETA { ETA(seconds: m * 60, arrival: now.addingTimeInterval(m * 60), departing: now) }
private func near(_ a: Date?, _ b: Date?) -> Bool {
    guard let a, let b else { return a == nil && b == nil }
    return abs(a.timeIntervalSince(b)) < 1
}

/// One day: home, a sunrise stop, a sunset stop, a night stop and a hotel (same shape as `LiveScheduleTests`).
private struct Day {
    var home = makePlace("home", lat: 40, lon: -110.5)
    var s1 = stop("Arch", day: 0, .goldenMorning, lat: 40, lon: -110)
    var s2 = stop("Mesa", day: 0, .goldenEvening, lat: 40.5, lon: -110)
    var s3 = stop("Dark", day: 0, .night, lat: 40.5, lon: -109.5)
    var trip: Trip
    var windows: SessionWindows
    var planned: [LegKey: Leg]

    init(mesaToDarkMinutes: Double = 20) {
        trip = makeTrip([s1, s2, s3], days: 1, start: home)
        windows = standardWindows(trip)
        planned = legs(startLeg(home, s1, minutes: 60), leg(s1, s2, minutes: 90), leg(s2, s3, minutes: mesaToDarkMinutes))
    }

    func live(now: Date, origin: Coordinate? = nil, etas: [UUID: ETA] = [:], offline: [UUID: ETA] = [:],
              progress: TripProgress = TripProgress()) -> LiveSchedule {
        LiveSchedule.make(trip: trip, start: home, windows: windows, plannedLegs: planned, progress: progress, now: now, origin: origin,
                          liveETAs: etas, offlineETAs: offline)
    }
}

@Suite struct LiveScheduleGoTests {
    // MARK: Drive-time precedence

    @Test func nextStopPrecedenceIsLiveThenOfflineThenStraightLineThenPlanned() {
        let d = Day()
        let now = at(3.5)
        let origin = c(40.01, -110.4)
        let straight = Leg.estimate(from: origin, to: d.s1.place.coordinate).seconds
        let ids = d.s1.id

        let live = d.live(now: now, origin: origin, etas: [ids: eta(61, from: now)], offline: [ids: eta(42, from: now)]).next!
        #expect(live.etaSource == .live && live.driveSeconds == minutes(61))

        let offline = d.live(now: now, origin: origin, offline: [ids: eta(42, from: now)]).next!
        #expect(offline.etaSource == .offlineEstimate && offline.driveSeconds == minutes(42))

        let line = d.live(now: now, origin: origin).next!
        #expect(line.etaSource == .offlineEstimate && line.driveSeconds == straight)

        let planned = d.live(now: now).next!
        #expect(planned.etaSource == .planned && planned.driveSeconds == minutes(60))

        // An offline ETA with no origin still wins over the planned leg.
        let offlineNoOrigin = d.live(now: now, offline: [ids: eta(42, from: now)]).next!
        #expect(offlineNoOrigin.etaSource == .offlineEstimate && offlineNoOrigin.driveSeconds == minutes(42))
    }

    @Test func offlineETAOnlyAppliesToTheNextStop() {
        let d = Day()
        let now = at(3.5)
        let live = d.live(now: now, offline: [d.s2.id: eta(5, from: now)])
        #expect(live.remaining.first!.etaSource == .planned)
        #expect(live.remaining.first!.driveSeconds == minutes(90))
    }

    @Test func alternativeUsesLiveThenOfflineThenStraightLine() {
        let d = Day()
        let now = at(7.5)     // Arch's window ended at 07:00
        let origin = c(40.2, -110)
        let s2 = d.s2.id
        let base = d.live(now: now, origin: origin, offline: [s2: eta(77, from: now)])
        #expect(base.next!.status == .missed)
        #expect(base.next!.alternative?.stopID == s2)
        #expect(base.next!.alternative?.etaSource == .offlineEstimate)
        #expect(base.next!.alternative?.driveSeconds == minutes(77))
        let live = d.live(now: now, origin: origin, etas: [s2: eta(30, from: now)], offline: [s2: eta(77, from: now)])
        #expect(live.next!.alternative?.etaSource == .live)
        #expect(live.next!.alternative?.driveSeconds == minutes(30))
        let line = d.live(now: now, origin: origin)
        #expect(line.next!.alternative?.driveSeconds == Leg.estimate(from: origin, to: d.s2.place.coordinate).seconds)
    }

    // MARK: Stay cost

    @Test func stayWithoutConflictAnchorsTheNextStopToTheShootEnd() {
        let d = Day()
        let now = at(17.75)
        let live = d.live(now: now, progress: TripProgress(visited: [d.s1.id], currentStopID: d.s2.id, atCurrentStop: true))
        let next = live.next!
        let planned = StandardDay.window(.goldenEvening, on: testDay).end
        let arriveBy = at(20.167).addingTimeInterval(-minutes(30))
        let leaveBy = arriveBy.addingTimeInterval(-minutes(20) - LiveSchedule.safetyMargin(forDriveSeconds: minutes(20)))
        #expect(next.stopID == d.s3.id)
        #expect(near(next.leaveBy, leaveBy))
        #expect(next.earliestDeparture == planned)
        #expect(near(next.projectedArrival, leaveBy.addingTimeInterval(minutes(20))))
        let stay = live.stay!
        #expect(stay.currentStopID == d.s2.id && stay.nextStopID == d.s3.id)
        #expect(stay.plannedDeparture == planned)
        #expect(near(stay.latestDeparture, leaveBy))
        #expect(stay.cutsShortBy == nil)
        #expect(!stay.conflicts)
        // AlarmPlan: leave-by (>= earliestDeparture) is untouched, so alarms fire at the truthful leave-by.
        let alarms = AlarmPlan.make(live: live, trip: d.trip, now: now).filter { $0.stopID == d.s3.id }
        #expect(alarms.map(\.kind) == [.leaveSoon, .leaveNow])
        #expect(near(alarms.last?.fireAt, leaveBy))
    }

    @Test func stayConflictKeepsTheTruthfulLeaveByAndExposesTheCost() {
        let d = Day(mesaToDarkMinutes: 100)
        let now = at(17.0)
        let live = d.live(now: now, progress: TripProgress(visited: [d.s1.id], currentStopID: d.s2.id, atCurrentStop: true))
        let next = live.next!
        let planned = StandardDay.window(.goldenEvening, on: testDay).end
        let arriveBy = at(20.167).addingTimeInterval(-minutes(30))
        let leaveBy = arriveBy.addingTimeInterval(-minutes(100) - LiveSchedule.safetyMargin(forDriveSeconds: minutes(100)))
        #expect(leaveBy < planned)
        #expect(near(next.leaveBy, leaveBy))
        #expect(next.earliestDeparture == nil)
        guard case .early = next.status else { Issue.record("expected early, got \(next.status)"); return }
        let stay = live.stay!
        #expect(stay.conflicts)
        #expect(near(stay.plannedDeparture, planned))
        #expect(abs(stay.cutsShortBy! - planned.timeIntervalSince(leaveBy)) < 1)
        // AlarmPlan: no earliestDeparture to push the alarm back, so it rings at the truthful leave-by, while you are still shooting.
        let alarms = AlarmPlan.make(live: live, trip: d.trip, now: now).filter { $0.stopID == d.s3.id }
        #expect(alarms.map(\.kind) == [.leaveSoon, .leaveNow])
        #expect(near(alarms.last?.fireAt, leaveBy))
    }

    @Test func stayIsNilWhenNotAtAStopOrWithNothingNext() {
        let d = Day()
        #expect(d.live(now: at(3)).stay == nil)
        let last = d.live(now: at(21), progress: TripProgress(visited: [d.s1.id, d.s2.id], currentStopID: d.s3.id, atCurrentStop: true))
        #expect(last.stay == nil)
    }

    @Test func overnightLodgingHasNoPlannedDeparture() {
        let a = stop("A", day: 0, .goldenEvening, lat: 40, lon: -110)
        let hotel = stop("Hotel", day: 0, .goldenEvening, lat: 40.1, lon: -110, kind: .lodging)
        let b = stop("B", day: 1, .goldenMorning, lat: 40.5, lon: -110)
        let trip = makeTrip([a, hotel, b])
        let live = LiveSchedule.make(trip: trip, start: nil, windows: standardWindows(trip), plannedLegs: legs(leg(hotel, b, minutes: 60)),
                                     progress: TripProgress(visited: [a.id], currentStopID: hotel.id, atCurrentStop: true),
                                     now: at(21), origin: nil, liveETAs: [:])
        let stay = live.stay!
        #expect(stay.plannedDeparture == nil)
        #expect(stay.cutsShortBy == nil && !stay.conflicts)
        #expect(stay.latestDeparture == live.next!.leaveBy)
        #expect(live.next!.earliestDeparture == nil)
    }

    // MARK: Evening-before transfers

    private func twoDay(_ timing: TransferTiming, lodging: Bool = false) -> (trip: Trip, a: Stop, b: Stop, hotel: Stop?, live: LiveSchedule) {
        let a = stop("A", day: 0, .goldenEvening, lat: 40, lon: -110)
        let hotel = stop("Hotel", day: 0, .goldenEvening, lat: 40.1, lon: -110, kind: .lodging)
        let b = stop("B", day: 1, .goldenMorning, lat: 41, lon: -110)
        let trip = makeTrip(lodging ? [a, hotel, b] : [a, b], timings: [1: timing])
        let visited: Set<UUID> = lodging ? [a.id, hotel.id] : [a.id]
        let live = LiveSchedule.make(trip: trip, start: nil, windows: standardWindows(trip), plannedLegs: [:],
                                     progress: TripProgress(visited: visited), now: at(19), origin: nil, liveETAs: [:])
        return (trip, a, b, lodging ? hotel : nil, live)
    }

    @Test func eveningBeforeCarriesTheTransferAndThePlannedDeparture() {
        let r = twoDay(.eveningBefore)
        let next = r.live.next!
        #expect(next.stopID == r.b.id)
        #expect(next.transfer == .eveningBefore)
        #expect(next.plannedDeparture == StandardDay.window(.goldenEvening, on: testDay).end)
        // leaveBy stays the hard morning latest departure.
        #expect(next.leaveBy! > at(0, day: 1) && next.leaveBy! < at(8, day: 1))
    }

    @Test func morningTransferHasNoPlannedDeparture() {
        let next = twoDay(.morning).live.next!
        #expect(next.transfer == .morning)
        #expect(next.plannedDeparture == nil)
    }

    @Test func sameDayStopsHaveNoTransfer() {
        let d = Day()
        let live = d.live(now: at(3))
        #expect(live.upcoming.allSatisfy { $0.transfer == nil && $0.plannedDeparture == nil })
    }

    @Test func eveningBeforeAfterAnOvernightLodgingIsMorning() {
        let next = twoDay(.eveningBefore, lodging: true).live.next!
        #expect(next.transfer == .morning)
        #expect(next.plannedDeparture == nil)
    }

    // MARK: Codable

    private func strip(_ any: Any, keys: Set<String>) -> Any {
        if let dict = any as? [String: Any] {
            return dict.filter { !keys.contains($0.key) }.mapValues { strip($0, keys: keys) }
        }
        if let array = any as? [Any] { return array.map { strip($0, keys: keys) } }
        return any
    }

    @Test func oldJSONWithoutTheNewKeysStillDecodes() throws {
        let r = twoDay(.eveningBefore)
        let d = Day()
        let stayLive = d.live(now: at(17.75), progress: TripProgress(visited: [d.s1.id], currentStopID: d.s2.id, atCurrentStop: true))
        #expect(stayLive.stay != nil)
        for original in [r.live, stayLive] {
            let data = try JSONEncoder().encode(original)
            let full = try JSONDecoder().decode(LiveSchedule.self, from: data)
            #expect(full == original)
            let old = try JSONSerialization.data(withJSONObject: strip(JSONSerialization.jsonObject(with: data), keys: ["stay", "transfer", "plannedDeparture"]))
            let decoded = try JSONDecoder().decode(LiveSchedule.self, from: old)
            #expect(decoded.stay == nil)
            #expect(decoded.upcoming.allSatisfy { $0.transfer == nil && $0.plannedDeparture == nil })
            #expect(decoded.next?.stopID == original.next?.stopID)
        }
    }
}

private func c(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }
