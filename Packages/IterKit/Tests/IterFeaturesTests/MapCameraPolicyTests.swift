import Foundation
import Testing
import IterCore
@testable import IterFeatures

private func c(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }

@Suite struct MapCameraPolicyTests {
    @Test func fitPadsAndHonoursMinimumSpan() throws {
        let one = try #require(MapCameraPolicy.fit([c(38, -109)]))
        #expect(one.latitudeDelta == MapCameraPolicy.minimumSpan)
        #expect(one.center == c(38, -109))
        let two = try #require(MapCameraPolicy.fit([c(36, -112), c(40, -108)]))
        #expect(abs(two.latitudeDelta - 4 * 1.25) < 1e-9)
        #expect(MapCameraPolicy.fit([]) == nil)
    }

    @Test func wideSetsNeverFitTheWorld() throws {
        // Utah, California and Iceland: the Iceland point is 60+ degrees away.
        let west = [c(38, -109), c(37, -110), c(36, -121), c(37, -122), c(38, -119)]
        let all = west + [c(64, -19)]
        let region = try #require(MapCameraPolicy.fit(all))
        #expect(region.latitudeDelta <= MapCameraPolicy.maxAutomaticSpan)
        #expect(region.longitudeDelta <= MapCameraPolicy.maxAutomaticSpan)
        // The densest cluster is the western US, so Iceland is left out of the frame.
        #expect(!region.contains(c(64, -19)))
        for p in west { #expect(region.contains(p)) }
    }

    @Test func aWorldSetIsCappedAtTheMaximum() throws {
        let spread = (0..<12).map { c(Double($0) * 10 - 50, Double($0) * 30 - 170) }
        let region = try #require(MapCameraPolicy.fit(spread))
        #expect(region.latitudeDelta <= MapCameraPolicy.maxAutomaticSpan)
        #expect(region.longitudeDelta <= MapCameraPolicy.maxAutomaticSpan)
    }

    @Test func settlingAtTheFitIsNotAUserMove() {
        var policy = MapCameraPolicy()
        let fit = GeoRegion(center: c(38, -110), latitudeDelta: 5, longitudeDelta: 6)
        policy.didApplyFit(fit)
        // MapKit widens the other axis to the pane's aspect ratio and nudges the centre a little.
        policy.cameraSettled(GeoRegion(center: c(38.05, -110.02), latitudeDelta: 5.1, longitudeDelta: 9))
        #expect(!policy.userMovedSinceFit)
        #expect(policy.savedRegion != nil)
    }

    @Test func zoomingOrPanningIsAUserMove() {
        let fit = GeoRegion(center: c(38, -110), latitudeDelta: 5, longitudeDelta: 6)
        var zoomedIn = MapCameraPolicy()
        zoomedIn.didApplyFit(fit)
        zoomedIn.cameraSettled(GeoRegion(center: c(38, -110), latitudeDelta: 2, longitudeDelta: 2.4), byUser: true)
        #expect(zoomedIn.userMovedSinceFit)

        var zoomedOut = MapCameraPolicy()
        zoomedOut.didApplyFit(fit)
        zoomedOut.cameraSettled(GeoRegion(center: c(38, -110), latitudeDelta: 20, longitudeDelta: 24), byUser: true)
        #expect(zoomedOut.userMovedSinceFit)

        var panned = MapCameraPolicy()
        panned.didApplyFit(fit)
        panned.cameraSettled(GeoRegion(center: c(41, -105), latitudeDelta: 5, longitudeDelta: 6), byUser: true)
        #expect(panned.userMovedSinceFit)
    }

    @Test func contentChangesRefitOnlyUntilTheUserMoves() throws {
        var policy = MapCameraPolicy()
        let firstFit = policy.regionAfterContentChange([c(38, -109), c(39, -108)])
        let first = try #require(firstFit)
        policy.cameraSettled(first)
        let secondFit = policy.regionAfterContentChange([c(34, -118), c(35, -117)])
        let second = try #require(secondFit)
        #expect(second.center.latitude < first.center.latitude)
        policy.cameraSettled(GeoRegion(center: c(10, 10), latitudeDelta: 3, longitudeDelta: 3), byUser: true)
        #expect(policy.regionAfterContentChange([c(40, -100)]) == nil)
        // A new fit hands control back to the app.
        policy.didApplyFit(second)
        #expect(!policy.userMovedSinceFit)
    }

    @Test func initialRegionPrefersTheSavedCamera() throws {
        var policy = MapCameraPolicy()
        let coordinates = [c(38, -109), c(39, -108)]
        #expect(policy.initialRegion(for: coordinates) == MapCameraPolicy.fit(coordinates))
        let saved = GeoRegion(center: c(30, -100), latitudeDelta: 8, longitudeDelta: 8)
        policy.cameraSettled(saved, byUser: true)
        #expect(policy.initialRegion(for: coordinates) == saved)
    }

    @Test func panMovesTheCentreButNeverTheSpan() {
        let region = GeoRegion(center: c(38, -110), latitudeDelta: 4, longitudeDelta: 6)
        // Already comfortably inside: unchanged.
        #expect(MapCameraPolicy.pan(region, toInclude: c(38.2, -110.3)) == region)
        // Outside to the north-east: centre moves, span stays.
        let moved = MapCameraPolicy.pan(region, toInclude: c(41, -105))
        #expect(moved.latitudeDelta == 4 && moved.longitudeDelta == 6)
        #expect(moved.center.latitude > 38 && moved.center.longitude > -110)
        let inner = GeoRegion(center: moved.center, latitudeDelta: 4 * 0.7, longitudeDelta: 6 * 0.7)
        #expect(inner.contains(c(41, -105)))
        // A larger bottom margin keeps a point out of the lower band (under a card).
        let margins = MapCameraPolicy.Margins(bottom: 0.5)
        let lifted = MapCameraPolicy.pan(region, toInclude: c(37.5, -110), margins: margins)
        // The point must sit in the upper half, so the centre drops to it.
        #expect(abs(lifted.center.latitude - 37.5) < 1e-9)
    }

    @Test func panWhileFitCurrentKeepsTheFit() {
        var policy = MapCameraPolicy()
        policy.didApplyFit(GeoRegion(center: c(38, -110), latitudeDelta: 5, longitudeDelta: 6))
        let panned = GeoRegion(center: c(39, -108), latitudeDelta: 5, longitudeDelta: 6)
        policy.didApplyPan(panned)
        policy.cameraSettled(panned)
        #expect(!policy.userMovedSinceFit)
    }

    @Test func persistsPerScreen() throws {
        let defaults = UserDefaults(suiteName: "MapCameraPolicyTests-\(UUID().uuidString)")!
        var policy = MapCameraPolicy()
        policy.didApplyFit(GeoRegion(center: c(38, -110), latitudeDelta: 5, longitudeDelta: 6))
        policy.cameraSettled(GeoRegion(center: c(40, -100), latitudeDelta: 2, longitudeDelta: 2), byUser: true)
        policy.save(screen: "explore", defaults: defaults)
        let loaded = MapCameraPolicy.load(screen: "explore", defaults: defaults)
        #expect(loaded == policy)
        #expect(loaded.userMovedSinceFit)
        #expect(MapCameraPolicy.load(screen: "trip", defaults: defaults) == MapCameraPolicy())
    }

    @Test func aNonUserSettleAtAWideRegionIsNotSavedNorAUserMoveAndAsksForTheFitAgain() {
        var policy = MapCameraPolicy()
        let fit = GeoRegion(center: c(40, -116), latitudeDelta: 17, longitudeDelta: 18)
        policy.didApplyFit(fit)
        // MapKit settled on its own default camera (the pane had no size yet).
        let world = GeoRegion(center: c(40, -116), latitudeDelta: 121, longitudeDelta: 122)
        let outcome = policy.cameraSettled(world)
        #expect(outcome == .reapply(fit))
        #expect(!policy.userMovedSinceFit)
        #expect(policy.savedRegion == nil)
        #expect(policy.lastFitRegion == fit)
        // The re-applied fit then settles (aspect-adjusted): saved, still not a user move.
        let adjusted = GeoRegion(center: c(40.1, -116), latitudeDelta: 17.2, longitudeDelta: 30)
        #expect(policy.cameraSettled(adjusted) == .saved)
        #expect(!policy.userMovedSinceFit && !policy.programmaticSettlePending)
        #expect(policy.savedRegion == adjusted)
        // A later layout settle at a wide region is ignored: never saved, never a move.
        #expect(policy.cameraSettled(world) != .saved)
        #expect(policy.savedRegion == adjusted && !policy.userMovedSinceFit)
        #expect(policy.regionAfterContentChange([c(38, -109), c(39, -108)]) != nil)
    }

    @Test func reapplyingGivesUpAfterAFewAttempts() {
        var policy = MapCameraPolicy()
        let fit = GeoRegion(center: c(40, -116), latitudeDelta: 17, longitudeDelta: 18)
        policy.didApplyFit(fit)
        let world = GeoRegion(center: c(0, 0), latitudeDelta: 121, longitudeDelta: 122)
        for _ in 0..<MapCameraPolicy.maxReapplyAttempts {
            _ = policy.cameraSettled(world)
        }
        #expect(policy.cameraSettled(world) == .ignored)
        #expect(policy.savedRegion == nil)
    }

    @Test func aUserSettleAfterAFitIsSavedAndMarksMoved() {
        var policy = MapCameraPolicy()
        policy.didApplyFit(GeoRegion(center: c(38, -110), latitudeDelta: 5, longitudeDelta: 6))
        let user = GeoRegion(center: c(38, -110), latitudeDelta: 1, longitudeDelta: 1)
        policy.cameraSettled(user, byUser: true)
        #expect(policy.userMovedSinceFit)
        #expect(policy.savedRegion == user)
        #expect(policy.regionAfterContentChange([c(40, -100)]) == nil)
    }

    @Test func aStoredVersionTwoCameraIsIgnored() throws {
        let defaults = UserDefaults(suiteName: "MapCameraPolicyTests-\(UUID().uuidString)")!
        let v2 = #"{"version":2,"savedRegion":{"latitudeDelta":122.65,"longitudeDelta":100,"center":{"longitude":-116.7,"latitude":40}},"lastFitRegion":{"latitudeDelta":2.33,"longitudeDelta":3,"center":{"longitude":-116.7,"latitude":40}},"userMovedSinceFit":true}"#
        defaults.set(Data(v2.utf8), forKey: MapCameraPolicy.storageKey("trip"))
        #expect(MapCameraPolicy.load(screen: "trip", defaults: defaults) == MapCameraPolicy())
    }

    @Test func aWideSavedCameraIsOnlyRestoredWhenTheUserChoseIt() throws {
        let defaults = UserDefaults(suiteName: "MapCameraPolicyTests-\(UUID().uuidString)")!
        let wide = GeoRegion(center: c(40, -100), latitudeDelta: 90, longitudeDelta: 100)
        var chosen = MapCameraPolicy()
        chosen.didApplyFit(GeoRegion(center: c(38, -110), latitudeDelta: 5, longitudeDelta: 6))
        chosen.cameraSettled(wide, byUser: true)
        chosen.save(screen: "a", defaults: defaults)
        #expect(MapCameraPolicy.load(screen: "a", defaults: defaults).savedRegion == wide)
        // Same data without the user flag (hand-edited or written by a bug): ignored.
        let json = String(data: try JSONEncoder().encode(chosen), encoding: .utf8)!
            .replacingOccurrences(of: "\"savedByUser\":true", with: "\"savedByUser\":false")
        defaults.set(Data(json.utf8), forKey: MapCameraPolicy.storageKey("b"))
        #expect(MapCameraPolicy.load(screen: "b", defaults: defaults).savedRegion == nil)
    }

    @Test func storedStateFromAnOlderVersionIsIgnored() throws {
        let defaults = UserDefaults(suiteName: "MapCameraPolicyTests-\(UUID().uuidString)")!
        let old = #"{"savedRegion":{"latitudeDelta":121.2,"longitudeDelta":122.2,"center":{"longitude":-116.73,"latitude":40.06}},"lastFitRegion":{"latitudeDelta":16.77,"longitudeDelta":18.08,"center":{"longitude":-116.73,"latitude":40.06}},"userMovedSinceFit":true}"#
        defaults.set(Data(old.utf8), forKey: MapCameraPolicy.storageKey("explore"))
        #expect(MapCameraPolicy.load(screen: "explore", defaults: defaults) == MapCameraPolicy())
        let stale = old.replacingOccurrences(of: "{\"savedRegion", with: "{\"version\":1,\"savedRegion")
        defaults.set(Data(stale.utf8), forKey: MapCameraPolicy.storageKey("explore"))
        #expect(MapCameraPolicy.load(screen: "explore", defaults: defaults).savedRegion == nil)
    }
}
