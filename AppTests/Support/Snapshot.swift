import AppKit
import SwiftUI
import Testing
@testable import Iter

// MARK: - Offscreen renderer: what works, what does not, and why
//
// Goal: faithful PNGs of whole SwiftUI screens with NO visible window, NO focus change and NO Screen Recording
// permission (so no ScreenCaptureKit and no CGWindowList). The only thing left is to draw the app's own view and layer
// trees into a CGContext, and the window server is never asked for pixels. Findings (macOS 26, Xcode 26 SDK):
//
//  * A window that is never ordered in does not lay out AppKit-backed `List` rows. The window is therefore ordered
//    in with `orderBack(_:)` at (-30000, -30000) (a subclass overrides `constrainFrameRect(_:to:)`, so a titled
//    window is not pulled back onto a display), is never key/main, ignores the mouse, and is closed after the render.
//  * `NSView.cacheDisplay(in:to:)` draws SwiftUI text black in dark appearance and misses layer-hosted SwiftUI content.
//    `CALayer.render(in:)` of the window's frame view layer is faithful for SwiftUI content, so that is what is used.
//  * Three things in the layer tree do not survive `CALayer.render(in:)` and are replaced here, on the throw-away
//    window, right before rendering (`prepareForCapture`):
//      1. `NSGlassEffectView` (the macOS 26 sidebar and toolbar glass): its glass is drawn by the window server, and
//         the view paints opaque white offscreen, hiding its content. The content view is lifted out of the glass
//         view and the glass is hidden (replaced by a faint flat fill).
//      2. Vibrancy: text layers use `plusL`/`plusD` (plus-lighter/darker) compositing and symbols use
//         `vibrantColorMatrixSourceOver`; both need the backdrop of a real window and come out wrong, so text is
//         redrawn as a `labelColor` fill through its own alpha mask (alpha scaled from the drawn luminance) and symbol
//         images as a `secondaryLabelColor` fill through the symbol mask.
//      3. `NSVisualEffectView` (list selection pill, materials) renders black. It is replaced by a flat translucent
//         `labelColor` fill.
//  * What stays approximate: glass is flat, not refractive; the sidebar selection is a neutral pill (an inactive
//    window's look), not the accent pill of a key window; vibrancy "secondary/tertiary" text levels are approximated
//    from the drawn luminance, so they can be off by a few percent; MapKit views, `WKWebView` and anything that needs
//    the GPU compositor (Metal layers) do not draw offscreen, which is why `RenderMode.snapshot` exists.
//  * Resolved colours depend on `NSAppearance.current`, so layout, display and capture all run inside
//    `performAsCurrentDrawingAppearance`, and the window and hosting view get the appearance explicitly.

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
    /// Pixels per point of every PNG.
    nonisolated static let scale: CGFloat = 2

    static var outputDirectory: URL {
        // One folder per run so parallel runs from different checkouts (same bundle ID, same container) don't collide.
        let run = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_RUN"] ?? "default"
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots/\(run)", isDirectory: true)
    }

    /// Renders `view` at every appearance and size. `settle` lets async work (forecast loads) finish first.
    /// `chrome` picks a titled window with a toolbar area (default) or a bare content window.
    static func render<V: View>(_ view: V, screen: String, state: String, sizes: [Size] = sizes,
                                settle: Duration = .milliseconds(600), chrome: Chrome = .titled) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        for appearance in Appearance.allCases {
            for size in sizes {
                let name = "\(screen)-\(state)-\(appearance.rawValue)-\(size.name).png"
                let png = try await renderPNG(view, appearance: appearance, size: size, settle: settle, chrome: chrome)
                try png.write(to: outputDirectory.appendingPathComponent(name))
            }
        }
    }

    enum Chrome { case titled, bare }

    static func renderPNG<V: View>(_ view: V, appearance: Appearance, size: Size, settle: Duration,
                                   chrome: Chrome = .titled) async throws -> Data {
        let image = try await renderImage(view, appearance: appearance, size: size, settle: settle, chrome: chrome)
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw SnapshotError.render }
        return data
    }

    static func renderImage<V: View>(_ view: V, appearance: Appearance, size: Size, settle: Duration,
                                     chrome: Chrome = .titled) async throws -> CGImage {
        let rect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let nsAppearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)!
        let style: NSWindow.StyleMask = chrome == .titled ? [.titled, .fullSizeContentView] : [.borderless]
        let window = OffscreenWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.appearance = nsAppearance
        if chrome == .titled {
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
        }
        let host = NSHostingView(rootView: view
            .environment(\.renderMode, .snapshot)
            .environment(\.colorScheme, appearance == .dark ? .dark : .light))
        host.appearance = nsAppearance
        window.contentView = host
        // Far outside every display, never key or main, so nothing is visible and focus is never taken.
        window.setFrame(NSRect(x: -30_000, y: -30_000, width: size.width, height: size.height), display: false)
        window.orderBack(nil)
        defer { window.orderOut(nil); window.close() }

        try await settleLayout(window: window, host: host, appearance: nsAppearance, settle: settle)

        let frameView: NSView = window.contentView?.superview ?? host
        // Lift content out of glass views, then let the moved views lay out and draw again before repairing layers.
        nsAppearance.performAsCurrentDrawingAppearance { liftContentOutOfGlass(frameView) }
        try await settleLayout(window: window, host: host, appearance: nsAppearance, settle: .milliseconds(100))
        var image: CGImage?
        nsAppearance.performAsCurrentDrawingAppearance {
            prepareForCapture(frameView)
            image = capture(frameView, size: size, appearance: nsAppearance)
        }
        guard let image else { throw SnapshotError.render }
        return image
    }

    // MARK: Settling

    /// Lays out, lets async work finish, then waits until the layer tree stops changing (two identical signatures
    /// in a row) so the capture does not depend on timing.
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
            try await Task.sleep(for: .milliseconds(100))
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

    // MARK: Capture

    private static func capture(_ frameView: NSView, size: Size, appearance: NSAppearance) -> CGImage? {
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

    // MARK: Layer tree repair (see the note at the top of the file)

    /// Mutates the throw-away window's view and layer trees so `CALayer.render(in:)` is faithful. Not idempotent:
    /// call once per window.
    private static func prepareForCapture(_ root: NSView) {
        if ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DUMP"] == "1" { dumpTree(root, 0) }
        root.layoutSubtreeIfNeeded()
        if let layer = root.layer { repair(layer) }
    }

    /// Debug aid: `ITER_SNAPSHOT_DUMP=1` appends the view tree of each capture to `<container tmp>/IterSnapshots/tree.txt`.
    private static func dumpTree(_ v: NSView, _ depth: Int) {
        let line = String(repeating: "  ", count: depth) + "\(String(describing: type(of: v)).prefix(60)) \(v.frame) hidden=\(v.isHidden) contents=\(v.layer?.contents != nil)\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots/tree.txt")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? Data(line.utf8).write(to: url) }
        for c in v.subviews { dumpTree(c, depth + 1) }
    }

    private static func liftContentOutOfGlass(_ view: NSView) {
        for child in view.subviews { liftContentOutOfGlass(child) }
        guard let glass = view as? NSGlassEffectView, let content = glass.contentView, let parent = glass.superview else { return }
        let frame = glass.frame
        glass.contentView = nil
        parent.addSubview(content, positioned: .above, relativeTo: glass)
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]
        content.frame = frame
        // The glass view sized its content with constraints that die with the reparenting: pin the content's
        // children to its bounds by hand.
        NSLayoutConstraint.deactivate(content.constraints)
        for child in content.subviews {
            child.translatesAutoresizingMaskIntoConstraints = true
            child.autoresizingMask = [.width, .height]
            child.frame = content.bounds
        }
        glass.isHidden = true
        // A flat stand-in for the glass so a sidebar is distinguishable from the detail column.
        if let layer = parent.layer {
            let fill = CALayer()
            fill.frame = frame
            fill.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
            if let glassLayer = glass.layer { layer.insertSublayer(fill, below: glassLayer) } else { layer.addSublayer(fill) }
        }
    }

    private static func repair(_ l: CALayer) {
        if l.isHidden { return }
        let className = String(describing: type(of: l))
        // Layers that sample the window server's backdrop (scroll-edge blurs, portals, SDF glass) render as opaque
        // white offscreen and would cover the content below them.
        if className == "CABackdropLayer" || className == "CAPortalLayer" || className == "PortalLayer" || className == "CASDFLayer" {
            l.isHidden = true
            return
        }
        if let v = l.delegate as? NSView, String(describing: type(of: v)).contains("ScrollPocket") {
            l.isHidden = true
            return
        }
        let compositing = l.compositingFilter.map { String(describing: $0) }
        l.filters = nil
        l.backgroundFilters = nil
        l.compositingFilter = nil

        if l.delegate is NSVisualEffectView {
            // Selection pills and materials render black offscreen.
            l.isHidden = true
            if let v = l.delegate as? NSVisualEffectView, v.superview.map({ String(describing: type(of: $0)).contains("ThemeFrame") }) == true {
                // The window's own background material: a flat window colour.
                insertFill(below: l, color: NSColor.windowBackgroundColor.cgColor)
            } else {
                insertFill(below: l, color: NSColor.labelColor.withAlphaComponent(0.12).cgColor, radius: 8)
            }
            return
        }
        if let compositing, l.bounds.width > 0, l.bounds.height > 0 {
            if compositing == "plusL" || compositing == "plusD", let mask = alphaMask(of: l) {
                // Vibrant text: redraw as a label-colour fill through the text's own alpha.
                insertFill(below: l, color: NSColor.labelColor.cgColor, mask: mask)
                l.isHidden = true
                return
            }
            if String(describing: type(of: l)) == "ImageLayer", let contents = l.contents {
                // Vibrant symbol: template image, filled with the secondary label colour.
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

    /// Draws `l` alone into a transparent bitmap and returns a mask layer carrying its alpha. Vibrant text is drawn
    /// in a grey that only makes sense when blended over the vibrancy backdrop (dark: light grey, light: mid grey for
    /// primary text, further from the extreme for secondary text); that luminance is turned into opacity.
    private static func alphaMask(of l: CALayer) -> CALayer? {
        let w = Int(ceil(l.bounds.width * scale)), h = Int(ceil(l.bounds.height * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // The mask is composited in the flipped layer space of a list row: draw it flipped.
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

    enum SnapshotError: Error { case render }

    /// True when snapshots were asked for (`scripts/snapshots.sh` sets it); otherwise snapshot tests are skipped
    /// so the normal test run stays fast.
    nonisolated static var enabled: Bool {
        ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"
    }
}

/// A window that is never constrained to a display, never key and never main.
private final class OffscreenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// MARK: - Pixel access for tests

/// A decoded PNG/CGImage with RGBA access in pixel coordinates (origin top-left).
struct Pixels {
    let width: Int
    let height: Int
    private let data: [UInt8]

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        self.width = width; self.height = height; data = buffer
    }

    /// Straight RGBA, 0...255, with y counted from the top.
    func rgba(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let o = (y * width + x) * 4
        let a = Int(data[o + 3])
        guard a > 0 else { return (0, 0, 0, 0) }
        func un(_ v: UInt8) -> Int { min(255, Int(v) * 255 / a) }
        return (un(data[o]), un(data[o + 1]), un(data[o + 2]), a)
    }

    func luma(_ x: Int, _ y: Int) -> Double {
        let p = rgba(x, y)
        return (0.2126 * Double(p.r) + 0.7152 * Double(p.g) + 0.0722 * Double(p.b)) / 255
    }

    /// Statistics over a point-space rect (multiplied by the render scale).
    func stats(x: Int, y: Int, w: Int, h: Int, scale: Int = Int(Snapshot.scale)) -> Stats {
        var lumas: [Double] = []
        var saturated = 0, transparent = 0, count = 0
        for py in (y * scale)..<min(height, (y + h) * scale) {
            for px in (x * scale)..<min(width, (x + w) * scale) {
                let p = rgba(px, py)
                count += 1
                if p.a < 250 { transparent += 1 }
                lumas.append(luma(px, py))
                if max(p.r, p.g, p.b) - min(p.r, p.g, p.b) > 60 { saturated += 1 }
            }
        }
        lumas.sort()
        return Stats(count: count, minLuma: lumas.first ?? 0, maxLuma: lumas.last ?? 0,
                     medianLuma: lumas.isEmpty ? 0 : lumas[lumas.count / 2], saturated: saturated, transparent: transparent)
    }

    struct Stats {
        let count: Int
        let minLuma: Double
        let maxLuma: Double
        let medianLuma: Double
        let saturated: Int
        let transparent: Int
        /// Pixels meaningfully different from the background (the median) exist.
        var hasContent: Bool { maxLuma - minLuma > 0.25 }
    }
}
