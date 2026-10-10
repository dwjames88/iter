import Foundation
import OSLog
import IterCore
#if canImport(AppKit)
import AppKit
#endif

/// Development-only scripts for the interactions a screenshot run cannot drive with a real mouse (a locked screen, or no
/// window server access): `-IterDragScript spot-to-folder|stop-reorder`, `-IterResizeScript 1100,1800` and
/// `-IterCaptureWindow <dir>`. They call the same handlers the user's gestures call; they are not the gestures.
/// See `AppLaunch` for the switches. Honoured only with `-IterInMemoryStore YES`, so they never touch real data.
enum DebugScripts {
    static let log = Logger(subsystem: "com.dwjames.iter", category: "script")

    static var dragScript: String? { AppLaunch.inMemoryStore ? UserDefaults.standard.string(forKey: "IterDragScript") : nil }
    static var captureDir: String? { UserDefaults.standard.string(forKey: "IterCaptureWindow") }
    /// `-IterResizeScript 1100,1800`: the width range, in points.
    static var resizeRange: ClosedRange<Double>? {
        guard AppLaunch.inMemoryStore, let raw = UserDefaults.standard.string(forKey: "IterResizeScript") else { return nil }
        let p = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count == 2, p[0] > 0, p[0] <= p[1] else { return nil }
        return p[0]...p[1]
    }

    /// One line to stdout (and the unified log), flushed so a redirected file stays current.
    static func say(_ text: String) {
        log.notice("\(text, privacy: .public)")
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    static func milliseconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }

    static func pause(_ seconds: Double) async { try? await Task.sleep(for: .milliseconds(Int(seconds * 1000))) }

    /// Quits when the script is done, unless `-IterScriptKeepOpen YES`.
    @MainActor static func finish() {
        #if canImport(AppKit)
        if !UserDefaults.standard.bool(forKey: "IterScriptKeepOpen") { NSApp.terminate(nil) }
        #endif
    }

    /// Writes the main window's content to `<dir>/<name>.png` through `cacheDisplay`, which works with the screen
    /// locked. MapKit and some glass layers may come out blank in it; it is for layout, not for the final look.
    @MainActor static func capture(_ name: String) async {
        #if canImport(AppKit)
        guard let dir = captureDir else { return }
        await pause(0.5)   // let SwiftUI settle after the state change
        // A hidden launch (`open -j`, scripts/render.sh) has windows that exist but are not "visible": take them too.
        guard let window = NSApp.windows.filter({ $0.contentView != nil && ($0.isVisible || $0.frame.width > 400) }).max(by: { $0.frame.width < $1.frame.width }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { say("capture \(name): no window"); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
            say("capture \(name) \(Int(window.frame.width))x\(Int(window.frame.height))")
        }
        #endif
    }

    /// `-IterCaptureAfter <seconds>` (with `-IterCaptureWindow <dir>`): one capture of whatever is on screen after that long, written
    /// as `<dir>/screen.png`, then the app quits unless `-IterScriptKeepOpen YES`. Lets any screen be captured without a script.
    @MainActor static func runCaptureAfter() async {
        guard captureDir != nil, let raw = UserDefaults.standard.string(forKey: "IterCaptureAfter"), let seconds = Double(raw), seconds >= 0 else { return }
        await pause(seconds)
        await capture("screen")
        finish()
    }

    /// Every launch-switch script, side by side (one task in `RootView`).
    @MainActor static func runAll() async {
        async let resize: Void = runResize()
        async let capture: Void = runCaptureAfter()
        _ = await (resize, capture)
    }

    /// `-IterResizeScript lo,hi`: steps the window's width from lo to hi and back, one step about every 16 ms, then holds at
    /// 1100, 1280, 1440, 1600 and 1800 (those inside the range) and captures each. Layout warnings land on stderr.
    @MainActor static func runResize() async {
        #if canImport(AppKit)
        guard let range = resizeRange else { return }
        await pause(6)
        guard let window = NSApp.windows.filter({ $0.contentView != nil && $0.frame.width > 400 }).max(by: { $0.frame.width < $1.frame.width }) else { return }
        func setWidth(_ w: Double) {
            var frame = window.frame
            frame.size.width = w
            window.setFrame(frame, display: true)
        }
        say("resize start \(range) from \(window.frame.width)")
        setWidth(range.lowerBound)
        await pause(1)
        let step = 8.0
        var widths = Array(stride(from: range.lowerBound, through: range.upperBound, by: step))
        widths += widths.reversed()
        IterPerf.resetCounters()
        let start = Date()
        // Per step: `sync` is setFrame(display: true) returning (layout and display of the window); `total` adds the
        // main queue turning twice after it, which is what the next step has to wait behind.
        var sync = StepStats(), total = StepStats()
        // `-IterResizeLive NO` runs the sweep as raw `setFrame` calls (no live-resize bracket), the way the script used to.
        let live = UserDefaults.standard.object(forKey: "IterResizeLive") == nil || UserDefaults.standard.bool(forKey: "IterResizeLive")
        if live { NotificationCenter.default.post(name: NSWindow.willStartLiveResizeNotification, object: window) }
        for w in widths {
            let t0 = ContinuousClock.now
            setWidth(w)
            let t1 = ContinuousClock.now
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { DispatchQueue.main.async { c.resume() } }
            }
            let t2 = ContinuousClock.now
            sync.record(Self.milliseconds(t1 - t0)); total.record(Self.milliseconds(t2 - t0))
            await pause(0.016)
        }
        if live {
            NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: window)
            await pause(0.5)
        }
        say("resize live=\(live)")
        say("resize sweep \(widths.count) steps in \(Int(Date().timeIntervalSince(start) * 1000)) ms")
        say("resize step sync \(sync.summary)")
        say("resize step total \(total.summary)")
        say("resize counters \(IterPerf.counterValues().sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))")
        IterPerf.log.notice("perf resize step sync \(sync.summary, privacy: .public)")
        IterPerf.log.notice("perf resize step total \(total.summary, privacy: .public)")
        for w in [1000.0, 1100, 1280, 1440, 1600, 1728, 1800] where range.contains(w) {
            setWidth(w)
            await capture("resize-\(Int(w))")
        }
        say("resize done")
        finish()
        #endif
    }
}

/// The folder row a scripted drag is "hovering" over, so the drop highlight can be rendered without a real drag.
@MainActor @Observable
final class ScriptedDropHover {
    static let shared = ScriptedDropHover()
    var folderID: UUID?
}
