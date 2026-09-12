import SwiftUI

/// Real streaming chat surface: transcript, composer with Send/Stop, and
/// a toolbar model selector. Transcripts are persisted via
/// `ChatCoordinator`'s `ConversationRepository` (Stage 4) — this view
/// itself has no persistence awareness.
///
/// Markdown/code-block rendering and copy actions are Stage 5.
struct ConversationDetailView: View {
    let conversation: Conversation
    @Bindable var viewModel: AppViewModel
    @Bindable var session: ConversationSessionState
    var coordinator: ChatCoordinator
    var modelCatalog: ModelPickerViewModel? = nil

    @State private var pendingServiceSwitchModel: ModelInfo?
    @State private var pendingServiceSwitchSettings = AdvancedChatSettings()
    @State private var pendingServiceSwitchDraft = ""
    @State private var pendingServiceSwitchTools: [AgentTool] = []
    @State private var isAdvancedSettingsPresented = false
    @State private var isWorkspacePresented = false
    @State private var autoError: String?

    var body: some View {
        VStack(spacing: 0) {
            if let modelCatalog {
                ModelBookmarkBar(viewModel: viewModel, catalog: modelCatalog,
                                 isBusy: isGeneratingHere)
            }
            TranscriptView(
                messages: coordinator.messages(for: conversation.id),
                contextBoundaryMessageID: coordinator.contextBoundaryMessageID(for: conversation.id),
                onStartContextHere: { messageID in
                    coordinator.setContextBoundary(messageID, in: conversation.id)
                }
            )

            Divider()

            if let invocation = coordinator.pendingToolApproval(for: conversation.id) {
                AgentToolApprovalView(
                    invocation: invocation,
                    onApprove: { coordinator.respondToToolApproval(in: conversation.id, approve: true, expectedToolCallID: invocation.toolCallID) },
                    onDeny: { coordinator.respondToToolApproval(in: conversation.id, approve: false, expectedToolCallID: invocation.toolCallID) }
                )
                .id(invocation.toolCallID)
            }

            if let position = coordinator.queuePosition(for: conversation.id) {
                Text("Queued · position \(position). No provider request has started. Stop removes this queued turn.")
                    .font(.caption).padding(.horizontal)
            } else if isGeneratingHere {
                Text(coordinator.state(for: conversation.id).title).font(.caption)
            } else if coordinator.activeTurnCount >= coordinator.maxConcurrentTurns {
                Text(coordinator.canAcceptTurn
                     ? "All execution slots are occupied. Send will queue this chat (up to \(coordinator.maxQueuedTurns) waiting)."
                     : "The queue is full. Your draft is preserved; wait or stop another chat.")
                    .font(.caption).padding(.horizontal)
            }

            if session.autoModeEnabled && !isGeneratingHere {
                let decision = autoDecision
                VStack(alignment: .leading, spacing: 2) {
                    Text(decision?.model.map { "🤖 Auto → \($0.displayName) · \($0.service.displayName)" } ?? "🤖 Auto needs attention")
                        .font(.caption)
                    Text(decision?.explanation ?? "Choose a model in the picker first.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            ComposerView(
                text: $session.draftText,
                isGenerating: isGeneratingHere,
                canSend: canSend,
                hasSelectedModel: session.selectedModel != nil,
                onSend: attemptSend,
                onStop: {
                    coordinator.stopGeneration(in: conversation.id)
                },
                willQueue: coordinator.activeTurnCount >= coordinator.maxConcurrentTurns
            )
            Text("Draft and chat settings stay with this chat until app quit. Transcript history is saved.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 6)
        }
        .toolbar {
            #if os(macOS)
            ToolbarItem {
                Button("Workspace", systemImage: "folder") { isWorkspacePresented = true }
                    .help("Local read-only workspace preview; nothing is sent to models")
                    .popover(isPresented: $isWorkspacePresented) {
                        WorkspacePreviewView(model: session.workspacePreview)
                    }
            }
            ToolbarItem(placement: .principal) {
                Button {
                    viewModel.isModelPickerPresented = true
                } label: {
                    Label(modelButtonTitle, systemImage: "cpu")
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("Choose a model (⌘K)")
                .disabled(isGeneratingHere)
                .accessibilityLabel(session.selectedModel == nil ? "Select a model" : "Model: \(modelButtonTitle)")
                .accessibilityHint("Opens the model picker")
            }
            ToolbarItem {
                Toggle(isOn: Binding(get: { session.autoModeEnabled }, set: {
                    guard viewModel.selectedConversationID == conversation.id else { return }
                    viewModel.setCurrentAutoEnabled($0, isBusy: isGeneratingHere)
                })) {
                    Text("🤖")
                }
                .toggleStyle(.button)
                .disabled(isGeneratingHere)
                .accessibilityLabel("Auto model selection")
                .accessibilityValue(session.autoModeEnabled ? "On" : "Off")
                .help("Auto uses this chat's policy snapshot. Saving a policy in another chat never changes it.")
            }
            ToolbarItem {
                Button {
                    isAdvancedSettingsPresented = true
                } label: {
                    Label("Advanced Settings", systemImage: "slider.horizontal.3")
                }
                .help("Advanced chat settings")
                .accessibilityLabel("Advanced chat settings")
                .popover(isPresented: $isAdvancedSettingsPresented) {
                    AdvancedSettingsView(
                        settings: $session.advancedChatSettings,
                        model: session.selectedModel,
                        contextUsage: session.selectedModel.map {
                            coordinator.contextUsageEstimate(for: conversation.id, model: $0, draft: session.draftText)
                        },
                        hasContextBoundary: coordinator.contextBoundaryMessageID(for: conversation.id) != nil,
                        onClearContextBoundary: {
                            coordinator.setContextBoundary(nil, in: conversation.id)
                        },
                        agentToolsEnabled: $session.agentToolsEnabled
                    )
                    .disabled(isGeneratingHere)
                }
            }
            #endif
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.isModelPickerPresented = true
                } label: {
                    Image(systemName: "cpu")
                }
                .accessibilityLabel("Choose model")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: Binding(get: { session.autoModeEnabled }, set: {
                    guard viewModel.selectedConversationID == conversation.id else { return }
                    viewModel.setCurrentAutoEnabled($0, isBusy: isGeneratingHere)
                })) {
                    Image(systemName: session.autoModeEnabled ? "wand.and.stars" : "wand.and.stars.inverse")
                }
                .disabled(isGeneratingHere)
                .accessibilityLabel("Automatic model selection")
            }
            #endif
        }
        .alert("Auto selection unavailable", isPresented: Binding(
            get: { autoError != nil }, set: { if !$0 { autoError = nil } }
        )) {
            Button("OK") { autoError = nil }
        } message: {
            Text(autoError ?? "")
        }
        .alert(
            "Share history with \(pendingServiceSwitchModel?.service.displayName ?? "")?",
            isPresented: Binding(
                get: { pendingServiceSwitchModel != nil },
                set: { if !$0 { pendingServiceSwitchModel = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { pendingServiceSwitchModel = nil }
            Button("Send") {
                if let model = pendingServiceSwitchModel {
                    guard viewModel.selectedConversationID == conversation.id,
                          !isGeneratingHere, coordinator.canAcceptTurn,
                          session.draftText == pendingServiceSwitchDraft,
                          session.toolsToOffer == pendingServiceSwitchTools,
                          session.effectiveChatSettings == pendingServiceSwitchSettings,
                          session.autoModeEnabled || session.selectedModel?.identity == model.identity else {
                        pendingServiceSwitchModel = nil
                        return
                    }
                    // Confirmation may stay open past the catalog freshness
                    // window. Never send a now-ineligible Auto candidate.
                    if session.autoModeEnabled && autoDecision?.model?.identity != model.identity {
                        pendingServiceSwitchModel = nil
                        autoError = "Auto's candidate changed or became unavailable. Refresh models and send again."
                        return
                    }
                    let accepted = coordinator.send(
                        text: pendingServiceSwitchDraft,
                        in: conversation.id,
                        using: model,
                        settings: pendingServiceSwitchSettings,
                        tools: pendingServiceSwitchTools,
                        validateBeforeStart: startValidator(for: model)
                    )
                    if accepted { session.draftText = "" }
                }
                pendingServiceSwitchModel = nil
            }
        } message: {
            Text(
                "This conversation's existing history was sent to a different service. " +
                "Sending now will share that history with \(pendingServiceSwitchModel?.service.displayName ?? "this service") too."
            )
        }
    }

    private var isGeneratingHere: Bool {
        coordinator.isBusy(conversation.id)
    }

    private var canSend: Bool {
        guard !isGeneratingHere, coordinator.canAcceptTurn else { return false }
        guard session.selectedModel != nil else { return false }
        return !session.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var modelButtonTitle: String {
        guard let model = session.selectedModel else { return "Select Model" }
        let prefix = session.autoModeEnabled ? "Chat Auto anchor: " : ""
        return "\(prefix)\(model.displayName) · \(model.service.displayName)"
    }

    private func attemptSend() {
        guard viewModel.selectedConversationID == conversation.id,
              !isGeneratingHere, coordinator.canAcceptTurn,
              let selected = session.selectedModel else { return }
        let model: ModelInfo
        if session.autoModeEnabled {
            guard let decision = autoDecision, let routed = decision.model else {
                autoError = autoDecision?.explanation ?? "Open the model picker first."
                return
            }
            model = routed
        } else {
            model = selected
        }
        if coordinator.wouldShareHistoryAcrossServices(conversationID: conversation.id, nextService: model.service) {
            pendingServiceSwitchSettings = session.effectiveChatSettings
            pendingServiceSwitchDraft = session.draftText
            pendingServiceSwitchTools = session.toolsToOffer
            pendingServiceSwitchModel = model
            return
        }
        let accepted = coordinator.send(
            text: session.draftText,
            in: conversation.id,
            using: model,
            settings: session.effectiveChatSettings,
            tools: session.toolsToOffer,
            validateBeforeStart: startValidator(for: model)
        )
        if accepted { session.draftText = "" }
    }

    /// Capture consent and routing inputs, not the view/draft that may change
    /// while waiting. Failure at dispatch is visible and never auto-retried.
    private func startValidator(for model: ModelInfo) -> (@MainActor () -> String?)? {
        guard session.autoModeEnabled else { return nil }
        guard let policy = session.autoPolicy, let catalog = modelCatalog else {
            return { "Auto policy unavailable. Configure Auto and send again." }
        }
        let prompt = session.draftText
        let context = coordinator.autoRoutingContext(for: conversation.id, draft: prompt)
        let settings = session.advancedChatSettings
        let tools = session.agentToolsEnabled
        return {
            let decision = catalog.autoDecision(prompt: prompt, recent: context.recent, requiredContext: context.required,
                                                policy: policy, requiresTools: tools, settings: settings)
            return decision.model?.identity == model.identity ? nil
                : "Queued Auto choice expired or changed. Refresh models and explicitly send again. No request was made."
        }
    }

    private var autoDecision: AutoModelDecision? {
        guard session.autoModeEnabled, let policy = session.autoPolicy,
              let modelCatalog else { return nil }
        let context = coordinator.autoRoutingContext(for: conversation.id, draft: session.draftText)
        return modelCatalog.autoDecision(prompt: session.draftText, recent: context.recent,
                                         requiredContext: context.required, policy: policy,
                                         requiresTools: session.agentToolsEnabled,
                                         settings: session.advancedChatSettings)
    }
}

#Preview("Conversation Detail") {
    ConversationDetailView(
        conversation: DemoFixtures.conversations[0],
        viewModel: AppViewModel(),
        session: ConversationSessionState(),
        coordinator: ChatCoordinator(credentialStore: PreviewCoordinatorStore(), clients: [:])
    )
}

private struct PreviewCoordinatorStore: CredentialStore {
    func saveKey(_ key: String, for service: AIService) throws {}
    func loadKey(for service: AIService) throws -> String? { nil }
    func deleteKey(for service: AIService) throws {}
}
