import Testing
import Foundation
import CoreGraphics
import IterCore
import IterData
@testable import IterServices

/// Live Look Around and satellite checks against MapKit. Run with `ITER_LIVE=1 swift test --filter SpotImageryLive`.
private let live = ProcessInfo.processInfo.environment["ITER_LIVE"] == "1"

@Suite(.enabled(if: live, "set ITER_LIVE=1")) struct SpotImageryLiveTests {
    @Test func curatedSpotsAndSnapshots() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-imagery-live-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let imagery = MapKitSpotImagery(directory: dir)
        let spots = CuratedSpots.all

        var yes: [String] = [], no: [String] = []
        for spot in spots {
            if await imagery.hasLookAround(spotID: spot.id, coordinate: spot.coordinate) { yes.append(spot.id) } else { no.append(spot.id) }
        }
        print("LOOKAROUND_SUMMARY lookAround=\(yes.count) satelliteOnly=\(no.count) of \(spots.count)")
        for spot in spots { print("LOOKAROUND \(spot.id) \(yes.contains(spot.id) ? "yes" : "no")") }

        let target = spots.first { yes.contains($0.id) } ?? spots[0]
        let request = SpotImageRequest(spotID: target.id, coordinate: target.coordinate, pointSize: CGSize(width: 320, height: 200), scale: 2)
        let images = await imagery.images(for: request)
        print("SPOTIMAGERY \(target.id) -> \(images.map { "\($0.source.rawValue) \($0.image.width)x\($0.image.height)" })")

        let satellite = try #require(images.first { $0.source == .satellite })
        #expect(satellite.image.width == 640 && satellite.image.height == 400)
        if !yes.isEmpty {
            let lookAround = try #require(images.first { $0.source == .lookAround })
            #expect(lookAround.image.width == 640 && lookAround.image.height == 400)
        }
        #expect(imagery.cachedImages(for: request)?.count == images.count)
        // Writes a copy to the scratch dir for eyeballing.
        if let out = ProcessInfo.processInfo.environment["ITER_IMAGERY_OUT"] {
            try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            for f in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where f.pathExtension == "png" {
                try FileManager.default.copyItem(at: f, to: URL(fileURLWithPath: out).appendingPathComponent(f.lastPathComponent))
            }
        }
    }
}
