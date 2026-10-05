import SwiftUI
import IterCore
import IterFeatures

/// Keys owned by the Settings window.
enum SettingsKeys {
    /// "" means each spot's own best light; otherwise a `LightIntent` raw value.
    static let preferredIntent = "IterPreferredIntent"
}

private struct AppliesStoredPreferences: ViewModifier {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKeys.preferredIntent) private var preferredIntentRaw = ""

    func body(content: Content) -> some View {
        content.onAppear { model.preferredIntent = LightIntent(rawValue: preferredIntentRaw) }
    }
}

extension View {
    /// Applies the "Show light for" setting to the app model. `RootView` can call this once on the main window so the
    /// stored choice is in effect from launch.
    func appliesStoredPreferences() -> some View { modifier(AppliesStoredPreferences()) }
}
