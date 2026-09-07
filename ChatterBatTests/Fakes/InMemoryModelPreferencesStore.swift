import Foundation
@testable import ChatterBat

/// In-memory `ModelPreferencesStore` double. Never touches UserDefaults.
final class InMemoryModelPreferencesStore: ModelPreferencesStore, @unchecked Sendable {
    private var favorites: Set<ModelIdentity> = []
    private var recents: [ModelIdentity] = []

    func favoriteIdentities() -> Set<ModelIdentity> { favorites }

    func setFavorite(_ identity: ModelIdentity, isFavorite: Bool) {
        if isFavorite { favorites.insert(identity) } else { favorites.remove(identity) }
    }

    func recentIdentities() -> [ModelIdentity] { recents }

    func recordUsed(_ identity: ModelIdentity) {
        recents.removeAll { $0 == identity }
        recents.insert(identity, at: 0)
    }
}
