import Foundation

/// UI-facing connection state for one service's account settings.
///
/// This is a presentation-layer concept, not a network response — it is
/// derived from `ConnectionCheckOutcome` (see
/// `Services/Providers/ConnectionCheckOutcome.swift`) plus whether a key is
/// currently stored in Keychain at all.
enum ConnectionState: Equatable, Sendable {
    /// No key stored for this service yet.
    case notConfigured
    /// A key is stored and a verification request is in flight.
    case checking
    /// The provider accepted the key. `summary` is a short, non-sensitive
    /// human-readable status derived from the provider's response (e.g.
    /// remaining credit or tier) — never the raw response body.
    case connected(summary: String)
    /// The provider explicitly rejected the key (401/403).
    case invalidCredential
    /// Verification could not be completed for some other reason
    /// (network failure, unexpected HTTP status, malformed response).
    /// `message` is safe to show to the user and contains no secrets.
    case error(String)
}
