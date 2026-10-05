import AppKit
import CoreGraphics
import Foundation

func die(_ m: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((m + "\n").data(using: .utf8)!)
    exit(code)
}

func frontString() -> (String, String, String)? {
    guard let a = NSWorkspace.shared.frontmostApplication else { return nil }
    return (a.bundleIdentifier ?? "?", String(a.processIdentifier), a.localizedName ?? "?")
}

func frontBundle() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

func waitFront(_ bid: String, _ secs: Double) -> Bool {
    let end = Date().addingTimeInterval(secs)
    while Date() < end {
        if frontBundle() == bid { return true }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return frontBundle() == bid
}

let args = CommandLine.arguments
guard args.count >= 2 else { die("usage: paperctl front|window|idle|keysdown|activate <bid>|waitfront <bid> <s>|click <x> <y>") }

switch args[1] {
case "front":
    guard let (b, p, n) = frontString() else { die("no frontmost app") }
    print("\(b)\t\(p)\t\(n)")

case "window":
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { die("no window list") }
    var best: (Double, String)? = nil
    for w in list {
        guard (w[kCGWindowOwnerName as String] as? String) == "Paper",
              (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? [String: Double],
              let num = w[kCGWindowNumber as String] as? Int else { continue }
        let x = b["X"] ?? 0, y = b["Y"] ?? 0, ww = b["Width"] ?? 0, h = b["Height"] ?? 0
        let title = ((w[kCGWindowName as String] as? String) ?? "").replacingOccurrences(of: "\t", with: " ")
        let line = "\(num)\t\(title)\t\(Int(x))\t\(Int(y))\t\(Int(ww))\t\(Int(h))"
        if best == nil || ww * h > best!.0 { best = (ww * h, line) }
    }
    guard let b = best else { die("no Paper window on screen") }
    print(b.1)

case "idle":
    let s = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    print(String(format: "%.2f", s))

case "keysdown":
    var down: [String] = []
    let f = CGEventSource.flagsState(.combinedSessionState)
    let names: [(CGEventFlags, String)] = [(.maskShift, "shift"), (.maskControl, "control"), (.maskAlternate, "alt"), (.maskCommand, "command")]  // fn omitted: synthetic arrow keys leave it set in the combined state
    for (m, n) in names where f.contains(m) { down.append(n) }
    for k in 0...127 where CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(k)) { down.append("key\(k)") }
    for (b, n) in [(CGMouseButton.left, "mouseLeft"), (.right, "mouseRight"), (.center, "mouseCenter")] where CGEventSource.buttonState(.combinedSessionState, button: b) { down.append(n) }
    if down.isEmpty { print("none") } else { print(down.joined(separator: ",")); exit(3) }

case "activate":
    guard args.count >= 3 else { die("activate <bundleId>") }
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[2]).first else { die("not running: \(args[2])") }
    app.activate(options: .activateAllWindows)
    if !waitFront(args[2], 1) {
        // macOS 14+ may refuse activation requested by a background process; LaunchServices (`open -b`) is honoured.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-b", args[2]]
        try? p.run(); p.waitUntilExit()
    }
    if waitFront(args[2], 3) { print("front\t\(args[2])") } else { die("did not become frontmost: now \(frontBundle() ?? "?")") }

case "waitfront":
    guard args.count >= 4, let s = Double(args[3]) else { die("waitfront <bundleId> <seconds>") }
    if waitFront(args[2], s) { print("front\t\(args[2])") } else { die("timeout: frontmost is \(frontBundle() ?? "?")") }

case "click":
    guard args.count >= 4, let x = Double(args[2]), let y = Double(args[3]) else { die("click <x> <y>") }
    let p = CGPoint(x: x, y: y)
    guard let d = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left),
          let u = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left) else { die("cannot create event") }
    d.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.05)
    u.post(tap: .cghidEventTap)
    print("clicked\t\(Int(x))\t\(Int(y))")

default:
    die("unknown subcommand \(args[1])")
}
