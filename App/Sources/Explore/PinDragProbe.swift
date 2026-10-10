import AppKit
import MapKit
import SwiftUI
import IterCore

/// Test aid behind `-IterPinDragProbe <file>` (see `AppLaunch.pinDragProbeFile`): reports where a pin is, in the
/// coordinates a pointer-event driver needs, and what each drop stored. It only ever writes the one file it was given.
@MainActor
final class PinDragProbe {
    static let shared = PinDragProbe()
    private var report: [String: Any] = [:]
    private var moves: [[String: Any]] = []
    private var path: String? { AppLaunch.pinDragProbeFile }
    private(set) var lastID: String?
    var isOn: Bool { path != nil }

    /// The window's frame in CG global display coordinates: top-left origin, so the window's top is the main screen's
    /// height less its top edge in AppKit's bottom-left space.
    private func windowFrame() -> [String: Double]? {
        guard let window = NSApp.windows.filter({ $0.isVisible && $0.frame.width > 400 }).max(by: { $0.frame.width < $1.frame.width }),
              let screen = NSScreen.screens.first else { return nil }
        let f = window.frame
        return ["x": f.minX, "y": screen.frame.height - f.maxY, "w": f.width, "h": f.height]
    }

    private func point(_ p: CGPoint) -> [String: Double] { ["x": p.x, "y": p.y] }

    /// Camera at each settle; the first one is `initialCamera`, so a pan shows as drift.
    func cameraSettled(_ camera: MapCamera) {
        guard isOn else { return }
        let c = ["lat": camera.centerCoordinate.latitude, "lon": camera.centerCoordinate.longitude,
                 "pitch": camera.pitch, "distance": camera.distance, "heading": camera.heading]
        if report["initialCamera"] == nil { report["initialCamera"] = c }
        report["camera"] = c
        report["settles"] = ((report["settles"] as? Int) ?? 0) + 1
        write()
    }

    /// The spot to grab: its stored coordinate, the tip's window point (CG global, via `proxy.convert(_, to: .global)`
    /// plus the window's origin when the map's global space is the window's), and a point on the capsule above the tip.
    func spotShown(id: String, coordinate: Coordinate, style: String, proxy: MapProxy) {
        lastID = id
        guard isOn, let frame = windowFrame(), let tip = proxy.convert(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude), to: .global) else { return }
        let twoPt = proxy.convert(CGPoint(x: tip.x + 2, y: tip.y), from: .global)
        let metres2pt = twoPt.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude).distance(to: coordinate) } ?? 0
        report["window"] = frame
        report["spot"] = ["id": id, "lat": coordinate.latitude, "lon": coordinate.longitude,
                          "tipWindow": point(tip),
                          "tipGlobal": point(CGPoint(x: frame["x"]! + tip.x, y: frame["y"]! + tip.y)),
                          "grabGlobal": point(CGPoint(x: frame["x"]! + tip.x, y: frame["y"]! + tip.y - (style == "dot" ? 0 : 14))),
                          "style": style, "metresPer2pt": metres2pt] as [String: Any]
        report["moves"] = moves
        write()
    }

    /// A committed drop. `expected` is the coordinate `proxy.convert` gives for the drop point (tip + drag delta) at drop time.
    func moveCommitted(stored: Coordinate, expected: Coordinate?, delta: CGSize, tipBefore: CGPoint?, proxy: MapProxy) {
        guard isOn else { return }
        var move: [String: Any] = ["lat": stored.latitude, "lon": stored.longitude, "deltaX": delta.width, "deltaY": delta.height]
        if let expected {
            move["expectedLat"] = expected.latitude
            move["expectedLon"] = expected.longitude
            move["errorMetres"] = stored.distance(to: expected)
        }
        if let tipBefore { move["tipBeforeWindow"] = point(tipBefore) }
        moves.append(move)
        report["moves"] = moves
        write()
    }

    /// The tip's window point once the drop has settled, so a driver can tell a moved pin from a panned map.
    func tipAfterDrop(stored: Coordinate, proxy: MapProxy) {
        guard isOn, !moves.isEmpty, let tip = proxy.convert(CLLocationCoordinate2D(latitude: stored.latitude, longitude: stored.longitude), to: .global) else { return }
        moves[moves.count - 1]["tipAfterWindow"] = point(tip)
        report["moves"] = moves
        write()
    }

    func note(_ key: String, _ value: Any) { guard isOn else { return }; report[key] = value; write() }

    private func write() {
        guard let path, JSONSerialization.isValidJSONObject(report),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
