import SwiftUI

/// Where you stand against the departure time.
public enum LeaveByStatus: Sendable, Hashable {
    case onTime
    case leaveNow
    case late(minutes: Int)

    /// Same one-minute tolerance as `TripText.leaveBy`: within it is "leave now", beyond it is late.
    public init(departure: Date, now: Date) {
        let delta = departure.timeIntervalSince(now)
        if delta > TripText.nowTolerance { self = .onTime }
        else if delta >= -TripText.nowTolerance { self = .leaveNow }
        else { self = .late(minutes: max(1, Int((-delta / 60).rounded(.up)))) }
    }

    func word(locale: Locale) -> String {
        switch self {
        case .onTime: String(localized: "On Time", bundle: .module, locale: locale, comment: "Trip mode status")
        case .leaveNow: String(localized: "Leave Now", bundle: .module, locale: locale, comment: "Trip mode status")
        case .late: String(localized: "Running Late", bundle: .module, locale: locale, comment: "Trip mode status")
        }
    }

    var symbol: String {
        switch self {
        case .onTime: "checkmark.circle"
        case .leaveNow: "car.fill"
        case .late: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .onTime: IterColor.textSecondary.color
        case .leaveNow: IterColor.accentText
        case .late: IterColor.warning
        }
    }
}

/// Trip mode, iPhone: the next stop, when to leave, when you arrive, and how long the drive is. Solid content card.
/// Go component (new, not yet drawn in Figma). All words come from `TripText`/`TimeText`.
public struct LeaveByCard: View {
    public let stopName: String
    public let departure: Date
    public let arrival: Date
    /// The window's start (or set-up time): an arrival after it reads as late.
    public let deadline: Date?
    public let driveSeconds: TimeInterval
    public let driveMeters: Double
    public let now: Date
    public let zone: TimeZone
    public let locale: Locale

    public init(stopName: String, departure: Date, arrival: Date, deadline: Date? = nil, driveSeconds: TimeInterval,
                driveMeters: Double, now: Date, zone: TimeZone, locale: Locale = .current) {
        self.stopName = stopName
        self.departure = departure
        self.arrival = arrival
        self.deadline = deadline
        self.driveSeconds = driveSeconds
        self.driveMeters = driveMeters
        self.now = now
        self.zone = zone
        self.locale = locale
    }

    var status: LeaveByStatus { LeaveByStatus(departure: departure, now: now) }
    var leaveByText: String { TripText.leaveBy(departure, now: now, in: zone, locale: locale) }
    var etaText: String { TripText.eta(arrival: arrival, deadline: deadline, in: zone, locale: locale) }
    var driveText: String { TripText.drive(seconds: driveSeconds, meters: driveMeters, locale: locale) }
    var accessibilityText: String { "\(stopName). \(leaveByText). \(etaText). \(driveText)" }

    public var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack {
                Text("Next Stop", bundle: .module).font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
                Spacer(minLength: IterSpace.sm)
                Label { Text(verbatim: status.word(locale: locale)) } icon: { Image(systemName: status.symbol) }
                    .font(IterFont.captionStrong)
                    .foregroundStyle(status.tint)
            }
            Text(verbatim: stopName).font(IterFont.titleSection).foregroundStyle(IterColor.textPrimary)
                .lineLimit(2)
            Text(verbatim: leaveByText).font(IterFont.titleSpot).foregroundStyle(status.leaveByInk)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                GoLine("flag.checkered") { Text(verbatim: etaText) }
                GoLine("car") { Text(verbatim: driveText) }
            }
            .font(IterFont.callout)
            .foregroundStyle(IterColor.textSecondary)
        }
        .goCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }
}

extension LeaveByStatus {
    /// The big leave-by line: ink, except late, which is violet with its icon above.
    var leaveByInk: Color {
        switch self {
        case .late: IterColor.warning
        default: IterColor.textPrimary.color
        }
    }
}
