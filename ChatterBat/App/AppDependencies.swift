import Foundation

/// Assembles the real (Keychain + URLSession) dependencies used by the
/// running app.
///
/// This is intentionally a small factory, not a general DI container, per
/// the brief's guidance against introducing heavyweight frameworks.
/// Tests bypass this entirely and construct view models directly with
/// fakes.
@MainActor
struct AppDependencies {
    let credentialStore: CredentialStore
    let veniceChecker: ConnectionChecking
    let openRouterChecker: ConnectionChecking
    let veniceCatalogFetcher: ModelCatalogFetching
    let openRouterCatalogFetcher: ModelCatalogFetching
    let modelPreferencesStore: ModelPreferencesStore
    let veniceChatClient: ChatStreamingClient
    let openRouterChatClient: ChatStreamingClient
    /// One shared `ChatCoordinator` for the whole app's lifetime — it
    /// owns in-memory transcripts and the single global generation slot,
    /// so it must not be recreated per-view.
    let chatCoordinator: ChatCoordinator
    /// One shared repository, backed by the app's real on-disk SwiftData
    /// store. `AppViewModel` and `ChatCoordinator` both read/write
    /// through this same instance so their views of persisted state
    /// never diverge.
    let conversationRepository: ConversationRepository
    /// The conversation list, already fetched synchronously during
    /// `live()` — see `AppViewModel.attachRepository` for why this
    /// fetch must not happen from inside a SwiftUI view on this
    /// toolchain.
    let initialConversations: [Conversation]
    let onboardingStateStore: OnboardingStateStore

    static func live() -> AppDependencies {
        let credentialStore = KeychainCredentialStore()
        let veniceChecker = VeniceConnectionChecker(
            httpClient: URLSessionHTTPClient(allowedHost: AIService.venice.apiHost)
        )
        let openRouterChecker = OpenRouterConnectionChecker(
            httpClient: URLSessionHTTPClient(allowedHost: AIService.openRouter.apiHost)
        )
        let veniceCatalogFetcher = VeniceModelCatalogFetcher(
            httpClient: URLSessionHTTPClient(allowedHost: AIService.venice.apiHost)
        )
        let openRouterCatalogFetcher = OpenRouterModelCatalogFetcher(
            httpClient: URLSessionHTTPClient(allowedHost: AIService.openRouter.apiHost)
        )
        let veniceChatClient = StandardChatStreamingClient(
            service: .venice,
            httpClient: URLSessionStreamingHTTPClient(allowedHost: AIService.venice.apiHost),
            endpointURL: URL(string: "https://api.venice.ai/api/v1/chat/completions")!
        )
        let openRouterChatClient = StandardChatStreamingClient(
            service: .openRouter,
            httpClient: URLSessionStreamingHTTPClient(allowedHost: AIService.openRouter.apiHost),
            endpointURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        )
        let container = ChatterBatModelContainer.live()
        let repository = SwiftDataConversationRepository(context: container.mainContext)
        let chatCoordinator = ChatCoordinator(
            credentialStore: credentialStore,
            clients: [.venice: veniceChatClient, .openRouter: openRouterChatClient],
            repository: repository
        )
        // Run interrupted-generation recovery, and the initial
        // conversation-list fetch, synchronously here — before any
        // SwiftUI view exists — rather than from a view's `init`,
        // `.task {}`, or `.onAppear`. See docs/DECISIONS.md: calling
        // SwiftData's `ModelContext.fetch` from any of those view
        // lifecycle points reproducibly crashed the app at launch
        // (EXC_BREAKPOINT during AppKit's window-restoration
        // re-entrancy) on this toolchain, while the same fetch called
        // synchronously here, before `ChatterBatApp.body` is even
        // evaluated, never did.
        chatCoordinator.markInterruptedGenerationsAtLaunch()
        let initialConversations = (try? repository.loadAllConversations()) ?? []
        return AppDependencies(
            credentialStore: credentialStore,
            veniceChecker: veniceChecker,
            openRouterChecker: openRouterChecker,
            veniceCatalogFetcher: veniceCatalogFetcher,
            openRouterCatalogFetcher: openRouterCatalogFetcher,
            modelPreferencesStore: UserDefaultsModelPreferencesStore(),
            veniceChatClient: veniceChatClient,
            openRouterChatClient: openRouterChatClient,
            chatCoordinator: chatCoordinator,
            conversationRepository: repository,
            initialConversations: initialConversations,
            onboardingStateStore: UserDefaultsOnboardingStateStore()
        )
    }

    func makeAccountSettingsViewModel() -> AccountSettingsViewModel {
        AccountSettingsViewModel(
            credentialStore: credentialStore,
            checkers: [
                .venice: veniceChecker,
                .openRouter: openRouterChecker
            ]
        )
    }

    func makeModelPickerViewModel() -> ModelPickerViewModel {
        ModelPickerViewModel(
            credentialStore: credentialStore,
            fetchers: [
                .venice: veniceCatalogFetcher,
                .openRouter: openRouterCatalogFetcher
            ],
            preferencesStore: modelPreferencesStore
        )
    }
}
