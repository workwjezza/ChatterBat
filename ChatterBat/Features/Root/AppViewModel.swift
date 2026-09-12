import Foundation
import Observation

/// Root presentation state for the conversation list.
///
/// As of Stage 4, this is backed by a real `ConversationRepository`
/// (SwiftData) rather than in-memory-only state. The `conversations:`
/// initializer parameter is retained only for previews/tests that want
/// to seed state without touching a repository at all; production code
/// always goes through `loadFromRepository()`.
@Observable
@MainActor
final class AppViewModel {
    private(set) var conversations: [Conversation]
    var selectedConversationID: Conversation.ID? {
        didSet {
            guard selectedConversationID != oldValue else { return }
            activateSelectedSession()
            isModelPickerPresented = false
        }
    }
    var isModelPickerPresented = false
    var searchText = ""

    private var sessions: [UUID: ConversationSessionState] = [:]
    /// The no-conversation surface can configure defaults without owning a chat.
    private let setupSession = ConversationSessionState()
    private(set) var currentSession = ConversationSessionState()

    // Selection actions operate on the active session. Detail views bind to
    // the captured session object directly, never through a switching proxy.
    var selectedModel: ModelInfo? {
        get { currentSession.selectedModel }
        set {
            currentSession.selectedModel = newValue
            currentSession.selectedIdentity = newValue?.identity
        }
    }
    var advancedChatSettings: AdvancedChatSettings {
        get { currentSession.advancedChatSettings }
        set { currentSession.advancedChatSettings = newValue }
    }
    var agentToolsEnabled: Bool {
        get { currentSession.agentToolsEnabled }
        set { currentSession.agentToolsEnabled = newValue }
    }
    var autoModeEnabled: Bool {
        get { currentSession.autoModeEnabled }
        set { currentSession.autoModeEnabled = newValue }
    }
    private(set) var modelDefaults: ModelSelectionDefaults
    var selectionNotice: String? {
        get { currentSession.selectionNotice }
        set { currentSession.selectionNotice = newValue }
    }
    private let selectionDefaultsStore: ModelSelectionDefaultsStore?
    private var selectionCatalog: ModelPickerViewModel?
    private var restoringDefault: Bool {
        get { currentSession.resolvesSelectionFromCatalog }
        set { currentSession.resolvesSelectionFromCatalog = newValue }
    }
    /// Prevent deletion while the coordinator still owns writes/approvals.
    var activeConversationID: () -> UUID? = { nil }
    var busyConversationIDs: () -> Set<UUID> = { [] }

    func canDelete(_ conversation: Conversation) -> Bool {
        activeConversationID() != conversation.id && !busyConversationIDs().contains(conversation.id)
    }

    private func activateSelectedSession() {
        guard let id = selectedConversationID else {
            currentSession = setupSession
            return
        }
        if let existing = sessions[id] {
            currentSession = existing
        } else {
            let session = makeSession()
            sessions[id] = session
            currentSession = session
        }
    }

    private func makeSession() -> ConversationSessionState {
        let session = ConversationSessionState()
        guard selectionCatalog != nil else { return session }
        session.autoPolicy = modelDefaults.autoPolicy
        session.autoModeEnabled = modelDefaults.pinnedModel == nil
        session.selectedIdentity = modelDefaults.pinnedModel
        session.resolvesSelectionFromCatalog = true
        resolveSelection(in: session)
        return session
    }

    private func registerConversationSessions() {
        for conversation in conversations where sessions[conversation.id] == nil {
            sessions[conversation.id] = makeSession()
        }
        activateSelectedSession()
    }

    func attachSelectionCatalog(_ catalog: ModelPickerViewModel) {
        selectionCatalog = catalog
        applyNewChatDefault()
        registerConversationSessions()
    }

    /// Called after an explicit catalog refresh; never causes network activity.
    func resolveSavedSelection() {
        // Resolve each session's own identity/policy, never reapply a newer
        // global default to previously created chats. Skip the running chat.
        for session in Array(sessions.filter { $0.key != activeConversationID() && !busyConversationIDs().contains($0.key) }.values) + [setupSession] {
            resolveSelection(in: session)
        }
    }

    private func resolveSelection(in session: ConversationSessionState) {
        guard session.resolvesSelectionFromCatalog || session.autoModeEnabled else { return }
        let identity = session.autoModeEnabled ? session.autoPolicy?.anchor : session.selectedIdentity
        session.selectedModel = identity.flatMap { selectionCatalog?.currentModel($0) }
        if session.autoModeEnabled && session.autoPolicy == nil {
            session.selectionNotice = "Auto needs setup: choose a model, then click Save Auto policy."
        } else if session.selectedModel == nil {
            session.selectionNotice = "This chat's model is unavailable. Refresh models or choose another model; no fallback will be sent."
        } else {
            session.selectionNotice = nil
        }
    }

    func selectCurrentModel(_ model: ModelInfo, isBusy: Bool) {
        guard !isBusy else { return }
        restoringDefault = false
        selectedModel = model
        autoModeEnabled = false
        selectionNotice = nil
    }

    func togglePinnedDefault(_ identity: ModelIdentity, isBusy: Bool) {
        guard !isBusy, let catalog = selectionCatalog else { return }
        if modelDefaults.pinnedModel == identity {
            modelDefaults.pinnedModel = nil
        } else {
            guard catalog.isFavorite(identity), let model = catalog.currentModel(identity) else {
                selectionNotice = "Refresh models before pinning this favorite. No fallback was selected."
                return
            }
            modelDefaults.pinnedModel = model.identity
            catalog.recordSelection(identity)
        }
        selectionDefaultsStore?.save(modelDefaults)
        applyNewChatDefault()
    }

    func useAutoDefault(isBusy: Bool) {
        guard !isBusy else { return }
        modelDefaults.pinnedModel = nil
        selectionDefaultsStore?.save(modelDefaults)
        applyNewChatDefault()
    }

    /// Explicit action; pinning or catalog updates never replace this consent.
    func saveAutoPolicyFromCurrentModel(isBusy: Bool) {
        guard !isBusy else { return }
        guard let selectedModel,
              let current = selectionCatalog?.currentModel(selectedModel.identity),
              let policy = SavedAutoPolicy(model: current, settings: advancedChatSettings) else {
            selectionNotice = "Choose a current, directly selectable model with known prices, then save its Auto policy."
            return
        }
        modelDefaults.autoPolicy = policy
        modelDefaults.pinnedModel = nil
        selectionDefaultsStore?.save(modelDefaults)
        applyNewChatDefault()
    }

    func setCurrentAutoEnabled(_ enabled: Bool, isBusy: Bool) {
        guard !isBusy else { return }
        restoringDefault = false
        autoModeEnabled = enabled
        selectionNotice = nil
        if enabled {
            selectedModel = currentSession.autoPolicy.flatMap { selectionCatalog?.currentModel($0.anchor) }
            if currentSession.autoPolicy == nil {
                selectionNotice = "Auto needs setup: choose a model, then click Save Auto policy."
            }
        }
    }

    var effectiveChatSettings: AdvancedChatSettings {
        currentSession.effectiveChatSettings
    }

    private func applyNewChatDefault() {
        restoringDefault = true
        selectionNotice = nil
        currentSession.autoPolicy = modelDefaults.autoPolicy
        if let pin = modelDefaults.pinnedModel {
            autoModeEnabled = false
            selectedModel = selectionCatalog?.currentModel(pin)
            currentSession.selectedIdentity = pin
            if selectedModel == nil {
                selectionNotice = "Saved default \(pin.modelID) · \(pin.service.displayName) is unavailable. Refresh models or choose another model; no fallback will be sent."
            }
        } else {
            autoModeEnabled = true
            selectedModel = modelDefaults.autoPolicy.flatMap { selectionCatalog?.currentModel($0.anchor) }
            if modelDefaults.autoPolicy == nil {
                selectionNotice = "Auto needs setup: choose a model, then click Save Auto policy."
            } else if selectedModel == nil {
                selectionNotice = "Refresh models to resolve the saved Auto anchor."
            }
        }
    }

    /// The tools to actually offer on the next send: every defined
    /// `AgentTool` when the toggle is on, otherwise none. `ChatCoordinator.send`
    /// still separately gates this on `model.supportsTools == .supported`
    /// — this computed property only reflects the user's own
    /// intent, not model capability.
    var toolsToOffer: [AgentTool] {
        agentToolsEnabled ? AgentTool.allCases : []
    }

    /// `nil` until `loadFromRepository()` runs (or in previews/tests that
    /// never call it), in which case conversation-list mutations stay
    /// in-memory-only — this lets existing previews/tests keep working
    /// unchanged.
    private var repository: ConversationRepository?

    init(conversations: [Conversation] = [], selectionDefaultsStore: ModelSelectionDefaultsStore? = nil) {
        self.selectionDefaultsStore = selectionDefaultsStore
        self.modelDefaults = selectionDefaultsStore?.load() ?? ModelSelectionDefaults()
        self.conversations = conversations
        self.selectedConversationID = conversations.first?.id
        activateSelectedSession()
    }

    /// Loads persisted conversations (most-recently-updated first) and
    /// selects the most recent one, if any. Call once at launch, after
    /// the repository has already run `interruptAllStreamingMessages()`
    /// (see `ChatCoordinator.loadPersistedState`), so the list never
    /// briefly shows a message as still "streaming."
    ///
    /// NOTE: prefer `attachRepository(_:initialConversations:)` in
    /// production — see its doc comment for why the initial fetch is
    /// deliberately done outside this method's caller (a SwiftUI view)
    /// on this toolchain.
    func loadFromRepository(_ repository: ConversationRepository) {
        self.repository = repository
        do {
            conversations = try repository.loadAllConversations()
            selectedConversationID = conversations.first?.id
            registerConversationSessions()
        } catch {
            // A load failure must not be silently treated as "no
            // conversations yet" — that would look identical to a
            // legitimately empty history to the user. Since Stage 4 has
            // no dedicated error-banner UI, this is surfaced honestly via
            // assertionFailure in debug builds; Stage 5+ should add a
            // visible error state for this path.
            assertionFailure("Failed to load conversations: \(error)")
            conversations = []
        }
    }

    /// Attaches a repository for future writes (create/rename/delete)
    /// using conversations that were *already fetched* by the caller —
    /// this view model never itself calls `loadAllConversations()` in
    /// this path.
    ///
    /// Why this exists as a separate method from `loadFromRepository`:
    /// on this toolchain, calling `ModelContext.fetch` from within a
    /// SwiftUI view's `init`, `.task {}`, or `.onAppear` (even deferred
    /// via `DispatchQueue.main.async`) reproducibly crashed the app at
    /// launch (EXC_BREAKPOINT inside AppKit's window-restoration
    /// re-entrancy — see docs/DECISIONS.md). The one place that never
    /// crashed was a plain synchronous call made before any SwiftUI view
    /// exists at all, i.e. inside `AppDependencies.live()`. So
    /// `AppDependencies.live()` performs the initial fetch and passes
    /// the result here.
    func attachRepository(_ repository: ConversationRepository, initialConversations: [Conversation]) {
        self.repository = repository
        conversations = initialConversations
        selectedConversationID = conversations.first?.id
        registerConversationSessions()
    }

    var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return conversations }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedConversation: Conversation? {
        conversations.first { $0.id == selectedConversationID }
    }

    /// Returns the stable in-memory session for a conversation without
    /// changing selection. Mobile navigation pushes a detail view instead of
    /// using the macOS split-view selection binding, so it needs this explicit
    /// lookup to preserve each chat's draft and model settings.
    func session(for conversationID: UUID) -> ConversationSessionState {
        if let existing = sessions[conversationID] { return existing }
        let session = makeSession()
        sessions[conversationID] = session
        return session
    }

    /// Creates a new conversation (persisted immediately if a repository
    /// is attached) and selects it.
    func startNewConversation() {
        if let repository {
            do {
                let conversation = try repository.createConversation(title: "New Chat")
                conversations.insert(conversation, at: 0)
                selectedConversationID = conversation.id
                return
            } catch {
                assertionFailure("Failed to create a new conversation: \(error)")
            }
        }
        let conversation = Conversation(title: "New Chat", updatedAt: .now)
        conversations.insert(conversation, at: 0)
        selectedConversationID = conversation.id
    }

    func delete(_ conversation: Conversation) {
        guard canDelete(conversation) else { return }
        if let repository {
            do {
                try repository.deleteConversation(conversationID: conversation.id)
            } catch {
                assertionFailure("Failed to delete conversation \(conversation.id): \(error)")
                return
            }
        }
        conversations.removeAll { $0.id == conversation.id }
        sessions[conversation.id]?.workspacePreview.disconnect()
        sessions[conversation.id] = nil
        if selectedConversationID == conversation.id {
            selectedConversationID = conversations.first?.id
        }
    }

    func rename(_ conversation: Conversation, to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else {
            return
        }
        if let repository {
            do {
                try repository.rename(conversationID: conversation.id, to: trimmed)
            } catch {
                assertionFailure("Failed to rename conversation \(conversation.id): \(error)")
                return
            }
        }
        conversations[index].title = trimmed
    }

    /// Errors specific to export/import, surfaced to the user via
    /// `exportError`/`importError` rather than an `assertionFailure` —
    /// unlike the repository-write failures above (which are treated
    /// as "should never realistically happen" internal-consistency
    /// bugs), a bad import file is an entirely expected, user-facing
    /// situation (wrong file picked, future/foreign format, corrupted
    /// download) that deserves a real, visible message.
    enum ExportImportError: Error, Equatable {
        case encodingFailed
        case decodingFailed
        case persistFailed
        case unsupportedSchemaVersion(Int)

        var userMessage: String {
            switch self {
            case .encodingFailed:
                return "Couldn't prepare this conversation for export."
            case .decodingFailed:
                return "This file isn't a ChatterBat conversation export."
            case .persistFailed:
                return "The file was read, but the imported conversation couldn't be saved."
            case .unsupportedSchemaVersion(let version):
                return "This file was exported by a newer version of ChatterBat (format \(version)) and can't be imported here."
            }
        }
    }

    private(set) var lastExportImportError: ExportImportError?

    /// Builds export data for `conversation`, using the repository's
    /// full transcript (not just whatever happens to be cached in
    /// `ChatCoordinator`'s in-memory `transcripts`, which this view
    /// model has no access to) so exporting a conversation that hasn't
    /// been opened this session still works.
    func exportData(for conversation: Conversation) -> Data? {
        lastExportImportError = nil
        guard let repository else { return nil }
        do {
            let messages = try repository.loadMessages(for: conversation.id)
            let export = ConversationExportCoding.export(conversation: conversation, messages: messages)
            return try ConversationExportCoding.encode(export)
        } catch {
            lastExportImportError = .encodingFailed
            return nil
        }
    }

    /// Imports `data` as a brand-new conversation (never overwriting or
    /// merging with an existing one — see
    /// `ConversationExportCoding.importAsNewConversation`), persists it
    /// through the repository if one is attached, and selects it.
    /// Returns `true` on success; on failure, `lastExportImportError`
    /// is set to a specific, user-presentable reason.
    @discardableResult
    func importConversation(from data: Data) -> Bool {
        lastExportImportError = nil
        let export: ConversationExport
        do {
            export = try ConversationExportCoding.decode(data)
        } catch let error as ConversationExportCoding.ImportError {
            if case .unsupportedSchemaVersion(let version) = error {
                lastExportImportError = .unsupportedSchemaVersion(version)
            }
            return false
        } catch {
            lastExportImportError = .decodingFailed
            return false
        }

        let (imported, messages) = ConversationExportCoding.importAsNewConversation(export)

        if let repository {
            do {
                let created = try repository.createConversation(title: imported.title)
                for message in messages {
                    try repository.appendMessage(message, toConversation: created.id)
                }
                conversations.insert(created, at: 0)
                selectedConversationID = created.id
                return true
            } catch {
                lastExportImportError = .persistFailed
                return false
            }
        }

        conversations.insert(imported, at: 0)
        selectedConversationID = imported.id
        return true
    }

    /// Refreshes one conversation's `lastMessagePreview`/`updatedAt` from
    /// the repository and re-sorts the list, most-recent first. Called
    /// by `RootView` after `ChatCoordinator` appends/updates a message so
    /// the sidebar reflects new activity without polling.
    func refreshConversationMetadata(conversationID: UUID) {
        refreshConversationMetadata(conversationIDs: [conversationID])
    }

    func refreshConversationMetadata(conversationIDs: Set<UUID>) {
        guard !conversationIDs.isEmpty else { return }
        guard let repository else { return }
        do {
            let updated = try repository.loadAllConversations().filter { conversationIDs.contains($0.id) }
            for conversation in updated {
                if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                    conversations[index] = conversation
                }
            }
            conversations.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            assertionFailure("Failed to refresh conversation metadata: \(error)")
        }
    }
}
