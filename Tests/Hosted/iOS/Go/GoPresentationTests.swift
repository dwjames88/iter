import Foundation
import IterGoActivity
import Testing
@testable import Iter

@Suite struct GoPresentationTests {
    private func p(_ s: GoSample, minutesLater: Double = 0, stale: Bool = false) -> GoPresentation {
        let now = GoRenderCase.now
        return GoPresentation(GoActivityContent(snapshot: s.snapshot(now: now)), clock: .frozen(now.addingTimeInterval(minutesLater * 60)),
                              zone: TimeZone(identifier: "America/Denver")!, isStale: stale)
    }

    @Test func armedCountsDownToLeaveBy() throws {
        let x = p(.armedEarly)
        let countdown = try #require(x.countdown)
        #expect(countdown.label == "Leave in")
        #expect(countdown.target == x.content.leaveBy)
        #expect(x.status == nil)
    }

    @Test func drivingCountsDownToArrival() throws {
        let x = p(.drivingOnTime)
        #expect(try #require(x.countdown).target == x.content.eta)
        #expect(x.clockLine?.hasPrefix("Arrive") == true)
    }

    @Test func leaveNowReplacesTheCountdown() {
        let x = p(.leaveNow)
        #expect(x.countdown == nil)
        #expect(x.status?.text == "Leave now")
    }

    @Test func lateAndMissedUseTheWarningTone() {
        #expect(p(.drivingLate).status?.tone == .warning)
        #expect(p(.drivingMissed).status?.tone == .warning)
    }

    @Test func pastLeaveByTurnsIntoLateWithoutANewUpdate() throws {
        // The content says "early"; the clock has since passed leave-by by ten minutes.
        let base = p(.armedEarly)
        let leaveBy = try #require(base.content.leaveBy)
        let later = GoPresentation(base.content, clock: .frozen(leaveBy.addingTimeInterval(10 * 60)), zone: base.zone)
        #expect(later.countdown == nil)
        #expect(later.status?.tone == .warning)
        #expect(later.status?.text.contains("10") == true)
    }

    @Test func oldDataSaysHowOldItIs() {
        #expect(p(.drivingOnTime).ageText == nil)
        #expect(p(.drivingOnTime, minutesLater: 20).ageText?.hasPrefix("As of") == true)
        let stale = p(.stale)
        #expect(stale.ageText != nil)
        #expect(stale.isDim)
    }

    @Test func offlineIsNamedEvenWhenFresh() {
        #expect(p(.offline).ageText?.contains("Offline") == true)
    }

    @Test func finishedRunHasNoAgeLine() { #expect(p(.finished).ageText == nil) }

    @Test func finishedPausedAndIdle() {
        #expect(p(.finished).status?.text == "Trip complete")
        #expect(p(.paused).status?.text == "Paused")
        #expect(p(.idle).isIdle)
        #expect(p(.idle).countdown == nil)
    }

    @Test func frozenCountdownFormat() {
        #expect(GoPresentation.frozen(5050) == "1:24:10")
        #expect(GoPresentation.frozen(1450) == "24:10")
        #expect(GoPresentation.frozen(-5) == "0:00")
    }

    @Test func deepLinks() {
        #expect(GoDeepLink.go.absoluteString == "iter://go")
        #expect(GoDeepLink.navigate().absoluteString == "iter://go/navigate")
        let id = UUID(uuidString: "5A3E0000-0000-4000-8000-000000000002")!
        #expect(GoDeepLink.navigate(stop: id).absoluteString == "iter://go/navigate?stop=5A3E0000-0000-4000-8000-000000000002")
    }

    @Test func contentFitsTheActivityBudget() throws {
        for s in GoSample.allCases {
            let data = try JSONEncoder().encode(GoActivityContent(snapshot: s.snapshot(now: GoRenderCase.now)))
            #expect(data.count < 2048)
        }
    }
}
