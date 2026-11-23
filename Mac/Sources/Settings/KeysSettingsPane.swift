import SwiftUI
import IterFeatures

/// Settings ▸ Keys: optional keys of your own, kept in the Keychain. When no source takes one, the model's plain sentence.
struct KeysSettingsPane: View {
    let model: SettingsModel

    var body: some View {
        Form {
            if model.keyRows.isEmpty {
                Section { Text(model.keysSummary) }
            } else {
                Section {
                    ForEach(model.keyRows) { row in KeyRowView(model: model, row: row) }
                } footer: {
                    Text(model.keysSummary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One key: a secure field with Save, and Remove once a key is saved. The key is never shown or logged.
struct KeyRowView: View {
    let model: SettingsModel
    let row: KeyRow
    @State private var draft = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SecureField(row.sourceName, text: $draft,
                            prompt: Text(row.hasKey ? "Saved in Keychain. Paste to replace" : (row.isRequired ? "Paste your key (required)" : "Paste your key")))
                Button("Save") { save() }.disabled(draft.isEmpty)
                if row.hasKey { Button("Remove", role: .destructive) { remove() } }
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
    }

    private func save() {
        do { try model.setKey(draft, for: row.id); draft = ""; failure = nil } catch { failure = "Couldn't save the key to your Keychain." }
    }

    private func remove() {
        do { try model.removeKey(for: row.id); failure = nil } catch { failure = "Couldn't remove the key from your Keychain." }
    }
}
