import Foundation

/// Result of fetching a service's model catalog.
///
/// Mirrors the shape of `ConnectionCheckOutcome` for consistency, but
/// carries the decoded models on success. `.success` always carries
/// whatever valid entries were decoded, even if some entries in the raw
/// response were skipped — see `skippedEntryCount` on the fetcher-level
/// diagnostics, not here, per "tolerate unknown optional fields; don't
/// discard all valid entries over one malformed one."
enum ModelCatalogFetchOutcome: Sendable {
    case success([ModelInfo])
    case invalidCredential
    case transportFailure(String)
    case unrecognizedResponse(String)
}

/// Fetches a service's chat-capable model catalog.
///
/// Implementations must call the service's real `/models` endpoint (not a
/// hardcoded list) and must filter out non-text/non-chat model types
/// where the API supports doing so, per the brief's requirement to keep
/// non-chat models out of the chat picker.
protocol ModelCatalogFetching: Sendable {
    var service: AIService { get }
    func fetchModels(apiKey: String) async -> ModelCatalogFetchOutcome
}
