import Foundation

/// Per-service model catalog loading state, as shown in the model picker.
///
/// This intentionally keeps stale/cached models visible alongside a
/// failure — per the brief: "Cache catalogs and show cache age/offline
/// state," and a refresh failure should not blank out a previously
/// successful catalog.
enum CatalogLoadState: Sendable, Equatable {
    /// No key configured for this service, so there's nothing to fetch.
    /// Distinct from `.failed` — this isn't an error.
    case notConfigured
    /// Never fetched yet this session.
    case idle
    /// A fetch is currently in flight. Carries any previously-cached
    /// models so the list doesn't flash empty during a refresh.
    case loading(cachedModels: [ModelInfo])
    /// Fetch succeeded. `fetchedAt` is used to display cache age.
    case loaded(models: [ModelInfo], fetchedAt: Date)
    /// Fetch failed. `cachedModels`/`cachedFetchedAt` are non-nil if a
    /// previous successful fetch exists this session, so the UI can keep
    /// showing the last-known catalog with an "offline" hint rather than
    /// an empty list.
    case failed(message: String, cachedModels: [ModelInfo], cachedFetchedAt: Date?)

    /// The best available list of models regardless of current state —
    /// used by the picker so a transient error/reload never empties the
    /// visible list if a cached catalog exists.
    var displayableModels: [ModelInfo] {
        switch self {
        case .notConfigured, .idle:
            return []
        case .loading(let cachedModels):
            return cachedModels
        case .loaded(let models, _):
            return models
        case .failed(_, let cachedModels, _):
            return cachedModels
        }
    }
}
