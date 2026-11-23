import SwiftUI
import Testing
@testable import IterScreens

// The package snapshot harness (copied from IterUITests/Support) renders shared screens offscreen into
// Design/snapshots/rebuild/screens/. System glass and MapKit do not draw there; judge layout, text, colour and states.
@MainActor @Suite struct ScreensHarnessTests {
    @Test func linksAndRenders() async throws {
        #expect(IterScreensModule.name == "IterScreens")
        let image = try await Snapshot.image(Text("Iter"), appearance: .light, size: CGSize(width: 80, height: 40))
        #expect(image.width > 0)
    }
}
