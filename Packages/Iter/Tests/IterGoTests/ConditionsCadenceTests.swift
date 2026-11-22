import Foundation
import Testing
import IterModel
import IterGo

private let nid = UUID()

private func due(_ phase: GoPhase = .driving, at offset: TimeInterval = 0, power: PowerState = .normal, memory: ConditionsCadenceMemory,
                 next: UUID? = nid, today: Bool = true, fix: LocationFix? = cFix()) -> [ConditionsItem] {
    ConditionsCadence.due(now: cT0.addingTimeInterval(offset), phase: phase, power: power, memory: memory, nextStopID: next,
                          hasTodayStops: today, fix: fix)
}

/// Everything fetched at cT0 for the next stop `nid`, here at the default fix.
private func fetchedAll(at: Date = cT0) -> ConditionsCadenceMemory {
    var m = ConditionsCadenceMemory(nextStopID: nid, hereCoordinate: cFix().coordinate)
    for item in ConditionsItem.allCases { m.setLastFetch(item, at) }
    return m
}

@Test(arguments: [GoPhase.idle, .paused, .finished])
func inactivePhasesFetchNothing(phase: GoPhase) {
    #expect(due(phase, memory: ConditionsCadenceMemory()).isEmpty)
    #expect(ConditionsCadence.nextDue(now: cT0, phase: phase, power: .normal, memory: ConditionsCadenceMemory(), nextStopID: nid,
                                      hasTodayStops: true, fix: cFix()) == nil)
}

@Test func firstCallWhileDrivingFetchesEverythingInPriorityOrder() {
    #expect(due(.driving, memory: ConditionsCadenceMemory()) == [.hereLive, .nextLive, .nextForecast, .todayForecast, .pack])
}

@Test func intervalsFollowTheTable() {
    let m = fetchedAll()
    #expect(due(.driving, at: 14 * 60, memory: m).isEmpty)
    #expect(due(.driving, at: 15 * 60, memory: m) == [.hereLive, .nextLive])
    #expect(due(.driving, at: 59 * 60, memory: m) == [.hereLive, .nextLive])
    #expect(due(.driving, at: 60 * 60, memory: m) == [.hereLive, .nextLive, .nextForecast, .todayForecast])
    #expect(due(.driving, at: 3 * 3600 - 1, memory: m).contains(.pack) == false)
    #expect(due(.driving, at: 3 * 3600, memory: m).contains(.pack))
}

@Test func powerSavingStretchesEveryInterval() {
    let saving = PowerState(isLowPowerMode: true)
    let m = fetchedAll()
    #expect(due(.driving, at: 29 * 60, power: saving, memory: m).isEmpty)
    #expect(due(.driving, at: 30 * 60, power: saving, memory: m) == [.hereLive, .nextLive])
    #expect(due(.driving, at: 119 * 60, power: saving, memory: m) == [.hereLive, .nextLive])
    #expect(due(.driving, at: 120 * 60, power: saving, memory: m) == [.hereLive, .nextLive, .nextForecast, .todayForecast])
    #expect(due(.driving, at: 5 * 3600 + 3599, power: saving, memory: m).contains(.pack) == false)
    #expect(due(.driving, at: 6 * 3600, power: saving, memory: m).contains(.pack))
}

@Test(arguments: [GoPhase.armed, .atStop, .betweenStops])
func hereLiveWhenNotDrivingFollowsPositionNotTime(phase: GoPhase) {
    let m = fetchedAll()
    // Hours later, same place: here is not due, the rest is.
    #expect(!due(phase, at: 4 * 3600, memory: m).contains(.hereLive))
    // Moved 9 km: not yet. 11 km: due.
    let near = cFix(lat: 39.74 + 9_000 / 111_195)
    let far = cFix(lat: 39.74 + 11_000 / 111_195)
    #expect(!due(phase, at: 60, memory: m, fix: near).contains(.hereLive))
    #expect(due(phase, at: 60, memory: m, fix: far).contains(.hereLive))
    // Never fetched: due once.
    #expect(due(phase, memory: ConditionsCadenceMemory(nextStopID: nid)).contains(.hereLive))
}

@Test func hereLiveNeedsAUsableFix() {
    #expect(!due(.driving, memory: ConditionsCadenceMemory(), fix: nil).contains(.hereLive))
    let bad = LocationFix(coordinate: cFix().coordinate, accuracyM: 5000, timestamp: cT0)
    #expect(!due(.driving, memory: ConditionsCadenceMemory(), fix: bad).contains(.hereLive))
}

@Test func changedNextStopMakesNextItemsDueImmediately() {
    let m = fetchedAll()
    #expect(due(.driving, at: 60, memory: m).isEmpty)
    #expect(due(.driving, at: 60, memory: m, next: UUID()) == [.nextLive, .nextForecast])
}

@Test func noNextStopOrNoTodayStopsDropsThoseItems() {
    let m = ConditionsCadenceMemory()
    #expect(due(.atStop, memory: m, next: nil, today: false) == [.hereLive, .pack])
}

@Test func nextDueIsTheEarliestScheduledTime() {
    let m = fetchedAll()
    let d = ConditionsCadence.nextDue(now: cT0.addingTimeInterval(60), phase: .driving, power: .normal, memory: m, nextStopID: nid,
                                      hasTodayStops: true, fix: cFix())
    #expect(d == cT0.addingTimeInterval(15 * 60))
    let saving = ConditionsCadence.nextDue(now: cT0.addingTimeInterval(60), phase: .driving, power: PowerState(isLowPowerMode: true), memory: m,
                                           nextStopID: nid, hasTodayStops: true, fix: cFix())
    #expect(saving == cT0.addingTimeInterval(30 * 60))
    // Something already overdue: now.
    let late = cT0.addingTimeInterval(2 * 3600)
    #expect(ConditionsCadence.nextDue(now: late, phase: .driving, power: .normal, memory: m, nextStopID: nid, hasTodayStops: true,
                                      fix: cFix()) == late)
    // At a stop, here is position-triggered: the next wake is the next live refresh.
    let atStop = ConditionsCadence.nextDue(now: cT0, phase: .atStop, power: .normal, memory: m, nextStopID: nid, hasTodayStops: true, fix: cFix())
    #expect(atStop == cT0.addingTimeInterval(15 * 60))
}
