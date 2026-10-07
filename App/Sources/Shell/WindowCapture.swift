import AppKit

/// `-IterCaptureWindow <name.png>`: draws the main window into a PNG in the app's temporary folder and quits.
/// It renders the app's own layer tree, so it works with the display asleep or locked (where `screencapture` returns
/// black) and needs no Screen Recording permission. The layer-tree repairs are the snapshot renderer's
/// (AppTests/Support/Snapshot.swift, which explains them): glass is lifted out, vibrant text and symbols are redrawn
/// with label colours, materials become flat fills. Live maps draw blank. Test instances only: it alters the window
/// for good, which is why the app quits right after.
@MainActor enum WindowCapture {
    private static var scale: CGFloat = 2

    static func schedule(_ window: NSWindow, to path: String, after seconds: Double) {
        Task { @MainActor [weak window] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let window, let frameView = window.contentView?.superview ?? window.contentView else { return }
            scale = window.backingScaleFactor
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: (path as NSString).lastPathComponent)
            let appearance = window.effectiveAppearance
            func pass() {
                appearance.performAsCurrentDrawingAppearance {
                    // No explicit layout pass: after the reparenting, a forced constraint update can throw in AppKit
                    // (seen on Explore); the display cycle lays out what it needs.
                    window.display()
                    CATransaction.flush()
                }
            }
            // Lift content out of the glass, then let the moved views lay out and draw again before repairing layers.
            appearance.performAsCurrentDrawingAppearance { liftContentOutOfGlass(frameView) }
            for _ in 0..<5 { pass(); try? await Task.sleep(for: .milliseconds(150)) }
            var image: CGImage?
            appearance.performAsCurrentDrawingAppearance {
                if let layer = frameView.layer { repair(layer) }
                image = capture(frameView)
            }
            if let image, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                do { try data.write(to: url); AppLaunch.log.notice("capture: wrote \(url.path, privacy: .public)") }
                catch { AppLaunch.log.error("capture: \(String(describing: error), privacy: .public)") }
            } else {
                AppLaunch.log.error("capture: render failed")
            }
            NSApp.terminate(nil)
        }
    }

    private static func capture(_ frameView: NSView) -> CGImage? {
        let size = frameView.bounds.size
        let pw = Int(size.width * scale), ph = Int(size.height * scale)
        guard let layer = frameView.layer,
              let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        ctx.scaleBy(x: scale, y: scale)
        layer.render(in: ctx)
        return ctx.makeImage()
    }

    fileprivate static func liftContentOutOfGlass(_ view: NSView) {
        for child in view.subviews { liftContentOutOfGlass(child) }
        guard let glass = view as? NSGlassEffectView, let content = glass.contentView, let parent = glass.superview else { return }
        // Only the sidebar's glass: lifting toolbar items (the search field) out of theirs makes AppKit throw on layout.
        guard glass.frame.height > 200 else { return }
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

    fileprivate static func repair(_ l: CALayer) {
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

    fileprivate static func insertFill(below l: CALayer, color: CGColor, radius: CGFloat = 0, mask: CALayer? = nil) {
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
    fileprivate static func alphaMask(of l: CALayer) -> CALayer? {
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

}
