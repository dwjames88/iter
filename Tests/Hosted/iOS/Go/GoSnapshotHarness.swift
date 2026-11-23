import SwiftUI
import UIKit

/// Offscreen iOS renders for the widget and Live Activity tests: a `UIWindow` that is never made key, a `UIHostingController`
/// and `CALayer.render`. No Simulator window, no screen capture. (The iOS backend of Packages/Iter's Snapshot.swift.)
enum GoHarnessAppearance: String, CaseIterable { case light, dark }

@MainActor
enum GoHarness {
    static let scale: CGFloat = 2

    static func image(_ view: some View, appearance: GoHarnessAppearance, size: CGSize) async throws -> CGImage {
        let content = view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, appearance == .dark ? .dark : .light)
        let controller = UIHostingController(rootView: AnyView(content))
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .systemBackground
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = appearance == .dark ? .dark : .light
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<4 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(60))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        format.preferredRange = .standard
        let ui = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            window.traitCollection.performAsCurrent {
                UIColor.systemBackground.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                controller.view.layer.render(in: ctx.cgContext)
            }
        }
        guard let cg = ui.cgImage else { throw HarnessError.render }
        return cg
    }

    /// Writes `<repo>/Design/snapshots/rebuild/go/<name>-ios-<appearance>.png` when `ITER_SNAPSHOT_RECORD=1`.
    /// Returns the image either way so the test can check it is not blank.
    @discardableResult
    static func render(_ view: some View, name: String, size: CGSize, appearances: [GoHarnessAppearance] = GoHarnessAppearance.allCases) async throws -> [CGImage] {
        var images: [CGImage] = []
        for appearance in appearances {
            let img = try await image(view, appearance: appearance, size: size)
            images.append(img)
            if ProcessInfo.processInfo.environment["ITER_SNAPSHOT_RECORD"] == "1" {
                let url = outputDirectory.appendingPathComponent("\(name)-ios-\(appearance.rawValue).png")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = UIImage(cgImage: img).pngData() else { throw HarnessError.png }
                try data.write(to: url)
            }
        }
        return images
    }

    /// `ITER_REPO_ROOT` (set by scripts/test-ios.sh); else walk up from this file (the build maps `#filePath` to /Iter).
    static var outputDirectory: URL {
        if let root = ProcessInfo.processInfo.environment["ITER_REPO_ROOT"] {
            return URL(fileURLWithPath: root).appendingPathComponent("Design/snapshots/rebuild/go", isDirectory: true)
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Design").path),
               FileManager.default.fileExists(atPath: dir.appendingPathComponent("Packages").path) {
                return dir.appendingPathComponent("Design/snapshots/rebuild/go", isDirectory: true)
            }
            dir.deleteLastPathComponent()
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterGoSnapshots", isDirectory: true)
    }

    /// True when the image has more than one distinct colour (not blank).
    static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return true }
        let n = CFDataGetLength(data)
        guard n >= 8 else { return true }
        let bpp = max(1, image.bitsPerPixel / 8)
        let first = Array(UnsafeBufferPointer(start: p, count: min(bpp, 4)))
        var i = bpp
        while i + bpp <= n {
            for k in 0..<min(bpp, 4) where p[i + k] != first[k] { return false }
            i += bpp
        }
        return true
    }
}

enum HarnessError: Error { case render, png }
