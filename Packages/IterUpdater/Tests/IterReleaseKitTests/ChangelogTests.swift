import Foundation
import Testing
import IterUpdater
@testable import IterReleaseKit

private let sample = """
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Updates.

### Fixed

- A bug.

## [0.1.0] - 2026-09-01

### Added

- First release.

[Unreleased]: https://github.com/dwjames88/iter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/dwjames88/iter/releases/tag/v0.1.0

"""

@Suite("Changelog")
struct ChangelogTests {
    @Test func releaseMovesBodyAndUpdatesLinks() throws {
        let result = try Changelog(sample).releasing(version: "0.2.0", date: "2026-10-06")
        let expected = """
        # Changelog

        All notable changes to this project will be documented in this file.

        ## [Unreleased]

        ## [0.2.0] - 2026-10-06

        ### Added

        - Updates.

        ### Fixed

        - A bug.

        ## [0.1.0] - 2026-09-01

        ### Added

        - First release.

        [Unreleased]: https://github.com/dwjames88/iter/compare/v0.2.0...HEAD
        [0.2.0]: https://github.com/dwjames88/iter/compare/v0.1.0...v0.2.0
        [0.1.0]: https://github.com/dwjames88/iter/releases/tag/v0.1.0

        """
        #expect(result == expected)
    }

    @Test func leadingVVersionIsAccepted() throws {
        let result = try Changelog(sample).releasing(version: "v0.2.0", date: "2026-10-06")
        #expect(result.contains("## [0.2.0] - 2026-10-06"))
    }

    @Test func releasedSectionIsExtractableAfterwards() throws {
        let result = Changelog(try Changelog(sample).releasing(version: "0.2.0", date: "2026-10-06"))
        #expect(result.section(version: "0.2.0") == "### Added\n\n- Updates.\n\n### Fixed\n\n- A bug.")
        #expect(result.section(version: "Unreleased") == "")
    }

    @Test func firstReleaseWithoutPriorVersionsUsesTagLink() throws {
        let text = "# Changelog\n\n## [Unreleased]\n\n- Everything.\n"
        let result = try Changelog(text).releasing(version: "0.1.0", date: "2026-10-06")
        #expect(result == """
        # Changelog

        ## [Unreleased]

        ## [0.1.0] - 2026-10-06

        - Everything.

        [Unreleased]: https://github.com/dwjames88/iter/compare/v0.1.0...HEAD
        [0.1.0]: https://github.com/dwjames88/iter/releases/tag/v0.1.0

        """)
    }

    @Test func emptyUnreleasedIsAnError() {
        let text = "# Changelog\n\n## [Unreleased]\n\n### Added\n\n## [0.1.0] - 2026-09-01\n\n- x\n"
        #expect(throws: ChangelogError.emptyUnreleased) { try Changelog(text).releasing(version: "0.2.0", date: "2026-10-06") }
        let bare = "# Changelog\n\n## [Unreleased]\n"
        #expect(throws: ChangelogError.emptyUnreleased) { try Changelog(bare).releasing(version: "0.2.0", date: "2026-10-06") }
    }

    @Test func otherErrors() {
        #expect(throws: ChangelogError.missingUnreleased) { try Changelog("# Changelog\n").releasing(version: "0.2.0", date: "2026-10-06") }
        #expect(throws: ChangelogError.invalidVersion("abc")) { try Changelog(sample).releasing(version: "abc", date: "2026-10-06") }
        #expect(throws: ChangelogError.invalidDate("6 Oct")) { try Changelog(sample).releasing(version: "0.2.0", date: "6 Oct") }
        #expect(throws: ChangelogError.versionAlreadyReleased("0.1.0")) { try Changelog(sample).releasing(version: "0.1.0", date: "2026-10-06") }
    }

    @Test func sectionExtraction() {
        let changelog = Changelog(sample)
        #expect(changelog.section(version: "0.1.0") == "### Added\n\n- First release.")
        #expect(changelog.section(version: "v0.1.0") == "### Added\n\n- First release.")
        #expect(changelog.section(version: "Unreleased")?.hasPrefix("### Added\n\n- Updates.") == true)
        #expect(changelog.section(version: "9.9.9") == nil)
    }

    @Test func releaseTwiceInARowUsesPreviousVersionInCompareLink() throws {
        var text = try Changelog(sample).releasing(version: "0.2.0", date: "2026-10-06")
        text = text.replacingOccurrences(of: "## [Unreleased]\n", with: "## [Unreleased]\n\n- More.\n")
        let result = try Changelog(text).releasing(version: "0.3.0", date: "2026-10-20")
        #expect(result.contains("[0.3.0]: https://github.com/dwjames88/iter/compare/v0.2.0...v0.3.0"))
        #expect(result.contains("[Unreleased]: https://github.com/dwjames88/iter/compare/v0.3.0...HEAD"))
        #expect(result.contains("[0.2.0]: https://github.com/dwjames88/iter/compare/v0.1.0...v0.2.0"))
        #expect(Changelog(result).section(version: "0.3.0") == "- More.")
    }
}
