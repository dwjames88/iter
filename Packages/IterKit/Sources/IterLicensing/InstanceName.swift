import Foundation

/// Builds the label shown in the Lemon Squeezy dashboard for an activation: "<model> – <user>".
public enum InstanceName {
    /// - Parameter userChosen: a name the user typed; used instead of the account name when not blank.
    public static func make(userChosen: String? = nil) -> String {
        let chosen = userChosen?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let user = chosen.isEmpty ? accountName() : chosen
        return format(model: hardwareModel(), user: user)
    }

    public static func format(model: String, user: String) -> String {
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        return user.isEmpty ? model : "\(model) \u{2013} \(user)"
    }

    public static func hardwareModel() -> String {
        #if os(macOS)
        var size = 0
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 {
                return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        #endif
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) { String(cString: $0) }
        }
        return machine.isEmpty ? ProcessInfo.processInfo.hostName : machine
    }

    private static func accountName() -> String {
        let full = NSFullUserName()
        return full.isEmpty ? NSUserName() : full
    }
}
