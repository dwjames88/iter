import Testing
import Foundation
import Synchronization
import IterCore
@testable import IterServices

private let moab = Coordinate(latitude: 38.5733, longitude: -109.5498)
private let mesa = Coordinate(latitude: 38.3896, longitude: -109.8681)

private final class Counter: Sendable {
    private let value = Mutex(0)
    func next() -> Int { value.withLock { $0 += 1; return $0 } }
    var count: Int { value.withLock { $0 } }
}

private func leg(_ a: Coordinate, _ b: Coordinate) -> DriveLeg {
    DriveLeg(from: a, to: b, seconds: 2400, meters: 50_000, isEstimate: false, path: [a, b])
}

@Suite struct MapsDriveTimesTests {
    @Test func cachesPerPair() async throws {
        let calls = Counter()
        let service = MapKitDriveTimes(minimumSpacing: .zero, backoffs: [], sleep: { _ in }, fetch: { a, b in _ = calls.next(); return leg(a, b) })
        #expect(service.cachedLeg(from: moab, to: mesa) == nil)
        _ = try await service.drive(from: moab, to: mesa)
        _ = try await service.drive(from: moab, to: mesa)
        #expect(calls.count == 1)
        #expect(service.cachedLeg(from: moab, to: mesa)?.seconds == 2400)
        // The reverse direction is a different pair.
        _ = try await service.drive(from: mesa, to: moab)
        #expect(calls.count == 2)
    }

    @Test func coalescesInFlightRequests() async throws {
        let calls = Counter()
        let service = MapKitDriveTimes(minimumSpacing: .zero, backoffs: [], sleep: { _ in }, fetch: { a, b in
            _ = calls.next()
            try? await Task.sleep(for: .milliseconds(100))
            return leg(a, b)
        })
        try await withThrowingTaskGroup(of: DriveLeg.self) { group in
            for _ in 0..<8 { group.addTask { try await service.drive(from: moab, to: mesa) } }
            for try await _ in group {}
        }
        #expect(calls.count == 1)
    }

    @Test func retriesThrottledWithBackoffThenSucceeds() async throws {
        let calls = Counter()
        let sleeps = Mutex<[Duration]>([])
        let service = MapKitDriveTimes(minimumSpacing: .zero, backoffs: [.seconds(2), .seconds(5)],
                                       sleep: { d in sleeps.withLock { $0.append(d) } },
                                       fetch: { a, b in
            if calls.next() < 3 { throw MapServiceError.throttled }
            return leg(a, b)
        })
        let result = try await service.drive(from: moab, to: mesa)
        #expect(result.isEstimate == false)
        #expect(calls.count == 3)
        #expect(sleeps.withLock { $0 } == [.seconds(2), .seconds(5)])
    }

    @Test func givesUpAfterBackoffs() async {
        let calls = Counter()
        let service = MapKitDriveTimes(minimumSpacing: .zero, backoffs: [.seconds(2), .seconds(5)], sleep: { _ in },
                                       fetch: { _, _ in _ = calls.next(); throw MapServiceError.throttled })
        await #expect(throws: MapServiceError.throttled) { try await service.drive(from: moab, to: mesa) }
        #expect(calls.count == 3)
        #expect(service.cachedLeg(from: moab, to: mesa) == nil)
    }

    @Test func noRouteIsNotRetriedOrCached() async {
        let calls = Counter()
        let service = MapKitDriveTimes(minimumSpacing: .zero, backoffs: [.seconds(2)], sleep: { _ in },
                                       fetch: { _, _ in _ = calls.next(); throw MapServiceError.noRoute })
        await #expect(throws: MapServiceError.noRoute) { try await service.drive(from: moab, to: mesa) }
        #expect(calls.count == 1)
    }

    @Test func requestsAreSerialised() async throws {
        let active = Mutex(0), maxActive = Mutex(0)
        let service = MapKitDriveTimes(minimumSpacing: .zero, backoffs: [], sleep: { _ in }, fetch: { a, b in
            let n = active.withLock { $0 += 1; return $0 }
            maxActive.withLock { $0 = max($0, n) }
            try? await Task.sleep(for: .milliseconds(30))
            active.withLock { $0 -= 1 }
            return leg(a, b)
        })
        try await withThrowingTaskGroup(of: DriveLeg.self) { group in
            for i in 0..<5 { group.addTask { try await service.drive(from: moab, to: Coordinate(latitude: 38 + Double(i), longitude: -109)) } }
            for try await _ in group {}
        }
        #expect(maxActive.withLock { $0 } == 1)
    }
}
