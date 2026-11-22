import Foundation
import Testing
import IterModel
@testable import IterPlan

@Suite struct PathSimplifierTests {
    private func c(_ lat: Double, _ lon: Double) -> Coordinate { Coordinate(latitude: lat, longitude: lon) }

    @Test func aStraightLineCollapsesToItsEndpoints() {
        let line = (0...100).map { c(40 + Double($0) * 0.001, -110 + Double($0) * 0.001) }
        let out = PathSimplifier.simplify(line, tolerance: PathSimplifier.routeTolerance)
        #expect(out == [line.first!, line.last!])
    }

    @Test func endpointsAreAlwaysKept() {
        var rng = SeededRNG(seed: 5)
        let wiggle = (0..<200).map { i in c(40 + Double(i) * 0.0005 + Double.random(in: -0.0004...0.0004, using: &rng), -110 + Double(i) * 0.0005) }
        for tolerance in [0.00001, 0.0001, 0.001, 1.0] {
            let out = PathSimplifier.simplify(wiggle, tolerance: tolerance)
            #expect(out.first == wiggle.first && out.last == wiggle.last)
            #expect(out.count >= 2 && out.count <= wiggle.count)
        }
    }

    @Test func aCornerBeyondTheToleranceStaysAndOneWithinItGoes() {
        let corner = [c(40, -110), c(40.0005, -110), c(40.001, -110.0005), c(40.002, -110.0005)]
        // The bend at the second point is far from the first-to-last chord; with a tight tolerance every point stays.
        #expect(PathSimplifier.simplify(corner, tolerance: 0.00001).count == 4)
        // A big tolerance collapses it.
        #expect(PathSimplifier.simplify(corner, tolerance: 0.1).count == 2)
        // A bump of about 0.0001 degrees: kept under a 0.00005 tolerance, dropped under a 0.0005 one.
        let bump = [c(40, -110), c(40.001, -110.0001), c(40.002, -110)]
        #expect(PathSimplifier.simplify(bump, tolerance: 0.00005).count == 3)
        #expect(PathSimplifier.simplify(bump, tolerance: 0.0005).count == 2)
    }

    @Test func noDroppedPointIsFurtherThanTheTolerance() {
        var rng = SeededRNG(seed: 11)
        let path = (0..<300).map { i in c(40 + sin(Double(i) / 20) * 0.01 + Double.random(in: -0.0002...0.0002, using: &rng), -110 + Double(i) * 0.0003) }
        let tolerance = 0.0005
        let out = PathSimplifier.simplify(path, tolerance: tolerance)
        #expect(out.count < path.count)
        // Every original point is within `tolerance` (in the scaled plane) of the simplified polyline.
        let scale = cos((path.reduce(0) { $0 + $1.latitude } / Double(path.count)) * .pi / 180)
        func distance(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
            let px = p.longitude * scale, py = p.latitude, ax = a.longitude * scale, ay = a.latitude, bx = b.longitude * scale, by = b.latitude
            let dx = bx - ax, dy = by - ay
            let l2 = dx * dx + dy * dy
            let t = l2 == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / l2))
            return hypot(px - (ax + t * dx), py - (ay + t * dy))
        }
        for p in path {
            let nearest = zip(out, out.dropFirst()).map { distance(p, $0, $1) }.min()!
            #expect(nearest <= tolerance + 1e-12)
        }
    }

    @Test func twoPointsOrFewerAreUnchanged() {
        #expect(PathSimplifier.simplify([], tolerance: 1).isEmpty)
        #expect(PathSimplifier.simplify([c(1, 2)], tolerance: 1) == [c(1, 2)])
        #expect(PathSimplifier.simplify([c(1, 2), c(3, 4)], tolerance: 1) == [c(1, 2), c(3, 4)])
        // And a zero or negative tolerance leaves any path alone.
        let path = [c(0, 0), c(1, 0.5), c(2, 0)]
        #expect(PathSimplifier.simplify(path, tolerance: 0) == path)
        #expect(PathSimplifier.simplify(path, tolerance: -1) == path)
    }

    @Test func aClosedLoopKeepsItsShape() {
        let loop = [c(40, -110), c(40.01, -110), c(40.01, -109.99), c(40, -109.99), c(40, -110)]
        let out = PathSimplifier.simplify(loop, tolerance: 0.0001)
        #expect(out.count == 5)
    }
}
