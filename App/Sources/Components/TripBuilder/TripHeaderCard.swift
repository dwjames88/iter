import SwiftUI
import IterDesign

/// The trip's header card: its name (edited in place), round glass actions trailing, and the facts under it. A solid
/// content card (the design models glass over an opaque fill; the content layer takes no glass).
struct TripHeaderCard<Actions: View, Accessory: View>: View {
    let title: String
    let meta: [TripMetaItem]
    let onRename: (String) -> Void
    @ViewBuilder var actions: Actions
    @ViewBuilder var accessory: Accessory

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                TextField(String(localized: "Trip name", comment: "Placeholder"), text: $name)
                    .textFieldStyle(.plain)
                    .font(BuilderType.title)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(1)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { if !focused { commit() } }
                    .onChange(of: title) { if !focused { name = title } }
                    .onAppear { name = title }
                    .help(Text("Click to rename", comment: "Tooltip"))
                    .accessibilityLabel(Text("Trip name", comment: "Accessibility label"))
                    .accessibilityAddTraits(.isHeader)
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
    init(title: String, meta: [TripMetaItem], onRename: @escaping (String) -> Void, @ViewBuilder actions: () -> Actions) {
        self.init(title: title, meta: meta, onRename: onRename, actions: actions, accessory: { EmptyView() })
    }
}

#Preview("Header card, light") { HeaderCardPreview().preferredColorScheme(.light) }
#Preview("Header card, dark") { HeaderCardPreview().preferredColorScheme(.dark) }

struct HeaderCardPreview: View {
    var body: some View {
        TripHeaderCard(title: "Canyon Country", meta: TripMetaItem.sample, onRename: { _ in }) {
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
