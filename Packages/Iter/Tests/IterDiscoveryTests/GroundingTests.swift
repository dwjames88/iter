import Foundation
import Testing
@testable import IterDiscovery

@Suite("Grounding invariant")
struct GroundingTests {
    static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/IterDiscovery")
    }

    @Test func onlyTheVerificationFileCreatesGroundedCoordinates() throws {
        let files = try FileManager.default.contentsOfDirectory(at: Self.sourcesDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        #expect(files.count > 10)
        var callers: [String] = []
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            if text.contains("GroundedCoordinate(") { callers.append(f.lastPathComponent) }
        }
        #expect(callers == ["GroundedVerification.swift"])
    }

    @Test func theInitialiserIsFileprivateAndTheModelShapesCarryNoNumbers() throws {
        let text = try String(contentsOf: Self.sourcesDirectory.appendingPathComponent("GroundedVerification.swift"), encoding: .utf8)
        #expect(text.contains("fileprivate init(value: Coordinate, source: SourceID, basis: CoordinateBasis)"))
        // Everything the model fills in is strings, integers and arrays of them.
        for name in ["QueryPlanner.swift", "Extraction.swift"] {
            let src = try String(contentsOf: Self.sourcesDirectory.appendingPathComponent(name), encoding: .utf8)
            for dto in ["struct QueryPlanDTO", "struct ExtractionDTO", "struct ExtractedNameDTO"] where src.contains(dto) {
                let body = src.components(separatedBy: dto)[1].prefix(900)
                let header = body.components(separatedBy: "static").first ?? ""
                #expect(!header.contains("Double") && !header.contains("Float") && !header.contains("Coordinate"), "\(dto) must not carry numbers or coordinates")
            }
        }
    }

    @Test func discoveredPlaceCoordinatesAreGrounded() {
        // The type of the field is the invariant: this fails to compile if it is ever a bare Coordinate.
        let keyPath: KeyPath<DiscoveredPlace, GroundedCoordinate> = \.coordinate
        _ = keyPath
    }

    @Test func savedPlaceKeepsTheGroundedCoordinateCitationsAndStatus() async {
        let s = LonePineScenario()
        let result = await s.engine(model: nil).discover(DiscoveryRequest(text: LonePineScenario.query))
        let p = result.places.first { $0.name == "Whitney Portal Overlook" }!
        let place = p.makePlace(timeZoneIdentifier: "America/Los_Angeles", locality: "Lone Pine, CA", discoveredAt: testNow)
        #expect(place.coordinate == p.coordinate.value)
        #expect(place.citations == p.citations && !place.citations.isEmpty)
        #expect(place.verification == .confirmed)
        #expect(place.sources == p.sources)
        #expect(place.discoveredAt == testNow)
        #expect(place.origin == .scout)
    }
}
