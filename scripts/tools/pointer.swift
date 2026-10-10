import CoreGraphics
import Foundation

// Posts real pointer events (CGEvent) for scripts/pin-drag-test.sh. Coordinates are CG global display points
// (top-left origin). The cursor is put back where it was afterwards.
//   pointer drag x0 y0 x1 y1 [steps=30] [holdMs=80] [stepMs=16]
//   pointer click x y
let args = Array(CommandLine.arguments.dropFirst())
func number(_ i: Int, _ fallback: Double? = nil) -> Double {
    if i < args.count, let v = Double(args[i]) { return v }
    if let fallback { return fallback }
    FileHandle.standardError.write(Data("usage: pointer drag x0 y0 x1 y1 [steps] [holdMs] [stepMs] | pointer click x y\n".utf8))
    exit(2)
}
guard let mode = args.first else { _ = number(99) ; exit(2) }
let saved = CGEvent(source: nil)!.location
let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left)!.post(tap: .cghidEventTap)
}
switch mode {
case "drag":
    let p0 = CGPoint(x: number(1), y: number(2)), p1 = CGPoint(x: number(3), y: number(4))
    let steps = Int(number(5, 30)), hold = number(6, 80), stepMs = number(7, 16)
    post(.mouseMoved, p0); usleep(150_000)
    post(.leftMouseDown, p0); usleep(useconds_t(hold * 1000))
    for i in 1...steps {
        let f = Double(i) / Double(steps)
        post(.leftMouseDragged, CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f))
        usleep(useconds_t(stepMs * 1000))
    }
    usleep(100_000); post(.leftMouseUp, p1); usleep(100_000)
case "click":
    let p = CGPoint(x: number(1), y: number(2))
    post(.mouseMoved, p); usleep(150_000)
    post(.leftMouseDown, p); usleep(60_000); post(.leftMouseUp, p); usleep(100_000)
default:
    _ = number(99)
}
CGWarpMouseCursorPosition(saved)
