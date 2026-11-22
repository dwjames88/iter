import Foundation
import Testing
import IterGoActivity

@Test func idleSnapshotRoundTrips() throws {
    let s = GoSnapshot.idle(at: Date(timeIntervalSince1970: 1_800_000_000))
    let data = try JSONEncoder().encode(s)
    #expect(try JSONDecoder().decode(GoSnapshot.self, from: data) == s)
}
