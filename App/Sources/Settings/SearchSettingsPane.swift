import SwiftUI
import IterCore
import IterDesign
import IterServices
import IterFeatures

/// Settings ▸ Search: what you like to shoot, whether Ask learns from your library, how many results and in which
/// order, which free sources are searched, and the optional Google key. System `Form` chrome only. Shared by the
/// Mac Settings window and the iPhone and iPad Settings page.
struct SearchSettingsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.searchSettings
        Form {
            Section {
                TextField(text: $settings.promptPrefix, prompt: Text("Quiet alpine lakes at sunrise, long-exposure waterfalls, no crowds",
                                                                      comment: "Settings: placeholder for what the user likes to shoot"), axis: .vertical) {
                    Text("What I Like to Shoot", comment: "Settings field")
                }
                .lineLimit(3...8)
                .labelsHidden()
            } header: {
                Text("What I Like to Shoot", comment: "Settings section")
            } footer: {
                Text("Added to every Ask and Discovery request on this device. It never leaves this device except as part of the on-device prompt.",
                     comment: "Settings footer: the personal search prefix")
            }
            Section {
                Toggle(isOn: $settings.learnsFromLibrary) {
                    Text("Use My Saved Spots and Trips", comment: "Settings toggle")
                }
            } header: {
                Text("Learn From My Library", comment: "Settings section")
            } footer: {
                Text("Ask gets a short summary of the spots you save, pin and add to trips. It stays on this device.",
                     comment: "Settings footer: library learning")
            }
            Section {
                Picker(selection: $settings.preference) {
                    Text("Popular", comment: "Discovery preference").tag(DiscoveryPreference.popular)
                    Text("Unique", comment: "Discovery preference").tag(DiscoveryPreference.unique)
                    Text("Mixed", comment: "Discovery preference").tag(DiscoveryPreference.mixed)
                } label: { Text("Prefer", comment: "Settings field: which kind of results come first") }
                .pickerStyle(.segmented)
                Stepper(value: $settings.maxResults, in: DiscoverySettings.maxResultsRange, step: 5) {
                    Text("Up to \(settings.maxResults) results", comment: "Settings field with its value, e.g. Up to 20 results")
                }
            } header: {
                Text("Results", comment: "Settings section")
            } footer: {
                Text("Popular puts the most talked-about places first, Unique the lesser-known ones. Mixed alternates.",
                     comment: "Settings footer: result order")
            }
            Section {
                LabeledContent {
                    Text("Always used", comment: "Settings: Apple Maps cannot be turned off").foregroundStyle(IterColor.textSecondary)
                } label: { Text("Apple Maps", comment: "Discovery source") }
                ForEach(SearchSettingsText.freeSources, id: \.self) { source in
                    Toggle(isOn: Binding(get: { settings.isEnabled(source) }, set: { settings.setEnabled(source, $0) })) {
                        Text(SearchSettingsText.name(source))
                    }
                }
            } header: {
                Text("Sources", comment: "Settings section")
            } footer: {
                Text("These are free public sources. They are rate limited and their answers are cached. Nothing is sent except the place and the search words.",
                     comment: "Settings footer: discovery sources")
            }
            GoogleSearchSection()
        }
        .formStyle(.grouped)
    }
}

// MARK: - Google

private struct GoogleSearchSection: View {
    @Environment(AppModel.self) private var model
    @State private var key = ""
    @State private var engineID = ""
    @State private var didLoad = false
    @State private var errorText: String?

    private var canSave: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !engineID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let settings = model.searchSettings
        Section {
            LabeledContent {
                Text(settings.hasGoogleKey ? "Saved" : "Not set up", comment: "Settings: Google search key state")
                    .foregroundStyle(IterColor.textSecondary)
            } label: { Text("Status", comment: "Settings field") }
            SecureField(text: $key, prompt: Text(settings.hasGoogleKey ? "Saved in Keychain. Paste to replace" : "Paste your API key",
                                                 comment: "Settings: API key field prompt")) {
                Text("API Key", comment: "Settings field")
            }
            .secureFieldPlatformTraits()
            TextField(text: $engineID, prompt: Text("Search engine ID", comment: "Settings: Programmable Search Engine ID prompt")) {
                Text("Search Engine ID", comment: "Settings field")
            }
            .secureFieldPlatformTraits()
            HStack {
                Button(action: save) { Text("Save", comment: "Button") }
                    .disabled(!canSave)
                if settings.hasGoogleKey {
                    Button(role: .destructive, action: remove) { Text("Remove", comment: "Button") }
                }
            }
            .buttonStyle(.borderless)
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill").foregroundStyle(IterColor.danger)
            }
            if let url = URL(string: "https://programmablesearchengine.google.com/") {
                Link(destination: url) { Text("Create a Search Engine", comment: "Settings: link to Google Programmable Search") }
            }
            if let url = URL(string: "https://developers.google.com/custom-search/v1/overview") {
                Link(destination: url) { Text("About the Search API", comment: "Settings: link to the Custom Search API overview") }
            }
        } header: {
            Text("Google (Optional)", comment: "Settings section")
        } footer: {
            Text("There is no free Google places API. If you want Google results, make your own Programmable Search Engine and API key. Google bills against your account after its free daily allowance. Off until you add them, and kept in your Keychain.",
                 comment: "Settings footer: Google search is optional and uses the user's own key")
        }
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            engineID = settings.googleEngineID ?? ""
        }
    }

    private func save() {
        do {
            try model.searchSettings.setGoogle(key: key, engineID: engineID)
            key = ""
            errorText = nil
        } catch {
            errorText = String(localized: "Couldn't save to your Keychain.", comment: "Settings: Keychain error")
        }
    }

    private func remove() {
        do {
            try model.searchSettings.removeGoogle()
            key = ""
            engineID = ""
            errorText = nil
        } catch {
            errorText = String(localized: "Couldn't remove from your Keychain.", comment: "Settings: Keychain error")
        }
    }
}

private extension View {
    /// Credentials are typed exactly: no capitals, no corrections.
    @ViewBuilder func secureFieldPlatformTraits() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self.autocorrectionDisabled()
        #endif
    }
}

// MARK: - Words

enum SearchSettingsText {
    /// The free sources a person can switch, in the order Settings lists them.
    static let freeSources: [DiscoverySourceID] = [.reddit, .wikipedia, .wikivoyage, .openStreetMap]

    static func name(_ source: DiscoverySourceID) -> String {
        switch source {
        case .appleMaps: String(localized: "Apple Maps", comment: "Discovery source")
        case .reddit: String(localized: "Reddit", comment: "Discovery source")
        case .wikipedia: String(localized: "Wikipedia", comment: "Discovery source")
        case .wikivoyage: String(localized: "Wikivoyage", comment: "Discovery source")
        case .openStreetMap: String(localized: "OpenStreetMap", comment: "Discovery source")
        case .google: String(localized: "Google", comment: "Discovery source")
        }
    }

    static let attribution = String(localized: "Place discovery uses OpenStreetMap data © OpenStreetMap contributors (ODbL), Wikipedia and Wikivoyage (CC BY-SA), and Reddit public posts; Google only with your own key.",
                                    comment: "About: discovery source attribution")
}
