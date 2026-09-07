import XCTest
@testable import ChatterBat

/// The one test file in this suite that touches the *real* macOS Keychain.
/// Per the brief: "Any real Keychain integration test uses isolated test
/// records and cleanup." Each test uses a unique, randomized Keychain
/// "service" namespace (never the app's real
/// `com.chatterbat.app.apikeys`) and deletes everything it wrote in
/// `tearDown`.
final class KeychainCredentialStoreTests: XCTestCase {
    private var sut: KeychainCredentialStore!

    override func setUp() {
        super.setUp()
        // Unique per test run so parallel/repeated runs never collide and
        // never touch the production credential namespace.
        let namespace = "com.chatterbat.tests.apikeys.\(UUID().uuidString)"
        sut = KeychainCredentialStore(keychainService: namespace)
    }

    override func tearDown() {
        for service in AIService.allCases {
            try? sut.deleteKey(for: service)
        }
        sut = nil
        super.tearDown()
    }

    func testSaveThenLoadRoundTrips() throws {
        try sut.saveKey("secret-value-123", for: .venice)

        XCTAssertEqual(try sut.loadKey(for: .venice), "secret-value-123")
    }

    func testLoadWithNoStoredKeyReturnsNil() throws {
        XCTAssertNil(try sut.loadKey(for: .openRouter))
    }

    func testSaveTwiceReplacesRatherThanDuplicating() throws {
        try sut.saveKey("first-value", for: .venice)
        try sut.saveKey("second-value", for: .venice)

        XCTAssertEqual(try sut.loadKey(for: .venice), "second-value")
    }

    func testDeleteRemovesKey() throws {
        try sut.saveKey("to-be-deleted", for: .venice)
        try sut.deleteKey(for: .venice)

        XCTAssertNil(try sut.loadKey(for: .venice))
    }

    func testDeleteWithNoStoredKeyDoesNotThrow() {
        XCTAssertNoThrow(try sut.deleteKey(for: .venice))
    }

    func testSavingEmptyKeyThrows() {
        XCTAssertThrowsError(try sut.saveKey("   ", for: .venice)) { error in
            XCTAssertEqual(error as? CredentialStoreError, .emptyKey)
        }
    }

    func testServicesAreStoredIndependently() throws {
        try sut.saveKey("venice-value", for: .venice)
        try sut.saveKey("openrouter-value", for: .openRouter)

        XCTAssertEqual(try sut.loadKey(for: .venice), "venice-value")
        XCTAssertEqual(try sut.loadKey(for: .openRouter), "openrouter-value")
    }
}
