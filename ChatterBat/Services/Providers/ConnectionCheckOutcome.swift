import Foundation

/// Result of verifying a stored API key against its provider's
/// non-billable account-status endpoint.
///
/// This is deliberately distinct from `ConnectionState` (a presentation
/// type): this is what a `ConnectionChecking` implementation returns,
/// before the view model turns it into UI state.
enum ConnectionCheckOutcome: Equatable, Sendable {
    /// The provider accepted the key. `summary` is a short, non-sensitive
    /// human-readable description built only from fields the provider
    /// intends for this purpose (e.g. remaining credit, tier) — never the
    /// full raw response.
    case valid(summary: String)
    /// The provider explicitly rejected the credential (HTTP 401/403).
    case invalidCredential
    /// A transport-level failure (no connectivity, timeout, TLS failure).
    case transportFailure(String)
    /// The provider responded, but not in a way this client recognizes
    /// (unexpected status code, undecodable body). Kept distinct from
    /// `transportFailure` so the two can be messaged differently.
    case unrecognizedResponse(String)
}

/// Verifies a stored credential against a provider without performing
/// billable inference.
///
/// Per the brief: "A public model-list response is not proof that a key is
/// valid" — each conforming type must call an endpoint that actually
/// authenticates the key (not merely a public catalog), and must not run
/// chat completions to do so.
protocol ConnectionChecking: Sendable {
    var service: AIService { get }
    func checkConnection(apiKey: String) async -> ConnectionCheckOutcome
}
