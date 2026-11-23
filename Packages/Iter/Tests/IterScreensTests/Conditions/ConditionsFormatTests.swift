import CoreGraphics
import Foundation
import Testing
import IterFeatures
import IterModel
import IterSky
import IterUI
@testable import IterScreens

@Suite struct ConditionsFormatTests {
    @Test func cardinals() {
        #expect(ConditionsFormat.cardinal(0) == "N")
        #expect(ConditionsFormat.cardinal(96) == "E")
        #expect(ConditionsFormat.cardinal(225) == "SW")
        #expect(ConditionsFormat.cardinal(359) == "N")
        #expect(ConditionsFormat.cardinal(-90) == "W")
        #expect(ConditionsFormat.azimuth(96) == "96\u{00B0} E")
        #expect(ConditionsFormat.azimuth(359.7) == "0\u{00B0} N")
    }

    @Test func missingNumbersAreDashesNeverZero() {
        #expect(ConditionsFormat.percent(nil) == "\u{2013}")
        #expect(ConditionsFormat.percent(0.554) == "55%")
        #expect(ConditionsFormat.temperature(nil) == "\u{2013}")
        #expect(ConditionsFormat.wind(nil) == "\u{2013}")
        #expect(ConditionsFormat.visibility(nil) == "\u{2013}")
    }

    @Test func skyPointGeometry() {
        let c = CGPoint(x: 100, y: 100)
        let north = ConditionsFormat.skyPoint(azimuth: 0, altitude: 0, radius: 80, center: c)
        #expect(abs(north.x - 100) < 0.001 && abs(north.y - 20) < 0.001)
        let east = ConditionsFormat.skyPoint(azimuth: 90, altitude: 0, radius: 80, center: c)
        #expect(abs(east.x - 180) < 0.001 && abs(east.y - 100) < 0.001)
        let zenith = ConditionsFormat.skyPoint(azimuth: 123, altitude: 90, radius: 80, center: c)
        #expect(abs(zenith.x - 100) < 0.001 && abs(zenith.y - 100) < 0.001)
        let below = ConditionsFormat.skyPoint(azimuth: 0, altitude: -50, radius: 80, center: c)   // clamped to -12
        #expect(below.y < 20)
        #expect(abs(below.y - (100 - 80 * (102.0 / 90))) < 0.001)
    }

    @Test func angleBetweenWraps() {
        #expect(ConditionsFormat.angleBetween(350, 10) == 20)
        #expect(ConditionsFormat.angleBetween(90, 270) == 180)
    }

    @Test func stateLines() {
        let zone = ConditionsFixtures.zone
        let now = ConditionsFixtures.now
        #expect(ConditionsFormat.stateLine(.complete, placeName: "Mesa Arch", generatedAt: now, offlineNote: nil, zone: zone) == nil)
        #expect(ConditionsFormat.stateLine(.quick, placeName: "Mesa Arch", generatedAt: now, offlineNote: nil, zone: zone)?.text
                == "Quick forecast from MET Norway; NOAA forecast loading")
        let stale = ConditionsFormat.stateLine(.stale(age: 5 * 3600), placeName: "Mesa Arch", generatedAt: now, offlineNote: nil, zone: zone)
        #expect(stale?.text.hasPrefix("Stale, as of ") == true)
        let off = ConditionsFormat.stateLine(.offline(lastGood: now, age: 3600), placeName: "Mesa Arch", generatedAt: now,
                                             offlineNote: "Forecast from 05:00, offline", zone: zone)
        #expect(off?.text == "Forecast from 05:00, offline")
        #expect(ConditionsFormat.stateLine(.outOfCoverage, placeName: "Mesa Arch", generatedAt: nil, offlineNote: nil, zone: zone)?.text
                == "No forecast source covers Mesa Arch")
        #expect(ConditionsFormat.stateLine(.loading, placeName: "x", generatedAt: nil, offlineNote: nil, zone: zone)?.data == .loading)
    }

    @MainActor @Test func terrainSentences() throws {
        let model = ConditionsPreviewData.model(.complete)
        let zone = model.place.timeZone
        let shortened = try #require(model.horizon.shortened.first)
        let line = ConditionsFormat.terrainLine(shortened, zone: zone)
        let minutes = Int((shortened.lostSeconds / 60).rounded())
        #expect(line.hasSuffix("\(minutes) min late") || line.hasSuffix("\(minutes) min early"))
        #expect(line.contains("terrain"))
    }

    @MainActor @Test func gapsAreNamedNeverNumbers() throws {
        let model = ConditionsPreviewData.model(.complete)
        let lines = model.gaps.map(ConditionsFormat.gapLine)
        #expect(lines.contains("Light Pollution: no free source"))
        #expect(lines.contains("Seeing: no free source"))
        #expect(lines.allSatisfy { !$0.contains(where: \.isNumber) })
    }

    @MainActor @Test func comparisonSentence() throws {
        let model = ConditionsPreviewData.model(.complete) { $0.withComparison = true }
        let c = try #require(model.comparison)
        let line = ConditionsFormat.comparisonLine(c)
        #expect(line.hasPrefix("MET Norway shows up to "))
        #expect(line.hasSuffix("Confidence is lowered."))
    }

    @MainActor @Test func headlineAndBestLines() {
        let model = ConditionsPreviewData.model(.complete)
        let zone = model.place.timeZone
        let h = try! #require(model.headline)
        let title = ConditionsFormat.headlineTitle(kind: h.kind, timeline: model.timeline, windows: model.windows, zone: zone)
        #expect(title.hasPrefix(ConditionsText.name(h.kind) + " at "))
        let best = try! #require(model.whenToGo)
        let line = ConditionsFormat.bestLine(best, locale: Locale(identifier: "en_US"))
        #expect(line.hasPrefix("Best: "))
        #expect(line.hasSuffix("\(ConditionsText.name(best.kind)) \(best.score)"))
    }

    @MainActor @Test func observationTitleNamesStationDistanceAndAge() throws {
        let model = ConditionsPreviewData.model(.complete)
        let o = try #require(model.observation)
        let title = ConditionsFormat.observationTitle(o)
        #expect(title.contains("(KCNY)"))
        #expect(title.contains(TimeText.distance(kilometers: 38)))
        #expect(title.hasSuffix("47 min ago"))
    }

    @Test func factorTextCoversEveryFactor() {
        for factor in LightContributor.Factor.allCases {
            let c = LightContributor(factor: factor, effect: .helps, points: 3, value: 0.4)
            let f = ConditionsFormat.factor(c)
            #expect(!f.name.isEmpty && !f.symbol.isEmpty && !f.value.isEmpty)
        }
    }

    @Test func facts() {
        #expect(PlaceFactsText.coordinates(Coordinate(latitude: 38.3884, longitude: -109.868)) == "38.3884\u{00B0} N, 109.8680\u{00B0} W")
        #expect(PlaceFactsText.elevation(nil) == "Unknown")
        #expect(PlaceFactsText.walkIn(nil) == "Unknown")
        #expect(PlaceFactsText.walkIn(12) == "12 min")
    }
}
