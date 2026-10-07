import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// One map pin. Three weights give the map hierarchy (critique C28): the selected spot, a few chips, the rest dots.
/// Chips and the selected pin are the event unit (`EventScore` `.pin`): symbol, score and time are one capsule, with no
/// outline. Selection is scale, elevation and shadow (the Apple Maps idiom), never a coral border.
struct ExplorePinView: View {
    let pin: ExplorePin

    @Environment(\.renderMode) private var renderMode

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
        .frame(width: IterSpace.sm + IterSpace.xs, height: IterSpace.sm + IterSpace.xs)
        .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
    }

    /// The chip: the pin variant, with its time.
    @ViewBuilder private var chip: some View {
        if let window = pin.row.window {
            EventScore(window: window, zone: pin.row.spot.timeZone, timeStyle: .start, variant: .pin, isLoading: pin.row.isLoading,
                       isTomorrow: LightText.isTomorrow(pin.row), isSelected: false)
        } else {
            dot
        }
    }

    @ViewBuilder private var selected: some View {
        if let window = pin.row.window {
            EventScore(window: window, zone: pin.row.spot.timeZone, timeStyle: .start, variant: .pin,
                       isLoading: pin.row.isLoading, isTomorrow: LightText.isTomorrow(pin.row), isSelected: true)
        } else {
            Text(pin.row.spot.name)
                .font(IterFont.captionStrong)
                .foregroundStyle(IterColor.textPrimary)
                .lineLimit(1)
                .padding(.vertical, IterSpace.xs)
                .padding(.horizontal, IterSpace.sm)
                .background(fill, in: Capsule())
                .shadow(radius: IterEvent.pinShadowRadiusSelected, y: 1)
                .scaleEffect(IterEvent.pinScaleSelected, anchor: .bottom)
        }
    }

    private var fill: AnyShapeStyle {
        // An offscreen render has no backdrop for materials.
        renderMode == .snapshot ? AnyShapeStyle(IterColor.backgroundContent) : AnyShapeStyle(.regularMaterial)
    }
}
