import SwiftUI

/// Live maps do not render offscreen. Snapshot renders set `.snapshot` and map views draw a static stand-in instead.
enum RenderMode: Sendable { case live, snapshot }

extension EnvironmentValues {
    @Entry var renderMode: RenderMode = .live
}
