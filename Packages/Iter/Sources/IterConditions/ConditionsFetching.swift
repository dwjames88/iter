import Foundation
import IterModel
import IterSources

// The forecast download scheduler inside `ConditionsService`.
//
// A job registers a `FetchTicket` for each download it needs (synchronously, in priority order) and then awaits it.
// Tickets for identical downloads are joined. A ticket for a `BatchForecastProvider` waits for the coalescing window and
// then goes out with every other ticket for the same source and horizon in ONE `forecasts(at:span:)` call, so nearby
// places share NOAA tiles. A ticket for any other provider waits for a slot in that source's lane (its policy's
// `maxConcurrent`), best priority first. Nothing is dispatched while a just-admitted job is still registering
// (`unsettled > 0`), so the order and the batch contents do not depend on task timing.
//
// The provider calls run in tasks owned by the service and tied to their tickets: when the last awaiter of a ticket is
// cancelled the call is cancelled, and a batch call is cancelled when every ticket in it has been.

typealias ForecastResult = Result<Sourced<HourlySeries>, SourceError>

struct FetchKey: Hashable, Sendable {
    var source: SourceID
    var cell: String
    var hours: Int
}

final class FetchTicket {
    enum State { case queued, running }
    let id: Int
    let key: FetchKey
    let provider: any ForecastProvider
    let batchProvider: (any BatchForecastProvider)?
    let coordinate: Coordinate
    let span: TimeSpan
    let maxConcurrent: Int
    var priority: ConditionsPriority
    var state: State = .queued
    var refs = 0
    var waiters: [Int: CheckedContinuation<ForecastResult, Never>] = [:]
    var task: Task<Void, Never>?
    var runID: Int?

    init(id: Int, key: FetchKey, provider: any ForecastProvider, coordinate: Coordinate, span: TimeSpan, priority: ConditionsPriority) {
        self.id = id
        self.key = key
        self.provider = provider
        self.batchProvider = provider as? any BatchForecastProvider
        self.coordinate = coordinate
        self.span = span
        self.priority = priority
        self.maxConcurrent = provider.descriptor.policy.maxConcurrent
    }
}

final class BatchRun {
    var ticketIDs: [Int]
    var task: Task<Void, Never>?

    init(ticketIDs: [Int]) { self.ticketIDs = ticketIDs }
}

extension ConditionsService {
    /// Registers (or joins) the download of `hours` of forecast for `coordinate`. Call `awaitTicket` to get the result.
    func registerFetch(provider: any ForecastProvider, coordinate: Coordinate, hours: Int, priority: ConditionsPriority) -> Int {
        let key = FetchKey(source: provider.descriptor.id, cell: GeoCell.key(coordinate, degrees: configuration.forecastCellDegrees), hours: hours)
        if let id = inflightByKey[key], let t = tickets[id] {
            t.refs += 1
            t.priority = min(t.priority, priority)
            return id
        }
        ticketCounter += 1
        let start = floorHour(clock.now)
        let t = FetchTicket(id: ticketCounter, key: key, provider: provider, coordinate: coordinate,
                            span: TimeSpan(start: start, end: start.addingTimeInterval(Double(hours) * 3600)), priority: priority)
        t.refs = 1
        tickets[t.id] = t
        inflightByKey[key] = t.id
        pump()
        return t.id
    }

    func awaitTicket(_ id: Int) async -> ForecastResult {
        waiterCounter += 1
        let wid = waiterCounter
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<ForecastResult, Never>) in
                guard let t = tickets[id] else { c.resume(returning: .failure(.cancelled)); return }
                if Task.isCancelled { c.resume(returning: .failure(.cancelled)); dropRef(id); return }
                t.waiters[wid] = c
            }
        } onCancel: {
            Task { await self.cancelWaiter(ticket: id, waiter: wid) }
        }
    }

    func cancelWaiter(ticket id: Int, waiter wid: Int) {
        guard let t = tickets[id], let c = t.waiters.removeValue(forKey: wid) else { return }
        c.resume(returning: .failure(.cancelled))
        dropRef(id)
    }

    /// One awaiter let go of the ticket; the download is cancelled when nobody wants it.
    func dropRef(_ id: Int) {
        guard let t = tickets[id] else { return }
        t.refs -= 1
        guard t.refs <= 0 else { return }
        t.task?.cancel()
        let run = t.runID.flatMap { batchRuns[$0] }
        complete(id, .failure(.cancelled))
        if let runID = t.runID, let run, run.ticketIDs.allSatisfy({ tickets[$0] == nil }) {
            run.task?.cancel()
            batchRuns[runID] = nil
        }
    }

    func complete(_ id: Int, _ result: ForecastResult) {
        guard let t = tickets.removeValue(forKey: id) else { return }
        if inflightByKey[t.key] == id { inflightByKey[t.key] = nil }
        if t.state == .running, t.batchProvider == nil { laneRunning[t.key.source] = max(0, laneRunning[t.key.source, default: 0] - 1) }
        for (_, c) in t.waiters { c.resume(returning: result) }
        t.waiters.removeAll()
        pump()
    }

    /// A job finished registering; once every admitted job has, the queues may move.
    func settle(_ key: JobKey, generation: UInt64) {
        guard var j = jobs[key], j.generation == generation, !j.settled else { return }
        j.settled = true
        jobs[key] = j
        unsettled -= 1
        if unsettled == 0 { pump() }
    }

    func pump() {
        guard unsettled == 0 else { return }
        let queued = tickets.values.filter { $0.state == .queued }
        for t in queued.filter({ $0.batchProvider == nil }).sorted(by: { ($0.priority, $0.id) < ($1.priority, $1.id) }) {
            let source = t.key.source
            guard laneRunning[source, default: 0] < t.maxConcurrent else { continue }
            laneRunning[source, default: 0] += 1
            start(lane: t)
        }
        if queued.contains(where: { $0.batchProvider != nil }) { scheduleBatchTimer() }
    }

    private func start(lane t: FetchTicket) {
        t.state = .running
        let (id, provider, coordinate, span) = (t.id, t.provider, t.coordinate, t.span)
        t.task = Task {
            let result: ForecastResult
            do { result = .success(try await provider.forecast(at: coordinate, span: span)) } catch { result = .failure(SourceError.wrap(error)) }
            self.complete(id, result)
        }
    }

    private func scheduleBatchTimer() {
        guard batchTimer == nil else { return }
        batchTimer = Task { await self.runBatchTimer() }
    }

    private func runBatchTimer() async {
        while true {
            try? await clock.sleep(for: configuration.coalescingWindow)
            if unsettled == 0 { break }
        }
        batchTimer = nil
        flushBatches()
    }

    private func flushBatches() {
        struct Group { var source: SourceID; var hours: Int }
        let queued = tickets.values.filter { $0.state == .queued && $0.batchProvider != nil }
        var groups: [Group] = []
        for t in queued.sorted(by: { ($0.priority, $0.id) < ($1.priority, $1.id) }) {
            let g = Group(source: t.key.source, hours: t.key.hours)
            if !groups.contains(where: { $0.source == g.source && $0.hours == g.hours }) { groups.append(g) }
        }
        for g in groups {
            let members = queued.filter { $0.key.source == g.source && $0.key.hours == g.hours }
                .sorted { ($0.priority, $0.id) < ($1.priority, $1.id) }
            guard let first = members.first, let provider = first.batchProvider else { continue }
            var coordinates: [Coordinate] = []
            for m in members where !coordinates.contains(m.coordinate) { coordinates.append(m.coordinate) }
            batchCounter += 1
            let runID = batchCounter
            let run = BatchRun(ticketIDs: members.map(\.id))
            for m in members { m.state = .running; m.runID = runID }
            batchRuns[runID] = run
            let span = first.span
            let asked = coordinates
            run.task = Task {
                let answers = await provider.forecasts(at: asked, span: span)
                self.finishBatch(runID, answers)
            }
        }
    }

    private func finishBatch(_ runID: Int, _ answers: [Coordinate: ForecastResult]) {
        guard let run = batchRuns.removeValue(forKey: runID) else { return }
        for id in run.ticketIDs {
            guard let t = tickets[id] else { continue }
            complete(id, answers[t.coordinate] ?? .failure(Task.isCancelled ? .cancelled : .decoding("the batch had no answer for this point")))
        }
    }

    func floorHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }
}
