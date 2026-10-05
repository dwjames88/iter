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
                Circle().fill(IterColor.backgroundContent)
                    .overlay(Circle().strokeBorder(IterColor.noForecast, lineWidth: IterStroke.regular))
            }
        }
        .frame(width: IterSpace.md, height: IterSpace.md)
        .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
    }

    @ViewBuilder private var chip: some View {
        if let window = pin.row.window {
            LightBadge(window: window, style: .compact, showsSource: false)
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
                        LightBadge(window: window, style: .compact, showsSource: false)
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
