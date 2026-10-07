import SwiftUI
import IterDesign

/// A 44 pt round glass button label. Use inside `Button` or `Menu`.
struct RoundGlassLabel: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(IterColor.textPrimary)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(Circle())
    }
}

/// A round glass button with a VoiceOver label.
struct RoundGlassButton: View {
    let systemImage: String
    let label: String
    var hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) { RoundGlassLabel(systemImage: systemImage) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
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
            GlassEffectContainer(spacing: IterSpace.sm) {
                HStack(spacing: IterSpace.sm) { trailing }
            }
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

/// A horizontally scrolling row of capsules, 16 pt gutters, clipped at the edges.
struct ChipRow: View {
    let chips: [ChipItem]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: IterSpace.sm) {
                ForEach(chips) { chip in
                    Button(action: chip.action) {
                        HStack(spacing: IterSpace.xs) {
                            if let symbol = chip.symbol { Image(systemName: symbol).font(.footnote) }
                            Text(chip.title).font(.subheadline.weight(.medium))
                        }
                        .padding(.horizontal, IterSpace.md)
                        .frame(minHeight: 36)
                        .foregroundStyle(chip.isSelected ? IterColor.onAccent : IterColor.textPrimary.color)
                        .background(chip.isSelected ? IterColor.accent : IterColor.backgroundModule, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chip.isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, IterSpace.lg)
        }
        .scrollIndicators(.hidden)
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
            .background(IterColor.backgroundModule, in: Capsule())
            .lineLimit(1)
    }
}

/// A floating glass capsule for secondary actions (share, open in Maps, more).
struct ActionPill<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: IterSpace.xs) { content }
            .padding(.horizontal, IterSpace.xs)
            .frame(height: 52)
            .glassEffect(.regular, in: .capsule)
    }
}

/// A 44 pt icon button label for use inside an `ActionPill`.
struct PillIconLabel: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(IterColor.textPrimary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// The one accent primary action next to the pill.
struct PrimaryPillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: IterSpace.sm) {
            configuration.icon
            configuration.title.font(.headline)
        }
        .foregroundStyle(IterColor.onAccent)
        .padding(.horizontal, IterSpace.lg)
        .frame(height: 52)
        .background(IterColor.accent, in: Capsule())
    }
}

/// A two-up card: icon on top, title, a grey hint. Hairline outline, no fill.
struct TwoUpCardLabelStyle: LabelStyle {
    var hint: String
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            configuration.icon.font(.title3).foregroundStyle(IterColor.accent)
            configuration.title.font(.headline).foregroundStyle(IterColor.textPrimary)
            Text(hint).font(.footnote).foregroundStyle(IterColor.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(IterSpace.lg)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(IterColor.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
