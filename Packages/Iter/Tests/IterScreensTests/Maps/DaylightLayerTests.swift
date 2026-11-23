import Foundation
import Testing
import IterModel
@testable import IterScreens

@Suite("Daylight layer geometry")
struct DaylightLayerTests {
    private let equinox = Date(timeIntervalSince1970: 1_774_008_000)       // 2026-03-20 12:00 UTC
    private let juneSolstice = Date(timeIntervalSince1970: 1_782_043_200)  // 2026-06-21 12:00 UTC
    private let decemberSolstice = Date(timeIntervalSince1970: 1_797_854_400)

    @Test func subsolarLatitudeIsTheSeason() {
        #expect(abs(DaylightGeometry(date: equinox).subsolar.latitude) < 0.5)
        #expect(DaylightGeometry(date: juneSolstice).subsolar.latitude > 23)
        #expect(DaylightGeometry(date: decemberSolstice).subsolar.latitude < -23)
    }

    @Test func terminatorLatitudeFollowsTheSeasons() {
        // At the June solstice the night reaches the south pole: the line stays north of -66.5 only on the day side; at the
        // sub-solar meridian's far side the line dips to about -(90 - 23.4) latitude.
        let june = DaylightGeometry(date: juneSolstice)
        let lats = june.terminator.flatMap { $0 }.map(\.latitude)
        #expect(lats.max()! > 60 && lats.min()! < -60)
        // At the equinox the line is a meridian pair: it runs pole to pole.
        let eq = DaylightGeometry(date: equinox).terminator.flatMap { $0 }.map(\.latitude)
        #expect(eq.max()! > 85 && eq.min()! < -85)
    }

    @Test func ringsCloseAndStayInRange() {
        for date in [equinox, juneSolstice, decemberSolstice, equinox.addingTimeInterval(5 * 3600), equinox.addingTimeInterval(12 * 3600)] {
            let g = DaylightGeometry(date: date)
            #expect(!g.night.isEmpty && g.night.count <= 2)
            for ring in g.night {
                #expect(ring.count >= 3)
                for c in ring { #expect(abs(c.longitude) <= 180 && abs(c.latitude) <= 89.5 + 1e-9) }
            }
        }
    }

    @Test func nightAcrossTheAntimeridianIsTwoRingsNeverAStripe() {
        // Noon at 0 degrees: midnight sits on the antimeridian, so the night is cut into a west and an east piece.
        let g = DaylightGeometry(date: equinox)
        #expect(g.night.count == 2)
        let west = g.night.contains { $0.contains { $0.longitude == -180 } }
        let east = g.night.contains { $0.contains { $0.longitude == 180 } }
        #expect(west && east)
        for ring in g.night { for (i, c) in ring.enumerated() {
            let next = ring[(i + 1) % ring.count]
            #expect(abs(next.longitude - c.longitude) < 30 || (abs(c.latitude) > 86 && abs(next.latitude) > 86) || c.longitude == next.longitude)
        } }
    }

    @Test func terminatorDropsTheClosingEdges() {
        let g = DaylightGeometry(date: equinox.addingTimeInterval(6 * 3600))
        for line in g.terminator {
            for (a, b) in zip(line, line.dropFirst()) {
                #expect(!(abs(a.latitude) >= 89.49 && abs(b.latitude) >= 89.49))
                #expect(!(abs(a.longitude) == 180 && a.longitude == b.longitude))
            }
        }
        #expect(!g.terminator.isEmpty)
    }

    @Test func showsOnlyWhenZoomedOut() {
        #expect(!DaylightGeometry.isVisible(latitudeSpan: 1))
        #expect(!DaylightGeometry.isVisible(latitudeSpan: 19.9))
        #expect(DaylightGeometry.isVisible(latitudeSpan: 20))
        #expect(DaylightGeometry.isVisible(latitudeSpan: 120))
    }

    @MainActor @Test func contentBuilds() { _ = DaylightTerminator(date: equinox) }
}
