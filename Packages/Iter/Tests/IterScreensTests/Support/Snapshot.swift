import CoreGraphics
import Foundation
import SwiftUI
import Testing
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Offscreen snapshot harness (package tests, no host app)
//
// Ported from AppTests/Support/Snapshot.swift. Goal: PNGs of SwiftUI views with NO visible window, NO focus change and
// NO Screen Recording permission, so never ScreenCaptureKit or CGWindowList.
//
// macOS (xctest bundle, no app): `NSApplication.shared` is created with the `.prohibited` activation policy (never
// activates, never fronts). The view is hosted in a borderless window at (-30000, -30000) that is ordered back, never
// key or main, ignores the mouse and is closed after the render. The window's frame-view layer is drawn with
// `CALayer.render(in:)` (faithful for SwiftUI; `cacheDisplay` draws dark text black). Layers that sample the window
// server (backdrop, portal, SDF glass) and vibrancy compositing filters do not survive that, so `repair` swaps them
// for flat equivalents on the throw-away window before the render. See the findings in HarnessTests.swift.
//
// iOS: a `UIWindow` that is never made key, hosting a `UIHostingController`, drawn with `drawHierarchy`.

enum SnapshotAppearance: String, CaseIterable, Sendable {
    case light, dark
}

/// A FIFO async mutex on the main actor (see `Snapshot.image`).
@MainActor
final class RenderLock {
    static let shared = RenderLock()
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }
}

enum SnapshotError: Error { case render, png, noRepoRoot }

@MainActor
enum Snapshot {
    /// Pixels per point of every PNG.
    static let defaultScale: CGFloat = 2

    // MARK: Public API

    /// Renders `view` in a `size`-point frame. `background` (default: the platform window/system background) fills
    /// behind the view. Resolves in the given appearance. Settles layout before capturing.
    static func image(_ view: some View, appearance: SnapshotAppearance, size: CGSize,
                      scale: CGFloat = defaultScale, background: Color? = nil,
                      settle: Duration = .milliseconds(800)) async throws -> CGImage {
        let content = view
            .frame(width: size.width, height: size.height)
            .background { background }
            .environment(\.colorScheme, appearance == .dark ? .dark : .light)
            .environment(\.rendersFieldsAsText, true)
            #if os(macOS)
            // The offscreen window is never key, and an inactive window draws prominent buttons and selection grey. Render controls as
            // they look in the focused window.
            .environment(\.controlActiveState, .key)
            #endif
        // One render at a time. Swift Testing runs the snapshot tests concurrently on the main actor and each render
        // suspends (settle sleeps), so renders interleaved: several off-screen windows at the same spot, shared
        // first-responder, display and CATransaction state. That moved text (the search placeholder) and layout between
        // runs: the cause of the flake. The lock makes each render run alone.
        await RenderLock.shared.acquire()
        defer { RenderLock.shared.release() }
        return try await renderBackend(AnyView(content), appearance: appearance, size: size, scale: scale, settle: settle)
    }

    /// Renders light and dark and writes `Design/snapshots/rebuild/<name>-<light|dark>.png` (`-ios` before the
    /// appearance on iOS).
    @discardableResult
    static func record(_ view: some View, name: String, size: CGSize, background: Color? = nil) async throws -> [URL] {
        var urls: [URL] = []
        for appearance in SnapshotAppearance.allCases {
            let img = try await image(view, appearance: appearance, size: size, background: background)
            let url = referenceURL(name: name, appearance: appearance)
            try write(img, to: url)
            urls.append(url)
        }
        return urls
    }

    /// Compares against the reference PNG; records it when missing or when `ITER_SNAPSHOT_RECORD=1`.
    /// On a mismatch beyond tolerance: `Issue.record` with the folder holding the actual render and the diff image.
    static func assertMatches(_ view: some View, name: String, size: CGSize, background: Color? = nil,
                              tolerance: ImageDiff = ImageDiff(),
                              sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let forceRecord = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_RECORD"] == "1"
        for appearance in SnapshotAppearance.allCases {
            let actual = try await image(view, appearance: appearance, size: size, background: background)
            let url = referenceURL(name: name, appearance: appearance)
            guard !forceRecord, let reference = PNG.image(at: url) else {
                try write(actual, to: url)
                print("Snapshot: recorded \(url.path)")
                continue
            }
            let result = tolerance.compare(actual, reference)
            if result.passed { continue }
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("IterSnapshotFailures/\(name)-\(appearance.rawValue)-\(UUID().uuidString.prefix(8))", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? write(actual, to: dir.appendingPathComponent("actual.png"))
            try? write(reference, to: dir.appendingPathComponent("reference.png"))
            if let diff = result.diffImage { try? write(diff, to: dir.appendingPathComponent("diff.png")) }
            Issue.record("Snapshot \(name)-\(appearance.rawValue) differs from reference: \(result.summary). Files in \(dir.path)",
                         sourceLocation: sourceLocation)
        }
    }

    // MARK: Files

    static var suffix: String {
        #if canImport(UIKit)
        return "-ios"
        #else
        return ""
        #endif
    }

    /// `<repo>/Design/snapshots/rebuild`, found by walking up from this file until a folder holds `Design` and `Packages`.
    static var referenceDirectory: URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let fm = FileManager.default
            if fm.fileExists(atPath: dir.appendingPathComponent("Design").path),
               fm.fileExists(atPath: dir.appendingPathComponent("Packages").path) {
                return dir.appendingPathComponent("Design/snapshots/rebuild/screens", isDirectory: true)
            }
            dir.deleteLastPathComponent()
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots", isDirectory: true)
    }

    static func referenceURL(name: String, appearance: SnapshotAppearance) -> URL {
        referenceDirectory.appendingPathComponent("\(name)\(suffix)-\(appearance.rawValue).png")
    }

    static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = PNG.data(image) else { throw SnapshotError.png }
        try data.write(to: url)
    }
}

// MARK: - macOS backend

#if canImport(AppKit)

extension Snapshot {
    @MainActor private static var keepAlive: [(NSWindow, NSView)] = []

    fileprivate static func renderBackend(_ view: AnyView, appearance: SnapshotAppearance, size: CGSize,
                                          scale: CGFloat, settle: Duration) async throws -> CGImage {
        // An xctest bundle has no app. A prohibited app never shows a Dock icon, never activates, never fronts.
        let app = NSApplication.shared
        if app.activationPolicy() != .prohibited { app.setActivationPolicy(.prohibited) }

        let nsAppearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)!
        let rect = NSRect(origin: .zero, size: size)
        let window = OffscreenWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.appearance = nsAppearance
        let host = NSHostingView(rootView: view)
        host.appearance = nsAppearance
        window.contentView = host
        // MapKit views deadlock in `-[VKMapView dealloc]` (a dispatch_sync to the main loop) when they die inside a test run, so
        // every hosting window and view lives until the process ends. Offscreen renders are small and few.
        keepAlive.append((window, host))
        window.setFrame(NSRect(x: -30_000, y: -30_000, width: size.width, height: size.height), display: false)
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }

        try await settleLayout(window: window, host: host, appearance: nsAppearance, settle: settle)
        let frameView: NSView = window.contentView?.superview ?? host
        var image: CGImage?
        nsAppearance.performAsCurrentDrawingAppearance {
            frameView.layoutSubtreeIfNeeded()
            if ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DUMP"] == "1", let layer = frameView.layer { dump(layer, 0) }
            if let layer = frameView.layer, ProcessInfo.processInfo.environment["ITER_SNAPSHOT_NOREPAIR"] != "1" { repair(layer) }
            image = capture(frameView, size: size, scale: scale)
        }
        guard let image else { throw SnapshotError.render }
        return image
    }

    private static func settleLayout(window: NSWindow, host: NSView, appearance: NSAppearance, settle: Duration) async throws {
        func pass() {
            appearance.performAsCurrentDrawingAppearance {
                host.layoutSubtreeIfNeeded()
                window.contentView?.superview?.layoutSubtreeIfNeeded()
                window.display()
                CATransaction.flush()
            }
        }
        pass()
        try await Task.sleep(for: settle)
        pass()
        // Stable pixels, not a stable layer tree: AppKit text fields (the search field's placeholder) and lists move
        // their text after the layer frames stop changing, and under load (a full parallel run) that happens late, so a
        // capture taken on an unchanged layer tree can still catch the earlier position. Wait until three consecutive
        // renders of the (unrepaired) layer tree are byte-identical, for at most about 6 seconds.
        var last = -1, stableRuns = 0
        for _ in 0..<120 {
            try await Task.sleep(for: .milliseconds(50))
            pass()
            let signature = layerSignature(host.layer) &* 31 &+ pixelSignature(of: window.contentView?.superview ?? host, appearance: appearance)
            if signature == last { stableRuns += 1; if stableRuns >= 6 { break } } else { stableRuns = 0 }
            last = signature
        }
    }

    /// A hash of what the layer tree draws right now (before `repair`, so it is only compared with itself).
    private static func pixelSignature(of view: NSView, appearance: NSAppearance) -> Int {
        let scale: CGFloat = 1
        let pw = Int(view.bounds.width * scale), ph = Int(view.bounds.height * scale)
        guard pw > 0, ph > 0, let layer = view.layer,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: pw * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return 0 }
        appearance.performAsCurrentDrawingAppearance { layer.render(in: ctx) }
        var h = Hasher()
        h.combine(bytes: UnsafeRawBufferPointer(start: data, count: pw * 4 * ph))
        return h.finalize()
    }

    private static func layerSignature(_ layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        var h = Hasher()
        h.combine(NSStringFromRect(layer.frame))
        h.combine(layer.contents != nil)
        h.combine(layer.isHidden)
        for s in layer.sublayers ?? [] { h.combine(layerSignature(s)) }
        return h.finalize()
    }

    /// Debug aid: `ITER_SNAPSHOT_DUMP=1` prints the layer tree before the repair.
    private static func dump(_ l: CALayer, _ depth: Int) {
        let cf = l.compositingFilter.map { " cf=\($0)" } ?? ""
        print(String(repeating: "  ", count: depth) + "\(type(of: l)) \(l.frame) hidden=\(l.isHidden) contents=\(l.contents != nil)\(cf)")
        for c in l.sublayers ?? [] { dump(c, depth + 1) }
    }

    private static func capture(_ frameView: NSView, size: CGSize, scale: CGFloat) -> CGImage? {
        let pw = Int(size.width * scale), ph = Int(size.height * scale)
        guard let layer = frameView.layer,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Opaque base: a bare window has no background of its own and the PNG must never be transparent.
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        return ctx.makeImage()
    }

    // Layer-tree repair, trimmed from the app harness to what component-sized views need.
    private static func repair(_ l: CALayer) {
        if l.isHidden { return }
        let className = String(describing: type(of: l))
        // Layers that sample the window server's backdrop render opaque white offscreen and would cover content.
        if className == "CABackdropLayer" || className == "CAPortalLayer" || className == "PortalLayer" {
            l.isHidden = true
            return
        }
        let compositing = l.compositingFilter.map { String(describing: $0) }
        l.filters = nil
        l.backgroundFilters = nil
        l.compositingFilter = nil
        if l.delegate is NSVisualEffectView {
            l.isHidden = true
            insertFill(below: l, color: NSColor.labelColor.withAlphaComponent(0.12).cgColor, radius: 8)
            return
        }
        if let compositing, l.bounds.width > 0, l.bounds.height > 0 {
            if compositing == "plusL" || compositing == "plusD", let mask = alphaMask(of: l) {
                insertFill(below: l, color: NSColor.labelColor.cgColor, mask: mask)
                l.isHidden = true
                return
            }
            if className == "ImageLayer", let contents = l.contents {
                let mask = CALayer()
                mask.frame = l.bounds
                mask.contents = contents
                mask.contentsScale = l.contentsScale
                mask.contentsGravity = l.contentsGravity
                l.contents = nil
                l.backgroundColor = NSColor.secondaryLabelColor.cgColor
                l.mask = mask
                return
            }
        }
        for c in l.sublayers ?? [] { repair(c) }
    }

    private static func insertFill(below l: CALayer, color: CGColor, radius: CGFloat = 0, mask: CALayer? = nil) {
        guard let parent = l.superlayer else { return }
        let fill = CALayer()
        fill.frame = l.frame
        fill.cornerRadius = radius
        fill.backgroundColor = color
        fill.mask = mask
        parent.insertSublayer(fill, below: l)
    }

    private static func alphaMask(of l: CALayer) -> CALayer? {
        let scale = defaultScale
        let w = Int(ceil(l.bounds.width * scale)), h = Int(ceil(l.bounds.height * scale))
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: scale, y: -scale)
        let savedMask = l.mask
        l.mask = nil
        l.render(in: ctx)
        l.mask = savedMask
        guard let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let bpr = ctx.bytesPerRow
        var best: (alpha: Int, grey: Double) = (0, 0)
        for y in 0..<h {
            for x in 0..<w {
                let o = y * bpr + x * 4, a = Int(data[o + 3])
                if a > best.alpha { best = (a, (Double(data[o]) + Double(data[o + 1]) + Double(data[o + 2])) / 3 / Double(max(a, 1))) }
            }
        }
        let dark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let factor = min(1, (dark ? best.grey : 1 - best.grey) / 0.6)
        for y in 0..<h {
            for x in 0..<w {
                let o = y * bpr + x * 4
                data[o + 3] = UInt8(Double(data[o + 3]) * factor)
                data[o] = 0; data[o + 1] = 0; data[o + 2] = 0
            }
        }
        guard let image = ctx.makeImage() else { return nil }
        let mask = CALayer()
        mask.frame = l.bounds
        mask.contents = image
        mask.contentsScale = scale
        return mask
    }
}

/// A window that is never constrained to a display, never key and never main.
private final class OffscreenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: - iOS backend

#elseif canImport(UIKit)

extension Snapshot {
    fileprivate static func renderBackend(_ view: AnyView, appearance: SnapshotAppearance, size: CGSize,
                                          scale: CGFloat, settle: Duration) async throws -> CGImage {
        let style: UIUserInterfaceStyle = appearance == .dark ? .dark : .light
        let controller = UIHostingController(rootView: view)
        controller.safeAreaRegions = []   // a scene-less window still reports a status-bar inset
        controller.view.backgroundColor = .systemBackground
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.isHidden = false   // visible to UIKit only; never made key, so nothing is brought to front
        defer { window.isHidden = true }
        for _ in 0..<4 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: settle / 4)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let mode = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_IOS_MODE"] ?? "layer"
        let ui = renderer.image { ctx in
            let bounds = CGRect(origin: .zero, size: size)
            // Trait collection of the window so dynamic colours resolve in the requested appearance.
            window.traitCollection.performAsCurrent {
                UIColor.systemBackground.setFill()
                ctx.fill(bounds)
                if mode == "hierarchy" {
                    controller.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
                } else {
                    controller.view.layer.render(in: ctx.cgContext)
                }
            }
        }
        guard let cg = ui.cgImage else { throw SnapshotError.render }
        return cg
    }
}

#endif
