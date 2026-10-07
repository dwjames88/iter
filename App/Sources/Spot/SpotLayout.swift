import SwiftUI
import IterDesign

/// Shared measures for the spot page, all derived from tokens. The timeline, the hourly strip and the arc use the
/// same left gutter and right inset, so their x-axes line up (critique C21).
enum SpotLayout {
    /// Comfortable reading width for the single column.
    static let contentMaxWidth: CGFloat = IterSize.listMax + IterSize.inspectorMax
    /// Left gutter: y-axis labels on the timeline, row labels on the hourly strip.
    static let gutter: CGFloat = IterGrid.unit * 5
    static let rightInset: CGFloat = IterGrid.inset
    /// One tier of bracket labels above the sky strip.
    static let labelTier: CGFloat = IterSpace.lg
    static let bracketDrop: CGFloat = IterSpace.xs
    static let tickLength: CGFloat = IterSpace.xs
    /// Height of the cloud and rain plot.
    static let plotHeight: CGFloat = IterSize.hourlyTintHeight * 2
    /// Rows of the hourly strip.
    static let hourlyRow: CGFloat = IterGrid.unit * 3

    static let windowTintOpacity = 0.2
    static let selectedFillOpacity = 0.16
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

/// A module card (the Weather idiom): a quiet title with a leading symbol inside the card at its top-left, an optional
/// control at the title row's trailing edge, then the content 8 below. Fill `background/module`, no border.
/// `flush` lets a list inside run edge to edge of the card (its rows carry their own 16 pt inset), so the lanes
/// measured from the card edge match the layout grid overlay.
struct ModuleCard<Accessory: View, Content: View>: View {
    let title: String
    let symbol: String
    var flush = false
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(title: String, symbol: String, flush: Bool = false,
         @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.flush = flush
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            titleRow
                .padding(.horizontal, flush ? IterGrid.inset : 0)
            content
        }
        .padding(.horizontal, flush ? 0 : IterGrid.inset)
        .padding(.top, IterGrid.inset)
        .padding(.bottom, flush ? IterSpace.sm : IterGrid.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IterColor.backgroundModule, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// The title and its control share a row; where they do not fit side by side the control drops below.
    private var titleRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                titleLabel
                Spacer(minLength: IterSpace.sm)
                accessory
            }
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                titleLabel
                accessory
            }
        }
    }

    private var titleLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(title)
        }
        .font(IterFont.moduleTitle)
        .foregroundStyle(IterColor.textSecondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension ModuleCard where Accessory == EmptyView {
    init(title: String, symbol: String, flush: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title: title, symbol: symbol, flush: flush, accessory: { EmptyView() }, content: content)
    }
}
