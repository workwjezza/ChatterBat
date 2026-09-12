import SwiftUI

/// Top-level split-view shell.
///
/// Sidebar shows the (currently in-memory/demo) conversation list. The
/// detail pane hosts real streaming chat as of Stage 3, backed by the
/// shared `ChatCoordinator` in `dependencies`. The model picker (⌘K)
/// fetches live/cached Venice and OpenRouter catalogs and lets the user
/// choose a model for the next message.
struct RootView: View {
    let dependencies: AppDependencies
    @State private var viewModel: AppViewModel
    @State private var modelCatalog: ModelPickerViewModel
    @State private var isOnboardingPresented: Bool
    @State private var isSettingsPresented = false
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        // Attaches the repository plus the conversation list that
        // AppDependencies.live() already fetched synchronously before
        // any view existed — this init never itself calls SwiftData.
        // See AppViewModel.attachRepository's doc comment and
        // docs/DECISIONS.md for why the fetch cannot safely happen here
        // or in any later view lifecycle hook on this toolchain.
        let viewModel = AppViewModel(selectionDefaultsStore: dependencies.modelSelectionDefaultsStore)
        viewModel.busyConversationIDs = { dependencies.chatCoordinator.busyConversationIDs }
        let catalog = dependencies.makeModelPickerViewModel()
        viewModel.attachSelectionCatalog(catalog)
        viewModel.attachRepository(dependencies.conversationRepository, initialConversations: dependencies.initialConversations)
        _viewModel = State(initialValue: viewModel)
        _modelCatalog = State(initialValue: catalog)
        _isOnboardingPresented = State(initialValue: !dependencies.onboardingStateStore.hasCompletedOnboarding())
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel, coordinator: dependencies.chatCoordinator)
        } detail: {
            if let conversation = viewModel.selectedConversation {
                ConversationDetailView(
                    conversation: conversation,
                    viewModel: viewModel,
                    session: viewModel.currentSession,
                    coordinator: dependencies.chatCoordinator,
                    modelCatalog: modelCatalog
                )
                .id(conversation.id)
            } else {
                VStack(spacing: 0) {
                    ModelBookmarkBar(viewModel: viewModel, catalog: modelCatalog,
                                      isBusy: false)
                    ContentUnavailableView(
                        "No Conversation Selected",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Choose a conversation from the sidebar, or start a new one.")
                    )
                }
            }
        }
        .sheet(isPresented: $viewModel.isModelPickerPresented) {
            let targetConversationID = viewModel.selectedConversationID
            ModelPickerView(viewModel: modelCatalog) { model in
                guard viewModel.selectedConversationID == targetConversationID else { return }
                viewModel.selectCurrentModel(model, isBusy: targetConversationID.map { dependencies.chatCoordinator.isBusy($0) } ?? false)
            }
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingView(
                onOpenSettings: { openAccountSettings() },
                onDismiss: {
                    dependencies.onboardingStateStore.markOnboardingCompleted()
                    isOnboardingPresented = false
                }
            )
        }
        #if os(iOS)
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView(dependencies: dependencies)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isSettingsPresented = false }
                        }
                    }
            }
        }
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { isSettingsPresented = true }
                    .accessibilityLabel("Settings")
            }
            #endif
        }
        .navigationTitle(viewModel.selectedConversation?.title ?? "ChatterBat")
        .onChange(of: modelCatalog.catalogStates) { _, _ in
            viewModel.resolveSavedSelection()
        }
        .onChange(of: dependencies.chatCoordinator.transcripts) { old, new in
            // Update metadata for background chats too, not just the detail
            // currently visible. Session configuration remains untouched.
            let changed = Set(new.keys.filter { old[$0] != new[$0] })
            viewModel.refreshConversationMetadata(conversationIDs: changed)
        }
        .onChange(of: dependencies.chatCoordinator.generationStates) { _, _ in
            viewModel.resolveSavedSelection()
        }
    }

    private func openAccountSettings() {
        #if os(macOS)
        openSettings()
        #else
        isSettingsPresented = true
        #endif
    }
}

#Preview("Root — Demo Data") {
    let store = PreviewOnlyStore()
    RootView(
        dependencies: AppDependencies(
            credentialStore: store,
            veniceChecker: PreviewOnlyChecker(service: .venice),
            openRouterChecker: PreviewOnlyChecker(service: .openRouter),
            veniceCatalogFetcher: PreviewOnlyFetcher(service: .venice),
            openRouterCatalogFetcher: PreviewOnlyFetcher(service: .openRouter),
            modelPreferencesStore: PreviewOnlyPreferences(),
            veniceChatClient: PreviewOnlyChatClient(service: .venice),
            openRouterChatClient: PreviewOnlyChatClient(service: .openRouter),
            chatCoordinator: ChatCoordinator(
                credentialStore: store,
                clients: [
                    .venice: PreviewOnlyChatClient(service: .venice),
                    .openRouter: PreviewOnlyChatClient(service: .openRouter)
                ]
            ),
            conversationRepository: PreviewOnlyRepository(),
            initialConversations: DemoFixtures.conversations,
            onboardingStateStore: PreviewOnlyOnboardingStore()
        )
    )
}

/// Preview-only doubles. Never referenced by `AppDependencies.live()` or
/// any production path — previews must not touch the real Keychain or
/// network.
private struct PreviewOnlyStore: CredentialStore {
    func saveKey(_ key: String, for service: AIService) throws {}
    func loadKey(for service: AIService) throws -> String? { nil }
    func deleteKey(for service: AIService) throws {}
}

private struct PreviewOnlyChecker: ConnectionChecking {
    let service: AIService
    func checkConnection(apiKey: String) async -> ConnectionCheckOutcome { .valid(summary: "preview") }
}

private struct PreviewOnlyFetcher: ModelCatalogFetching {
    let service: AIService
    func fetchModels(apiKey: String) async -> ModelCatalogFetchOutcome { .success([]) }
}

private final class PreviewOnlyPreferences: ModelPreferencesStore {
    func favoriteIdentities() -> Set<ModelIdentity> { [] }
    func setFavorite(_ identity: ModelIdentity, isFavorite: Bool) {}
    func recentIdentities() -> [ModelIdentity] { [] }
    func recordUsed(_ identity: ModelIdentity) {}
}

private struct PreviewOnlyChatClient: ChatStreamingClient {
    let service: AIService
    func streamChatCompletion(
        apiKey: String,
        modelID: String,
        messages: [OutgoingChatMessage],
        settings: AdvancedChatSettings,
        tools: [AgentTool]
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@MainActor
private final class PreviewOnlyRepository: ConversationRepository {
    func loadAllConversations() throws -> [Conversation] { DemoFixtures.conversations }
    func loadMessages(for conversationID: UUID) throws -> [TranscriptMessage] { [] }
    func createConversation(title: String) throws -> Conversation { Conversation(title: title) }
    func rename(conversationID: UUID, to newTitle: String) throws {}
    func deleteConversation(conversationID: UUID) throws {}
    func appendMessage(_ message: TranscriptMessage, toConversation conversationID: UUID) throws {}
    func updateMessage(_ message: TranscriptMessage, inConversation conversationID: UUID) throws {}
    func deleteMessage(_ messageID: UUID, fromConversation conversationID: UUID) throws {}
    func interruptAllStreamingMessages() throws {}
    func contextBoundaryMessageID(for conversationID: UUID) throws -> UUID? { nil }
    func setContextBoundary(_ messageID: UUID?, forConversation conversationID: UUID) throws {}
}

private final class PreviewOnlyOnboardingStore: OnboardingStateStore {
    func hasCompletedOnboarding() -> Bool { false }
    func markOnboardingCompleted() {}
}
