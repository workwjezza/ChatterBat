import Foundation

/// The two chat services ChatterBat can connect to.
///
/// This is intentionally a closed, small enum rather than a general
/// "provider" abstraction — the brief is explicit that Venice and
/// OpenRouter are distinct services with distinct payloads, and model
/// identity is always the pair (service, modelID). Do not merge them.
enum AIService: String, CaseIterable, Identifiable, Sendable, Codable {
    case venice
    case openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .venice: return "Venice"
        case .openRouter: return "OpenRouter"
        }
    }

    /// The official web page where a user creates/manages API keys for this
    /// service. Verified against current provider documentation as of
    /// Stage 1 implementation:
    /// - Venice: https://docs.venice.ai/guides/getting-started/generating-api-key
    /// - OpenRouter: https://openrouter.ai/docs/quickstart
    var keyManagementURL: URL {
        switch self {
        case .venice:
            return URL(string: "https://venice.ai/settings/api")!
        case .openRouter:
            return URL(string: "https://openrouter.ai/settings/keys")!
        }
    }

    /// The exact HTTPS host requests to this service must be pinned to.
    /// Used by the HTTP client to refuse to follow a redirect to a
    /// different host, per the brief's requirement not to forward
    /// Authorization headers across hosts.
    var apiHost: String {
        switch self {
        case .venice: return "api.venice.ai"
        case .openRouter: return "openrouter.ai"
        }
    }
}
