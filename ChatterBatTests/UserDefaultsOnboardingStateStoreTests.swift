import XCTest
@testable import ChatterBat

/// Uses an isolated, randomly-named `UserDefaults` suite (never
/// `.standard`), same isolation discipline as the other UserDefaults-
/// backed store tests.
final class UserDefaultsOnboardingStateStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.chatterbat.tests.onboarding.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testDefaultsToNotCompleted() {
        let store = UserDefaultsOnboardingStateStore(defaults: defaults)
        XCTAssertFalse(store.hasCompletedOnboarding())
    }

    func testMarkCompletedPersists() {
        let store = UserDefaultsOnboardingStateStore(defaults: defaults)
        store.markOnboardingCompleted()
        XCTAssertTrue(store.hasCompletedOnboarding())
    }
}
