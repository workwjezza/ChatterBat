import Foundation

/// Persists favorite and recently-used model identities.
///
/// Favorites/recents are explicitly "non-secret settings" per the brief
/// (unlike API keys, which must never go in UserDefaults) and must be
/// preserved independently of catalog refreshes — a favorite is
/// remembered by `ModelIdentity` even if that model is temporarily absent
/// from a freshly fetched catalog (see `.notConfigured`/`.failed` states
/// in `CatalogLoadState`, and `ModelPickerViewModel`'s handling of
/// unavailable favorites).
///
/// Real durable persistence moves to SwiftData in Stage 4; this
/// UserDefaults-backed store is intentionally simple for Stage 2 and
/// holds no secrets, so that migration carries no security concern.
protocol ModelPreferencesStore: Sendable {
    func favoriteIdentities() -> Set<ModelIdentity>
    func setFavorite(_ identity: ModelIdentity, isFavorite: Bool)

    /// Most-recently-used identities, most recent first, capped at a
    /// small fixed size by the implementation.
    func recentIdentities() -> [ModelIdentity]
    func recordUsed(_ identity: ModelIdentity)
}

/// `ModelPreferencesStore` backed by `UserDefaults`.
///
/// Stores identities as `"service:modelID"` strings, mirroring
/// `ModelInfo.id`, under two fixed keys scoped to this app.
///
/// `@unchecked Sendable`: `UserDefaults` is documented by Apple as
/// thread-safe for concurrent reads/writes, but the type itself predates
/// Swift's `Sendable` conformance annotations, so the compiler can't
/// verify this automatically. The class holds no other mutable state.
final class UserDefaultsModelPreferencesStore: ModelPreferencesStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let favoritesKey = "com.chatterbat.app.favoriteModelIdentities"
    private let recentsKey = "com.chatterbat.app.recentModelIdentities"
    private let maxRecents = 10

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func favoriteIdentities() -> Set<ModelIdentity> {
        let raw = defaults.stringArray(forKey: favoritesKey) ?? []
        return Set(raw.compactMap(Self.decode))
    }

    func setFavorite(_ identity: ModelIdentity, isFavorite: Bool) {
        var current = favoriteIdentities()
        if isFavorite {
            current.insert(identity)
        } else {
            current.remove(identity)
        }
        defaults.set(current.map(Self.encode), forKey: favoritesKey)
    }

    func recentIdentities() -> [ModelIdentity] {
        let raw = defaults.stringArray(forKey: recentsKey) ?? []
        return raw.compactMap(Self.decode)
    }

    func recordUsed(_ identity: ModelIdentity) {
        var current = recentIdentities()
        current.removeAll { $0 == identity }
        current.insert(identity, at: 0)
        if current.count > maxRecents {
            current = Array(current.prefix(maxRecents))
        }
        defaults.set(current.map(Self.encode), forKey: recentsKey)
    }

    private static func encode(_ identity: ModelIdentity) -> String {
        "\(identity.service.rawValue):\(identity.modelID)"
    }

    private static func decode(_ raw: String) -> ModelIdentity? {
        guard let separatorIndex = raw.firstIndex(of: ":") else { return nil }
        let serviceRaw = String(raw[raw.startIndex..<separatorIndex])
        let modelID = String(raw[raw.index(after: separatorIndex)...])
        guard let service = AIService(rawValue: serviceRaw), !modelID.isEmpty else { return nil }
        return ModelIdentity(service: service, modelID: modelID)
    }
}
