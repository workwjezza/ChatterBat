import Foundation

/// Saved consent boundaries, not cached catalog metadata or a billing cap.
struct SavedAutoPolicy: Codable, Equatable, Sendable {
    let anchor: ModelIdentity
    let privacyDescription: String?
    let maxInputUSDPerMillion: Decimal
    let maxOutputUSDPerMillion: Decimal
    let denyDataCollection: Bool
    let zeroDataRetention: Bool
    let allowProviderFallbacks: Bool

    init?(model: ModelInfo, settings: AdvancedChatSettings) {
        guard ModelValuePolicy.score(model) != nil,
              !model.modelID.hasPrefix("openrouter/"),
              let input = model.pricing.inputPerMillionTokensUSD,
              let output = model.pricing.outputPerMillionTokensUSD else { return nil }
        anchor = model.identity
        privacyDescription = model.privacyDescription
        maxInputUSDPerMillion = input
        maxOutputUSDPerMillion = output
        denyDataCollection = settings.openRouterRouting.dataCollection == .deny
        zeroDataRetention = settings.openRouterRouting.zdr
        allowProviderFallbacks = settings.openRouterRouting.allowFallbacks
    }

    var isValid: Bool {
        !anchor.modelID.isEmpty && !anchor.modelID.hasPrefix("openrouter/")
            && !maxInputUSDPerMillion.isNaN && !maxOutputUSDPerMillion.isNaN
            && maxInputUSDPerMillion >= 0 && maxOutputUSDPerMillion >= 0
    }

    func applyingPrivacy(to settings: AdvancedChatSettings) -> AdvancedChatSettings {
        var result = settings
        if anchor.service == .openRouter {
            // The saved policy is a floor for privacy, never permission to
            // weaken stricter settings the user has selected for this send.
            if denyDataCollection { result.openRouterRouting.dataCollection = .deny }
            result.openRouterRouting.zdr = zeroDataRetention || settings.openRouterRouting.zdr
            result.openRouterRouting.allowFallbacks = allowProviderFallbacks && settings.openRouterRouting.allowFallbacks
        }
        return result
    }

    /// Catalog capabilities stay current; rates stay within the user's saved
    /// ceilings even if the anchor becomes more expensive after a refresh.
    func constrainedAnchor(_ current: ModelInfo) -> ModelInfo? {
        guard isValid, current.identity == anchor,
              current.privacyDescription == privacyDescription else { return nil }
        return ModelInfo(identity: anchor, displayName: current.displayName,
                         contextLength: current.contextLength, maxOutputTokens: current.maxOutputTokens,
                         pricing: ModelPricing(inputPerMillionTokensUSD: maxInputUSDPerMillion,
                                               outputPerMillionTokensUSD: maxOutputUSDPerMillion),
                         supportsTools: current.supportsTools, supportsReasoning: current.supportsReasoning,
                         supportsVision: current.supportsVision, privacyDescription: privacyDescription)
    }
}

struct ModelSelectionDefaults: Codable, Equatable, Sendable {
    var schemaVersion = 1
    /// nil means Auto, which requires an explicit saved policy before sending.
    var pinnedModel: ModelIdentity?
    var autoPolicy: SavedAutoPolicy?

    var isValid: Bool {
        schemaVersion == 1 && pinnedModel?.modelID.isEmpty != true
            && (autoPolicy?.isValid ?? true)
    }
}