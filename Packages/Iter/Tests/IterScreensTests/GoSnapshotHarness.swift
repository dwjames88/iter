import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
import SwiftUI
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Offscreen snapshot harness for the Go screens (copied from IterUITests/Support/Snapshot.swift, renamed)
//
// Ported from the old app's test support. Goal: PNGs of SwiftUI views with NO visible window, NO focus change and
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

enum GoSnapshotAppearance: String, CaseIterable, Sendable {
    case light, dark
}

enum GoSnapshotError: Error { case render, png, noRepoRoot }

enum GoPNG {
    static func data(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

@MainActor
enum GoSnapshotHarness {
    /// Pixels per point of every PNG.
    static let defaultScale: CGFloat = 2

    // MARK: Public API

    /// Renders `view` in a `size`-point frame. `background` (default: the platform window/system background) fills
    /// behind the view. Resolves in the given appearance. Settles layout before capturing.
    static func image(_ view: some View, appearance: GoSnapshotAppearance, size: CGSize,
                      scale: CGFloat = defaultScale, background: Color? = nil,
                      settle: Duration = .milliseconds(300)) async throws -> CGImage {
        let content = view
            .frame(width: size.width, height: size.height)
            .background { background }
            .environment(\.colorScheme, appearance == .dark ? .dark : .light)
        // The same process-wide lock as `Snapshot` (this copy had none): see `RenderLock`.
        await RenderLock.shared.acquire()
        defer { RenderLock.shared.release() }
        return try await renderBackend(AnyView(content), appearance: appearance, size: size, scale: scale, settle: settle)
    }

    /// Renders `view` in both appearances. Always renders (so a crash or an empty image fails the test); writes
    /// `Design/snapshots/rebuild/go/<name>-<ios|mac>-<light|dark>.png` only when `ITER_SNAPSHOT_RECORD=1`.
    @discardableResult
    static func render(_ view: some View, name: String, size: CGSize, background: Color? = nil) async throws -> [GoSnapshotAppearance: CGImage] {
        let record = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_RECORD"] == "1"
        var images: [GoSnapshotAppearance: CGImage] = [:]
        for appearance in GoSnapshotAppearance.allCases {
            let img = try await image(view, appearance: appearance, size: size, background: background)
            guard img.width > 0, img.height > 0, GoPNG.data(img) != nil else { throw GoSnapshotError.png }
            if record { try write(img, to: referenceURL(name: name, appearance: appearance)) }
            images[appearance] = img
        }
        return images
    }

    // MARK: Files

    static var suffix: String {
        #if canImport(UIKit)
        return "-ios"
        #else
        return "-mac"
        #endif
    }

    /// `<repo>/Design/snapshots/rebuild`, found by walking up from this file until a folder holds `Design` and `Packages`.
    static var referenceDirectory: URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let fm = FileManager.default
            if fm.fileExists(atPath: dir.appendingPathComponent("Design").path),
               fm.fileExists(atPath: dir.appendingPathComponent("Packages").path) {
                return dir.appendingPathComponent("Design/snapshots/rebuild/go", isDirectory: true)
            }
            dir.deleteLastPathComponent()
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterGoSnapshots", isDirectory: true)
    }

    static func referenceURL(name: String, appearance: GoSnapshotAppearance) -> URL {
        referenceDirectory.appendingPathComponent("\(name)\(suffix)-\(appearance.rawValue).png")
    }

    static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = GoPNG.data(image) else { throw GoSnapshotError.png }
        try data.write(to: url)
    }
}

// MARK: - macOS backend

#if canImport(AppKit)

extension GoSnapshotHarness {
    fileprivate static func renderBackend(_ view: AnyView, appearance: GoSnapshotAppearance, size: CGSize,
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
        guard let image else { throw GoSnapshotError.render }
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
        var last = -1
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(50))
            pass()
            let signature = layerSignature(host.layer)
            if signature == last { break }
            last = signature
        }
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

extension GoSnapshotHarness {
    fileprivate static func renderBackend(_ view: AnyView, appearance: GoSnapshotAppearance, size: CGSize,
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
        guard let cg = ui.cgImage else { throw GoSnapshotError.render }
        return cg
    }
}

#endif
