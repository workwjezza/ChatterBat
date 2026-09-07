import XCTest
@testable import ChatterBat

/// Uses a private, isolated `UserDefaults` suite (never `.standard`) so
/// this never touches real app preferences and cleans up fully in
/// `tearDown` — the same isolation discipline as the real-Keychain test.
final class UserDefaultsModelPreferencesStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: UserDefaultsModelPreferencesStore!

    override func setUp() {
        super.setUp()
        suiteName = "com.chatterbat.tests.preferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = UserDefaultsModelPreferencesStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        super.tearDown()
    }

    func testFavoriteRoundTrips() {
        let identity = ModelIdentity(service: .venice, modelID: "llama-3.2-3b")

        sut.setFavorite(identity, isFavorite: true)

        XCTAssertTrue(sut.favoriteIdentities().contains(identity))
    }

    func testUnfavoriteRemovesIt() {
        let identity = ModelIdentity(service: .venice, modelID: "llama-3.2-3b")
        sut.setFavorite(identity, isFavorite: true)

        sut.setFavorite(identity, isFavorite: false)

        XCTAssertFalse(sut.favoriteIdentities().contains(identity))
    }

    func testRecordUsedMovesExistingEntryToFront() {
        let a = ModelIdentity(service: .venice, modelID: "a")
        let b = ModelIdentity(service: .venice, modelID: "b")
        sut.recordUsed(a)
        sut.recordUsed(b)

        sut.recordUsed(a)

        XCTAssertEqual(sut.recentIdentities(), [a, b])
    }

    func testRecentsAreCappedAtTen() {
        for index in 0..<15 {
            sut.recordUsed(ModelIdentity(service: .venice, modelID: "model-\(index)"))
        }

        XCTAssertEqual(sut.recentIdentities().count, 10)
        XCTAssertEqual(sut.recentIdentities().first, ModelIdentity(service: .venice, modelID: "model-14"))
    }

    func testServiceIsPartOfIdentityRoundTrip() {
        let venice = ModelIdentity(service: .venice, modelID: "same-name")
        let openRouter = ModelIdentity(service: .openRouter, modelID: "same-name")
        sut.setFavorite(venice, isFavorite: true)

        XCTAssertTrue(sut.favoriteIdentities().contains(venice))
        XCTAssertFalse(sut.favoriteIdentities().contains(openRouter))
    }
}
