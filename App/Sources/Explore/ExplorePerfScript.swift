import AppKit
import Foundation
import IterCore
import IterFeatures

/// `-IterPerfScript YES`: a fixed, repeatable workload on Explore for performance measurement. It waits for the
/// listed rows to be scored, then pans and zooms the map, hovers pins and selects pins from the map, marking each
/// step with a signpost (`IterPerf`). `-IterPerfQuit YES` quits when it is done. Development only; nothing in the
/// normal app path calls it.
@MainActor
enum ExplorePerfScript {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "IterPerfScript") }
    static var quitWhenDone: Bool { UserDefaults.standard.bool(forKey: "IterPerfQuit") }

    static func run(_ explore: ExploreModel) async {
        IterPerf.startLagMonitor()
        IterPerf.mark("script.start")
        let start = Date()
        while Date().timeIntervalSince(start) < 30 {
            let shown = explore.sections.filter { $0.kind != .morePlaces || explore.isMorePlacesOpen }.flatMap(\.rows)
            if explore.visibleRegion != nil, !shown.isEmpty, shown.allSatisfy({ $0.score != nil }) { break }
            await pause(0.1)
        }
        IterPerf.report("loaded", resetLag: true)
        await pause(2)

        if let base = explore.visibleRegion {
            let moves: [GeoRegion] = [
                shifted(base, dx: 0.3, dy: 0), shifted(base, dx: 0.3, dy: 0.2), zoomed(base, 0.4),
                zoomed(base, 0.15), zoomed(base, 1.0), zoomed(base, 2.5), base,
            ]
            for (i, region) in moves.enumerated() {
                IterPerf.mark("script.camera", "step=\(i)")
                let state = IterPerf.signposter.beginInterval("script.camera")
                await IterPerf.step("explore.camera \(i)") { explore.perfRequestCamera(region) }
                await pause(1.5)
                IterPerf.signposter.endInterval("script.camera", state)
            }
        }
        IterPerf.report("afterCamera", resetLag: true)

        let ids = explore.rows.filter { r in explore.visibleRegion?.contains(r.spot.coordinate) ?? true }.prefix(10).map(\.id)
        for id in ids {
            explore.hoveredID = id
            await pause(0.15)
        }
        explore.hoveredID = nil
        IterPerf.report("afterHover", resetLag: true)

        for id in ids.prefix(5) {
            IterPerf.mark("script.select", id)
            let state = IterPerf.signposter.beginInterval("script.select")
            await IterPerf.step("explore.select") { explore.select(id, from: .map) }
            await pause(1.5)
            IterPerf.signposter.endInterval("script.select", state)
        }
        explore.select(nil, from: .map)
        await pause(1)
        IterPerf.report("afterSelect", resetLag: true)
        IterPerf.mark("script.end")
        if quitWhenDone { NSApp.terminate(nil) }
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }

    private static func shifted(_ r: GeoRegion, dx: Double, dy: Double) -> GeoRegion {
        GeoRegion(center: Coordinate(latitude: r.center.latitude + r.latitudeDelta * dy,
                                     longitude: r.center.longitude + r.longitudeDelta * dx),
                  latitudeDelta: r.latitudeDelta, longitudeDelta: r.longitudeDelta)
    }

    private static func zoomed(_ r: GeoRegion, _ factor: Double) -> GeoRegion {
        GeoRegion(center: r.center, latitudeDelta: min(r.latitudeDelta * factor, 120), longitudeDelta: min(r.longitudeDelta * factor, 300))
    }
}
