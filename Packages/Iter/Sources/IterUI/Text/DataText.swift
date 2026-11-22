import Foundation
import IterModel

/// How old a datum is, and where it came from, in words.
public enum DataText {
    /// The age bucket a datum falls in. `stale` wins once the age reaches `staleAfter`.
    public enum Age: Hashable, Sendable {
        case justNow
        case minutes(Int)
        case hours(Int)
        case days(Int)
        case stale
    }

    /// Default point at which a datum is called stale: six hours.
    public static let defaultStaleAfter: TimeInterval = 6 * 3600

    /// Buckets `now - fetchedAt`: under a minute is just now, under an hour is minutes, under a day is hours, then days;
    /// at or beyond `staleAfter` it is stale. A date in the future counts as just now.
    public static func age(of fetchedAt: Date, now: Date, staleAfter: TimeInterval = defaultStaleAfter) -> Age {
        let s = now.timeIntervalSince(fetchedAt)
        if s >= staleAfter { return .stale }
        if s < 60 { return .justNow }
        if s < 3600 { return .minutes(Int(s / 60)) }
        if s < 86_400 { return .hours(Int(s / 3600)) }
        return .days(Int(s / 86_400))
    }

    /// "Updated just now", "Updated 12 min ago", "3 hr old", "2 days old", "Stale".
    public static func ageText(of fetchedAt: Date, now: Date, staleAfter: TimeInterval = defaultStaleAfter,
                               locale: Locale = .current) -> String {
        switch age(of: fetchedAt, now: now, staleAfter: staleAfter) {
        case .justNow:
            return String(localized: "Updated just now", bundle: .module, locale: locale, comment: "Data age under a minute")
        case .minutes(let m):
            let d = unit(m, .minutes, locale)
            return String(localized: "Updated \(d) ago", bundle: .module, locale: locale, comment: "Data age in minutes, e.g. Updated 12 min ago")
        case .hours(let h):
            let d = unit(h, .hours, locale)
            return String(localized: "\(d) old", bundle: .module, locale: locale, comment: "Data age in hours, e.g. 3 hr old")
        case .days(let n):
            let d = unit(n, .days, locale)
            return String(localized: "\(d) old", bundle: .module, locale: locale, comment: "Data age in days, e.g. 2 days old")
        case .stale:
            return String(localized: "Stale", bundle: .module, locale: locale, comment: "Data is too old to trust as current")
        }
    }

    /// The age phrase for a datum's provenance.
    public static func ageText(_ provenance: Provenance, now: Date, staleAfter: TimeInterval = defaultStaleAfter,
                               locale: Locale = .current) -> String {
        ageText(of: provenance.fetchedAt, now: now, staleAfter: staleAfter, locale: locale)
    }

    private static func unit(_ n: Int, _ unit: Duration.UnitsFormatStyle.Unit, _ locale: Locale) -> String {
        let seconds: Int = switch unit {
        case .days: n * 86_400
        case .hours: n * 3600
        default: n * 60
        }
        return Duration.seconds(seconds).formatted(.units(allowed: [unit], width: .abbreviated).locale(locale))
    }

    // MARK: Source tiers

    /// The tier as a label: "Military Origin", "Government", "Open Data", "Your Key", "This Device".
    public static func name(_ tier: SourceTier) -> String {
        switch tier {
        case .military: String(localized: "Military Origin", bundle: .module, comment: "Source tier label")
        case .government: String(localized: "Government", bundle: .module, comment: "Source tier label")
        case .openData: String(localized: "Open Data", bundle: .module, comment: "Source tier label")
        case .userKey: String(localized: "Your Key", bundle: .module, comment: "Source tier label: data fetched with the user's own API key")
        case .device: String(localized: "This Device", bundle: .module, comment: "Source tier label: data computed or sensed on this device")
        }
    }

    /// The tier as a sentence fragment: "Military-origin data", "Government data", "Open data", "Your key", "This device".
    public static func phrase(_ tier: SourceTier) -> String {
        switch tier {
        case .military: String(localized: "Military-origin data", bundle: .module, comment: "Source tier phrase")
        case .government: String(localized: "Government data", bundle: .module, comment: "Source tier phrase")
        case .openData: String(localized: "Open data", bundle: .module, comment: "Source tier phrase")
        case .userKey: String(localized: "Your key", bundle: .module, comment: "Source tier phrase: fetched with the user's own API key")
        case .device: String(localized: "This device", bundle: .module, comment: "Source tier phrase: computed or sensed on this device")
        }
    }

    /// The marker shown beside military-origin data (GPS, GFS and similar feeds); nil for every other tier.
    public static func originMarker(_ tier: SourceTier) -> String? {
        tier == .military ? phrase(.military) : nil
    }

    /// The provenance line: "GFS · Updated 12 min ago", or "Updated 12 min ago" with no model.
    public static func provenanceLine(_ provenance: Provenance, now: Date, staleAfter: TimeInterval = defaultStaleAfter,
                                      locale: Locale = .current) -> String {
        let age = ageText(provenance, now: now, staleAfter: staleAfter, locale: locale)
        guard let model = provenance.model, !model.isEmpty else { return age }
        return String(localized: "\(model) · \(age)", bundle: .module, locale: locale,
                      comment: "Provenance line: model, then data age, e.g. GFS · Updated 12 min ago")
    }
}
