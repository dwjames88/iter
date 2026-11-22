import SwiftUI

/// The map's controls as Apple Maps stacks them on the trailing edge, in one `GlassEffectContainer`: the screen's own
/// map actions in a glass capsule at the top (Explore: Windy and Add Spot), the map controls (style, your location) in
/// another glass capsule, then `accessories` (zoom, compass: MapKit's own controls, which the caller builds with its
/// map scope). All content arrives through slots, so the stack has no app dependencies. Figma part: map control stack.
public struct MapControlStack<Actions: View, Controls: View, Accessories: View>: View {
    private let actions: Actions
    private let controls: Controls
    private let accessories: Accessories

    /// Apple Maps' control width and the gap between groups.
    public static var size: CGFloat { 36 }
    public static var gap: CGFloat { 6 }

    /// - Parameters:
    ///   - actions: the screen's map actions, one 36 pt `MapControlButton` each, in the top capsule. Omit for none.
    ///   - controls: map style and location, one 36 pt button each, in the second capsule.
    ///   - accessories: further controls under the capsules (zoom, compass), not wrapped in glass here.
    public init(@ViewBuilder actions: () -> Actions, @ViewBuilder controls: () -> Controls,
                @ViewBuilder accessories: () -> Accessories) {
        self.actions = actions()
        self.controls = controls()
        self.accessories = accessories()
    }

    public var body: some View {
        GlassEffectContainer(spacing: Self.gap) {
            VStack(spacing: Self.gap) {
                if Actions.self != EmptyView.self {
                    capsule { actions }
                }
                if Controls.self != EmptyView.self {
                    capsule { controls }
                }
                accessories
            }
        }
        .padding(IterSpace.sm)
    }

    private func capsule(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .buttonStyle(.plain)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.primary)
            .glassEffect(.regular.interactive(), in: .capsule)
    }
}

extension MapControlStack where Actions == EmptyView, Accessories == EmptyView {
    /// Only the controls capsule.
    public init(@ViewBuilder controls: () -> Controls) {
        self.init(actions: { EmptyView() }, controls: controls, accessories: { EmptyView() })
    }
}

extension MapControlStack where Accessories == EmptyView {
    /// The actions capsule over the controls capsule.
    public init(@ViewBuilder actions: () -> Actions, @ViewBuilder controls: () -> Controls) {
        self.init(actions: actions, controls: controls, accessories: { EmptyView() })
    }
}

/// One button in a map control capsule: a 36 pt icon, with a tooltip and an accessibility label.
public struct MapControlButton: View {
    let title: String
    let systemImage: String
    var help: String?
    var isOn: Bool
    let action: () -> Void

    public init(title: String, systemImage: String, help: String? = nil, isOn: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(isOn ? AnyShapeStyle(IterColor.accent) : AnyShapeStyle(.primary))
                .frame(width: MapControlStack<EmptyView, EmptyView, EmptyView>.size,
                       height: MapControlStack<EmptyView, EmptyView, EmptyView>.size)
                .contentShape(.rect)
        }
        .help(help ?? title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
