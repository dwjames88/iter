import CoreGraphics
import Testing
@testable import IterUI

@Suite("Glass geometry")
struct GlassGeometryTests {
    @Test func valuesMatchGlassRules() {
        #expect(GlassGeometry.cardCorner == 27.5)
        #expect(GlassGeometry.cornerButton == 32)
        #expect(GlassGeometry.cornerButtonInset == 11.5)
    }

    @Test func cornerButtonInsetIsConcentricWithTheCardCorner() {
        let reach: CGFloat = GlassGeometry.cornerButtonInset + GlassGeometry.cornerButton / 2
        #expect(reach == GlassGeometry.cardCorner)
    }
}

@Suite("IterUI module")
struct IterUIModuleTests {
    @Test func moduleName() {
        #expect(IterUIModule.name == "IterUI")
    }

    @Test func chipMetricsAreTheEventMetrics() {
        #expect(IterChip.heightLarge == IterEvent.heightLarge && IterChip.heightLarge == 48)
        #expect(IterChip.heightSmall == 38 && IterChip.heightCompact == 26)
    }
}
