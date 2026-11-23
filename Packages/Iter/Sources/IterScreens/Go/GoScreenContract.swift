import Foundation
import SwiftUI
import IterModel
import IterGo
import IterGoActivity
import IterFeatures

// The contract every Go screen file is written against. The screens are value-driven: they render a `GoSnapshot`, the
// `GoPermissions` and a `now`, and call back through `GoActions`. `GoRootView(model:library:)` binds these to a live
// `GoModel`; snapshot tests and previews pass sample values and no-op actions.

/// Everything a Go screen can ask for. Each closure is the matching `GoModel` call (or the shell's, for navigate/settings).
@MainActor
public struct GoActions {
    public var leaveNow: () async -> Void
    public var arrived: () async -> Void
    public var doneHere: () async -> Void
    /// nil skips the next stop.
    public var skip: (_ stopID: UUID?) async -> Void
    public var notYet: () async -> Void
    public var pause: () async -> Void
    public var resume: () async -> Void
    public var end: () async -> Void
    /// Opens Apple Maps for turn-by-turn.
    public var navigate: (_ to: NavigationHandoff) -> Void
    public var requestLocationWhenInUse: () -> Void
    public var requestLocationAlways: () -> Void
    public var requestNotifications: () async -> Void
    /// Opens the app's page in Settings (a denied permission).
    public var openSettings: () -> Void
    /// Starts a run of `tripID`, optionally from a later stop (mid-trip or a later day), optionally already there.
    public var start: (_ tripID: UUID, _ stopID: UUID?, _ alreadyThere: Bool) async -> Void

    public init(leaveNow: @escaping () async -> Void = {}, arrived: @escaping () async -> Void = {}, doneHere: @escaping () async -> Void = {},
                skip: @escaping (UUID?) async -> Void = { _ in }, notYet: @escaping () async -> Void = {},
                pause: @escaping () async -> Void = {}, resume: @escaping () async -> Void = {}, end: @escaping () async -> Void = {},
                navigate: @escaping (NavigationHandoff) -> Void = { _ in }, requestLocationWhenInUse: @escaping () -> Void = {},
                requestLocationAlways: @escaping () -> Void = {}, requestNotifications: @escaping () async -> Void = {},
                openSettings: @escaping () -> Void = {}, start: @escaping (UUID, UUID?, Bool) async -> Void = { _, _, _ in }) {
        self.leaveNow = leaveNow
        self.arrived = arrived
        self.doneHere = doneHere
        self.skip = skip
        self.notYet = notYet
        self.pause = pause
        self.resume = resume
        self.end = end
        self.navigate = navigate
        self.requestLocationWhenInUse = requestLocationWhenInUse
        self.requestLocationAlways = requestLocationAlways
        self.requestNotifications = requestNotifications
        self.openSettings = openSettings
        self.start = start
    }

    /// Does nothing: snapshots and previews.
    public static var inert: GoActions { GoActions() }
}

/// A trip the not-running screen offers to start. The shell builds these from the library (Go never opens the store).
public struct GoTripChoice: Identifiable, Hashable, Sendable {
    public struct StopChoice: Identifiable, Hashable, Sendable {
        public var id: UUID
        public var number: Int
        public var name: String
        public var dayIndex: Int
        public var windowKind: LightWindowKind?
        public init(id: UUID, number: Int, name: String, dayIndex: Int, windowKind: LightWindowKind?) {
            self.id = id
            self.number = number
            self.name = name
            self.dayIndex = dayIndex
            self.windowKind = windowKind
        }
    }

    public var id: UUID
    public var name: String
    public var startDay: LocalDay
    public var dayCount: Int
    public var stops: [StopChoice]

    public init(id: UUID, name: String, startDay: LocalDay, dayCount: Int, stops: [StopChoice]) {
        self.id = id
        self.name = name
        self.startDay = startDay
        self.dayCount = dayCount
        self.stops = stops
    }
}

/// How countdowns are drawn. `.live` uses timer-style text that ticks on its own; `.frozen` draws the value at the given
/// `now` as plain text, so snapshot renders are deterministic.
public enum GoClockMode: Hashable, Sendable {
    case live
    case frozen
}

extension EnvironmentValues {
    /// Default `.live`. Snapshot tests set `.frozen`.
    @Entry public var goClockMode: GoClockMode = .live
}
