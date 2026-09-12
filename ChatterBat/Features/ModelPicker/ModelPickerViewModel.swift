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
    var capabilityFilters: Set<ModelPickerCapability> = []
    var taskPreset: ModelPickerTaskPreset = .all
    private(set) var favorites: Set<ModelIdentity>

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
        self.favorites = preferencesStore.favoriteIdentities()
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
        if case .loading = catalogStates[service] { return }
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

    /// Failed/loading/old catalogs remain visible, but cannot drive Auto or
    /// value claims. No background polling or per-prompt catalog request.
    func freshModels(for service: AIService, now: Date = .now) -> [ModelInfo] {
        guard case .loaded(let models, let fetchedAt) = catalogStates[service],
              now.timeIntervalSince(fetchedAt) < 15 * 60 else { return [] }
        return models
    }

    func isGoodValue(_ model: ModelInfo) -> Bool {
        ModelValuePolicy.isGoodValue(model, among: freshModels(for: model.service))
    }

    func currentModel(_ identity: ModelIdentity) -> ModelInfo? {
        freshModels(for: identity.service).first { $0.identity == identity }
    }

    func displayModel(_ identity: ModelIdentity) -> ModelInfo? {
        catalogStates[identity.service]?.displayableModels.first { $0.identity == identity }
    }

    /// Independent of picker search/provider filters; retain unavailable stars.
    var bookmarkedIdentities: [ModelIdentity] {
        favorites.sorted {
            "\($0.service.rawValue):\($0.modelID)" < "\($1.service.rawValue):\($1.modelID)"
        }
    }

    func autoDecision(prompt: String, recent: String, requiredContext: Int,
                      policy: SavedAutoPolicy, requiresTools: Bool,
                      settings: AdvancedChatSettings) -> AutoModelDecision {
        guard let current = currentModel(policy.anchor),
              let anchor = policy.constrainedAnchor(current) else {
            return AutoModelDecision(model: nil, explanation: "Auto's saved anchor is unavailable, stale, or its privacy label changed. Refresh models or explicitly save a new Auto policy.")
        }
        return AutoModelRouter.select(prompt: prompt, recentUserContext: recent,
                                      requiredContext: requiredContext, anchor: anchor,
                                      models: freshModels(for: policy.anchor.service), favorites: favorites,
                                      requiresTools: requiresTools, settings: policy.applyingPrivacy(to: settings))
    }

    func autoDecision(prompt: String, recent: String, requiredContext: Int,
                      anchor: ModelInfo, requiresTools: Bool,
                      settings: AdvancedChatSettings) -> AutoModelDecision {
        let models = freshModels(for: anchor.service)
        guard let currentAnchor = models.first(where: { $0.identity == anchor.identity }) else {
            return AutoModelDecision(model: nil, explanation: "Refresh the model picker: Auto needs a current catalog and selected model (maximum age 15 minutes).")
        }
        return AutoModelRouter.select(prompt: prompt, recentUserContext: recent,
                                      requiredContext: requiredContext, anchor: currentAnchor,
                                      models: models, favorites: favorites,
                                      requiresTools: requiresTools, settings: settings)
    }

    /// Explicit capabilities intersect with preset requirements. Choosing a
    /// preset never clears the user's independent capability toggles.
    var requiredCapabilities: Set<ModelPickerCapability> {
        capabilityFilters.union(taskPreset.suggestedCapabilities)
    }

    var hasActiveFilters: Bool {
        !searchText.isEmpty || serviceFilter != .all || showFavoritesOnly
            || !capabilityFilters.isEmpty || taskPreset != .all
    }

    func setCapability(_ capability: ModelPickerCapability, enabled: Bool) {
        if enabled { capabilityFilters.insert(capability) }
        else { capabilityFilters.remove(capability) }
    }

    func resetFilters() {
        searchText = ""
        serviceFilter = .all
        showFavoritesOnly = false
        capabilityFilters = []
        taskPreset = .all
    }

    /// Shared by search, provider sections, and Recent. Unknown does not
    /// satisfy a requirement, but remains visible when that filter is off.
    func matchesFilters(_ model: ModelInfo) -> Bool {
        guard taskPreset.isAvailable, serviceFilter.matches(model.service),
              !showFavoritesOnly || favorites.contains(model.identity),
              requiredCapabilities.allSatisfy({ $0.support(in: model) == .supported }) else { return false }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || model.displayName.localizedCaseInsensitiveContains(query)
            || model.modelID.localizedCaseInsensitiveContains(query)
    }

    /// All models from every service currently known (loaded or cached),
    /// consistently filtered regardless of which section displays them.
    var filteredModels: [ModelInfo] {
        let allModels = AIService.allCases.flatMap { catalogStates[$0]?.displayableModels ?? [] }
        return allModels.filter(matchesFilters)
    }

    func filteredModels(for service: AIService) -> [ModelInfo] {
        filteredModels.filter { $0.service == service }
    }

    var filteredRecentModels: [ModelInfo] {
        recentModels.filter(matchesFilters)
    }

    func capabilitySummary(for model: ModelInfo) -> String {
        ModelPickerCapability.allCases.map { "\($0.title): \($0.status(in: model))" }.joined(separator: "; ")
    }

    func isFavorite(_ identity: ModelIdentity) -> Bool {
        favorites.contains(identity)
    }

    func toggleFavorite(_ identity: ModelIdentity) {
        preferencesStore.setFavorite(identity, isFavorite: !isFavorite(identity))
        favorites = preferencesStore.favoriteIdentities()
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
