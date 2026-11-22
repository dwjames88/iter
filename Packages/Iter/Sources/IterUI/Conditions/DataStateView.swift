import SwiftUI
import IterModel

/// An honest state for a datum that is missing, old or still coming: never a number, always a symbol, a title and words.
public enum DataStateKind: Sendable, Hashable {
    /// Nothing known: neutral grey, "unknown is not poor".
    case noData
    /// Held, but older than it should be; `age` in seconds.
    case stale(age: TimeInterval)
    /// No connection; the last good update, when there was one.
    case offline(lastUpdated: Date?)
    case loading
    /// The source cannot supply it; `reason` is a short sentence.
    case unavailable(reason: String)
}

/// Conditions component (new, not yet drawn in Figma). Two forms: `.inline` (one small line with a symbol, for rows and
/// footers) and `.large` (a `ContentUnavailableView` for a whole empty module). Status colours come with icons:
/// stale and unavailable are warning violet (never coral), no data and offline are the neutral "no forecast" grey.
public struct DataStateView: View {
    public enum Style: Sendable { case inline, large }

    public let state: DataStateKind
    public let style: Style
    public let now: Date
    public let zone: TimeZone
    public let locale: Locale

    public init(_ state: DataStateKind, style: Style = .inline, now: Date = .now, zone: TimeZone = .current, locale: Locale = .current) {
        self.state = state
        self.style = style
        self.now = now
        self.zone = zone
        self.locale = locale
    }

    /// The symbol, title and detail for a state.
    struct Words: Equatable {
        var symbol: String
        var title: String
        var detail: String
    }

    var words: Words { Self.words(for: state, zone: zone, locale: locale) }

    static func words(for state: DataStateKind, zone: TimeZone, locale: Locale) -> Words {
        switch state {
        case .noData:
            return Words(symbol: "circle.dashed",
                  title: String(localized: "No Data", bundle: .module, locale: locale, comment: "Data state title"),
                  detail: String(localized: "Iter has nothing for this yet.", bundle: .module, locale: locale, comment: "Data state detail: no data"))
        case .stale(let age):
            let d = TimeText.duration(age, locale: locale)
            return Words(symbol: "clock.badge.exclamationmark",
                  title: String(localized: "Stale Data", bundle: .module, locale: locale, comment: "Data state title"),
                  detail: String(localized: "\(d) old. Check again before you rely on it.", bundle: .module, locale: locale, comment: "Data state detail: stale, with age"))
        case .offline(let last):
            return Words(symbol: "wifi.slash",
                  title: String(localized: "Offline", bundle: .module, locale: locale, comment: "Data state title"),
                  detail: last.map {
                      let t = TimeText.time($0, in: zone, locale: locale)
                      return String(localized: "Last updated at \(t).", bundle: .module, locale: locale, comment: "Data state detail: offline with last update time")
                  } ?? String(localized: "This appears when you're back online.", bundle: .module, locale: locale, comment: "Data state detail: offline, nothing cached"))
        case .loading:
            return Words(symbol: "arrow.triangle.2.circlepath",
                  title: String(localized: "Loading", bundle: .module, locale: locale, comment: "Data state title"),
                  detail: String(localized: "Getting the latest conditions.", bundle: .module, locale: locale, comment: "Data state detail: loading"))
        case .unavailable(let reason):
            return Words(symbol: "exclamationmark.triangle.fill",
                  title: String(localized: "Unavailable", bundle: .module, locale: locale, comment: "Data state title"),
                  detail: reason)
        }
    }

    /// Violet for stale and unavailable; the neutral grey for the rest.
    var tint: Color {
        switch state {
        case .stale, .unavailable: IterColor.warning
        case .noData, .offline, .loading: IterColor.noForecast
        }
    }

    public var body: some View {
        let w = words
        Group {
            switch style {
            case .inline: inline(w)
            case .large: large(w)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(w.title). \(w.detail)"))
    }

    private func inline(_ w: Words) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
            if case .loading = state {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: w.symbol).foregroundStyle(tint)
            }
            Text(verbatim: w.title).font(IterFont.captionStrong).foregroundStyle(IterColor.textPrimary)
            Text(verbatim: w.detail).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
        }
        .font(IterFont.caption)
    }

    private func large(_ w: Words) -> some View {
        ContentUnavailableView {
            if case .loading = state {
                VStack(spacing: IterSpace.sm) {
                    ProgressView()
                    Text(verbatim: w.title)
                }
            } else {
                Label { Text(verbatim: w.title) } icon: { Image(systemName: w.symbol).foregroundStyle(tint) }
            }
        } description: {
            Text(verbatim: w.detail)
        }
    }
}

#Preview("Data states") {
    VStack(alignment: .leading, spacing: 8) {
        DataStateView(.noData)
        DataStateView(.stale(age: 7 * 3600))
        DataStateView(.offline(lastUpdated: nil))
        DataStateView(.loading)
        DataStateView(.unavailable(reason: "Outside coverage."))
    }
    .padding()
}
