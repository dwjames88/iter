import SwiftUI
import IterDesign

extension EnvironmentValues {
    /// True for content on a Liquid Glass panel: the Mac's floating map card, the iPad's Explore column and the phone's
    /// sheet. Cards and cells there take a translucent system fill instead of an opaque paper colour, so the glass reads
    /// through them, as Maps' and Find My's cells do.
    @Entry var isOnGlass = false
}

/// The module fill (`background/module`) on paper; a translucent system fill on glass.
struct ModuleFill: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.isOnGlass ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(IterColor.backgroundModule)
    }
}

/// The control fill (`background/control`) on paper; a translucent system fill on glass.
struct ControlFill: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.isOnGlass ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(IterColor.backgroundControl)
    }
}

/// The content fill (`background/content`) on paper; a lighter translucent system fill on glass.
struct ContentFill: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.isOnGlass ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(IterColor.backgroundContent)
    }
}

/// A round glass button with a primary glyph, as on Maps' cards (Share, Close): neutral glass, never filled with the
/// app's accent, which the system glass style takes on the Mac.
struct GlassCircleButtonStyle: ButtonStyle {
    static var diameter: CGFloat { 28 }

    func makeBody(configuration: Configuration) -> some View {
        GlassCircle(configuration: configuration)
    }

    private struct GlassCircle: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: GlassCircleButtonStyle.diameter, height: GlassCircleButtonStyle.diameter)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
                .opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}
