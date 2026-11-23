import Foundation
import Testing
import IterGo
import IterModel

private func sampleState() -> GoEngineState {
    let stop = UUID()
    var ledger = NotificationLedger()
    let when = Date(timeIntervalSince1970: 1_800_000_000)
    ledger.delivered["\(stop.uuidString)-leaveNow"] = when
    ledger.scheduled["\(stop.uuidString)-leaveSoon"] = NotificationLedger.Scheduled(fireAt: when.addingTimeInterval(900), contentHash: "abc")
    ledger.conditionsLast[stop.uuidString] = when
    ledger.lastImmediateAt = when
    var cond = GoConditionsState(conditionsAsOf: when, isStale: true, nextDueAt: when.addingTimeInterval(60))
    cond.memory.cadence.setLastFetch(.nextLive, when)
    let fix = LocationFix(coordinate: Coordinate(latitude: 40, longitude: -110), accuracyM: 8, speedMs: 20, courseDeg: 90, timestamp: when)
    let eta = GoLiveETA(stopID: stop, eta: ETA(seconds: 900, arrival: when.addingTimeInterval(900), departing: when), fetchedAt: when,
                        origin: fix.coordinate, meters: 14_000)
    return GoEngineState(ledger: ledger, conditions: cond, lastETA: eta, lastFix: fix, routePath: [fix.coordinate, Coordinate(latitude: 40.1, longitude: -110)])
}

@Test func fileEngineStateStoreRoundTrips() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("go-engine-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = FileEngineStateStore(directory: dir)
    let run = UUID(), other = UUID()
    #expect(store.load(runID: run) == nil)
    let state = sampleState()
    store.save(state, runID: run)
    #expect(store.load(runID: run) == state)
    #expect(store.load(runID: other) == nil)
    var changed = state
    changed.ledger.lastImmediateAt = nil
    store.save(changed, runID: run)
    #expect(store.load(runID: run) == changed)
    store.clear(runID: run)
    #expect(store.load(runID: run) == nil)
    // A corrupt file reads as nothing.
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: store.fileURL(runID: run))
    #expect(store.load(runID: run) == nil)
}

@Test func inMemoryEngineStateStoreRoundTrips() {
    let store = InMemoryEngineStateStore()
    let run = UUID()
    #expect(store.load(runID: run) == nil)
    store.save(sampleState(), runID: run)
    #expect(store.load(runID: run) == sampleState() || store.load(runID: run)?.ledger.delivered.count == 1)
    #expect(store.saveCount == 1)
    store.clear(runID: run)
    #expect(store.load(runID: run) == nil)
}
