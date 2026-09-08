import SwiftUI

/// Real streaming chat surface: transcript, composer with Send/Stop, and
/// a toolbar model selector. Transcripts are persisted via
/// `ChatCoordinator`'s `ConversationRepository` (Stage 4) — this view
/// itself has no persistence awareness.
///
/// Markdown/code-block rendering and copy actions are Stage 5.
struct ConversationDetailView: View {
    let conversation: Conversation
    // @Bindable (rather than a plain `var`) so `AdvancedSettingsView`'s
    // `$viewModel.advancedChatSettings` binding below can write back
    // to the shared view model — needed as of Stage 6; earlier stages
    // only ever read from `viewModel`.
    @Bindable var viewModel: AppViewModel
    var coordinator: ChatCoordinator

    @State private var draftText = ""
    @State private var pendingServiceSwitchModel: ModelInfo?
    @State private var isAdvancedSettingsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            TranscriptView(
                messages: coordinator.messages(for: conversation.id),
                contextBoundaryMessageID: coordinator.contextBoundaryMessageID(for: conversation.id),
                onStartContextHere: { messageID in
                    coordinator.setContextBoundary(messageID, in: conversation.id)
                }
            )

            Divider()

            ComposerView(
                text: $draftText,
                isGenerating: isGeneratingHere,
                canSend: canSend,
                hasSelectedModel: viewModel.selectedModel != nil,
                onSend: attemptSend,
                onStop: coordinator.stopGeneration
            )
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    viewModel.isModelPickerPresented = true
                } label: {
                    Label(modelButtonTitle, systemImage: "cpu")
                }
                .keyboardShortcut("k", modifiers: .command)
                .help("Choose a model (⌘K)")
                .disabled(isGeneratingHere)
                .accessibilityLabel(viewModel.selectedModel == nil ? "Select a model" : "Model: \(modelButtonTitle)")
                .accessibilityHint("Opens the model picker")
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
                        settings: $viewModel.advancedChatSettings,
                        model: viewModel.selectedModel,
                        contextUsage: viewModel.selectedModel.map {
                            coordinator.contextUsageEstimate(for: conversation.id, model: $0)
                        },
                        hasContextBoundary: coordinator.contextBoundaryMessageID(for: conversation.id) != nil,
                        onClearContextBoundary: {
                            coordinator.setContextBoundary(nil, in: conversation.id)
                        },
                        agentToolsEnabled: $viewModel.agentToolsEnabled
                    )
                }
            }
        }
        .sheet(item: Binding(
            get: { coordinator.pendingToolApproval(for: conversation.id) },
            set: { newValue in
                // Only denies if a decision genuinely hasn't already
                // been made — Approve/Deny inside the sheet resolve
                // the pending call directly via ChatCoordinator, which
                // is what actually clears `pendingToolApproval` and
                // lets SwiftUI dismiss this sheet on its own; this
                // guard exists purely so an unexpected dismissal
                // (e.g. the window closing) never leaves a tool call
                // silently unresolved.
                if newValue == nil && coordinator.pendingToolApproval(for: conversation.id) != nil {
                    coordinator.respondToToolApproval(in: conversation.id, approve: false)
                }
            }
        )) { invocation in
            AgentToolApprovalView(
                invocation: invocation,
                onApprove: { coordinator.respondToToolApproval(in: conversation.id, approve: true) },
                onDeny: { coordinator.respondToToolApproval(in: conversation.id, approve: false) }
            )
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
                    coordinator.send(
                        text: draftText,
                        in: conversation.id,
                        using: model,
                        settings: viewModel.advancedChatSettings,
                        tools: viewModel.toolsToOffer
                    )
                    draftText = ""
                }
                pendingServiceSwitchModel = nil
            }
        } message: {
            Text(
                "This conversation's existing history was sent to a different service. " +
                "Sending now will share that history with \(pendingServiceSwitchModel?.service.displayName ?? "this service") too."
            )
        }
        .onChange(of: coordinator.messages(for: conversation.id)) { _, _ in
            // Keeps the sidebar's preview/updatedAt in sync as messages
            // are appended/checkpointed, without the sidebar needing to
            // poll or duplicate ChatCoordinator's persistence logic.
            viewModel.refreshConversationMetadata(conversationID: conversation.id)
        }
    }

    private var isGeneratingHere: Bool {
        coordinator.generationState.activeConversationID == conversation.id
    }

    private var canSend: Bool {
        guard case .idle = coordinator.generationState else { return false }
        guard viewModel.selectedModel != nil else { return false }
        return !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var modelButtonTitle: String {
        guard let model = viewModel.selectedModel else { return "Select Model" }
        return "\(model.displayName) · \(model.service.displayName)"
    }

    private func attemptSend() {
        guard let model = viewModel.selectedModel else { return }
        if coordinator.wouldShareHistoryAcrossServices(conversationID: conversation.id, nextService: model.service) {
            pendingServiceSwitchModel = model
            return
        }
        coordinator.send(
            text: draftText,
            in: conversation.id,
            using: model,
            settings: viewModel.advancedChatSettings,
            tools: viewModel.toolsToOffer
        )
        draftText = ""
    }
}

#Preview("Conversation Detail") {
    ConversationDetailView(
        conversation: DemoFixtures.conversations[0],
        viewModel: AppViewModel(),
        coordinator: ChatCoordinator(credentialStore: PreviewCoordinatorStore(), clients: [:])
    )
}

private struct PreviewCoordinatorStore: CredentialStore {
    func saveKey(_ key: String, for service: AIService) throws {}
    func loadKey(for service: AIService) throws -> String? { nil }
    func deleteKey(for service: AIService) throws {}
}
