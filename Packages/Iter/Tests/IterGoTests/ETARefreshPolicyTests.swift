import Foundation
import Testing
import IterGo
import IterModel

private let now = Date(timeIntervalSince1970: 1_000_000)
private let saving = PowerState(isLowPowerMode: true)

private func next(last: Date? = nil, phase: GoPhase, until: TimeInterval? = nil, moved: Double = 0, stationary: Bool = false,
                  power: PowerState = .normal, backoff: Date? = nil) -> Date? {
    ETARefreshPolicy.nextRefresh(lastRequestAt: last, now: now, phase: phase, untilLeaveBy: until, remainingDriveSeconds: nil,
                                 movedSinceLastRequestM: moved, isStationary: stationary, power: power, backoffUntil: backoff)
}

private func interval(_ phase: GoPhase, until: TimeInterval?, power: PowerState = .normal) -> TimeInterval? {
    next(last: now, phase: phase, until: until, power: power).map { $0.timeIntervalSince(now) }
}

@Test func etaNilPhases() {
    for p in [GoPhase.idle, .paused, .finished] { #expect(next(phase: p) == nil) }
}

@Test func etaDrivingCadence() {
    #expect(interval(.driving, until: nil) == 180)
    #expect(interval(.driving, until: nil, power: saving) == 600)
    #expect(next(last: now, phase: .driving, stationary: true)?.timeIntervalSince(now) == 360)
    #expect(next(last: now, phase: .driving, stationary: true, power: saving)?.timeIntervalSince(now) == 600)
    #expect(next(phase: .driving) == now)
    // Moved 2 km: due 60 s after the last, not before and not at the 3 min mark.
    #expect(next(last: now, phase: .driving, moved: 2000)?.timeIntervalSince(now) == 60)
    #expect(next(last: now, phase: .driving, moved: 1999)?.timeIntervalSince(now) == 180)
    #expect(next(last: now.addingTimeInterval(-100), phase: .driving, moved: 5000) == now.addingTimeInterval(-40))
}

@Test func etaLeaveByTable() {
    let table: [(TimeInterval?, TimeInterval)] = [
        (nil, 3600), (3 * 3600, 3600), (7201, 3600),
        (7200, 900), (3601, 900), (3600, 900),
        (3599, 300), (1800, 300),
        (1799, 180), (1, 180),
        (0, 120), (-60, 120), (-7200, 120),
    ]
    for phase in [GoPhase.armed, .betweenStops, .atStop] {
        for (until, expected) in table {
            #expect(interval(phase, until: until) == expected, "\(phase) \(String(describing: until))")
        }
    }
}

@Test func etaPowerSavingDoublesWithFloor() {
    let table: [(TimeInterval?, TimeInterval)] = [(10_000, 7200), (5000, 1800), (2000, 600), (900, 600), (0, 600)]
    for (until, expected) in table { #expect(interval(.armed, until: until, power: saving) == expected, "\(String(describing: until))") }
    #expect(interval(.armed, until: 5000, power: PowerState(batteryLevel: 0.19)) == 1800)
}

@Test func etaNeverBeforeBackoff() {
    let backoff = now.addingTimeInterval(500)
    #expect(next(last: now, phase: .driving, backoff: backoff) == backoff)
    #expect(next(phase: .armed, until: 100, backoff: backoff) == backoff)
    #expect(next(last: now, phase: .driving, backoff: now.addingTimeInterval(10)) == now.addingTimeInterval(180))
}

@Test func etaDepartureDate() {
    let later = now.addingTimeInterval(3600)
    #expect(ETARefreshPolicy.departureDate(now: now, leaveBy: later, phase: .driving) == now)
    #expect(ETARefreshPolicy.departureDate(now: now, leaveBy: later, phase: .armed) == later)
    #expect(ETARefreshPolicy.departureDate(now: now, leaveBy: now.addingTimeInterval(-5), phase: .atStop) == now)
    #expect(ETARefreshPolicy.departureDate(now: now, leaveBy: nil, phase: .betweenStops) == now)
}
