#if os(macOS)  // Mac only: the direct-download build's updater and store location (the iOS app excludes these)
import SwiftUI
import IterDesign

/// Settings ▸ Updates.
struct UpdatesSettingsPane: View {
    @Bindable var controller: UpdateController

    init(controller: UpdateController = .shared) { self.controller = controller }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $controller.automaticChecks) {
                    Text("Check for updates automatically", comment: "Settings field")
                }
                Picker(selection: .constant(controller.channel)) {
                    Text("Releases", comment: "Settings: the update channel").tag("release")
                } label: { Text("Channel", comment: "Settings field") }
                    .disabled(true)
            } footer: {
                VStack(alignment: .leading) {
                    Text("Iter checks once a day, when it opens.", comment: "Settings footer")
                    Text("Pre-release channels may come later.", comment: "Settings footer")
                    #if DEBUG
                    if let feed = controller.feedURL { Text(feed.absoluteString).textSelection(.enabled) }
                    #endif
                }
            }
            Section {
                LabeledContent {
                    Text(VersionText.currentPlain)
                } label: { Text("Current version", comment: "Settings field") }
                LabeledContent {
                    if let last = controller.lastCheck {
                        Text(last.formatted(.relative(presentation: .named)))
                    } else {
                        Text("Never", comment: "Settings: updates have not been checked yet")
                    }
                } label: { Text("Last checked", comment: "Settings field") }
                Button(String(localized: "Check Now", comment: "Settings button")) { controller.checkForUpdates() }
                    .disabled(controller.isBusy)
            }
            if !controller.blockers.isEmpty {
                Section {
                    ForEach(controller.blockers, id: \.self) { blocker in
                        Label { Text(UpdateText.message(for: blocker)) } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning)
                        }
                    }
                } header: {
                    Text("Updates can't be installed here", comment: "Settings section")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { controller.refreshBlockers() }
    }
}

#endif
