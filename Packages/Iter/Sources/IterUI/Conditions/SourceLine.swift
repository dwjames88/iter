import SwiftUI
import IterModel

/// The provenance line under a conditions value: where it came from, how authoritative that source is, and how old it is.
/// "NOAA · GFS · 12 km away · Updated 12 min ago", then the tier on its own line ("Government data"; military-origin
/// feeds get a shield symbol and "Military-origin data", so the marker is never colour alone) and an optional link.
/// Replaces `ProvenanceTag` / `ForecastSourceLine` for conditions: plain caption text, `text/secondary` and `text/tertiary`.
public struct SourceLine: View {
    /// The words of the line, computed once so tests can check them without rendering.
    struct Content: Equatable {
        var primary: String
        var tier: String
        var isMilitary: Bool
        var isStale: Bool
        var accessibility: String
    }

    let content: Content
    public let url: URL?

    public init(sourceName: String, tier: SourceTier, issuedAt: Date? = nil, fetchedAt: Date, now: Date,
                model: String? = nil, distanceKm: Double? = nil, url: URL? = nil,
                staleAfter: TimeInterval = DataText.defaultStaleAfter, zone: TimeZone = .current, locale: Locale = .current) {
        self.content = Self.content(sourceName: sourceName, tier: tier, issuedAt: issuedAt, fetchedAt: fetchedAt, now: now,
                                    model: model, distanceKm: distanceKm, staleAfter: staleAfter, zone: zone, locale: locale)
        self.url = url
    }

    /// From a `Provenance`, the source's display name (the id is a catalogue key, not words) and its tier.
    public init(_ provenance: Provenance, displayName: String, tier: SourceTier, now: Date,
                staleAfter: TimeInterval = DataText.defaultStaleAfter, zone: TimeZone = .current, locale: Locale = .current) {
        self.init(sourceName: displayName, tier: tier, issuedAt: provenance.issuedAt, fetchedAt: provenance.fetchedAt, now: now,
                  model: provenance.model, distanceKm: provenance.distanceKm, url: provenance.url,
                  staleAfter: staleAfter, zone: zone, locale: locale)
    }

    static func content(sourceName: String, tier: SourceTier, issuedAt: Date?, fetchedAt: Date, now: Date, model: String?,
                        distanceKm: Double?, staleAfter: TimeInterval, zone: TimeZone, locale: Locale) -> Content {
        let reference = issuedAt ?? fetchedAt
        let isStale = DataText.age(of: reference, now: now, staleAfter: staleAfter) == .stale
        var parts = [sourceName]
        if let model, !model.isEmpty { parts.append(model) }
        if let km = distanceKm {
            let d = TimeText.distance(kilometers: km, locale: locale)
            parts.append(String(localized: "\(d) away", bundle: .module, locale: locale, comment: "Station or grid-point distance, e.g. 12 km away"))
        }
        if isStale {
            let t = TimeText.time(reference, in: zone, locale: locale)
            parts.append(String(localized: "Stale, as of \(t)", bundle: .module, locale: locale, comment: "Data too old to be current, with its time"))
        } else {
            parts.append(DataText.ageText(of: reference, now: now, staleAfter: staleAfter, locale: locale))
        }
        let primary = parts.joined(separator: " · ")
        let tierText = DataText.phrase(tier)
        return Content(primary: primary, tier: tierText, isMilitary: tier == .military, isStale: isStale,
                       accessibility: "\(primary). \(tierText)")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                if content.isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(IterColor.warning)
                        .accessibilityHidden(true)
                }
                Text(verbatim: content.primary)
                    .foregroundStyle(content.isStale ? IterColor.warning : IterColor.textSecondary.color)
            }
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                if content.isMilitary {
                    Image(systemName: "shield.lefthalf.filled").accessibilityHidden(true)
                }
                Text(verbatim: content.tier)
                if let url {
                    Text(verbatim: "·")
                    Link(destination: url) { Text("View Source", bundle: .module, comment: "Link to the data source's page") }
                        .foregroundStyle(IterColor.accentText)
                }
            }
            .foregroundStyle(IterColor.textTertiary)
        }
        .font(IterFont.caption)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: url == nil ? .ignore : .combine)
        .accessibilityLabel(Text(verbatim: content.accessibility))
    }
}

#Preview("Source line") {
    SourceLine(sourceName: "NOAA", tier: .military, fetchedAt: .now.addingTimeInterval(-720), now: .now, model: "GFS", distanceKm: 12)
        .padding()
}
