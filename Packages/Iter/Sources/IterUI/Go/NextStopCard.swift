import SwiftUI
import IterModel

/// Trip mode, iPhone: a stop in the run: its number, name, locality, the light window it is for with its start time,
/// and when you arrive. Solid content card. Go component (new, not yet drawn in Figma).
public struct NextStopCard: View {
    public let number: Int
    public let name: String
    public let locality: String?
    public let kind: LightWindowKind
    public let windowStart: Date
    public let arrival: Date
    public let zone: TimeZone
    public let locale: Locale

    public init(number: Int, name: String, locality: String? = nil, kind: LightWindowKind, windowStart: Date,
                arrival: Date, zone: TimeZone, locale: Locale = .current) {
        self.number = number
        self.name = name
        self.locality = locality
        self.kind = kind
        self.windowStart = windowStart
        self.arrival = arrival
        self.zone = zone
        self.locale = locale
    }

    var windowText: String {
        let t = TimeText.time(windowStart, in: zone, locale: locale)
        return String(localized: "\(LightText.name(kind)) starts \(t)", bundle: .module, locale: locale, comment: "Trip mode: the light window and its start time")
    }
    var arriveText: String { TripText.arrive(arrival, in: zone, locale: locale) }
    var accessibilityText: String {
        let n = String(localized: "Stop \(number)", bundle: .module, locale: locale, comment: "Stop number for VoiceOver")
        return [n, name, locality, windowText, arriveText].compactMap { $0 }.joined(separator: ", ")
    }

    public var body: some View {
        HStack(alignment: .top, spacing: IterSpace.md) {
            Text(verbatim: number.formatted(.number.locale(locale)))
                .font(IterFont.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(IterColor.onAccent)
                .frame(width: IterSize.badgeHeightLarge, height: IterSize.badgeHeightLarge)
                .background(IterColor.accent, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(verbatim: name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary).lineLimit(2)
                if let locality {
                    Text(verbatim: locality).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                }
                GoLine(LightText.symbol(kind)) { Text(verbatim: windowText) }
                    .font(IterFont.callout).foregroundStyle(IterColor.textPrimary)
                GoLine("flag.checkered") { Text(verbatim: arriveText) }
                    .font(IterFont.callout).foregroundStyle(IterColor.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .goCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }
}
