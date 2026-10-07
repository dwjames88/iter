import Foundation
import IterReleaseKit
import IterUpdater

// iter-release: signing, feed and changelog helpers for the release scripts.
// Private keys are read from stdin only, never argv, and never written anywhere.

struct Failure: Error { let message: String }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("iter-release: \(message)\n".utf8))
    exit(1)
}

func out(_ text: String) {
    FileHandle.standardOutput.write(Data((text.hasSuffix("\n") ? text : text + "\n").utf8))
}

struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]

    init(_ raw: [String]) throws {
        var index = 0
        while index < raw.count {
            let argument = raw[index]
            if argument.hasPrefix("--") {
                guard index + 1 < raw.count else { throw Failure(message: "\(argument) needs a value") }
                options[argument] = raw[index + 1]
                index += 2
            } else {
                positional.append(argument)
                index += 1
            }
        }
    }

    func require(_ name: String) throws -> String {
        guard let value = options[name] else { throw Failure(message: "missing \(name)") }
        return value
    }

    func file() throws -> String {
        guard positional.count == 1 else { throw Failure(message: "expected exactly one file argument") }
        return positional[0]
    }
}

func readPrivateKey() throws -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let key = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { throw Failure(message: "expected the private key on stdin") }
    return key
}

func parseDate(_ string: String) throws -> Date {
    if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
    if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
    throw Failure(message: "invalid ISO 8601 date \"\(string)\"")
}

func readText(_ path: String) throws -> String {
    do { return try String(contentsOfFile: path, encoding: .utf8) } catch { throw Failure(message: "cannot read \(path)") }
}

func run(_ command: String, _ rest: [String]) throws {
    let args = try Arguments(rest)
    switch command {
    case "keygen":
        let pair = UpdateSigning.generateKeyPair()
        out(#"{"privateKey":"\#(pair.privateKey)","publicKey":"\#(pair.publicKey)"}"#)

    case "public-key":
        out(try UpdateSigning.publicKey(forPrivateKey: readPrivateKey()))

    case "sign":
        let file = try args.file()
        out(try UpdateSigning.sign(fileAt: URL(fileURLWithPath: file), privateKey: readPrivateKey()))

    case "verify":
        let file = try args.file()
        do {
            try UpdateVerifier.verifySignature(
                fileAt: URL(fileURLWithPath: file), signature: args.require("--signature"),
                publicKey: args.require("--public-key"))
        } catch let error as Failure {
            throw error
        } catch {
            fail("verification failed: \(String(reflecting: error))")
        }

    case "feed":
        let archive = URL(fileURLWithPath: try args.require("--archive"))
        guard let version = SemanticVersion(try args.require("--version")) else { throw Failure(message: "invalid --version") }
        guard let build = Int(try args.require("--build")) else { throw Failure(message: "--build must be an integer") }
        guard let url = URL(string: try args.require("--url")) else { throw Failure(message: "invalid --url") }
        let notes = try readText(try args.require("--notes-file"))
        let notesURL = try args.options["--notes-url"].map { string -> URL in
            guard let url = URL(string: string) else { throw Failure(message: "invalid --notes-url") }
            return url
        }
        let notarizedText = args.options["--notarized"] ?? "false"
        guard notarizedText == "true" || notarizedText == "false" else { throw Failure(message: "--notarized must be true or false") }
        let published = try args.options["--published-at"].map(parseDate) ?? Date()

        var previous: UpdateFeed?
        if let path = args.options["--previous"], FileManager.default.fileExists(atPath: path) {
            previous = try UpdateFeed.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        }
        let item = try FeedBuilder.item(
            archive: archive, version: version, build: build, channel: args.options["--channel"] ?? "release",
            minimumSystemVersion: args.options["--min-os"] ?? "26.0", url: url, signature: try args.require("--signature"),
            publishedAt: published, notarized: notarizedText == "true", notes: notes, notesURL: notesURL)
        let data = try FeedBuilder.merge(item, into: previous).encoded()
        try data.write(to: URL(fileURLWithPath: try args.require("--out")), options: .atomic)

    case "changelog-release":
        let path = try args.file()
        let updated = try Changelog(readText(path)).releasing(
            version: args.require("--version"), date: args.require("--date"),
            repository: args.options["--repository"] ?? Changelog.defaultRepository)
        try updated.write(toFile: path, atomically: true, encoding: .utf8)

    case "changelog-section":
        let version = try args.require("--version")
        guard let body = Changelog(try readText(try args.file())).section(version: version) else {
            throw Failure(message: "no section for version \(version)")
        }
        out(body)

    default:
        throw Failure(message: "unknown command \"\(command)\". Commands: keygen, public-key, sign, verify, feed, changelog-release, changelog-section")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { fail("usage: iter-release <command> [options]") }
do {
    try run(command, Array(arguments.dropFirst()))
} catch let failure as Failure {
    fail(failure.message)
} catch {
    fail(String(reflecting: error))
}
