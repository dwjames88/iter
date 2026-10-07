// Exports the vector outline of each SF Symbol named in USAGE.json (no window, no app bundle, nothing drawn).
//   swift export-symbols.swift [out.json]      (default: scratch dir below / raw-outlines.json)
//
// Method: NSImage(systemSymbolName:) -> withSymbolConfiguration(pointSize 100, .regular) -> its NSSymbolImageRep
// exposes `outlinePath` (an NSBezierPath of the real glyph outline, y-down, ~2 units per point). We walk the path
// elements and write SVG-style path data in those native units; pdf2svg.py / outline2svg.py then
// normalises. (Drawing the image into a PDF context does NOT work: AppKit rasterises symbols to an image mask.)
import AppKit
import Foundation

let usage = URL(fileURLWithPath: "Design/paper/tools/symbols/USAGE.json")
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : "/tmp/iter-scratch/paper/symbols/raw-outlines.json"
let names = ((try JSONSerialization.jsonObject(with: Data(contentsOf: usage))) as! [String: Any]).keys.sorted()
let pointSize: CGFloat = 100

// outlinePath is the plain concatenation of the symbol's layers, so knock-outs that the real symbol applies are
// lost for two symbols. Rebuild them with CGPath boolean ops (subpath order verified by inspection).
func subpaths(_ p: NSBezierPath) -> [CGPath] {
    var out: [CGPath] = []; var cur = NSBezierPath(); var pts = [NSPoint](repeating: .zero, count: 3)
    for i in 0..<p.elementCount {
        let e = p.element(at: i, associatedPoints: &pts)
        if e == .moveTo, cur.elementCount > 0 { out.append(cur.cgPath); cur = NSBezierPath() }
        switch e {
        case .moveTo: cur.move(to: pts[0])
        case .lineTo: cur.line(to: pts[0])
        case .curveTo, .cubicCurveTo: cur.curve(to: pts[2], controlPoint1: pts[0], controlPoint2: pts[1])
        case .closePath: cur.close()
        default: break
        }
    }
    if cur.elementCount > 0 { out.append(cur.cgPath) }
    return out
}
func fixup(_ name: String, _ p: NSBezierPath) -> NSBezierPath? {
    let s = subpaths(p)
    var r: CGPath?
    switch name {
    case "xmark.circle.fill" where s.count == 3:
        r = s[0].subtracting(s[1].union(s[2]))
    case "square.and.arrow.up", "square.and.arrow.down":
        guard s.count == 5 else { return nil }
        r = s[0].subtracting(s[1]).subtracting(s[2]).union(s[3]).union(s[4])
    case "square.on.square" where s.count == 5:
        r = s[0].subtracting(s[1]).subtracting(s[2]).union(s[3].subtracting(s[4]))
    default: return nil
    }
    return r.map { NSBezierPath(cgPath: $0) }
}

func f(_ v: CGFloat) -> String { String(format: "%.3f", Double(v)) }

var result: [String: Any] = [:]
var failed: [String] = []
for name in names {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil),
          let img = base.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)),
          let rep = img.representations.first,
          rep.responds(to: NSSelectorFromString("outlinePath")),
          let path = rep.value(forKey: "outlinePath") as? NSBezierPath, path.elementCount > 0
    else { failed.append(name); continue }
    var d = ""
    var pts = [NSPoint](repeating: .zero, count: 3)
    var elementPath: NSBezierPath = path
    if let fixed = fixup(name, path) { elementPath = fixed }
    for i in 0..<elementPath.elementCount {
        switch elementPath.element(at: i, associatedPoints: &pts) {
        case .moveTo: d += "M\(f(pts[0].x)) \(f(pts[0].y))"
        case .lineTo: d += "L\(f(pts[0].x)) \(f(pts[0].y))"
        case .curveTo: d += "C\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y)) \(f(pts[2].x)) \(f(pts[2].y))"
        case .closePath: d += "Z"
        case .cubicCurveTo: d += "C\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y)) \(f(pts[2].x)) \(f(pts[2].y))"
        case .quadraticCurveTo: d += "Q\(f(pts[0].x)) \(f(pts[0].y)) \(f(pts[1].x)) \(f(pts[1].y))"
        @unknown default: break
        }
    }
    let b = elementPath.bounds
    result[name] = ["d": d, "bounds": [b.minX, b.minY, b.width, b.height],
                    "evenOdd": elementPath.windingRule == .evenOdd, "imageSize": [img.size.width, img.size.height]] as [String: Any]
}
let data = try JSONSerialization.data(withJSONObject: ["pointSize": pointSize, "symbols": result], options: [.sortedKeys])
try data.write(to: URL(fileURLWithPath: outPath))
print("exported \(result.count) of \(names.count)")
if !failed.isEmpty { print("FAILED: " + failed.joined(separator: " ")) }
