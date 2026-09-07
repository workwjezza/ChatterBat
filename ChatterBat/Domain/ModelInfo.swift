import Foundation

/// A normalized, provider-agnostic description of one selectable chat
/// model, built from a single catalog entry.
///
/// Fields here are intentionally limited to what the model picker
/// actually displays in Stage 2 (identity, context/output limits,
/// pricing, a handful of capability badges, and Venice's privacy label).
/// Unknown values must stay `nil`/`.unknown` — never guessed.
struct ModelInfo: Identifiable, Hashable, Sendable {
    let identity: ModelIdentity
    /// Human-readable name from the provider's catalog. Falls back to the
    /// raw model ID if the provider didn't supply one.
    let displayName: String
    let contextLength: Int?
    let maxOutputTokens: Int?
    let pricing: ModelPricing
    let supportsTools: CapabilitySupport
    let supportsReasoning: CapabilitySupport
    let supportsVision: CapabilitySupport
    /// Venice-only baseline privacy label from `model_spec.privacy`
    /// (e.g. "private", "anonymized"). Always `nil` for OpenRouter models
    /// — OpenRouter's provider-routing privacy controls are a different,
    /// per-request concept handled in a later stage, not a per-model label
    /// like Venice's.
    let privacyDescription: String?

    var service: AIService { identity.service }
    var modelID: String { identity.modelID }

    /// Stable `Identifiable` id combining both parts of `identity`, so two
    /// same-named models on different services never collide in a
    /// SwiftUI `List`/`ForEach`.
    var id: String { "\(identity.service.rawValue):\(identity.modelID)" }
}
