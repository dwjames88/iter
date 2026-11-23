import SwiftUI

/// The trip's header card: its name (edited in place), round glass actions trailing, and the facts under it. A solid
/// content card (the design models glass over an opaque fill; the content layer takes no glass). The actions slot is the
/// owner's: Share and More as `GlassCircleButtonStyle(diameter: 36)` inside a `GlassEffectContainer`.
/// Figma part: trip header card.
public struct TripHeaderCard<Actions: View, Accessory: View>: View {
    public let title: String
    public let meta: [TripMetaItem]
    public let onRename: (String) -> Void
    let actions: Actions
    let accessory: Accessory

    @State private var name = ""
    @FocusState private var focused: Bool
    @Environment(\.rendersFieldsAsText) private var rendersFieldsAsText

    public init(title: String, meta: [TripMetaItem], onRename: @escaping (String) -> Void,
                @ViewBuilder actions: () -> Actions, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.meta = meta
        self.onRename = onRename
        self.actions = actions()
        self.accessory = accessory()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if rendersFieldsAsText {
                    Text(title)
                        .font(BuilderType.title)
                        .foregroundStyle(IterColor.textPrimary)
                        .lineLimit(1)
                } else {
                TextField(String(localized: "Trip name", bundle: .module, comment: "Placeholder"), text: $name)
                    .textFieldStyle(.plain)
                    .font(BuilderType.title)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(1)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { if !focused { commit() } }
                    .onChange(of: title) { if !focused { name = title } }
                    .onAppear { name = title }
                    .help(Text("Click to rename", bundle: .module, comment: "Tooltip"))
                    .accessibilityLabel(Text("Trip name", bundle: .module, comment: "Accessibility label"))
                    .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                actions
            }
            TripMetaRow(items: meta)
            accessory
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { BuilderCardBackground() }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { name = title } else if trimmed != title { onRename(trimmed) }
    }
}

extension TripHeaderCard where Accessory == EmptyView {
    public init(title: String, meta: [TripMetaItem], onRename: @escaping (String) -> Void, @ViewBuilder actions: () -> Actions) {
        self.init(title: title, meta: meta, onRename: onRename, actions: actions, accessory: { EmptyView() })
    }
}

#Preview("Header card, light") { HeaderCardPreview().preferredColorScheme(.light) }
#Preview("Header card, dark") { HeaderCardPreview().preferredColorScheme(.dark) }

private struct HeaderCardPreview: View {
    var body: some View {
        TripHeaderCard(title: "Canyon Country", meta: [
            TripMetaItem(symbol: "calendar", text: "Tue, Oct 6 – Fri, Oct 9", action: {}),
            TripMetaItem(symbol: "car.fill", text: "490 mi • 9 hr, 34 min"),
        ], onRename: { _ in }) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {} label: { Label("Share", systemImage: "square.and.arrow.up") }
                    Button {} label: { Label("More", systemImage: "ellipsis") }
                }
                .buttonStyle(GlassCircleButtonStyle(diameter: 36))
            }
        }
        .padding(BuilderMetrics.panelInset)
        .frame(width: 640)
        .background(IterColor.backgroundWindow)
    }
}
