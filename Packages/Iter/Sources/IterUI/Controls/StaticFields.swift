import SwiftUI

extension EnvironmentValues {
    /// Snapshot renders only: draw editable text fields as plain text in the same font and colour. AppKit lays out a
    /// field's text (and placeholder) a few points off on some offscreen passes, depending on timing, so comparisons of
    /// any view holding a field flaked under load. The app never sets this.
    @Entry public var rendersFieldsAsText: Bool = false
}
