import SwiftUI

/// The window's search field at the top of the sidebar, as Maps has it: a 37 pt Liquid Glass capsule with the magnifier,
/// 13 pt text, a 12 pt inset and a clear button (measured from Maps). The system fields don't come at this size:
/// SwiftUI's sidebar `searchable` stays 28 pt and AppKit's search field keeps its bezel at 24 pt whatever its frame.
/// Figma part: Sidebar (11:1768), search field.
public struct SidebarSearchField: View {
    @Binding var text: String
    let prompt: String
    /// Bumps when Edit > Find asks for the field.
    let focusRequest: Int
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    public static var height: CGFloat { 37 }

    public init(text: Binding<String>, prompt: String, focusRequest: Int = 0, onSubmit: @escaping () -> Void = {}) {
        _text = text
        self.prompt = prompt
        self.focusRequest = focusRequest
        self.onSubmit = onSubmit
    }

    public var body: some View {
        GlassEffectContainer {
            HStack(spacing: IterSpace.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(prompt, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit(onSubmit)
                    .onKeyPress(.escape) {
                        guard !text.isEmpty else { return .ignored }
                        text = ""
                        return .handled
                    }
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Clear the search", bundle: .module, comment: "Tooltip"))
                    .accessibilityLabel(Text("Clear", bundle: .module, comment: "VoiceOver: clear the search field"))
                }
            }
            .padding(.horizontal, IterSpace.md)
            .frame(height: Self.height)
            .contentShape(.capsule)
            .onTapGesture { isFocused = true }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .onChange(of: focusRequest) { isFocused = true }
    }
}
