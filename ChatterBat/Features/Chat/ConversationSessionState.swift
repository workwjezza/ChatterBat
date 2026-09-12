import Foundation
import Observation

/// In-memory configuration for one conversation. Transcript persistence is
/// separate; drafts/settings are not written to UserDefaults or exports.
@Observable
@MainActor
final class ConversationSessionState {
    var draftText = ""
    var selectedModel: ModelInfo?
    var selectedIdentity: ModelIdentity?
    var advancedChatSettings = AdvancedChatSettings()
    var agentToolsEnabled = false
    var autoModeEnabled = false
    var autoPolicy: SavedAutoPolicy?
    var selectionNotice: String?
    var resolvesSelectionFromCatalog = false
    let workspacePreview = WorkspacePreviewModel()

    var toolsToOffer: [AgentTool] {
        agentToolsEnabled ? AgentTool.allCases : []
    }

    var effectiveChatSettings: AdvancedChatSettings {
        guard autoModeEnabled, let autoPolicy else { return advancedChatSettings }
        return autoPolicy.applyingPrivacy(to: advancedChatSettings)
    }
}