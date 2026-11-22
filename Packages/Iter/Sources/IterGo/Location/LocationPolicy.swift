import Foundation
import IterModel

// What the location hardware should be doing in each phase (BLUEPRINT §10.6). Pure: no CoreLocation.
// All battery figures below are ESTIMATES from typical iPhone behaviour, not measurements. The lead's budget report
// and an on-device drive test are what settle them.

/// Whether a region reports the device entering it or leaving it.
public enum RegionTrigger: String, Codable, Hashable, Sendable {
    case enter, exit
}

/// A circular region to watch. `id` comes back in `LocationEvent.regionEntered` / `.regionExited`.
public struct MonitoredRegion: Codable, Hashable, Sendable {
    public var id: String
    public var center: Coordinate
    public var radiusM: Double
    public var notifyOn: RegionTrigger

    public init(id: String, center: Coordinate, radiusM: Double, notifyOn: RegionTrigger) {
        self.id = id
        self.center = center
        self.radiusM = radiusM
        self.notifyOn = notifyOn
    }
}

/// How hard continuous updates work. The adapter maps `kind` to a `CLLocationUpdate.LiveConfiguration` and applies
/// `distanceFilterM` itself (live updates have no distance-filter setting), so every platform behaves alike.
public struct LocationAccuracyProfile: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case automotiveNavigation, otherNavigation, standard
    }

    public var kind: Kind
    /// Wanted horizontal accuracy in metres; 0 = best available.
    public var desiredAccuracyM: Double
    /// Updates closer than this to the last delivered fix are dropped; 0 = deliver all.
    public var distanceFilterM: Double

    public init(kind: Kind, desiredAccuracyM: Double, distanceFilterM: Double) {
        self.kind = kind
        self.desiredAccuracyM = desiredAccuracyM
        self.distanceFilterM = distanceFilterM
    }

    /// Driving, normal power. ESTIMATE: about 4-8 % battery per hour with the screen off (navigation-app class, minus the screen).
    public static let drivingNormal = LocationAccuracyProfile(kind: .automotiveNavigation, desiredAccuracyM: 0, distanceFilterM: 0)
    /// Driving in Low Power Mode or under 20 %. ESTIMATE: roughly half of `drivingNormal`, about 2-4 % per hour.
    public static let drivingPowerSaving = LocationAccuracyProfile(kind: .standard, desiredAccuracyM: 100, distanceFilterM: 200)
}

/// What the location layer should be doing right now.
public enum LocationMode: Hashable, Sendable {
    /// Nothing running. Battery cost: zero.
    case off
    /// Region monitoring (and optionally significant-change). ESTIMATE: under 1 % per day; the OS does the work.
    case monitor(regions: [MonitoredRegion], significantChange: Bool)
    /// Continuous live updates, plus backup regions that fire while the phone is locked and updates stall.
    /// ESTIMATE: see the two profiles. Ends at arrival.
    case continuous(LocationAccuracyProfile, backupRegions: [MonitoredRegion])
}

public enum LocationPolicy {
    /// Region ids the policy uses; the engine matches events on these.
    public static let leaveRegionID = "go.leave"
    public static let arrivalRegionID = "go.arrive"
    public static let stopExitRegionID = "go.stop.exit"

    /// Exit radius around where you are before leaving, metres.
    public static let leaveRadiusM: Double = 500
    /// Extra metres added to a stop's radius for the "left the stop" exit region.
    public static let stopExitMarginM: Double = 250
    /// Inside this long before leave-by the app watches for you leaving.
    public static let watchWindow: TimeInterval = 2 * 3600

    /// The §10.6 table.
    ///
    /// - armed / betweenStops: more than 2 h before leave-by (or no leave-by, or no coordinate): `.off` (a local
    ///   notification and a best-effort background refresh cover it; ESTIMATE ~0 %/day). Within 2 h: a 500 m exit
    ///   region on where you are plus significant-change (ESTIMATE < 1 %/day).
    /// - driving: continuous, automotive navigation (ESTIMATE ~4-8 %/h) or the power-saving profile (ESTIMATE ~2-4 %/h),
    ///   plus an enter region on the next stop as a locked-phone arrival backup.
    /// - atStop: exit region on the stop (its radius + 250 m) plus significant-change (ESTIMATE < 1 %/day). For this
    ///   phase `nextStop` is the stop you are at.
    /// - idle / paused / finished: `.off`.
    ///
    /// `nextStop.radius` is the stop's arrival radius in metres.
    public static func mode(phase: GoPhase, untilLeaveBy: TimeInterval?, startOrCurrentCoordinate: Coordinate?,
                            nextStop: (id: String, coordinate: Coordinate, radius: Double)?, power: PowerState) -> LocationMode {
        switch phase {
        case .idle, .paused, .finished:
            return .off
        case .armed, .betweenStops:
            guard let untilLeaveBy, untilLeaveBy <= watchWindow, let here = startOrCurrentCoordinate else { return .off }
            let region = MonitoredRegion(id: leaveRegionID, center: here, radiusM: leaveRadiusM, notifyOn: .exit)
            return .monitor(regions: [region], significantChange: true)
        case .driving:
            let profile = power.isSaving ? LocationAccuracyProfile.drivingPowerSaving : .drivingNormal
            var backup: [MonitoredRegion] = []
            if let nextStop {
                backup.append(MonitoredRegion(id: arrivalRegionID, center: nextStop.coordinate, radiusM: nextStop.radius, notifyOn: .enter))
            }
            return .continuous(profile, backupRegions: backup)
        case .atStop:
            guard let nextStop else { return .monitor(regions: [], significantChange: true) }
            let region = MonitoredRegion(id: stopExitRegionID, center: nextStop.coordinate,
                                         radiusM: nextStop.radius + stopExitMarginM, notifyOn: .exit)
            return .monitor(regions: [region], significantChange: true)
        }
    }
}
