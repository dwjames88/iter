import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// One map pin. Three weights give the map hierarchy (critique C28): the selected spot, a few chips, the rest dots.
struct ExplorePinView: View {
    let pin: ExplorePin

    var body: some View {
        Group {
            switch pin.style {
            case .dot: dot
            case .chip: chip
            case .selected: selected
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LightText.rowDescription(pin.row))
        .accessibilityAddTraits(pin.style == .selected ? [.isButton, .isSelected] : .isButton)
    }

    private var dot: some View {
        Group {
            if let score = pin.row.window?.assessment.lightScore {
                Circle().fill(IterColor.ramp(score.band))
            } else {
                Circle().fill(IterColor.backgroundControl)
            }
        }
        .frame(width: IterSpace.md, height: IterSpace.md)
        .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
    }

    /// The window symbol and, when scored, the score. Without a score the chip is plain (a neutral chip while loading).
    private func lightContent(_ window: LightWindow, chipSize: ScoreChip.Size) -> some View {
        HStack(spacing: IterSpace.xs) {
            WindowSymbol(kind: window.kind, font: .system(size: IterSize.pinSymbol))
            if let score = window.assessment.lightScore {
                ScoreChip(score: score, size: chipSize)
            }
        }
    }

    @ViewBuilder private var chip: some View {
        if let window = pin.row.window {
            lightContent(window, chipSize: .compact)
                .padding(.horizontal, IterSpace.xs)
                .padding(.vertical, IterSpace.xxs)
                .background(IterColor.backgroundContent, in: Capsule())
                .overlay(Capsule().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
        } else {
            dot
        }
    }

    private var selected: some View {
        VStack(spacing: IterSpace.xxs) {
            Group {
                if let window = pin.row.window {
                    HStack(spacing: IterSpace.xs) {
                        lightContent(window, chipSize: .compact)
                        if let time = LightText.startTime(window, in: pin.row.spot.timeZone) {
                            Text(time).font(IterFont.timeSmall).foregroundStyle(IterColor.textPrimary)
                        }
                    }
                } else {
                    Text(pin.row.spot.name).font(IterFont.captionStrong)
                }
            }
            .padding(.horizontal, IterSpace.sm)
            .padding(.vertical, IterSpace.xs)
            .background(IterColor.backgroundContent, in: Capsule())
            .overlay(Capsule().strokeBorder(IterColor.mapPin, lineWidth: IterStroke.thick))
            Image(systemName: "arrowtriangle.down.fill")
                .font(IterFont.caption)
                .foregroundStyle(IterColor.mapPin)
                .accessibilityHidden(true)
        }
    }
}

extension IterSize {
    /// The window symbol inside a map pin chip.
    static let pinSymbol: CGFloat = 12
}
