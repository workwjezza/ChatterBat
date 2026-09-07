import XCTest
@testable import ChatterBat

/// Exercises `AccountSettingsViewModel` entirely with in-memory fakes — no
/// real Keychain access and no network calls, per the brief's testing
/// contract.
final class AccountSettingsViewModelTests: XCTestCase {
    @MainActor
    func testSaveAndVerifySucceedsAndStoresKey() async {
        let store = InMemoryCredentialStore()
        let checker = FakeConnectionChecker(service: .venice, outcomeToReturn: .valid(summary: "Connected · $5.00 USD"))
        let viewModel = AccountSettingsViewModel(credentialStore: store, checkers: [.venice: checker])
        viewModel.draftKeys[.venice] = "test-key-123"

        await viewModel.saveAndVerify(.venice)

        XCTAssertEqual(viewModel.state(for: .venice), .connected(summary: "Connected · $5.00 USD"))
        XCTAssertEqual(try store.loadKey(for: .venice), "test-key-123")
        XCTAssertNil(viewModel.draftKeys[.venice], "Draft key should be cleared after a successful save.")
        XCTAssertEqual(checker.receivedKeys, ["test-key-123"])
    }

    @MainActor
    func testSaveAndVerifyWithEmptyKeyDoesNotCallChecker() async {
        let store = InMemoryCredentialStore()
        let checker = FakeConnectionChecker(service: .venice, outcomeToReturn: .valid(summary: "unused"))
        let viewModel = AccountSettingsViewModel(credentialStore: store, checkers: [.venice: checker])
        viewModel.draftKeys[.venice] = "   "

        await viewModel.saveAndVerify(.venice)

        XCTAssertEqual(viewModel.state(for: .venice), .error("Enter an API key before saving."))
        XCTAssertTrue(checker.receivedKeys.isEmpty)
        XCTAssertNil(try store.loadKey(for: .venice))
    }

    @MainActor
    func testInvalidCredentialOutcomeSurfacesAsInvalidState() async {
        let store = InMemoryCredentialStore()
        let checker = FakeConnectionChecker(service: .openRouter, outcomeToReturn: .invalidCredential)
        let viewModel = AccountSettingsViewModel(credentialStore: store, checkers: [.openRouter: checker])
        viewModel.draftKeys[.openRouter] = "revoked-key"

        await viewModel.saveAndVerify(.openRouter)

        XCTAssertEqual(viewModel.state(for: .openRouter), .invalidCredential)
        // The key remains stored — invalid does not silently delete it;
        // the user explicitly disconnects if they want it removed.
        XCTAssertEqual(try store.loadKey(for: .openRouter), "revoked-key")
    }

    @MainActor
    func testTransportFailureSurfacesAsErrorAndKeepsStoredKey() async {
        let store = InMemoryCredentialStore()
        let checker = FakeConnectionChecker(service: .venice, outcomeToReturn: .transportFailure("offline"))
        let viewModel = AccountSettingsViewModel(credentialStore: store, checkers: [.venice: checker])
        viewModel.draftKeys[.venice] = "some-key"

        await viewModel.saveAndVerify(.venice)

        XCTAssertEqual(viewModel.state(for: .venice), .error("Network error: offline"))
        XCTAssertEqual(try store.loadKey(for: .venice), "some-key")
    }

    @MainActor
    func testDisconnectRemovesKeyAndResetsState() async {
        let store = InMemoryCredentialStore()
        let checker = FakeConnectionChecker(service: .venice, outcomeToReturn: .valid(summary: "Connected"))
        let viewModel = AccountSettingsViewModel(credentialStore: store, checkers: [.venice: checker])
        viewModel.draftKeys[.venice] = "some-key"
        await viewModel.saveAndVerify(.venice)

        viewModel.disconnect(.venice)

        XCTAssertEqual(viewModel.state(for: .venice), .notConfigured)
        XCTAssertNil(try store.loadKey(for: .venice))
    }

    @MainActor
    func testVerifyConnectionWithNoStoredKeyReportsNotConfigured() async {
        let store = InMemoryCredentialStore()
        let checker = FakeConnectionChecker(service: .venice, outcomeToReturn: .valid(summary: "unused"))
        let viewModel = AccountSettingsViewModel(credentialStore: store, checkers: [.venice: checker])

        await viewModel.verifyConnection(.venice)

        XCTAssertEqual(viewModel.state(for: .venice), .notConfigured)
        XCTAssertTrue(checker.receivedKeys.isEmpty)
    }

    @MainActor
    func testRefreshStoredKeyPresenceReflectsUnverifiedExistingKey() throws {
        let store = InMemoryCredentialStore()
        try store.saveKey("pre-existing", for: .venice)
        let viewModel = AccountSettingsViewModel(credentialStore: store, checkers: [:])

        viewModel.refreshStoredKeyPresence()

        XCTAssertEqual(viewModel.state(for: .venice), .error("Saved, not yet verified."))
        XCTAssertEqual(viewModel.state(for: .openRouter), .notConfigured)
    }

    @MainActor
    func testTwoServicesAreIndependent() async {
        let store = InMemoryCredentialStore()
        let veniceChecker = FakeConnectionChecker(service: .venice, outcomeToReturn: .valid(summary: "Venice OK"))
        let openRouterChecker = FakeConnectionChecker(service: .openRouter, outcomeToReturn: .invalidCredential)
        let viewModel = AccountSettingsViewModel(
            credentialStore: store,
            checkers: [.venice: veniceChecker, .openRouter: openRouterChecker]
        )
        viewModel.draftKeys[.venice] = "venice-key"
        viewModel.draftKeys[.openRouter] = "openrouter-key"

        await viewModel.saveAndVerify(.venice)
        await viewModel.saveAndVerify(.openRouter)

        XCTAssertEqual(viewModel.state(for: .venice), .connected(summary: "Venice OK"))
        XCTAssertEqual(viewModel.state(for: .openRouter), .invalidCredential)
        XCTAssertEqual(try store.loadKey(for: .venice), "venice-key")
        XCTAssertEqual(try store.loadKey(for: .openRouter), "openrouter-key")
    }
}
