import Foundation
import IterCore
import IterData
import IterLight
import IterServices
import IterFeatures

/// Walks the main view models once and logs what it found. Runs with `-IterSmokeTest YES -IterInMemoryStore YES`,
/// shows no UI, and never throws or crashes: every step is isolated and reports its own failure.
enum SmokeHook {
    private struct TimedOut: Error {}

    @MainActor static func run(_ model: AppModel) async {
        log("start")
        await trip(model)
        await forecast(model)
        light(model)
        await search(model)
        await geocode(model)
        await scout(model)
        log("done")
    }

    // MARK: Steps

    @MainActor private static func trip(_ model: AppModel) async {
        let record = model.store.seedSampleTrip(startDay: model.today(in: .current).adding(days: 1))
        let plan = record.plan
        log("trip: \(plan.name), \(plan.dayCount) days, \(plan.stops.count) stops")
        let byID = Dictionary(uniqueKeysWithValues: plan.stops.map { ($0.id, $0.spot) })
        var legs: [LegKey: DriveLeg] = [:]
        let pairs = model.scheduler.legPairsNeeded(for: plan)
        for key in pairs {
            guard let a = byID[key.from], let b = byID[key.to] else { continue }
            do {
                legs[key] = try await withTimeout(seconds: 20) { try await model.drives.drive(from: a.coordinate, to: b.coordinate) }
            } catch {
                log("drive \(a.name) to \(b.name): failed (\(describe(error))); the schedule will use an estimate")
            }
        }
        let schedule = model.scheduler.schedule(plan, legs: legs)
        let estimated = legs.values.filter(\.isEstimate).count
        log("schedule: \(schedule.stops.count) stops, \(schedule.issueCount) issues; legs fetched \(legs.count) of \(pairs.count), \(estimated) estimated")
    }

    @MainActor private static func forecast(_ model: AppModel) async {
        guard let spot = CuratedSpots.all.first else { log("forecast: no curated spots"); return }
        let state = await model.forecasts.load(spot.coordinate)
        switch state {
        case .loaded(let f): log("forecast: loaded \(f.hours.count) hours for \(spot.name) (\(f.source.rawValue))")
        case .unavailable(let reason): log("forecast: unavailable (\(reason))")
        case .loading: log("forecast: still loading")
        }
    }

    @MainActor private static func light(_ model: AppModel) {
        for spot in CuratedSpots.all.prefix(3) {
            let day = model.today(in: spot.timeZone)
            let dayLight = model.dayLight(for: spot, on: day)
            let summary = dayLight.windows.map { "\($0.kind.rawValue)=\($0.score.map(String.init) ?? "none")" }.joined(separator: " ")
            log("light: \(spot.name) \(day): \(summary)")
        }
    }

    @MainActor private static func search(_ model: AppModel) async {
        do {
            let search = model.search
            let results = try await withTimeout(seconds: 20) { try await search.search("Mesa Arch", near: nil) }
            log("search: \(results.count) results; first \(results.first?.name ?? "none")")
        } catch {
            log("search: failed (\(describe(error)))")
        }
    }

    @MainActor private static func geocode(_ model: AppModel) async {
        do {
            let geocoder = model.geocoder
            let spot = CuratedSpots.all.first?.coordinate ?? Coordinate(latitude: 38.3659, longitude: -109.6213)
            let place = try await withTimeout(seconds: 20) { try await geocoder.reverseGeocode(spot) }
            log("geocode: \(place.name), \(place.locality), zone \(place.timeZoneIdentifier ?? "none")")
        } catch {
            log("geocode: failed (\(describe(error)))")
        }
    }

    @MainActor private static func scout(_ model: AppModel) async {
        guard let scout = model.scout else { log("scout: not part of this build"); return }
        let availability = scout.availability()
        log("scout availability: \(availability)")
        guard availability == .available else { return }
        do {
            let found = try await withTimeout(seconds: 60) {
                try await scout.scout("Waterfalls near Portland, Oregon", progress: { _ in })
            }
            log("scout: \(found.count) results")
            for s in found.prefix(5) { log("scout result: \(s.spot.name), \(s.spot.locality) [\(s.provenance.rawValue)]") }
        } catch {
            log("scout: failed (\(describe(error)))")
        }
    }

    // MARK: Helpers

    private static func log(_ message: String) {
        AppLaunch.log.notice("smoke: \(message, privacy: .public)")
    }

    private static func describe(_ error: any Error) -> String {
        error is TimedOut ? "timed out" : String(describing: error)
    }

    /// Runs `body`, giving up after `seconds`. The body keeps running if it ignores cancellation, but the caller moves on.
    private static func withTimeout<T: Sendable>(seconds: Double, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }
}
