import Foundation
import Testing
@testable import IterCore

@Suite struct CoordinateParserTests {
    private func expect(_ text: String, _ lat: Double, _ lon: Double, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let c = CoordinateParser.parse(text) else {
            Issue.record("did not parse: \(text)", sourceLocation: sourceLocation); return
        }
        #expect(abs(c.latitude - lat) < 1e-6 && abs(c.longitude - lon) < 1e-6, "\(text) gave \(c)", sourceLocation: sourceLocation)
    }

    @Test func plainPairs() {
        expect("38.5, -109.5", 38.5, -109.5)
        expect("38.5 -109.5", 38.5, -109.5)
        expect("  38.5,-109.5  ", 38.5, -109.5)
        expect("-33.8688, 151.2093", -33.8688, 151.2093)
        expect("38.5; -109.5", 38.5, -109.5)
        expect("+38.5, +109.5", 38.5, 109.5)
        expect("0, 0", 0, 0)
        expect("90, 180", 90, 180)
        expect("-90 -180", -90, -180)
    }

    @Test func degreeSignsAndHemispheres() {
        expect("38.5°, -109.5°", 38.5, -109.5)
        expect("38.5° N, 109.5° W", 38.5, -109.5)
        expect("38.5N 109.5W", 38.5, -109.5)
        expect("38.5 S, 109.5 E", -38.5, 109.5)
        expect("N 38.5 W 109.5", 38.5, -109.5)
        expect("W 109.5, N 38.5", 38.5, -109.5)
        expect("109.5 W 38.5 N", 38.5, -109.5)
        expect("n38.5 w109.5", 38.5, -109.5)
        expect("38.5 N, -109.5", 38.5, -109.5)
    }

    @Test func degreesMinutesSeconds() {
        expect("38°30′00″N 109°30′00″W", 38.5, -109.5)
        expect("38° 30' 0\" N, 109° 30' 0\" W", 38.5, -109.5)
        expect("38°30′N 109°15′W", 38.5, -109.25)
        expect("40°26′46″N 79°58′56″W", 40.446111, -79.982222)
    }

    @Test func appleMapsLinks() {
        expect("https://maps.apple.com/?ll=38.5,-109.5", 38.5, -109.5)
        expect("https://maps.apple.com/?ll=38.5%2C-109.5&q=Mesa%20Arch", 38.5, -109.5)
        expect("https://maps.apple.com/?q=38.5,-109.5", 38.5, -109.5)
        expect("http://maps.apple.com/?sll=38.5,-109.5&z=10", 38.5, -109.5)
        expect("https://maps.apple.com/?address=Moab&ll=38.5,-109.5", 38.5, -109.5)
        expect("https://maps.apple.com/place?coordinate=38.5,-109.5&name=Mesa%20Arch&map=satellite", 38.5, -109.5)
        expect("https://maps.apple.com/place?place-id=I123&coordinate=38.573%2C-109.5494", 38.573, -109.5494)
    }

    @Test func rejectsWhatIsNotACoordinate() {
        for text in ["", "   ", "hello", "38.5", "38.5, ", "91, 0", "0, 181", "-91, 10", "38.5, 109.5, 12", "1 2 3 4",
                     "38.5 N, 109.5 N", "38.5 W, 109.5 E 7", "38°75′N 10°W", "abc 38.5, 109.5",
                     "https://example.com/?ll=38.5,-109.5", "https://maps.apple.com/?q=Moab", "https://maps.apple.com/"] {
            #expect(CoordinateParser.parse(text) == nil, "\(text)")
        }
    }

    @Test func singleFieldValuesAreRangeChecked() {
        #expect(CoordinateParser.parseDegrees("38.5", axis: .latitude) == 38.5)
        #expect(CoordinateParser.parseDegrees("-109.5", axis: .longitude) == -109.5)
        #expect(CoordinateParser.parseDegrees("109.5 W", axis: .longitude) == -109.5)
        #expect(CoordinateParser.parseDegrees("38.5° S", axis: .latitude) == -38.5)
        #expect(CoordinateParser.parseDegrees("91", axis: .latitude) == nil)
        #expect(CoordinateParser.parseDegrees("181", axis: .longitude) == nil)
        #expect(CoordinateParser.parseDegrees("109 W", axis: .latitude) == nil)
        #expect(CoordinateParser.parseDegrees("", axis: .latitude) == nil)
        #expect(CoordinateParser.parseDegrees("north", axis: .latitude) == nil)
        #expect(CoordinateParser.parseDegrees("1, 2", axis: .latitude) == nil)
    }
}
