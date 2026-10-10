import Foundation
import Testing
@testable import IterCore

@Suite struct RenderCopyTests {
    @Test func shippedBundleIDIsNotARenderCopy() {
        #expect(!RenderCopy.isRenderCopy(bundleID: "com.dwjames.iter"))
    }

    @Test func otherBundleIDsAreRenderCopies() {
        #expect(RenderCopy.isRenderCopy(bundleID: "com.dwjames.iter.render"))
        #expect(RenderCopy.isRenderCopy(bundleID: "com.dwjames.iter.render.tests"))
        #expect(RenderCopy.isRenderCopy(bundleID: "com.dwjames.iter2"))
        #expect(RenderCopy.isRenderCopy(bundleID: "com.example.other"))
    }

    @Test func missingBundleIDCountsAsShipped() {
        #expect(!RenderCopy.isRenderCopy(bundleID: nil))
        #expect(!RenderCopy.isRenderCopy(bundleID: ""))
    }

    @Test func scratchDirectoryIsInsideTemporaryDirectory() {
        let url = RenderCopy.scratchDirectory("Packs")
        #expect(url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        #expect(url.lastPathComponent.hasPrefix("IterRender-Packs-"))
    }
}
