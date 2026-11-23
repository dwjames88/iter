import SwiftUI

/// "Add a note…": a stop's or a drive's note, edited in place through a binding. The caller debounces saving (a moment
/// after typing stops); `onCommit` fires on Return and when the field loses focus, so a note is never lost.
/// Figma part: note placeholder.
public struct NotePlaceholder: View {
    @Binding public var text: String
    /// The placeholder; a stop's note by default, a drive's note when given.
    public var prompt: LocalizedStringResource
    /// The VoiceOver label; "Note" by default, "Drive note" for a drive.
    public var accessibilityName: LocalizedStringResource
    public var onCommit: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.rendersFieldsAsText) private var rendersFieldsAsText

    public init(text: Binding<String>,
                prompt: LocalizedStringResource? = nil,
                accessibilityName: LocalizedStringResource? = nil,
                onCommit: @escaping () -> Void = {}) {
        self._text = text
        self.prompt = prompt ?? LocalizedStringResource("Add a note…", bundle: .atURL(Bundle.module.bundleURL), comment: "Placeholder for a stop's note")
        self.accessibilityName = accessibilityName
            ?? LocalizedStringResource("Note", bundle: .atURL(Bundle.module.bundleURL), comment: "Accessibility label of a stop's note field")
        self.onCommit = onCommit
    }

    /// The drive's note: "Add a note…" and the VoiceOver name "Drive note".
    public static var driveNotePrompt: LocalizedStringResource {
        LocalizedStringResource("Add a note…", bundle: .atURL(Bundle.module.bundleURL), comment: "Placeholder for a drive's note")
    }
    public static var driveNoteName: LocalizedStringResource {
        LocalizedStringResource("Drive note", bundle: .atURL(Bundle.module.bundleURL), comment: "Accessibility label of a drive's note field")
    }

    public var body: some View {
        if rendersFieldsAsText {
            Text(text.isEmpty ? String(localized: prompt) : text)
                .font(BuilderType.control)
                .foregroundStyle(text.isEmpty ? IterColor.textTertiary : IterColor.textSecondary)
                .lineLimit(1...4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            field
        }
    }

    private var field: some View {
        TextField(text: $text, prompt: Text(prompt).foregroundStyle(IterColor.textTertiary), axis: .vertical) {
            Text(accessibilityName)
        }
        .textFieldStyle(.plain)
        .font(BuilderType.control)
        .foregroundStyle(IterColor.textSecondary)
        .lineLimit(1...4)
        .focused($focused)
        .onChange(of: focused) { if !focused { onCommit() } }
        .onSubmit(onCommit)
        .accessibilityLabel(Text(accessibilityName))
    }
}
