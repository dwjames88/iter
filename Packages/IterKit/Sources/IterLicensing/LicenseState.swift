import Foundation

public enum LicenseState: Sendable, Equatable {
    case unlicensed
    case trial(daysLeft: Int)
    case licensed(email: String?, activatedAt: Date)
    /// Trial over, grace period over, tampered record or suspicious clock: validate again to continue.
    case expired
    /// The key was disabled or refunded. Local activation has been cleared.
    case revoked

    /// Days left of a trial that began at `start`, or `.expired` when it is over (or the clock jumped far back).
    public static func trial(
        startedAt start: Date,
        now: Date,
        lengthDays: Int = 14,
        maxClockSkew: TimeInterval = 86_400
    ) -> LicenseState {
        if now < start.addingTimeInterval(-maxClockSkew) { return .expired }
        let end = start.addingTimeInterval(TimeInterval(lengthDays) * 86_400)
        let remaining = end.timeIntervalSince(now)
        guard remaining > 0 else { return .expired }
        return .trial(daysLeft: min(lengthDays, Int((remaining / 86_400).rounded(.up))))
    }
}
