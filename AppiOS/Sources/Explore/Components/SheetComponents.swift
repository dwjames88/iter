import SwiftUI
import IterDesign

/// A 44 pt round glass button label. Use inside `Button` or `Menu`.
struct RoundGlassLabel: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(Circle())
    }
}

/// A 44 pt icon for a button in a group of map controls that share one glass capsule (as Maps groups map style and
/// location).
struct MapControlLabel: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
    }
}

/// The sheet header: a very large bold title (and an optional quiet line under it), round glass actions trailing.
struct SheetTitleHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: IterSpace.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(IterColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: IterSpace.sm)
            HStack(spacing: IterSpace.sm) { trailing }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
        }
        .padding(.horizontal, IterSpace.lg)
        .contentShape(Rectangle())
    }
}

/// One chip: a capsule, filled when selected.
struct ChipItem: Identifiable {
    let id: String
    let title: String
    var symbol: String?
    var isSelected: Bool
    let action: () -> Void
}

/// A horizontally scrolling row of filter toggles.
struct ChipRow: View {
    let chips: [ChipItem]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: IterSpace.sm) {
                ForEach(chips) { chip in
                    FilterChip(title: chip.title, symbol: chip.symbol, isOn: chip.isSelected, action: chip.action)
                }
            }
            .filterChipStyle()
            .padding(.horizontal, IterSpace.lg)
        }
        .scrollIndicators(.hidden)
    }
}

/// One filter: a system button-style toggle. Put a row of them under `.filterChipStyle()`.
struct FilterChip: View {
    let title: String
    var symbol: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
        .toggleStyle(.button)
        .lineLimit(1)
    }
}

extension View {
    /// Filter chips as the system draws them: bordered capsules, the accent when on.
    func filterChipStyle() -> some View {
        buttonStyle(.bordered).buttonBorderShape(.capsule).tint(IterColor.accent)
    }
}

/// A small fact: icon and short value in a neutral capsule.
struct FactChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(IterColor.textPrimary)
            .padding(.horizontal, IterSpace.md)
            .frame(minHeight: 32)
            .background(ModuleFill(), in: Capsule())
            .lineLimit(1)
    }
}
