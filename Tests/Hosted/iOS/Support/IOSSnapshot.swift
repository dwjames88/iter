import SwiftUI
import UIKit

/// Offscreen iOS renders (general form of `GoHarness`): a `UIWindow` that is never made key, a `UIHostingController` and
/// `CALayer.render`. No Simulator window, no screen capture. Map tiles, MapKit pins and system glass and system sheets do NOT
/// draw offscreen.
enum IOSSnapshot {
    enum Appearance: String, CaseIterable { case light, dark }
    static let scale: CGFloat = 2

    @MainActor
    static func image(_ view: some View, appearance: Appearance, size: CGSize) async throws -> CGImage {
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
        for _ in 0..<6 {
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
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
        guard let cg = ui.cgImage else { throw Failure.render }
        return cg
    }

    /// Renders each appearance; with `ITER_SNAPSHOT_RECORD=1` writes `Design/snapshots/rebuild/ios/<name>-<appearance>.png`.
    @MainActor @discardableResult
    static func render(_ view: some View, name: String, size: CGSize, appearances: [Appearance] = Appearance.allCases) async throws -> [CGImage] {
        var images: [CGImage] = []
        for appearance in appearances {
            let img = try await image(view, appearance: appearance, size: size)
            images.append(img)
            if ProcessInfo.processInfo.environment["ITER_SNAPSHOT_RECORD"] == "1" {
                let url = outputDirectory.appendingPathComponent("\(name)-\(appearance.rawValue).png")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = UIImage(cgImage: img).pngData() else { throw Failure.png }
                try data.write(to: url)
            }
        }
        return images
    }

    static var outputDirectory: URL {
        if let root = ProcessInfo.processInfo.environment["ITER_REPO_ROOT"] {
            return URL(fileURLWithPath: root).appendingPathComponent("Design/snapshots/rebuild/ios", isDirectory: true)
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Design").path),
               FileManager.default.fileExists(atPath: dir.appendingPathComponent("Packages").path) {
                return dir.appendingPathComponent("Design/snapshots/rebuild/ios", isDirectory: true)
            }
            dir.deleteLastPathComponent()
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterIOSSnapshots", isDirectory: true)
    }

    /// True when the image has only one distinct colour.
    static func isBlank(_ image: CGImage) -> Bool {
        guard let data = image.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return true }
        let n = CFDataGetLength(data)
        let bpp = max(1, image.bitsPerPixel / 8)
        guard n >= 2 * bpp else { return true }
        var i = bpp
        while i + bpp <= n {
            for k in 0..<min(bpp, 4) where p[i + k] != p[k] { return false }
            i += bpp
        }
        return true
    }

    enum Failure: Error { case render, png }
}
