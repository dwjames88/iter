import SwiftUI
import UIKit

// The few AppKit names that shared views (compiled into both apps from App/Sources) use for text measurement.
// UIFont has the same API for what they call: preferredFont(forTextStyle:), monospacedDigitSystemFont(ofSize:weight:),
// systemFont(ofSize:weight:) and TextStyle. Keeping the AppKit spelling means the shared files need no edits beyond
// their import line.
typealias NSFont = UIFont

/// iOS has no Settings scene, so `openSettings` is unavailable. Shared views that offer "Settings…" (the weather banner)
/// read this action instead; the iOS shell sets it to show its Settings tab (iPhone) or Settings sheet (iPad).
struct OpenIterSettingsAction {
    var handler: @MainActor () -> Void = {}
    @MainActor func callAsFunction() { handler() }
}

extension EnvironmentValues {
    @Entry var openIterSettings = OpenIterSettingsAction()
}
