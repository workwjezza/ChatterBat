import SwiftUI

/// Real streaming chat surface as of Stage 3: transcript, composer with
/// Send/Stop, and a toolbar model selector.
///
/// Markdown/code-block rendering, copy actions, and persistence are
/// later stages (5 and 4 respectively) — this stage renders plain text
/// and keeps everything in memory via `ChatCoordinator`.
struct ConversationDetailView: View {
    let conversation: Conversation
    var viewModel: AppViewModel
    var coordinator: ChatCoordinator

    @State private var draftText = ""
    @State private var pendingServiceSwitchModel: ModelInfo?

    var body: some View {
        VStack(spacing: 0) {
            TranscriptView(messages: coordinator.messages(for: conversation.id))

            Divider()

            ComposerView(
                text: $draftText,
                isGenerating: isGeneratingHere,
                canSend: canSend,
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
            }
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
                    coordinator.send(text: draftText, in: conversation.id, using: model)
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
        coordinator.send(text: draftText, in: conversation.id, using: model)
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
