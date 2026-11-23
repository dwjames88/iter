import Foundation
import IterAstro
import IterModel

/// An ephemeris that remembers the sun and moon events and moon phases it has solved, for previews and tests that build many
/// models over the same few places and days (the sun and moon solvers are the expensive part of a model's first load).
/// Answers are the wrapped ephemeris's, unchanged.
public final class MemoizedEphemeris: Ephemeris, @unchecked Sendable {
    private struct DayKey: Hashable {
        var day: LocalDay
        var coordinate: Coordinate
        var zone: String
    }

    private let base: any Ephemeris
    private let lock = NSLock()
    private var suns: [DayKey: SunEvents] = [:]
    private var moons: [DayKey: MoonEvents] = [:]
    private var phases: [Date: MoonPhase] = [:]

    /// One shared instance over `Astronomy`.
    public static let shared = MemoizedEphemeris(Astronomy())

    public init(_ base: any Ephemeris) { self.base = base }

    public func sunEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> SunEvents {
        let key = DayKey(day: day, coordinate: coordinate, zone: timeZone.identifier)
        if let hit = lock.withLock({ suns[key] }) { return hit }
        let value = base.sunEvents(on: day, at: coordinate, in: timeZone)
        lock.withLock { suns[key] = value }
        return value
    }

    public func moonEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> MoonEvents {
        let key = DayKey(day: day, coordinate: coordinate, zone: timeZone.identifier)
        if let hit = lock.withLock({ moons[key] }) { return hit }
        let value = base.moonEvents(on: day, at: coordinate, in: timeZone)
        lock.withLock { moons[key] = value }
        return value
    }

    public func moonPhase(at date: Date) -> MoonPhase {
        if let hit = lock.withLock({ phases[date] }) { return hit }
        let value = base.moonPhase(at: date)
        lock.withLock { phases[date] = value }
        return value
    }

    public func sunPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { base.sunPosition(at: date, coordinate: coordinate) }
    public func moonPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { base.moonPosition(at: date, coordinate: coordinate) }
}
