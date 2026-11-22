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
struct IterIOSApp: App {
    var body: some Scene {
        WindowGroup {
            RebuildRootView()
        }
    }
}
