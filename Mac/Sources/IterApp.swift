import AppKit
import SwiftUI
import IterScreens

struct RebuildRootView: View {
    var body: some View {
        Text("Rebuild")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier(IterScreensModule.name)
    }
}

@main
struct IterApp: App {
    init() {
        // Hosted tests (xcodebuild test, scripts/test-mac.sh): never show, activate or take focus. Hook for the test
        // host only; the Mac shell worker keeps this when it replaces the stub.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            NSApplication.shared.setActivationPolicy(.prohibited)
        }
    }

    var body: some Scene {
        WindowGroup {
            RebuildRootView()
        }
    }
}
