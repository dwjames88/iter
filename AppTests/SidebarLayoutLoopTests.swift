#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import Iter

/// Guards the "more Update Constraints in Window passes than there are views" crash: the sidebar's sample-data banner
/// once had `fixedSize(horizontal: false, vertical: true)` on its wrapping text, so the sidebar column's minimum height
/// depended on its width. With the trip inspector open the split view's constraints pass kept changing that width, and
/// AppKit threw. The banner's minimum height (what it asks for when offered no height) must not depend on the width.
@MainActor
struct SidebarLayoutLoopTests {
    private func minimumHeight(atWidth width: CGFloat) -> CGFloat {
        let controller = NSHostingController(rootView: SampleDataLabel(style: .banner))
        // Offered no height at all: what comes back is the least height the banner can be laid out in at this width.
        return controller.sizeThatFits(in: CGSize(width: width, height: 0)).height
    }

    /// The narrow widths matter: the wrapped text only changes height once the column is squeezed (with the old
    /// `fixedSize` the minimum was 96 pt at 120 pt wide and 70 pt at 160, against 57 pt from 200 up).
    @Test func bannerMinimumHeightDoesNotDependOnWidth() {
        let heights = [120, 160, 200, 280, 320].map { minimumHeight(atWidth: CGFloat($0)) }
        #expect(heights.allSatisfy { $0 == heights[0] }, "banner minimum height varies with width: \(heights)")
    }
}
#endif
