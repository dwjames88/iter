import Foundation

/// Network access for the feed and the archive. `URLSession` follows redirects itself, which matters because
/// GitHub's `releases/latest/download/...` redirects twice.
enum Downloader {
    private static let chunkSize = 32 * 1024

    static func fetchFeed(from url: URL, session: URLSession) async throws -> UpdateFeed {
        // A stale cached feed would hide a release, so always go to the network.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw map(error)
        }
        try checkStatus(response, url: url, what: "Feed")
        return try UpdateFeed.decode(data)
    }

    /// Streams `url` into `destination`, reporting 0...1, or -1 when the server did not say how long it is.
    static func download(
        _ url: URL, to destination: URL, session: URLSession, progress: @Sendable (Double) -> Void
    ) async throws {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let fm = FileManager.default
        do {
            let (bytes, response) = try await session.bytes(for: request)
            try checkStatus(response, url: url, what: "Download")
            let total = response.expectedContentLength
            progress(total > 0 ? 0 : -1)

            guard fm.createFile(atPath: destination.path, contents: nil) else {
                throw UpdateError.installFailed("Cannot create \(destination.path)")
            }
            let handle = try FileHandle(forWritingTo: destination)
            defer { try? handle.close() }

            var buffer = [UInt8]()
            buffer.reserveCapacity(chunkSize)
            var received: Int64 = 0
            var lastReported = 0.0
            for try await byte in bytes {
                buffer.append(byte)
                guard buffer.count >= chunkSize else { continue }
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 {
                    let fraction = min(Double(received) / Double(total), 1)
                    if fraction - lastReported >= 0.01 {
                        lastReported = fraction
                        progress(fraction)
                    }
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            progress(1)
        } catch {
            try? fm.removeItem(at: destination)
            throw map(error)
        }
    }

    private static func checkStatus(_ response: URLResponse, url: URL, what: String) throws {
        if let http = response as? HTTPURLResponse {
            guard http.statusCode == 200 else { throw UpdateError.feedUnavailable("\(what) returned HTTP \(http.statusCode)") }
        } else if !url.isFileURL {
            throw UpdateError.feedUnavailable("\(what) returned a non-HTTP response")
        }
    }

    private static func map(_ error: any Error) -> UpdateError {
        if let error = error as? UpdateError { return error }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        return .feedUnavailable(error.localizedDescription)
    }
}
