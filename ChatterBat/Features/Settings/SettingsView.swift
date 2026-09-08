import SwiftUI

/// Native Settings scene.
///
/// General shows app version. Accounts (added in Stage 1) hosts
/// Keychain-backed Venice/OpenRouter key entry, verification, and
/// disconnect. No base-URL or other developer-facing fields are exposed
/// here, per the brief.
struct SettingsView: View {
    let dependencies: AppDependencies

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            AccountsSettingsView(viewModel: dependencies.makeAccountSettingsViewModel())
                .tabItem {
                    Label("Accounts", systemImage: "person.badge.key")
                }
        }
        .frame(width: 480, height: 420)
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersionString)
            }
            Section {
                Text("Connect your Venice and OpenRouter accounts in the Accounts tab.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .padding(20)
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    // Uses in-memory fakes, not `.live()` — previews must never touch the
    // real Keychain or network.
    let store = PreviewOnlyCredentialStore()
    let veniceChat = PreviewOnlyChatClient(service: .venice)
    let openRouterChat = PreviewOnlyChatClient(service: .openRouter)
    SettingsView(
        dependencies: AppDependencies(
            credentialStore: store,
            veniceChecker: PreviewOnlyConnectionChecker(service: .venice),
            openRouterChecker: PreviewOnlyConnectionChecker(service: .openRouter),
            veniceCatalogFetcher: PreviewOnlyCatalogFetcher(service: .venice),
            openRouterCatalogFetcher: PreviewOnlyCatalogFetcher(service: .openRouter),
            modelPreferencesStore: PreviewOnlyPreferencesStore(),
            veniceChatClient: veniceChat,
            openRouterChatClient: openRouterChat,
            chatCoordinator: ChatCoordinator(
                credentialStore: store,
                clients: [.venice: veniceChat, .openRouter: openRouterChat]
            ),
            conversationRepository: PreviewOnlyRepository(),
            initialConversations: [],
            onboardingStateStore: PreviewOnlyOnboardingStore()
        )
    )
}

/// In-memory, no-op doubles used only by SwiftUI previews in this file.
/// Never referenced from `AppDependencies.live()` or any production path.
private struct PreviewOnlyCredentialStore: CredentialStore {
    func saveKey(_ key: String, for service: AIService) throws {}
    func loadKey(for service: AIService) throws -> String? { nil }
    func deleteKey(for service: AIService) throws {}
}

private struct PreviewOnlyConnectionChecker: ConnectionChecking {
    let service: AIService
    func checkConnection(apiKey: String) async -> ConnectionCheckOutcome {
        .valid(summary: "Connected (preview)")
    }
}

private struct PreviewOnlyCatalogFetcher: ModelCatalogFetching {
    let service: AIService
    func fetchModels(apiKey: String) async -> ModelCatalogFetchOutcome { .success([]) }
}

private final class PreviewOnlyPreferencesStore: ModelPreferencesStore {
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
        settings: AdvancedChatSettings
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

@MainActor
private final class PreviewOnlyRepository: ConversationRepository {
    func loadAllConversations() throws -> [Conversation] { [] }
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
    func hasCompletedOnboarding() -> Bool { true }
    func markOnboardingCompleted() {}
}
