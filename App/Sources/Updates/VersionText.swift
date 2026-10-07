import Foundation

/// The version string shown in Settings ▸ About, Settings ▸ Updates and the About panel, in one place.
/// "Version 0.1.0 (412)"; a build number of 0 (built outside the scripts) reads "(dev)"; Debug builds append the
/// short git commit when the build has one.
enum VersionText {
    static func build(_ raw: String) -> String { raw == "0" || raw.isEmpty ? "dev" : raw }

    /// "0.1.0 (412)".
    static func plain(short: String, build raw: String) -> String {
        let build = build(raw)
        return String(localized: "\(short) (\(build))", comment: "App version and build number, e.g. 0.1.0 (412); the build reads dev when built outside the scripts")
    }

    /// "Version 0.1.0 (412)" and, in Debug with a commit, " · abc1234".
    static func full(short: String, build raw: String, commit: String, includesCommit: Bool) -> String {
        let build = build(raw)
        var text = String(localized: "Version \(short) (\(build))", comment: "About: version and build, e.g. Version 0.1.0 (412)")
        if includesCommit, !commit.isEmpty { text += " · " + commit }
        return text
    }

    private static var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    static var short: String { info["CFBundleShortVersionString"] as? String ?? "0" }
    static var buildNumber: String { info["CFBundleVersion"] as? String ?? "0" }
    static var commit: String { (info["IterGitCommit"] as? String) ?? "" }

    static var includesCommit: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// "Version 0.1.0 (412)" for this app.
    static var current: String { full(short: short, build: buildNumber, commit: commit, includesCommit: includesCommit) }
    /// "0.1.0 (412)" for this app.
    static var currentPlain: String { plain(short: short, build: buildNumber) }
    /// The build field of the About panel (it shows "Version <short> (<this>)").
    static var aboutPanelBuild: String {
        let build = build(buildNumber)
        return includesCommit && !commit.isEmpty ? build + " · " + commit : build
    }
}
