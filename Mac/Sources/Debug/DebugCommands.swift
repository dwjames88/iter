import SwiftUI
import IterFeatures

#if DEBUG
/// The Debug menu (Debug builds, which include the render copy and the test host). Every item that changes data goes through
/// `AppContainer`'s guarded actions, which refuse the owner's real store.
struct DebugCommands: Commands {
    let shell: AppShell?
    @FocusedValue(\.windowShell) private var window
    @AppStorage("IterShowLayoutGrid") private var showLayoutGrid = false

    var body: some Commands {
        CommandMenu("Debug") {
            Button(sampleModeTitle) {}
                .disabled(true)
            Button("Relaunch with -IterSampleDataEnabled YES to change") {}
                .disabled(true)
            Divider()
            Button("Seed Sample Trip") { window?.seedSampleTrip() }
                .disabled(window == nil)
            Button("Reset All Data…", role: .destructive) { window?.showsResetConfirmation = true }
                .disabled(window == nil)
            Divider()
            Toggle("Show Layout Grid", isOn: $showLayoutGrid)
        }
    }

    private var sampleModeTitle: String {
        "Sample Data Mode: " + (shell?.container.dataMode == .sample ? "On" : "Off")
    }
}
#endif
