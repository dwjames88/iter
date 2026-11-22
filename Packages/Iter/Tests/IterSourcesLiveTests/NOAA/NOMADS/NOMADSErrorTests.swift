import Foundation
import Testing
import IterSources
import IterSourcesLive

/// The recorded NOMADS error pages, run through the same excerpt rule SourceHTTP uses (first 300 characters).
@Suite struct NOMADSErrorTests {
    private func excerpt(_ name: String) throws -> String {
        String(decoding: try Fixtures.data("NOMADS/\(name).html").prefix(300), as: UTF8.self)
    }

    @Test(arguments: ["hrrr-cycle-running", "hrrr-f48-on-13z", "gfs-12z-f384-early"])
    func a404DataFileIsNotPresentIsNotPublished(_ name: String) throws {
        let e = SourceError.http(status: 404, excerpt: try excerpt(name))
        #expect(NOMADSErrors.classify(e, what: "x") == .notPublished("x"))
    }

    @Test(arguments: ["hrrr-not-posted", "gfs-not-posted", "hrrr-dir-missing"])
    func a403RequestForFutureDataIsNotPublished(_ name: String) throws {
        let e = SourceError.http(status: 403, excerpt: try excerpt(name))
        #expect(NOMADSErrors.classify(e, what: "x") == .notPublished("x"))
    }

    @Test func otherHttpErrorsStayHttp() {
        let forbidden = SourceError.http(status: 403, excerpt: "<html>Access Denied</html>")
        #expect(NOMADSErrors.classify(forbidden, what: "x") == forbidden)
        let plain404 = SourceError.http(status: 404, excerpt: "no such page")
        #expect(NOMADSErrors.classify(plain404, what: "x") == plain404)
        let server = SourceError.http(status: 503, excerpt: "Data file is not present")
        #expect(NOMADSErrors.classify(server, what: "x") == server)
        let noBody = SourceError.http(status: 404, excerpt: nil)
        #expect(NOMADSErrors.classify(noBody, what: "x") == noBody)
        #expect(NOMADSErrors.classify(.offline, what: "x") == .offline)
    }

    @Test func aBodyThatIsNotGRIBIsADecodingError() throws {
        func isDecoding(_ body: Data) -> Bool {
            do { try NOMADSErrors.checkGRIB(body, what: "f"); return false } catch { if case .decoding = error { return true } else { return false } }
        }
        #expect(isDecoding(Data("<html>oops</html>".utf8)))
        #expect(isDecoding(Data()))
        #expect(isDecoding(Data("GRI".utf8)))
        try NOMADSErrors.checkGRIB(try GRIB2Fixtures.data("gfs-W-20261122t06z-f003"), what: "f")
    }
}
