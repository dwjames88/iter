import Foundation
import Observation

/// The screens of the first-run guide, in order.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, location, weather, intelligence, done
}

/// Whether the first-run guide is showing, and where it is. Completion persists in UserDefaults as
/// `iter.onboarding.completedVersion`; raise `currentVersion` to show a new guide to people who saw an old one.
/// The app decides when to call `presentIfNeeded()` (never under tests); Help ▸ Welcome to Iter and the weather
/// banner call `present(at:)`, which always works.
@MainActor
@Observable
public final class OnboardingModel {
    public static let completedVersionKey = "iter.onboarding.completedVersion"
    public static let currentVersion = 1

    public var isPresented = false
    public private(set) var step: OnboardingStep = .welcome

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let version: Int

    public init(defaults: UserDefaults = .standard, currentVersion: Int = OnboardingModel.currentVersion) {
        self.defaults = defaults
        self.version = currentVersion
    }

    /// The guide version the person last finished or skipped (0 = never).
    public var completedVersion: Int { defaults.integer(forKey: Self.completedVersionKey) }
    public var isCompleted: Bool { completedVersion >= version }

    /// Shows the guide from the start when this person has not seen this version of it.
    public func presentIfNeeded() {
        guard !isCompleted, !isPresented else { return }
        present(at: .welcome)
    }

    /// Opens the guide at `step`, whether or not it was completed before.
    public func present(at step: OnboardingStep = .welcome) {
        self.step = step
        isPresented = true
    }

    public var isFirst: Bool { step == .welcome }
    public var isLast: Bool { step == .done }
    /// "Step 2 of 5" numbers.
    public var position: (index: Int, count: Int) { (step.rawValue + 1, OnboardingStep.allCases.count) }

    /// The next screen; on the last one it finishes.
    public func next() {
        guard let following = OnboardingStep(rawValue: step.rawValue + 1) else { finish(); return }
        step = following
    }

    public func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Closes the guide and does not show it again on its own.
    public func skip() { complete() }
    public func finish() { complete() }

    /// The sheet went away by some other route (for example a system dismissal): count it as seen.
    public func dismissed() {
        if isPresented { isPresented = false }
        defaults.set(version, forKey: Self.completedVersionKey)
    }

    private func complete() {
        defaults.set(version, forKey: Self.completedVersionKey)
        isPresented = false
    }
}
