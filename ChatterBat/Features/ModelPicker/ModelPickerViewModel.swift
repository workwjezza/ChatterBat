import Foundation
import Observation

/// Drives the unified Venice/OpenRouter model picker.
///
/// Owns per-service catalog state, search/filter text, and
/// favorites/recents, but not the caller's current selection — the
/// caller (e.g. `ConversationDetailView`) owns that and passes an
/// `onSelect` closure, since "choosing a model does not send a chat
/// request" and the picker itself has no chat/session concept.
@Observable
@MainActor
final class ModelPickerViewModel {
    private(set) var catalogStates: [AIService: CatalogLoadState] = [
        .venice: .idle,
        .openRouter: .idle
    ]

    var searchText = ""
    var serviceFilter: ModelPickerServiceFilter = .all
    var showFavoritesOnly = false

    private let credentialStore: CredentialStore
    private let fetchers: [AIService: ModelCatalogFetching]
    private let preferencesStore: ModelPreferencesStore

    init(
        credentialStore: CredentialStore,
        fetchers: [AIService: ModelCatalogFetching],
        preferencesStore: ModelPreferencesStore
    ) {
        self.credentialStore = credentialStore
        self.fetchers = fetchers
        self.preferencesStore = preferencesStore
    }

    // MARK: - Loading

    /// Loads (or reloads) catalogs for every service that currently has a
    /// stored key. Services with no key are marked `.notConfigured`
    /// without any network call — per the brief, there should be no
    /// network activity for a service the user hasn't connected.
    func loadAllConfiguredCatalogs() async {
        for service in AIService.allCases {
            guard (try? credentialStore.loadKey(for: service)).flatMap({ $0 }) != nil else {
                catalogStates[service] = .notConfigured
                continue
            }
            await refresh(service)
        }
    }

    func refresh(_ service: AIService) async {
        guard let fetcher = fetchers[service] else { return }
        guard let key = (try? credentialStore.loadKey(for: service)) ?? nil else {
            catalogStates[service] = .notConfigured
            return
        }

        let cached = catalogStates[service]?.displayableModels ?? []
        let cachedFetchedAt: Date? = {
            if case .loaded(_, let fetchedAt) = catalogStates[service] { return fetchedAt }
            if case .failed(_, _, let fetchedAt) = catalogStates[service] { return fetchedAt }
            return nil
        }()

        catalogStates[service] = .loading(cachedModels: cached)
        let outcome = await fetcher.fetchModels(apiKey: key)

        switch outcome {
        case .success(let models):
            catalogStates[service] = .loaded(models: models, fetchedAt: .now)
        case .invalidCredential:
            catalogStates[service] = .failed(
                message: "This key was rejected. Check it in Settings → Accounts.",
                cachedModels: cached,
                cachedFetchedAt: cachedFetchedAt
            )
        case .transportFailure(let message):
            catalogStates[service] = .failed(
                message: "Network error: \(message)",
                cachedModels: cached,
                cachedFetchedAt: cachedFetchedAt
            )
        case .unrecognizedResponse(let message):
            catalogStates[service] = .failed(
                message: message,
                cachedModels: cached,
                cachedFetchedAt: cachedFetchedAt
            )
        }
    }

    // MARK: - Derived list

    /// All models from every service currently known (loaded or cached),
    /// filtered by search text, service filter, and favorites-only,
    /// grouped into recents/favorites/rest by the view.
    var filteredModels: [ModelInfo] {
        let allModels = AIService.allCases.flatMap { catalogStates[$0]?.displayableModels ?? [] }
        let favorites = preferencesStore.favoriteIdentities()

        return allModels.filter { model in
            guard serviceFilter.matches(model.service) else { return false }
            if showFavoritesOnly && !favorites.contains(model.identity) { return false }
            guard !searchText.isEmpty else { return true }
            return model.displayName.localizedCaseInsensitiveContains(searchText)
                || model.modelID.localizedCaseInsensitiveContains(searchText)
        }
    }

    func isFavorite(_ identity: ModelIdentity) -> Bool {
        preferencesStore.favoriteIdentities().contains(identity)
    }

    func toggleFavorite(_ identity: ModelIdentity) {
        preferencesStore.setFavorite(identity, isFavorite: !isFavorite(identity))
    }

    /// Recently-used models, resolved against currently-known catalog
    /// entries. A recent identity whose model has disappeared from the
    /// catalog is silently omitted here (the picker only shows selectable
    /// models) — this does not affect historical message attribution,
    /// which is a separate, later-stage concern.
    var recentModels: [ModelInfo] {
        let allModels = AIService.allCases.flatMap { catalogStates[$0]?.displayableModels ?? [] }
        let byIdentity = Dictionary(uniqueKeysWithValues: allModels.map { ($0.identity, $0) })
        return preferencesStore.recentIdentities().compactMap { byIdentity[$0] }
    }

    /// Call when the user actually selects a model (not merely when the
    /// picker opens), so recents reflect real usage.
    func recordSelection(_ identity: ModelIdentity) {
        preferencesStore.recordUsed(identity)
    }
}
