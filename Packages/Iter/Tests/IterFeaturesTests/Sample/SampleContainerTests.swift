import Foundation
import Testing
import IterModel
import IterSources
import IterStore
import IterConditions
import IterDiscovery
@testable import IterFeatures

@MainActor
@Suite("Sample composition") struct SampleContainerTests {
    let day = LocalDay(year: 2027, month: 3, day: 10)

    @Test func aReportArrivesForASamplePlaceAndSaysSampleData() async throws {
        let c = try AppContainer.test()
        let place = try #require(CuratedSpots.spot(id: "mesa-arch"))
        let report = await c.conditionsService.report(for: place, day: LocalDay(AppContainer.testNow, in: place.timeZone), waitFor: .complete)
        #expect(report.tier == .complete)
        #expect(report.loading.isEmpty)
        #expect(report.forecast.value?.hours.isEmpty == false)
        #expect(report.daylight.windows.contains { $0.assessment.skyScore != nil })
        #expect(report.provenanceLines.contains { $0.line.contains("Sample") })
        #expect(report.observations.value?.first?.value.stationName?.contains("Sample") == true)
        #expect(report.observations.value?.first?.provenance.distanceKm != nil)
        #expect(report.alerts.value?.isEmpty == true)
        // Light pollution and seeing stay honest gaps.
        #expect(report.gaps.contains { $0.reasons.contains(.notProvidedBySource) })
        for line in report.provenanceLines { #expect(!line.line.contains("NOAA")) }
    }

    @Test func differentPlacesAndDaysScoreDifferently() async throws {
        let c = try AppContainer.test()
        var scores = Set<Int>()
        for slug in ["mesa-arch", "tunnel-view", "bixby-bridge", "crater-lake"] {
            let place = try #require(CuratedSpots.spot(id: slug))
            for offset in [0, 1, 2] {
                let r = await c.conditionsService.report(for: place, day: LocalDay(AppContainer.testNow, in: place.timeZone).adding(days: offset), waitFor: .complete)
                for w in r.daylight.windows { if let s = w.assessment.skyScore { scores.insert(s.value) } }
            }
        }
        #expect(scores.count > 3)
    }

    @Test func theSampleFunctionIsDeterministic() {
        let c = Coordinate(latitude: 38.5, longitude: -109.5)
        let t = AppContainer.testNow
        #expect(SampleConditions.hour(at: c, time: t) == SampleConditions.hour(at: c, time: t))
        #expect(SampleConditions.hour(at: c, time: t) != SampleConditions.hour(at: Coordinate(latitude: 47, longitude: -122), time: t))
        let h = SampleConditions.hour(at: c, time: t)
        #expect((h.cloudTotal ?? -1) >= 0 && (h.cloudTotal ?? 2) <= 1)
        #expect(h.presentFields.count == HourlyField.allCases.count)
    }

    @Test func findRunsOverSampleProvidersWithTheBasicSearchLabel() async throws {
        let c = try AppContainer.test()
        let result = await c.discovery.discover(DiscoveryRequest(text: "viewpoints in Yosemite", maxResults: 10))
        #expect(!result.places.isEmpty, "\(result.failure.map(String.init(describing:)) ?? "no failure"): \(result.statuses.map(\.summary))")
        #expect(result.planOrigin.label != nil)   // Basic search, no language model
        #expect(result.places.contains { $0.name == "Tunnel View" })
        let falls = await c.discovery.discover(DiscoveryRequest(text: "waterfalls near Columbia River Gorge", maxResults: 10))
        #expect(falls.places.contains { $0.name.contains("Multnomah") })
        for p in result.places { #expect(p.coordinate.source.rawValue.hasPrefix("iter.sample")) }
        #expect(result.statuses.contains { $0.source == FixedSources.reddit })
    }

    @Test func nearMeSearchUsesTheFixedLocation() async throws {
        let c = try AppContainer.test(location: Coordinate(latitude: 38.5733, longitude: -109.5498))
        let result = await c.discovery.discover(DiscoveryRequest(text: "arches near me", currentLocation: c.location.current, maxResults: 10))
        #expect(!result.places.isEmpty)
        #expect(result.places.contains { $0.name.contains("Arch") })
    }

    @Test func sampleRoutingIsAStraightLineEstimate() async throws {
        let c = try AppContainer.test()
        let a = Coordinate(latitude: 36.9, longitude: -111.45), b = Coordinate(latitude: 37.0, longitude: -110.1)
        let r = try await c.routing.route(from: a, to: b, departing: nil)
        #expect(r.isEstimate)
        #expect(abs(r.meters - a.distance(to: b) * 1.3) < 1)
        #expect(abs(r.seconds - r.meters / (70_000.0 / 3600)) < 1)
        #expect(c.routing.descriptor.name.contains("estimate"))
        let eta = try await c.routing.eta(from: a, to: b, departing: AppContainer.testNow)
        #expect(eta.arrival > eta.departing)
    }

    @Test func onDeviceProvidersAreWired() throws {
        let c = try AppContainer.test()
        let place = Coordinate(latitude: 38.5, longitude: -109.5)
        #expect(try c.gridReference.mgrs(for: place, precision: 3).value.hasPrefix("12S"))
        #expect(try c.magnetic.field(at: place, elevationM: 1200, on: AppContainer.testNow).value.declinationDegrees != 0)
    }

    @Test func theSampleLibraryHasTheDocumentedShape() throws {
        let c = try AppContainer.test(seed: true)
        let canyon = try #require(c.library.trips.values().first { $0.name == SampleLibrary.tripName })
        #expect(canyon.dayCount == 4)
        #expect(canyon.isPinned)
        #expect(canyon.stops.filter { $0.kind == .light }.count == 6)
        #expect(canyon.stops.contains { $0.kind == .lodging && $0.fixedArrival != nil })
        #expect(canyon.stops.contains { $0.kind == .waypoint })
        #expect(canyon.transferTimings[2] == .eveningBefore)
        #expect(canyon.stops.contains { !$0.driveNote.isEmpty })
        #expect(c.library.folders.list(kind: .locations).first?.places?.count == 3)
        #expect(c.library.places.pinned().count == 1)
        #expect(c.library.folders.list(kind: .trips).count == 1)
        // The seed is in the store, not just the context.
        c.library.flush()
        #expect(c.library.lastSaveError == nil)
    }
}
