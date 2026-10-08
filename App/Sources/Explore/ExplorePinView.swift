import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// One map pin. Three weights give the map hierarchy (critique C28): the selected spot, a few chips, the rest dots.
/// Chips and the selected pin are the event unit (`EventScore` `.pin`): symbol, score and time are one capsule, with no
/// outline. Selection is scale, elevation and shadow (the Apple Maps idiom), never a coral border.
struct ExplorePinView: View, Equatable {
    let pin: ExplorePin


    /// A pin that did not change is not redrawn (the map pane draws it with `.equatable()`).
    nonisolated static func == (a: ExplorePinView, b: ExplorePinView) -> Bool { a.pin == b.pin }

    var body: some View {
        let _ = IterPerf.count("pin.body")
        Group {
            switch pin.style {
            case .dot: dot
            case .chip: chip
            case .selected: selected
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LightText.pinDescription(pin))
        .accessibilityAddTraits(pin.style == .selected ? [.isButton, .isSelected] : .isButton)
        .onAppear { IterPerf.once("pin.firstAppear") }
    }

    private var dot: some View {
        Group {
            if let score = pin.scoreValue {
                Circle().fill(IterColor.ramp(score: score))
            } else {
                Circle().fill(IterColor.backgroundControl)
            }
        }
        .frame(width: IterSpace.sm + IterSpace.xs, height: IterSpace.sm + IterSpace.xs)
        .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
    }

    /// The chip: the pin variant of the event unit, with its time.
    @ViewBuilder private var chip: some View {
        if let light = pin.light {
            EventScore(pin: light, zone: pin.timeZone, isSelected: false)
        } else {
            dot
        }
    }

    @ViewBuilder private var selected: some View {
        if let light = pin.light {
            EventScore(pin: light, zone: pin.timeZone, isSelected: true)
        } else {
            Text(pin.name)
                .font(IterFont.captionStrong)
                .foregroundStyle(IterColor.textPrimary)
                .lineLimit(1)
                .padding(.vertical, IterSpace.xs)
                .padding(.horizontal, IterSpace.sm)
                .background(IterColor.backgroundContent, in: Capsule())
                .shadow(radius: IterEvent.pinShadowRadiusSelected, y: 1)
                .scaleEffect(IterEvent.pinScaleSelected, anchor: .bottom)
        }
    }

}
