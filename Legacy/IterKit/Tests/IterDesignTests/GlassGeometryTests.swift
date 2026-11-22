import CoreGraphics
import Testing
@testable import IterDesign

@Suite("Glass geometry")
struct GlassGeometryTests {
    @Test func cornerButtonInsetIsConcentricWithTheCardCorner() {
        #expect(GlassGeometry.cornerButtonInset == 11.5)
        let reach: CGFloat = GlassGeometry.cornerButtonInset + GlassGeometry.cornerButton / 2
        #expect(reach == GlassGeometry.cardCorner)
    }
}
