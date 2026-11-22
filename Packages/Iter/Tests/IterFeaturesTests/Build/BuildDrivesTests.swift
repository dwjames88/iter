import Foundation
import Testing
import IterAstro
import IterModel
import IterPlan
import IterSky
import IterSources
import IterStore
@testable import IterFeatures

@MainActor
@Suite struct BuildDrivesTests {
    private func settled(_ model: BuildModel) async -> Bool {
        let done = await settle { !model.isLoadingDrives }
        model.refreshIfChanged()
        return done
    }

    @Test func backoffDoublesFromThirtySecondsAndStopsAtFiveMinutes() {
        let backoff = DriveRetryBackoff.standard
        #expect((0..<8).map { backoff.delay(forAttempt: $0) } == [30, 60, 120, 240, 300, 300, 300, 300])
        #expect(backoff.delay(forAttempt: 10_000) == 300)
        #expect(backoff.delay(forAttempt: -1) == 30)
    }

    // MARK: Cache

    @Test func aKnownPairIsNeverAskedForAgain() async throws {
        let h = try BuildHarness()
        let model = h.model()
        model.open()
        #expect(await settled(model))
        // Five pairs, each asked for typical and, being within the traffic horizon, once with its departure time.
        #expect(model.directionsRequestCount == 10)
        let before = model.directionsRequestCount
        let mesa = try #require(model.stop(named: "Mesa Arch")).id
        // Nudge Mesa Arch to day 2 (new pairs), then back (known pairs again), then reorder and reload.
        model.moveStop(mesa, toDay: 1, index: 1)
        #expect(await settled(model))
        let afterNudge = model.directionsRequestCount
        #expect(afterNudge > before)
        let seen = Set(model.directionsRequests.map { "\($0.from.latitude),\($0.to.latitude),\($0.departing.map { String($0.timeIntervalSince1970) } ?? "-")" })
        #expect(seen.count == afterNudge, "no request repeated")
        model.moveStop(mesa, toDay: 2, index: 0)
        #expect(await settled(model))
        #expect(model.directionsRequestCount == afterNudge, "moving back is answered by the cache")
        model.close()
    }

    @Test func aMovedPlaceMakesItsPairsStaleButOthersStay() async throws {
        let h = try BuildHarness()
        let model = h.model()
        // An own place can be moved; put one in the middle of day 3.
        let own = h.ownPlace("Camp")
        let place = try #require(h.library.places.value(id: own))
        let id = try #require(model.addStop(place, day: 2, session: .goldenEvening, at: 1))
        model.open()
        #expect(await settled(model))
        let count = model.directionsRequestCount
        let record = try #require(h.library.places.place(id: own))
        let moved = Coordinate(latitude: 38.5, longitude: -109.7)
        h.library.places.moveSpot(record, to: moved)
        model.refreshIfChanged()
        #expect(await settled(model))
        let fresh = model.directionsRequests.dropFirst(count)
        #expect(!fresh.isEmpty)
        // Only the pairs into and out of the moved place are asked for again.
        #expect(fresh.allSatisfy { $0.from == moved || $0.to == moved })
        #expect(model.stopRows.first { $0.id == id }?.coordinate == moved)
        model.close()
    }

    // MARK: Spacing and in-flight cap

    @Test func lookupsAreSpacedAndAtMostTwoRunAtOnce() async throws {
        // Spacing sleeps wait for the test; the answers are held too, so lookups pile up in flight.
        let sleeper = TestSleeper(holds: { $0 == .milliseconds(200) })
        let h = try BuildHarness(sleeper: sleeper)
        h.routing.hold()
        let model = h.model()
        model.open()
        #expect(await settle { h.routing.inFlight == 1 })
        for _ in 0..<50 { await Task.yield() }
        #expect(h.routing.inFlight == 1, "the gate is closed until the spacing has passed")
        #expect(sleeper.requested == [.milliseconds(200)])
        sleeper.fire()
        #expect(await settle { h.routing.inFlight == 2 })
        // Two in flight: a third never starts, however often the gate opens.
        for _ in 0..<5 {
            sleeper.fire()
            for _ in 0..<50 { await Task.yield() }
        }
        #expect(h.routing.inFlight == 2)
        #expect(h.routing.peak == 2)
        #expect(model.isLoadingDrives)
        // Let the answers through: the rest follow, each start one spacing after the last.
        h.routing.release()
        for _ in 0..<40 {
            sleeper.fire()
            for _ in 0..<20 { await Task.yield() }
        }
        h.routing.hold()
        h.routing.release()
        for _ in 0..<40 {
            sleeper.fire()
            for _ in 0..<20 { await Task.yield() }
        }
        #expect(await settle { !model.isLoadingDrives })
        #expect(h.routing.peak <= 2 && model.peakDirectionsInFlight <= 2)
        #expect(model.directionsRequestCount == 10)
        model.close()
    }

    @Test func closingCancelsQueuedAndRunningLookups() async throws {
        let sleeper = TestSleeper(holds: { $0 == .milliseconds(200) })
        let h = try BuildHarness(sleeper: sleeper)
        h.routing.hold()
        let model = h.model()
        model.open()
        #expect(await settle { h.routing.inFlight == 1 })
        model.close()
        #expect(await settle { h.routing.inFlight == 0 }, "the running lookup was cancelled")
        sleeper.fire()
        for _ in 0..<50 { await Task.yield() }
        #expect(model.directionsRequestCount == 1, "nothing started after close")
        #expect(!model.isLoadingDrives)
    }

    // MARK: Retry

    @Test func failedLookupsAreRetriedOnTheOldBackoffAndTheRowsSayWhen() async throws {
        let sleeper = TestSleeper(holds: { $0 >= .seconds(30) })
        let h = try BuildHarness(sleeper: sleeper)
        h.routing.setFailure(SourceError.rateLimited(retryAfter: nil))
        let model = h.model()
        model.open()
        // Five typical lookups fail once each and wait 30 seconds.
        #expect(await settle { sleeper.waiting.count == 5 })
        #expect(sleeper.requested.filter { $0 >= .seconds(30) } == Array(repeating: .seconds(30), count: 5))
        model.refreshIfChanged()
        let states = model.driveRows.map(\.state)
        #expect(states.allSatisfy { $0 == .failed(retryAt: testNow.addingTimeInterval(30)) })
        #expect(model.driveRows.allSatisfy { $0.isEstimate && $0.basis == .estimate }, "the estimate shows meanwhile")
        // Each pass fails again and waits twice as long, up to five minutes.
        for expected in [60.0, 120, 240, 300, 300] {
            sleeper.fire { $0 >= .seconds(30) }
            #expect(await settle { sleeper.waiting.count == 5 && sleeper.requested.contains(.seconds(expected)) })
            #expect(Set(sleeper.waiting) == [.seconds(expected)])
        }
        // The connection comes back: the next retry succeeds and the rows become real.
        h.routing.setFailure(nil)
        sleeper.fire { $0 >= .seconds(30) }
        #expect(await settle { model.refreshIfChanged(); return model.driveRows.allSatisfy { $0.state == .ready && !$0.isEstimate } })
        model.close()
    }

    @Test func noRouteIsFinalAndNeverRetried() async throws {
        let sleeper = TestSleeper(holds: { $0 >= .seconds(30) })
        let h = try BuildHarness(sleeper: sleeper)
        h.routing.setFailure(SourceError.http(status: 404, excerpt: "directions not found"))
        let model = h.model()
        model.open()
        #expect(await settled(model))
        #expect(model.driveRows.allSatisfy { $0.state == .noRoute && $0.isEstimate && $0.basis == .estimate })
        #expect(sleeper.requested.allSatisfy { $0 < .seconds(30) }, "no retry timer")
        #expect(model.directionsRequestCount == 5)
        model.close()
    }

    // MARK: Departure time

    @Test func driveRowsSayWhetherTrafficOrTypicalWasUsed() async throws {
        let h = try BuildHarness()
        let model = h.model()
        model.open()
        #expect(await settled(model))
        let leaveBys = model.driveRows.compactMap(\.leaveBy)
        #expect(leaveBys.count == 5)
        for drive in model.driveRows {
            guard case .trafficAware(let departing) = drive.basis else { Issue.record("not traffic-aware: \(String(describing: drive.basis))"); continue }
            // The departure is the planned leave time rounded down to a half hour.
            let leave = try #require(drive.leaveBy)
            #expect(departing <= leave.addingTimeInterval(DriveFetcher.bucketSeconds * 2))
            #expect(departing.timeIntervalSince1970.truncatingRemainder(dividingBy: DriveFetcher.bucketSeconds) == 0)
            #expect(drive.state == .ready)
        }
        let requests = model.directionsRequests
        #expect(requests.filter { $0.departing == nil }.count == 5)
        #expect(requests.filter { $0.departing != nil }.count == 5)
        #expect(requests.prefix(5).allSatisfy { $0.departing == nil }, "the typical drives come first")
        model.close()
    }

    @Test func aTripBeyondTheTrafficHorizonIsLabelledTypical() async throws {
        let h = try BuildHarness()
        let model = h.model()
        _ = model.changeDates(startDay: h.day.adding(days: 60), dayCount: 4)
        model.open()
        #expect(await settled(model))
        #expect(model.directionsRequests.allSatisfy { $0.departing == nil })
        #expect(model.directionsRequestCount == 5)
        #expect(model.driveRows.allSatisfy { $0.basis == .typical && $0.state == .ready })
        #expect(DriveBasis.typical.label == "Typical" && DriveBasis.estimate.label == "Estimated")
        model.close()
    }

    @Test func aTripInThePastIsLabelledTypicalToo() async throws {
        let h = try BuildHarness()
        let model = h.model()
        _ = model.changeDates(startDay: h.day.adding(days: -30), dayCount: 4)
        model.open()
        #expect(await settled(model))
        #expect(model.directionsRequests.allSatisfy { $0.departing == nil })
        model.close()
    }

    // MARK: Start place and leave-by

    @Test func theFirstStopHasALeaveByFromTheStartPlace() async throws {
        let h = try BuildHarness()
        let model = h.model()
        #expect(model.startPlace == nil)
        let home = h.ownPlace()
        model.setStartPlace(home)
        let start = try #require(model.startPlace)
        #expect(start.name == "Home Base")
        // Before the drive is known the leave-by comes from the straight-line estimate.
        let estimate = try #require(start.firstLeaveBy)
        model.open()
        #expect(await settled(model))
        let leave = try #require(model.startPlace?.firstLeaveBy)
        #expect(leave != estimate)
        // arrive-by (window start - set-up - walk-in) minus the drive.
        let place = h.spot("horseshoe-bend")
        let window = try #require(LightEngine(ephemeris: Astronomy()).sessionWindow(for: place, kind: .goldenEvening, on: h.day))
        let arrive = window.start.addingTimeInterval(-(20 + 25) * 60)
        let first = try #require(model.driveRows.first)
        #expect(first.fromStart && first.fromName == "Home Base")
        #expect(leave == arrive.addingTimeInterval(-(first.seconds ?? 0)))
        #expect(first.leaveBy == leave)
        // The first drive is a transfer card on day 1 with no morning or evening choice.
        let transfer = try #require(model.transferRows.first { $0.day == 0 })
        #expect(transfer.canChooseTiming == false && transfer.overnight == nil)
        model.setStartPlace(nil)
        #expect(model.startPlace == nil)
        model.close()
    }

    @Test func startPlaceCandidatesListLodgingFirst() throws {
        let h = try BuildHarness()
        let model = h.model()
        let hotel = Place(name: "Page Inn", coordinate: Coordinate(latitude: 36.91, longitude: -111.46),
                          timeZoneIdentifier: "America/Phoenix", category: .landscape, origin: .user)
        _ = model.addStop(hotel, day: 0, kind: .lodging)
        #expect(model.startPlaceCandidates().first?.name == "Page Inn")
        #expect(model.startPlaceCandidates().count >= 7)
    }

    // MARK: A drive that does not fit

    @Test func aDriveThatDoesNotFitIsAnIssueOnTheDriveAndTheTrip() async throws {
        let h = try BuildHarness()
        h.routing.setScale(30)   // every drive takes thirty times as long
        let model = h.model()
        model.open()
        #expect(await settled(model))
        let failing = model.driveRows.filter { !$0.fits }
        #expect(!failing.isEmpty)
        let issue = try #require(failing.first?.issue)
        guard case .driveDoesNotFit(let short) = issue else { Issue.record("wrong issue"); return }
        #expect(short > 0)
        #expect(issue.message(locale: Locale(identifier: "en_US")).hasPrefix("Drive doesn't fit: "))
        #expect(issue.message(locale: Locale(identifier: "en_US")).hasSuffix(" short"))
        #expect(model.header?.issueCount ?? 0 > 0)
        #expect(model.rows.contains { if case .conflicts(let n) = $0.kind { n > 0 } else { false } })
        // The stop card does not repeat it.
        #expect(model.stopRows.allSatisfy { stop in !stop.issues.contains { if case .driveDoesNotFit = $0 { true } else { false } } })
        model.close()
    }

    @Test func issueMessagesAreWordedForTheCard() {
        let en = Locale(identifier: "en_US")
        #expect(BuildIssue.driveDoesNotFit(shortBySeconds: 25 * 60).message(locale: en) == "Drive doesn't fit: 25 min short")
        #expect(BuildIssue.driveDoesNotFit(shortBySeconds: 65 * 60).message(locale: en) == "Drive doesn't fit: 1 hr, 5 min short")
        #expect(BuildIssue.driveDoesNotFit(shortBySeconds: 10).message(locale: en) == "Drive doesn't fit: 1 min short")
        #expect(BuildIssue.outOfOrder.message(locale: en) == "This window starts before the stop above it")
        #expect(BuildIssue(.driveEstimated) == nil)
    }
}
