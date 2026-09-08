import Foundation

/// A small, OpenAI-style reasoning-effort hint sent as the top-level
/// `reasoning_effort` string field, which both Venice and OpenRouter
/// document as accepting directly (Venice's chat completions schema
/// lists `reasoning_effort` alongside the richer `reasoning` object;
/// OpenRouter documents the same field as "OpenAI-style reasoning
/// effort setting"). Deliberately limited to three values rather than
/// the full provider-specific range (OpenRouter also accepts `xhigh`/
/// `minimal`/`none`) — per the brief, "keep the initial supported
/// subset deliberate," and these three map onto both providers without
/// per-provider translation.
enum ReasoningEffort: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

/// Venice-only advanced controls, sent inside the `venice_parameters`
/// request object. Both fields are documented booleans on Venice's
/// chat completions endpoint (`venice_parameters.disable_thinking`,
/// `venice_parameters.strip_thinking_response`) — see
/// docs/DECISIONS.md. Never sent to OpenRouter.
struct VeniceAdvancedSettings: Equatable, Sendable {
    /// Disables thinking entirely on reasoning-capable Venice models.
    var disableThinking: Bool = false
    /// Removes `<think>` blocks from the response content, keeping the
    /// final answer only. Independent of `disableThinking` — a model
    /// can still think internally while having the trace stripped from
    /// what's returned.
    var stripThinkingResponse: Bool = false
}

/// Whether OpenRouter may route a request to providers that store
/// input data. Mirrors OpenRouter's documented `provider.data_collection`
/// field exactly: `"allow"` (OpenRouter's own default) or `"deny"`.
enum DataCollectionPreference: String, CaseIterable, Identifiable, Sendable {
    case allow
    case deny

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allow: return "Allow providers that may store data"
        case .deny: return "Deny — only zero-retention-compliant providers"
        }
    }
}

/// A deliberately small subset of OpenRouter's `provider` routing
/// object — per the brief, "a deliberately small set of OpenRouter
/// routing controls." These three were chosen because they are the
/// only documented provider-routing fields that (a) map directly to a
/// privacy/reliability concern ChatterBat already cares about for
/// Venice, and (b) never require fetching OpenRouter's separate
/// provider-slug catalog to present (unlike `order`/`only`/`ignore`,
/// which need a picker over provider names ChatterBat doesn't fetch
/// anywhere yet). Never sent to Venice.
struct OpenRouterRoutingPreferences: Equatable, Sendable {
    /// OpenRouter's own default is `true`; only sent explicitly when
    /// `false`; matches OpenRouter's documented default so leaving this
    /// untouched never changes the request.
    var allowFallbacks: Bool = true
    var dataCollection: DataCollectionPreference = .allow
    /// Restrict routing to Zero Data Retention endpoints only.
    var zdr: Bool = false
}

/// The full set of advanced, per-send chat settings a user can opt
/// into. Mirrors the brief's "advanced controls must stay hidden by
/// default" requirement: every field defaults to a value that changes
/// nothing about the request that would otherwise be sent.
struct AdvancedChatSettings: Equatable, Sendable {
    /// `nil` means "don't send `reasoning_effort` at all" — never
    /// defaults to a non-nil value, since sending it to a model that
    /// doesn't support reasoning risks an "unsupported parameter"
    /// failure per the brief's capability-aware requirement.
    var reasoningEffort: ReasoningEffort?
    var venice: VeniceAdvancedSettings = VeniceAdvancedSettings()
    var openRouterRouting: OpenRouterRoutingPreferences = OpenRouterRoutingPreferences()

    init(
        reasoningEffort: ReasoningEffort? = nil,
        venice: VeniceAdvancedSettings = VeniceAdvancedSettings(),
        openRouterRouting: OpenRouterRoutingPreferences = OpenRouterRoutingPreferences()
    ) {
        self.reasoningEffort = reasoningEffort
        self.venice = venice
        self.openRouterRouting = openRouterRouting
    }

    /// Returns a copy with every field that doesn't apply to `model`
    /// reset to its no-op default, so a caller can safely build a
    /// request from the result without re-checking capabilities itself.
    ///
    /// This is the single place "capability-aware" gating happens —
    /// per the brief, unknown capability must never be treated as
    /// supported, so `reasoningEffort`/Venice thinking controls are
    /// dropped whenever `model.supportsReasoning != .supported`
    /// (`.unknown` is treated the same as `.unsupported` here,
    /// specifically to avoid sending a parameter the provider might
    /// reject — this is a request-safety decision, not a capability-
    /// badge display decision, which is why it differs from how
    /// `.unknown` is displayed elsewhere).
    func applicable(to model: ModelInfo) -> AdvancedChatSettings {
        var result = self
        if model.supportsReasoning != .supported {
            result.reasoningEffort = nil
            result.venice = VeniceAdvancedSettings()
        }
        if model.service != .venice {
            result.venice = VeniceAdvancedSettings()
        }
        if model.service != .openRouter {
            result.openRouterRouting = OpenRouterRoutingPreferences()
        }
        return result
    }
}
