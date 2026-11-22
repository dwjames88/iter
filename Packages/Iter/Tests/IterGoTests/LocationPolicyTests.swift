import Foundation
import Testing
import IterGo
import IterModel

private let here = Coordinate(latitude: 36.0, longitude: -118.0)
private let stopC = Coordinate(latitude: 36.5, longitude: -118.5)
private let stop = (id: "s1", coordinate: stopC, radius: 300.0)
private let saving = PowerState(isLowPowerMode: true)

private func mode(_ phase: GoPhase, _ until: TimeInterval? = nil, power: PowerState = .normal, withStop: Bool = true) -> LocationMode {
    LocationPolicy.mode(phase: phase, untilLeaveBy: until, startOrCurrentCoordinate: here, nextStop: withStop ? stop : nil, power: power)
}

@Test func locationOffPhases() {
    for phase in [GoPhase.idle, .paused, .finished] {
        #expect(mode(phase, 60) == .off)
        #expect(mode(phase, 60, power: saving) == .off)
    }
}

@Test func armedAndBetweenStopsBoundary() {
    for phase in [GoPhase.armed, .betweenStops] {
        #expect(mode(phase, 2 * 3600 + 1) == .off)
        #expect(mode(phase, nil) == .off)
        let expected = LocationMode.monitor(regions: [MonitoredRegion(id: LocationPolicy.leaveRegionID, center: here, radiusM: 500, notifyOn: .exit)],
                                            significantChange: true)
        #expect(mode(phase, 2 * 3600) == expected)
        #expect(mode(phase, 0) == expected)
        #expect(mode(phase, -600) == expected)
        #expect(mode(phase, 600, power: saving) == expected)
    }
    #expect(LocationPolicy.mode(phase: .armed, untilLeaveBy: 60, startOrCurrentCoordinate: nil, nextStop: nil, power: .normal) == .off)
}

@Test func drivingProfilesAndBackupRegion() {
    let backup = [MonitoredRegion(id: LocationPolicy.arrivalRegionID, center: stopC, radiusM: 300, notifyOn: .enter)]
    #expect(mode(.driving) == .continuous(.drivingNormal, backupRegions: backup))
    #expect(mode(.driving, power: saving) == .continuous(.drivingPowerSaving, backupRegions: backup))
    #expect(mode(.driving, power: PowerState(batteryLevel: 0.1)) == .continuous(.drivingPowerSaving, backupRegions: backup))
    #expect(mode(.driving, withStop: false) == .continuous(.drivingNormal, backupRegions: []))
    #expect(LocationAccuracyProfile.drivingNormal.kind == .automotiveNavigation)
    #expect(LocationAccuracyProfile.drivingPowerSaving.desiredAccuracyM == 100)
    #expect(LocationAccuracyProfile.drivingPowerSaving.distanceFilterM == 200)
}

@Test func atStopExitRegionIsRadiusPlus250() {
    let expected = LocationMode.monitor(regions: [MonitoredRegion(id: LocationPolicy.stopExitRegionID, center: stopC, radiusM: 550, notifyOn: .exit)],
                                        significantChange: true)
    #expect(mode(.atStop) == expected)
    #expect(mode(.atStop, power: saving) == expected)
    #expect(mode(.atStop, withStop: false) == .monitor(regions: [], significantChange: true))
}

@Test func routeDeviation() {
    let a = Coordinate(latitude: 40, longitude: -100)
    let b = Coordinate(latitude: 40, longitude: -99)   // about 85 km east
    let path = [a, b]
    func fix(_ c: Coordinate, accuracy: Double = 10) -> LocationFix { LocationFix(coordinate: c, accuracyM: accuracy, timestamp: Date(timeIntervalSince1970: 0)) }
    let onLine = Coordinate(latitude: 40, longitude: -99.5)
    #expect(RouteDeviation.distance(from: onLine, to: path) < 1)
    // 0.005 deg of latitude is about 556 m, 0.012 about 1334 m.
    #expect(!RouteDeviation.needsReroute(fix: fix(Coordinate(latitude: 40.005, longitude: -99.5)), path: path))
    #expect(RouteDeviation.needsReroute(fix: fix(Coordinate(latitude: 40.012, longitude: -99.5)), path: path))
    // Beyond the end, the distance is to the endpoint.
    let beyond = Coordinate(latitude: 40, longitude: -98.9)
    #expect(abs(RouteDeviation.distance(from: beyond, to: path) - beyond.distance(to: b)) < 5)
    #expect(!RouteDeviation.needsReroute(fix: fix(Coordinate(latitude: 41, longitude: -99.5)), path: []))
    #expect(!RouteDeviation.needsReroute(fix: fix(Coordinate(latitude: 41, longitude: -99.5), accuracy: 500), path: path))
    #expect(RouteDeviation.distance(from: onLine, to: []) == .infinity)
}

@Test func locationTraceIsDeterministic() {
    let path = [Coordinate(latitude: 40, longitude: -100), Coordinate(latitude: 40, longitude: -99.9), Coordinate(latitude: 40.1, longitude: -99.9)]
    let start = Date(timeIntervalSince1970: 1_000_000)
    let a = LocationTrace.fixes(along: path, speedMs: 25, interval: 5, start: start, jitterM: 8, seed: 7)
    let b = LocationTrace.fixes(along: path, speedMs: 25, interval: 5, start: start, jitterM: 8, seed: 7)
    let c = LocationTrace.fixes(along: path, speedMs: 25, interval: 5, start: start, jitterM: 8, seed: 8)
    #expect(a == b)
    #expect(a != c)
    let total = LocationTrace.length(of: path)
    #expect(a.count == Int((total / 25 / 5).rounded(.down)) + 2)
    #expect(a.first?.timestamp == start)
    #expect(a.allSatisfy { $0.speedMs == 25 && $0.accuracyM >= 8 })
    // Without jitter the fixes sit on the line and end at the end.
    let clean = LocationTrace.fixes(along: path, speedMs: 25, interval: 5, start: start)
    #expect(clean.allSatisfy { RouteDeviation.distance(from: $0.coordinate, to: path) < 1 })
    #expect(clean.last!.coordinate.distance(to: path.last!) < 1)
    #expect(abs(clean[1].coordinate.distance(to: clean[0].coordinate) - 125) < 1)
    #expect(zip(clean, clean.dropFirst()).allSatisfy { $0.1.timestamp > $0.0.timestamp })
    let parked = LocationTrace.stationary(at: path[0], duration: 60, interval: 10, start: start)
    #expect(parked.count == 7 && parked.allSatisfy { $0.speedMs == 0 })
}

@MainActor
@Test func scriptedLocationRecords() async {
    let clock = ManualClock(Date(timeIntervalSince1970: 100))
    let loc = ScriptedLocation(clock: clock)
    #expect(loc.authorization == .notDetermined)
    loc.requestWhenInUse()
    loc.requestAlways()
    #expect(loc.authorizationRequests == [.whenInUse, .always])
    #expect(loc.authorization == .notDetermined)
    loc.apply(.off)
    clock.advance(by: 30)
    loc.apply(.continuous(.drivingNormal, backupRegions: []))
    #expect(loc.applied.map(\.at) == [Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 130)])
    #expect(loc.currentMode == .continuous(.drivingNormal, backupRegions: []))
    let fix = LocationFix(coordinate: here, accuracyM: 5, timestamp: clock.now)
    loc.send(.fix(fix))
    loc.send(.regionExited("go.leave"))
    loc.setAuthorization(.always)
    loc.finish()
    var got: [LocationEvent] = []
    for await e in loc.events { got.append(e) }
    #expect(got == [.fix(fix), .regionExited("go.leave"), .authorizationChanged(.always)])
}

@MainActor
@Test func scriptedLocationGrantsWhenAsked() {
    let loc = ScriptedLocation(clock: ManualClock(.now))
    loc.grantOnRequest = true
    loc.requestWhenInUse()
    #expect(loc.authorization == .whenInUse)
    loc.requestAlways()
    #expect(loc.authorization == .always)
}
