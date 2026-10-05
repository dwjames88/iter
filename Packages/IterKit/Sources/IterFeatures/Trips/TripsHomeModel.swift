import Foundation
import Observation
import IterCore
import IterLight
import IterData

/// The first session of a trip that has not finished yet.
public struct NextSession: Hashable, Sendable {
    public var stopID: UUID
    public var spotName: String
    public var kind: LightWindowKind
    /// When the window starts.
    public var start: Date
    /// The spot's zone: the time and weekday are shown there.
    public var timeZoneIdentifier: String
    public var day: LocalDay

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }
}

/// A trip as the overview shows it.
public struct TripSummary: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var startDay: LocalDay
    public var dayCount: Int
    public var stopCount: Int
    public var next: NextSession?

    public var endDay: LocalDay { startDay.adding(days: dayCount - 1) }
}

public enum TripImportFailure: Error, Hashable, Sendable {
    /// The file is not an Iter trip (not JSON, or the wrong shape).
    case corrupt
    /// Written by a newer version of Iter.
    case unsupportedVersion(Int)
    /// The file could not be read at all.
    case unreadable
}

/// What the user fills in on the New Trip sheet.
public struct NewTripDraft: Hashable, Sendable {
    public var name = ""
    public var startDay: LocalDay
    public var dayCount = 3
    public var templateID: String?

    public init(startDay: LocalDay, dayCount: Int = 3, templateID: String? = nil, name: String = "") {
        self.startDay = startDay
        self.dayCount = dayCount
        self.templateID = templateID
        self.name = name
    }

    public var template: TripTemplate? { templateID.flatMap(TripTemplates.template(id:)) }
    /// A template fixes the number of days.
    public var effectiveDayCount: Int { template?.dayCount ?? max(1, dayCount) }
}

/// The trips overview: summaries, creating, importing.
@MainActor
@Observable
public final class TripsHomeModel {
    public static let maximumDayCount = 30

    @ObservationIgnored private let store: IterStore
    @ObservationIgnored private let engine: LightEngine
    @ObservationIgnored private let now: @MainActor () -> Date

    public init(store: IterStore, engine: LightEngine, now: @escaping @MainActor () -> Date = { Date() }) {
        self.store = store
        self.engine = engine
        self.now = now
    }

    /// Newest-edited first, like the sidebar. Reading `store.revision` ties the caller to store changes.
    public func summaries() -> [TripSummary] {
        _ = store.revision
        let clock = now()
        return store.trips().map { Self.summary(of: $0.plan, engine: engine, now: clock) }
    }

    public static func summary(of plan: TripPlan, engine: LightEngine, now: Date) -> TripSummary {
        TripSummary(id: plan.id, name: plan.name, startDay: plan.startDay, dayCount: plan.dayCount,
                    stopCount: plan.stops.count, next: nextSession(in: plan, engine: engine, now: now))
    }

    /// The first stop, in trip order, whose session window has not ended at `now`.
    public static func nextSession(in plan: TripPlan, engine: LightEngine, now: Date) -> NextSession? {
        let ordered = plan.stops.enumerated().sorted {
            $0.element.dayIndex != $1.element.dayIndex ? $0.element.dayIndex < $1.element.dayIndex : $0.offset < $1.offset
        }.map(\.element)
        for stop in ordered {
            let day = plan.day(stop.dayIndex)
            guard let window = engine.windows(for: stop.spot, on: day).first(where: { $0.kind == stop.session }),
                  window.span.end > now else { continue }
            return NextSession(stopID: stop.id, spotName: stop.spot.name, kind: stop.session, start: window.span.start,
                               timeZoneIdentifier: stop.spot.timeZoneIdentifier, day: day)
        }
        return nil
    }

    /// Makes the trip. A blank name falls back to the template's, then to `fallbackName`.
    @discardableResult
    public func create(_ draft: NewTripDraft, fallbackName: String) -> TripRecord {
        let typed = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let template = draft.template {
            let trip = store.createTrip(from: template, startDay: draft.startDay)
            if !typed.isEmpty, typed != template.defaultName { store.renameTrip(trip, to: typed) }
            return trip
        }
        return store.createTrip(name: typed.isEmpty ? fallbackName : typed, startDay: draft.startDay, dayCount: draft.effectiveDayCount)
    }

    /// Imports a `.iter` document. Returns the new trip's id, or why it failed. Nothing changes on failure.
    public func importTrip(from data: Data) -> Result<UUID, TripImportFailure> {
        do {
            let document = try TripDocument.decode(data)
            return .success(store.importTrip(document).id)
        } catch TripDocument.DocumentError.unsupportedVersion(let version) {
            return .failure(.unsupportedVersion(version))
        } catch {
            return .failure(.corrupt)
        }
    }

    /// Imports from a file the user picked (handles the sandbox's security scope).
    public func importTrip(contentsOf url: URL) -> Result<UUID, TripImportFailure> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        return importTrip(from: data)
    }
}
