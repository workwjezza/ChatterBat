import Foundation

/// Tracks whether the user has already dismissed the first-run
/// onboarding screen.
///
/// A plain non-secret UI flag — stored in `UserDefaults`, never
/// Keychain, consistent with the favorites/recents preferences store.
protocol OnboardingStateStore: Sendable {
    func hasCompletedOnboarding() -> Bool
    func markOnboardingCompleted()
}

final class UserDefaultsOnboardingStateStore: OnboardingStateStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "com.chatterbat.app.hasCompletedOnboarding"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasCompletedOnboarding() -> Bool {
        defaults.bool(forKey: key)
    }

    func markOnboardingCompleted() {
        defaults.set(true, forKey: key)
    }
}
