import Foundation
import MapKit
import Testing
import IterModel
import IterGoActivity
@testable import IterScreens

@Suite("Go map camera and pins")
struct GoMapCameraTests {
    /// An iPhone 17 Pro: 402 x 874, Dynamic Island inset 62, the sheet at half height.
    let phone = GoMapViewport(size: CGSize(width: 402, height: 874), top: 62, bottom: 437)
    let next = Coordinate(latitude: 38.6, longitude: -109.6)

    func offset(_ c: Coordinate, northKm: Double = 0, eastKm: Double = 0) -> Coordinate {
        Coordinate(latitude: c.latitude + northKm / 111.0, longitude: c.longitude + eastKm / (111.0 * cos(c.latitude * .pi / 180)))
    }

    /// Every framed point sits inside the uncovered area, padding included.
    func expectInside(_ points: [Coordinate], _ f: GoMapCamera.Framing, _ vp: GoMapViewport, sourceLocation: SourceLocation = #_sourceLocation) {
        let pad = GoMapCamera.pinPadding - 0.5
        for c in points {
            let p = GoMapCamera.screenPoint(c, rect: f.rect, viewport: vp)
            #expect(p.x >= vp.leading + pad && p.x <= vp.size.width - vp.trailing - pad, "x \(p.x)", sourceLocation: sourceLocation)
            #expect(p.y >= vp.top + pad && p.y <= vp.size.height - vp.bottom - pad, "y \(p.y)", sourceLocation: sourceLocation)
        }
    }

    @Test func framesYouAndTheNextStopAboveTheSheetAndBelowTheIsland() throws {
        let user = offset(next, northKm: -11)
        let f = try #require(GoMapCamera.frame(user: user, next: next, today: [next], viewport: phone))
        expectInside([user, next], f, phone)
        #expect(f.includesUser && f.framedStops == [next])
        // The rect has the view's own shape, so nothing is stretched.
        #expect(abs(f.rect.width / f.rect.height - phone.size.width / phone.size.height) < 1e-9)
    }

    @Test func aLowerSheetFramesTheSamePointsLowerAndNeverUnderIt() throws {
        let user = offset(next, northKm: -11)
        var peek = phone; peek.bottom = 220
        let half = try #require(GoMapCamera.frame(user: user, next: next, today: [next], viewport: phone))
        let low = try #require(GoMapCamera.frame(user: user, next: next, today: [next], viewport: peek))
        expectInside([user, next], low, peek)
        func middle(_ f: GoMapCamera.Framing, _ vp: GoMapViewport) -> Double {
            (GoMapCamera.screenPoint(user, rect: f.rect, viewport: vp).y + GoMapCamera.screenPoint(next, rect: f.rect, viewport: vp).y) / 2
        }
        #expect(middle(low, peek) > middle(half, phone), "with less covered, the pair sits lower on screen")
        #expect(GoMapCamera.screenPoint(user, rect: low.rect, viewport: peek).y < peek.size.height - peek.bottom)
    }

    @Test func todaysRestStopsJoinWhileTheyFitAndTheTripNeverDoes() throws {
        let user = offset(next, northKm: -11)
        let second = offset(next, northKm: 18, eastKm: 6)
        let third = offset(next, northKm: 30, eastKm: -4)
        let f = try #require(GoMapCamera.frame(user: user, next: next, today: [next, second, third], viewport: phone))
        #expect(f.framedStops == [next, second, third])
        expectInside([user, next, second, third], f, phone)
        // A stop on another continent stays off the picture, and the first two stay framed.
        let far = offset(next, northKm: 2_500)
        let g = try #require(GoMapCamera.frame(user: user, next: next, today: [next, second, far], viewport: phone))
        #expect(g.framedStops == [next, second])
        expectInside([user, next, second], g, phone)
        let visibleMeters = g.rect.width / MKMapPointsPerMeterAtLatitude(next.latitude)
        #expect(visibleMeters <= GoMapCamera.legibleVisibleMeters)
    }

    @Test func youAndTheNextStopAreFramedEvenWhenFarApart() throws {
        let user = offset(next, northKm: -600)
        let f = try #require(GoMapCamera.frame(user: user, next: next, today: [next], viewport: phone))
        expectInside([user, next], f, phone)
    }

    @Test func standingAtTheStopDoesNotZoomToADoorstep() throws {
        let f = try #require(GoMapCamera.frame(user: next, next: next, today: [next], viewport: phone))
        let across = f.rect.width / MKMapPointsPerMeterAtLatitude(next.latitude) * (phone.visibleWidth / phone.size.width)
        #expect(across >= GoMapCamera.minimumVisibleMeters - 1)
    }

    @Test func withoutALocationItFramesTheStopsAndWithoutAnythingItSaysNothing() throws {
        let second = offset(next, northKm: 9)
        let f = try #require(GoMapCamera.frame(user: nil, next: next, today: [next, second], viewport: phone))
        #expect(!f.includesUser && f.framedStops == [next, second])
        expectInside([next, second], f, phone)
        let onlyToday = try #require(GoMapCamera.frame(user: nil, next: nil, today: [second], viewport: phone))
        #expect(onlyToday.framedStops == [second])
        #expect(GoMapCamera.frame(user: nil, next: nil, today: [], viewport: phone) == nil)
        #expect(GoMapCamera.frame(user: next, next: next, today: [], viewport: GoMapViewport(size: .zero)) == nil)
    }

    @Test func theSameInputsGiveTheSameRect() throws {
        let user = offset(next, northKm: -5)
        let a = try #require(GoMapCamera.frame(user: user, next: next, today: [next], viewport: phone))
        let b = try #require(GoMapCamera.frame(user: user, next: next, today: [next], viewport: phone))
        #expect(MKMapRectEqualToRect(a.rect, b.rect))
    }

    // MARK: Pins

    func stop(_ n: Int, _ c: Coordinate, day: Int = 0) -> GoStopInfo {
        GoStopInfo(id: UUID(), number: n, name: "S\(n)", kind: .light, dayIndex: day, coordinate: c, timeZoneIdentifier: "UTC")
    }

    @Test func pinsCloserThanAPlateMergeIntoOneBadge() throws {
        // At the camera that frames a 11 km drive, three stops a few hundred metres apart would overlap.
        let user = offset(next, northKm: -11)
        let f = try #require(GoMapCamera.frame(user: user, next: next, today: [next], viewport: phone))
        let a = stop(6, next), b = stop(7, offset(next, northKm: 0.15)), c = stop(8, offset(next, northKm: 0.3, eastKm: 0.1))
        let far = stop(9, offset(next, northKm: 9))
        let groups = GoMapPins.groups(stops: [a, b, c, far], nextID: a.id, mapPointsPerPoint: f.mapPointsPerPoint)
        #expect(groups.count == 2)
        #expect(groups[0].isCluster && groups[0].label == "6–8" && groups[0].containsNext)
        #expect(groups[0].accessibilityLabel == "Stops 6, 7 and 8")
        #expect(!groups[1].isCluster && groups[1].label == "9" && !groups[1].containsNext)
        // No two drawn plates are closer than a plate on screen.
        for (i, g) in groups.enumerated() {
            for h in groups[(i + 1)...] {
                let p = GoMapCamera.screenPoint(g.coordinate, rect: f.rect, viewport: phone)
                let q = GoMapCamera.screenPoint(h.coordinate, rect: f.rect, viewport: phone)
                #expect(hypot(p.x - q.x, p.y - q.y) >= GoMapPins.minimumSeparation)
            }
        }
    }

    @Test func zoomedInTheSameStopsStandApart() throws {
        let a = stop(1, next), b = stop(2, offset(next, northKm: 0.15))
        // 2 m per point: 150 m is 75 points.
        let perMeter = MKMapPointsPerMeterAtLatitude(next.latitude)
        let groups = GoMapPins.groups(stops: [a, b], nextID: a.id, mapPointsPerPoint: 2 * perMeter)
        #expect(groups.count == 2 && groups.allSatisfy { !$0.isCluster })
        let together = GoMapPins.groups(stops: [a, b], nextID: a.id, mapPointsPerPoint: 20 * perMeter)
        #expect(together.count == 1 && together[0].label == "1–2")
    }

    @Test func aChainOfNearStopsIsOneBadgeAndAnUnknownZoomMergesNothing() {
        let perMeter = MKMapPointsPerMeterAtLatitude(next.latitude)
        let chain = (0..<4).map { stop($0 + 1, offset(next, northKm: Double($0) * 0.05)) }
        let g = GoMapPins.groups(stops: chain, nextID: nil, mapPointsPerPoint: 5 * perMeter)
        #expect(g.count == 1 && g[0].stops.count == 4 && g[0].label == "1–4")
        #expect(GoMapPins.groups(stops: chain, nextID: nil, mapPointsPerPoint: 0).count == 4)
    }
}
