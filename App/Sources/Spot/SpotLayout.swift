import SwiftUI
import IterDesign

/// Shared measures for the spot page, all derived from tokens. The timeline, the hourly strip and the arc use the
/// same left gutter and right inset, so their x-axes line up (critique C21).
enum SpotLayout {
    /// Comfortable reading width for the single column.
    static let contentMaxWidth: CGFloat = IterSize.listMax + IterSize.inspectorMax
    /// Left gutter: y-axis labels on the timeline, row labels on the hourly strip.
    static let gutter: CGFloat = IterSize.controlHeightLarge + IterSpace.sm
    static let rightInset: CGFloat = IterSpace.lg
    /// One tier of bracket labels above the sky strip.
    static let labelTier: CGFloat = IterSpace.lg
    static let bracketDrop: CGFloat = IterSpace.xs
    static let tickLength: CGFloat = IterSpace.xs
    /// Height of the cloud and rain plot.
    static let plotHeight: CGFloat = IterSize.hourlyTintHeight * 2
    /// Rows of the hourly strip.
    static let hourlyRow: CGFloat = IterSize.iconLarge + IterSpace.xxs

    static let windowTintOpacity = 0.2
    static let selectedFillOpacity = 0.16
    static let fadeMedium = 0.8
    static let fadeLow = 0.6
    static let cloudFillOpacity = 0.5
    static let belowHorizonOpacity = 0.35
}

/// Where the spot page's sections are drawn. `.page` is the full spot page; `.compact` is a narrow host (an
/// expanded Explore row, the map's place card, about 300–360 pt wide) where sections drop their large titles and
/// page-only chrome and fit the width they are given.
enum SpotDensity: Sendable { case page, compact }

extension EnvironmentValues {
    @Entry var spotDensity: SpotDensity = .page
}

/// A card surface used for the lead and the charts.
struct SpotCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(IterSpace.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IterColor.backgroundControl, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous)
                .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
    }
}

/// A section title: the large page title, or a headline in a narrow host.
struct SpotSectionTitle: View {
    @Environment(\.spotDensity) private var density
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(density == .compact ? IterFont.headline : IterFont.titleSection)
    }
}
