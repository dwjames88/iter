import SwiftUI

/// How far a Sky Index can be trusted (BLUEPRINT §8.1). A plain value so the UI kit does not depend on `IterSky`.
public enum ConfidenceLevel: Int, CaseIterable, Sendable, Hashable, Comparable {
    case low, medium, high

    public static func < (a: ConfidenceLevel, b: ConfidenceLevel) -> Bool { a.rawValue < b.rawValue }

    /// "Low", "Medium", "High".
    public func name(locale: Locale = .current) -> String {
        switch self {
        case .low: String(localized: "Low", bundle: .module, locale: locale, comment: "Confidence level")
        case .medium: String(localized: "Medium", bundle: .module, locale: locale, comment: "Confidence level")
        case .high: String(localized: "High", bundle: .module, locale: locale, comment: "Confidence level")
        }
    }

    /// "Low Confidence", "Medium Confidence", "High Confidence": the VoiceOver and long label.
    public func phrase(locale: Locale = .current) -> String {
        switch self {
        case .low: String(localized: "Low Confidence", bundle: .module, locale: locale, comment: "Confidence phrase")
        case .medium: String(localized: "Medium Confidence", bundle: .module, locale: locale, comment: "Confidence phrase")
        case .high: String(localized: "High Confidence", bundle: .module, locale: locale, comment: "Confidence phrase")
        }
    }
}

/// A small mark for confidence plus an optional word. The level reads from the mark's shape, not its colour: an empty
/// ring is low, a half-filled disc is medium, a full disc is high (ink on every level).
/// Conditions component (new, not yet drawn in Figma); built to `size/confidenceMark`.
public struct ConfidenceIndicator: View {
    public let level: ConfidenceLevel
    public let showsLabel: Bool
    public let locale: Locale

    public init(_ level: ConfidenceLevel, showsLabel: Bool = true, locale: Locale = .current) {
        self.level = level
        self.showsLabel = showsLabel
        self.locale = locale
    }

    public var body: some View {
        HStack(spacing: IterSpace.xs) {
            ConfidenceMark(level: level)
            if showsLabel {
                Text(verbatim: level.name(locale: locale))
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: level.phrase(locale: locale)))
    }
}

/// The mark alone.
struct ConfidenceMark: View {
    let level: ConfidenceLevel

    var body: some View {
        let d = IterSize.confidenceMark
        ZStack {
            Circle().strokeBorder(IterColor.textSecondary, lineWidth: IterStroke.regular)
            switch level {
            case .low: EmptyView()
            case .medium: HalfDisc().fill(IterColor.textSecondary).padding(IterStroke.regular * 2)
            case .high: Circle().fill(IterColor.textSecondary).padding(IterStroke.regular * 2)
            }
        }
        .frame(width: d, height: d)
        .accessibilityHidden(true)
    }
}

private struct HalfDisc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.move(to: c)
        p.addArc(center: c, radius: min(rect.width, rect.height) / 2, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

#Preview("Confidence") {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(ConfidenceLevel.allCases, id: \.self) { ConfidenceIndicator($0) }
    }
    .padding()
}
