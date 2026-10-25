import SwiftUI
import IterDesign

/// "Add a note…": a stop's note, edited in place. Saved a moment after you stop typing and when you leave the field, so a
/// note is never lost and typing does not write on every key.
struct NotePlaceholder: View {
    let note: String
    /// The placeholder; a stop's note by default, a drive's note when given.
    var prompt: LocalizedStringResource = LocalizedStringResource("Add a note…", comment: "Placeholder for a stop's note")
    /// The VoiceOver label; "Note" by default, "Drive note" for a drive.
    var accessibilityName: LocalizedStringResource = LocalizedStringResource("Note", comment: "Accessibility label of a stop's note field")
    let onCommit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(text: $text, prompt: Text(prompt).foregroundStyle(IterColor.textTertiary), axis: .vertical) {
            Text(accessibilityName)
        }
        .textFieldStyle(.plain)
        .font(BuilderType.control)
        .foregroundStyle(IterColor.textSecondary)
        .lineLimit(1...4)
        .focused($focused)
        .onAppear { text = note }
        .onChange(of: note) { if !focused { text = note } }
        .onChange(of: focused) { if !focused { commit() } }
        .onSubmit(commit)
        .task(id: text) {
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled { commit() }
        }
        .accessibilityLabel(Text(accessibilityName))
    }

    private func commit() {
        if text != note { onCommit(text) }
    }
}

#Preview("Note, light") { NotePreview().preferredColorScheme(.light) }
#Preview("Note, dark") { NotePreview().preferredColorScheme(.dark) }

private struct NotePreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            NotePlaceholder(note: "") { _ in }
            NotePlaceholder(note: "Park in the lower lot") { _ in }
            NotePlaceholder(note: "", prompt: LocalizedStringResource("Add a note…", comment: "Placeholder for a drive's note"),
                            accessibilityName: LocalizedStringResource("Drive note", comment: "Accessibility label of a drive's note field")) { _ in }
        }
        .frame(width: 260, alignment: .leading)
        .padding(IterSpace.xl)
        .background(IterColor.backgroundModule)
    }
}
