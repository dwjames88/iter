import SwiftUI

/// A factor's contribution to a Sky Index: signed points, or a signed fraction of the factor's weight (-1 to 1).
public enum FactorContribution: Sendable, Hashable {
    case points(Int)
    /// -1 hurts as much as it can, 0 is neutral, 1 helps as much as it can.
    case fraction(Double)

    var signed: Double {
        switch self {
        case .points(let p): Double(p)
        case .fraction(let f): max(-1, min(1, f))
        }
    }

    public enum Direction: Sendable { case helps, hurts, neutral }

    public var direction: Direction {
        switch self {
        case .points(let p): p > 0 ? .helps : (p < 0 ? .hurts : .neutral)
        case .fraction(let f): f > 0 ? .helps : (f < 0 ? .hurts : .neutral)
        }
    }

    /// "+12", "−4", "0" for points; "+40%", "−25%", "0%" for a fraction. The minus is U+2212.
    public func text(locale: Locale = .current) -> String {
        switch self {
        case .points(let p):
            if p == 0 { return 0.formatted(.number.locale(locale)) }
            let n = abs(p).formatted(.number.locale(locale))
            return p > 0 ? "+\(n)" : "\u{2212}\(n)"
        case .fraction(let f):
            let pct = Int((max(-1, min(1, f)) * 100).rounded())
            let n = abs(pct).formatted(.number.locale(locale))
            if pct == 0 { return "0%" }
            return pct > 0 ? "+\(n)%" : "\u{2212}\(n)%"
        }
    }
}

/// One factor of the Sky Index: symbol, name, its reading, and how much it moved the score. Direction reads from the
/// side of the centre line and the sign, never from colour (green is never used; both sides are `text/secondary`,
/// like `SignedBar`). A missing reading says "No data" in the neutral grey, and the row has no bar.
/// Conditions component (new, not yet drawn in Figma).
public struct FactorRow: View {
    public let name: String
    public let symbol: String
    public let valueText: String?
    public let contribution: FactorContribution?
    /// The largest magnitude among the factors shown, so bars share a scale (points only; fractions use 1). Minimum 10.
    public let scaleMax: Double
    public let locale: Locale

    public init(name: String, symbol: String, valueText: String?, contribution: FactorContribution?,
                scaleMax: Double = 30, locale: Locale = .current) {
        self.name = name
        self.symbol = symbol
        self.valueText = valueText
        self.contribution = contribution
        self.scaleMax = scaleMax
        self.locale = locale
    }

    private static let half: CGFloat = 32

    var noDataText: String { String(localized: "No data", bundle: .module, locale: locale, comment: "Factor row: the factor has no reading") }

    /// "Cloud cover, 30 percent, helps by +12".
    var accessibilityText: String {
        var parts = [name, valueText ?? noDataText]
        if let c = contribution {
            let t = c.text(locale: locale)
            switch c.direction {
            case .helps: parts.append(String(localized: "helps, \(t)", bundle: .module, locale: locale, comment: "Factor row VoiceOver: positive contribution"))
            case .hurts: parts.append(String(localized: "hurts, \(t)", bundle: .module, locale: locale, comment: "Factor row VoiceOver: negative contribution"))
            case .neutral: parts.append(String(localized: "no effect", bundle: .module, locale: locale, comment: "Factor row VoiceOver: zero contribution"))
            }
        }
        return parts.joined(separator: ", ")
    }

    public var body: some View {
        HStack(spacing: IterSpace.sm) {
            Image(systemName: symbol)
                .font(IterFont.callout)
                .foregroundStyle(valueText == nil ? IterColor.noForecast : IterColor.textSecondary.color)
                .frame(width: IterSize.iconLarge, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(verbatim: name).font(IterFont.callout).foregroundStyle(IterColor.textPrimary)
                Text(verbatim: valueText ?? noDataText).font(IterFont.secondary)
                    .foregroundStyle(valueText == nil ? IterColor.textTertiary.color : IterColor.textSecondary.color)
            }
            Spacer(minLength: IterSpace.sm)
            contributionView
        }
        .padding(.vertical, IterSpace.xs)
        .frame(minHeight: IterGrid.rowDouble)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }

    @ViewBuilder private var contributionView: some View {
        if let contribution {
            HStack(spacing: IterSpace.xs) {
                SignedBarTrack(signed: contribution.signed, scale: scale(for: contribution))
                    .frame(width: Self.half * 2 + IterSpace.xs, height: 14)
                Text(verbatim: contribution.text(locale: locale))
                    .font(IterFont.timeSmall)
                    .foregroundStyle(IterColor.textSecondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        } else {
            Text(verbatim: "–").font(IterFont.timeSmall).foregroundStyle(IterColor.textTertiary)
        }
    }

    private func scale(for c: FactorContribution) -> Double {
        switch c {
        case .points: max(scaleMax, 10)
        case .fraction: 1
        }
    }
}

/// A centre line with a bar growing right (helps) or left (hurts).
private struct SignedBarTrack: View {
    let signed: Double
    let scale: Double
    private let half: CGFloat = 32

    var body: some View {
        let length = signed == 0 ? 0 : max(2, CGFloat(min(abs(signed) / scale, 1)) * half)
        ZStack {
            Rectangle().fill(IterColor.separator).frame(width: IterStroke.thin, height: 14)
            Rectangle().fill(IterColor.textSecondary)
                .frame(width: length, height: IterSpace.sm)
                .offset(x: signed >= 0 ? length / 2 : -length / 2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

#Preview("Factor rows") {
    VStack {
        FactorRow(name: "Cloud Cover", symbol: "cloud.sun", valueText: "30% mid, 10% high", contribution: .points(21))
        FactorRow(name: "Smoke", symbol: "smoke", valueText: "Moderate", contribution: .points(-8))
        FactorRow(name: "Wind", symbol: "wind", valueText: nil, contribution: nil)
    }
    .padding()
}
