import AppKit
import SwiftUI
import Testing
@testable import Iter

/// Proves the hosted harness: the host is the render copy, a simple view renders in light and dark with real content,
/// and the app's current root view renders. PNGs land in ITER_SNAPSHOT_DIR (scripts/test-mac.sh copies them to
/// Design/snapshots/rebuild/mac/).
@MainActor @Suite struct SnapshotHarnessTests {
    @Test func hostIsTheRenderCopy() {
        #expect(Bundle.main.bundleIdentifier == Snapshot.renderBundleID)
        #expect(ProcessInfo.processInfo.arguments.contains("-IterInMemoryStore"))
    }

    @Test func simpleViewRendersLightAndDark() async throws {
        let view = VStack(spacing: 12) {
            Text("Iter").font(.largeTitle.bold())
            Text("Harness proof").foregroundStyle(.secondary)
            RoundedRectangle(cornerRadius: 12).fill(Color.orange).frame(width: 160, height: 48)
        }
        .frame(width: 320, height: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        let urls = try await Snapshot.render(view, name: "harness-simple", size: CGSize(width: 320, height: 200))
        #expect(urls.count == 2)
        var lumas: [Double] = []
        for url in urls {
            let image = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(image.width == 640 && image.height == 400)
            let pixels = try #require(Pixels(image))
            let stats = pixels.stats(x: 0, y: 0, w: 320, h: 200)
            #expect(stats.hasContent, "\(url.lastPathComponent) looks blank")
            #expect(stats.transparent == 0)
            // The orange block is saturated in both appearances.
            #expect(stats.saturated > 1000)
            lumas.append(stats.medianLuma)
        }
        // Light background is lighter than the dark one: the appearance really changed.
        #expect(lumas[0] > lumas[1])
    }

    @Test func rootViewRenders() async throws {
        let urls = try await Snapshot.render(RebuildRootView(), name: "harness-root", size: CGSize(width: 480, height: 320))
        #expect(urls.count == 2)
        for url in urls { #expect(FileManager.default.fileExists(atPath: url.path)) }
    }

    @Test func hostIsNotActiveAndShowsNoWindow() {
        // IterApp sets the activation policy to .prohibited under XCTest: nothing is ever frontmost, key or visible.
        #expect(NSApp.activationPolicy() == .prohibited)
        #expect(!NSApp.isActive)
        #expect(NSApp.windows.allSatisfy { !$0.isKeyWindow })
    }

    @Test func hostNeverBecameActiveOrKey() async throws {
        _ = try await Snapshot.renderImage(Text("x").frame(width: 40, height: 20), appearance: .light, size: CGSize(width: 40, height: 20), settle: .milliseconds(100))
        #expect(NSApp.keyWindow == nil || NSApp.keyWindow?.frame.origin.x ?? 0 != -30_000)
    }
}
