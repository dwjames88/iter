import SwiftUI
import UIKit
import IterFeatures
import IterModel
@testable import Iter

/// Offscreen iOS renders of the iPhone and iPad screens: a `UIWindow` that is never made key, a `UIHostingController` and
/// `CALayer.render` (the pattern of GoHarness). Writes Design/snapshots/rebuild/ios/screens/<name>-<light|dark>.png under
/// ITER_SNAPSHOT_RECORD=1. MapKit tiles and pins, and system glass, do not draw offscreen.
@MainActor
enum ScreensHarness {
    static let scale: CGFloat = 2
    static let phone = CGSize(width: 402, height: 874)
    static let phoneHalf = CGSize(width: 402, height: 480)
    static let phoneFull = CGSize(width: 402, height: 780)
    static let pad = CGSize(width: 1210, height: 834)

    static var recording: Bool { ProcessInfo.processInfo.environment["ITER_SNAPSHOT_RECORD"] == "1" }

    /// A shell on the sample container (in-memory store, sample library, fixed location), optionally with a given Find model.
    static func shell(find: FindModel? = nil) throws -> IOSShell {
        let options = LaunchOptions(inMemoryStore: true, sampleData: true, fixedLocation: Coordinate(latitude: 38.5733, longitude: -109.5498),
                                    seedTrip: true)
        let container = try AppContainer.live(options: options, bundleID: "com.dwjames.iter.render", environment: [:])
        return IOSShell(container: container, find: find)
    }

    /// The sheet's stand-in: what the system sheet draws is glass, which does not render offscreen, so a flat system background.
    static func sheet<V: View>(_ shell: IOSShell, @ViewBuilder _ content: () -> V) -> some View {
        NavigationStack { content() }
            .environment(\.isOnGlass, true)
            .iterShellEnvironment(shell)
            .background(Color(uiColor: .systemBackground))
    }

    @discardableResult
    static func render(_ view: some View, name: String, size: CGSize) async throws -> [CGImage] {
        var images: [CGImage] = []
        for dark in [false, true] {
            let image = try await image(view, dark: dark, size: size)
            images.append(image)
            if recording {
                let url = outputDirectory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard let data = UIImage(cgImage: image).pngData() else { throw HarnessError.png }
                try data.write(to: url)
            }
        }
        return images
    }

    static func image(_ view: some View, dark: Bool, size: CGSize) async throws -> CGImage {
        let content = view
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .environment(\.colorScheme, dark ? .dark : .light)
        let controller = UIHostingController(rootView: AnyView(content))
        controller.view.backgroundColor = .systemBackground
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<8 {
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
        guard let cg = ui.cgImage else { throw HarnessError.render }
        return cg
    }

    static var outputDirectory: URL {
        var root: URL?
        if let r = ProcessInfo.processInfo.environment["ITER_REPO_ROOT"] { root = URL(fileURLWithPath: r) }
        if root == nil {
            var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            for _ in 0..<10 {
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Design").path),
                   FileManager.default.fileExists(atPath: dir.appendingPathComponent("Packages").path) { root = dir; break }
                dir.deleteLastPathComponent()
            }
        }
        return (root ?? FileManager.default.temporaryDirectory).appendingPathComponent("Design/snapshots/rebuild/ios/screens", isDirectory: true)
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
