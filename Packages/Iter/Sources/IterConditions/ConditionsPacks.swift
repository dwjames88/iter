import Foundation
import IterModel
import IterSources

extension ConditionsService {
    /// Collects every stop's composite forecast, observations, horizon, alerts, smoke and aurora for its days into one JSON
    /// file `<packDirectory>/<tripID>.json` (written atomically), and returns the pack. Stops are loaded together, so nearby
    /// stops share downloads. Anything whose licence forbids storing stays out of the file but is kept in memory.
    @discardableResult
    public func buildPack(tripID: UUID, stops: [PackStop], priority: ConditionsPriority = .activeTrip) async throws -> ConditionsPack {
        guard let directory = packDirectory else { throw ConditionsError.packsDisabled }
        var requests: [ConditionsRequest] = []
        var seen = Set<PlaceDay>()
        for stop in stops {
            for day in stop.days where seen.insert(PlaceDay(placeID: stop.place.id, day: day)).inserted {
                requests.append(ConditionsRequest(place: stop.place, day: day, priority: priority))
            }
        }
        var latest: [PlaceDay: SkyReport] = [:]
        for await report in reports(for: requests) { latest[PlaceDay(placeID: report.placeID, day: report.day)] = report }
        let now = clock.now
        let entries = requests.compactMap { r -> ConditionsPack.Entry? in
            latest[PlaceDay(placeID: r.place.id, day: r.day)].map { ConditionsPack.Entry(placeID: r.place.id, day: r.day, report: $0) }
        }
        let pack = ConditionsPack(tripID: tripID, builtAt: now, entries: entries)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(pack.scrubbedForStorage()).write(to: directory.appendingPathComponent("\(tripID.uuidString).json"), options: .atomic)
        } catch {
            throw ConditionsError.packWriteFailed(String(describing: error))
        }
        loadPacksIfNeeded()
        index(pack)
        return pack
    }

    /// A trip's stops, each on the day its `dayIndex` says.
    public func buildPack(for trip: Trip, priority: ConditionsPriority = .activeTrip) async throws -> ConditionsPack {
        var byPlace: [UUID: PackStop] = [:]
        var order: [UUID] = []
        for stop in trip.stops {
            let day = trip.startDay.adding(days: stop.dayIndex)
            if byPlace[stop.place.id] == nil { byPlace[stop.place.id] = PackStop(place: stop.place, days: []); order.append(stop.place.id) }
            if !(byPlace[stop.place.id]?.days.contains(day) ?? false) { byPlace[stop.place.id]?.days.append(day) }
        }
        return try await buildPack(tripID: trip.id, stops: order.compactMap { byPlace[$0] }, priority: priority)
    }

    /// The stored pack for a trip, if there is one and it can be read.
    public func pack(for tripID: UUID) -> ConditionsPack? {
        guard let directory = packDirectory else { return nil }
        return Self.readPack(directory.appendingPathComponent("\(tripID.uuidString).json"))
    }

    /// A pack's report for a place and day, re-scored for `now` and marked stale with the pack's age ("Forecast from 06:29,
    /// offline"). nil when no pack holds that place and day.
    public func packedReport(for place: Place, day: LocalDay) -> SkyReport? {
        loadPacksIfNeeded()
        guard let e = packIndex[PlaceDay(placeID: place.id, day: day)] else { return nil }
        return assembler.rescored(e.report, place: place, now: clock.now, pack: PackServing(tripID: e.tripID, builtAt: e.builtAt))
    }

    // MARK: Index

    func packEntry(_ placeID: UUID, _ day: LocalDay) async -> PackEntry? {
        loadPacksIfNeeded()
        return packIndex[PlaceDay(placeID: placeID, day: day)]
    }

    func loadPacksIfNeeded() {
        guard !packsLoaded else { return }
        packsLoaded = true
        guard let directory = packDirectory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "json" {
            if let pack = Self.readPack(f) { index(pack) }
        }
    }

    private func index(_ pack: ConditionsPack) {
        for e in pack.entries {
            let k = PlaceDay(placeID: e.placeID, day: e.day)
            if let old = packIndex[k], old.builtAt > pack.builtAt { continue }
            packIndex[k] = PackEntry(tripID: pack.tripID, builtAt: pack.builtAt, report: e.report)
        }
    }

    private static func readPack(_ url: URL) -> ConditionsPack? {
        guard let data = try? Data(contentsOf: url), let pack = try? JSONDecoder().decode(ConditionsPack.self, from: data),
              pack.format <= ConditionsPack.currentFormat else { return nil }
        return pack
    }
}
