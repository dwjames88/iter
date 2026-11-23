import Foundation
import OSLog
import IterSources

extension KeyVault {
    /// Carries the old app's Keychain keys over once at launch (BLUEPRINT §5.3 step 7). Called for the real process only.
    /// `migrateLegacyItems` is idempotent (a marker makes later launches a no-op), never overwrites a new item and never
    /// touches an old one, and a handful of Keychain reads is quick, so it runs inline. Logs source names and outcomes only,
    /// never a value. Returns the report for tests.
    @discardableResult
    func carryOverLegacyKeys(log: Logger = Logger(subsystem: "com.dwjames.iter", category: "keys")) -> KeyVaultMigrationReport {
        let report = migrateLegacyItems()
        if report.alreadyMigrated { return report }
        let summary = report.entries.map { "\($0.source.rawValue): \(Self.describe($0.outcome))" }.joined(separator: ", ")
        log.info("Legacy key carry-over: \(summary, privacy: .public)")
        return report
    }

    private static func describe(_ outcome: KeyVaultMigrationReport.Outcome) -> String {
        switch outcome {
        case .copied: "copied"
        case .skippedAlreadyPresent: "already present"
        case .absent: "absent"
        case .failed: "failed"
        }
    }
}
