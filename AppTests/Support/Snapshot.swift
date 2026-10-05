import AppKit
import SwiftUI
import Testing
@testable import Iter

/// Renders a SwiftUI view offscreen (no window is shown) to PNG.
/// Files go to the host app's container tmp (the app is sandboxed): `scripts/snapshots.sh` copies them to
/// Design/snapshots. Name: <screen>-<state>-<appearance>-<size>.png
@MainActor
enum Snapshot {
    enum Appearance: String, CaseIterable { case light, dark }
    struct Size { let name: String; let width: CGFloat; let height: CGFloat }
    static let regular = Size(name: "1280x820", width: 1280, height: 820)
    static let compact = Size(name: "960x640", width: 960, height: 640)
    static let sizes = [regular, compact]

    static var outputDirectory: URL {
        // One folder per run so parallel runs from different checkouts (same bundle ID, same container) don't collide.
        let run = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_RUN"] ?? "default"
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots/\(run)", isDirectory: true)
    }

    /// Renders `view` at every appearance and size. `settle` lets async work (forecast loads) finish first.
    static func render<V: View>(_ view: V, screen: String, state: String, sizes: [Size] = sizes,
                                settle: Duration = .milliseconds(600)) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for appearance in Appearance.allCases {
            for size in sizes {
                let name = "\(screen)-\(state)-\(appearance.rawValue)-\(size.name).png"
                let png = try await renderPNG(view, appearance: appearance, size: size, settle: settle)
                try png.write(to: outputDirectory.appendingPathComponent(name))
            }
        }
    }

    static func renderPNG<V: View>(_ view: V, appearance: Appearance, size: Size, settle: Duration) async throws -> Data {
        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        // AppKit-backed lists only lay out rows in a window that is ordered in. A borderless window is not
        // constrained to a screen, so it sits far outside every display; it is never key or main, so nothing is
        // visible and focus is never taken.
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        let nsAppearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)!
        window.appearance = nsAppearance
        let host = NSHostingView(rootView: view
            .environment(\.renderMode, .snapshot)
            .environment(\.colorScheme, appearance == .dark ? .dark : .light))
        host.appearance = nsAppearance
        host.frame = rect
        window.contentView = host
        window.orderBack(nil)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: settle)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.displayIfNeeded()
        // Render the layer tree (cacheDisplay misses layer-hosted SwiftUI content and resolves vibrancy wrongly).
        let scale: CGFloat = 2
        let pw = Int(size.width * scale), ph = Int(size.height * scale)
        guard let layer = window.contentView?.superview?.layer ?? host.layer,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw SnapshotError.render }
        ctx.scaleBy(x: scale, y: scale)
        if !layer.isGeometryFlipped && !(window.contentView?.isFlipped ?? false) {
            // AppKit layers are bottom-left origin like CGContext: draw as is.
        }
        nsAppearance.performAsCurrentDrawingAppearance {
            layer.render(in: ctx)
        }
        guard let cg = ctx.makeImage() else { throw SnapshotError.render }
        var rep = NSBitmapImageRep(cgImage: cg)
        if ProcessInfo.processInfo.environment["ITER_SNAPSHOT_CACHE"] == "1", let r2 = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            nsAppearance.performAsCurrentDrawingAppearance { host.cacheDisplay(in: host.bounds, to: r2) }
            rep = r2
        }
        window.orderOut(nil)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.render }
        return data
    }

    enum SnapshotError: Error { case render }

    /// True when snapshots were asked for (`scripts/snapshots.sh` sets it); otherwise snapshot tests are skipped
    /// so the normal test run stays fast.
    nonisolated static var enabled: Bool {
        ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"
    }
}
