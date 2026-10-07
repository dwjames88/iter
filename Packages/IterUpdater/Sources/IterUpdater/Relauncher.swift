import Foundation

public enum Relauncher {
    /// Starts a detached `/bin/sh` that waits for `pid` to exit, then opens the app. The caller terminates right
    /// after. The pid and path are positional parameters so nothing is interpolated into the script, and the
    /// child is not waited on, so it outlives this process.
    public static func relaunch(appAt appURL: URL, waitingFor pid: Int32 = getpid(), hidden: Bool = false) throws {
        let flags = hidden ? "-g -j " : ""
        let script = "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \(flags)\"$2\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "iter-relaunch", String(pid), appURL.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw UpdateError.installFailed("Cannot relaunch: \(error.localizedDescription)")
        }
    }
}
