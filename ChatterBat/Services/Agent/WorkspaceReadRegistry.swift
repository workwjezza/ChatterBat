import Foundation

/// In-process prototype boundary. Only trusted human setup may register a
/// root/bind a session/resolve approval. Not an authenticated host interface.
/// Local preview integration only; no persistent grants, writes or upload.
@MainActor
final class WorkspaceReadRegistry {
    static let previewShared = WorkspaceReadRegistry()
    private struct Entry {
        let root: WorkspaceReadAccess.Root
        var scope: WorkspacePermissionScope
        var lease: WorkspaceSecurityLease? = nil
    }
    private var entries: [UUID: Entry] = [:]
    private var sessions: [UUID: UUID] = [:]
    private var bindingGenerations: [UUID: UUID] = [:]
    private let approvals: WorkspaceApprovalLedger
    private let worker: any WorkspaceReadWorking
    private var pendingRegistrations = 0
    private var pendingReads: Set<UUID> = []

    init(approvals: WorkspaceApprovalLedger = WorkspaceApprovalLedger(), worker: any WorkspaceReadWorking = WorkspaceReadWorker.shared) {
        self.approvals = approvals
        self.worker = worker
    }

    func register(userSelectedRoot: URL) throws -> WorkspacePermissionScope {
        guard entries.count + pendingRegistrations < 32 else { throw WorkspaceReadError.registryFull }
        let root = try WorkspaceReadAccess.openRoot(userSelectedRoot)
        let scope = WorkspacePermissionScope(workspaceID: UUID(), revision: 1)
        entries[scope.workspaceID] = Entry(root: root, scope: scope)
        return scope
    }

    /// UI path: retain OS access while awaiting the worker. No root is
    /// registered if the calling task is cancelled before the worker returns.
    func registerForPreview(userSelectedRoot: URL) async throws -> WorkspacePermissionScope {
        guard entries.count + pendingRegistrations < 32 else { throw WorkspaceReadError.registryFull }
        pendingRegistrations += 1
        defer { pendingRegistrations -= 1 }
        let lease = WorkspaceSecurityLease(url: userSelectedRoot)
        let root = try await worker.openRoot(lease.url)
        try Task.checkCancellation()
        let scope = WorkspacePermissionScope(workspaceID: UUID(), revision: 1)
        entries[scope.workspaceID] = Entry(root: root, scope: scope, lease: lease)
        return scope
    }

    func bind(sessionID: UUID, to workspaceID: UUID) throws {
        guard entries[workspaceID] != nil else { throw WorkspaceReadError.unknownWorkspace }
        approvals.cancel(sessionID: sessionID)
        sessions[sessionID] = workspaceID
        bindingGenerations[sessionID] = UUID()
    }

    func unbind(sessionID: UUID) {
        sessions[sessionID] = nil
        bindingGenerations[sessionID] = nil
        approvals.cancel(sessionID: sessionID)
    }

    func revoke(workspaceID: UUID) {
        entries[workspaceID] = nil // closes root FD when no synchronous read owns it
        for session in sessions where session.value == workspaceID { bindingGenerations[session.key] = nil }
        sessions = sessions.filter { $0.value != workspaceID }
        approvals.revoke(workspaceID: workspaceID)
    }

    /// Re-registration gets a fresh identity; revision change invalidates
    /// proposals without changing the authorized root or widening read access.
    func invalidateApprovals(workspaceID: UUID) throws -> WorkspacePermissionScope {
        guard var entry = entries[workspaceID] else { throw WorkspaceReadError.unknownWorkspace }
        guard entry.scope.revision < UInt64.max else {
            revoke(workspaceID: workspaceID)
            throw WorkspaceReadError.revokedWorkspace
        }
        entry.scope = WorkspacePermissionScope(workspaceID: workspaceID, revision: entry.scope.revision + 1)
        entries[workspaceID] = entry
        approvals.revoke(workspaceID: workspaceID)
        return entry.scope
    }

    func requestApproval(for proposal: WorkspaceActionProposal) throws -> UUID {
        let entry = try authorizedEntry(for: proposal)
        guard proposal.action.isReadOnly else { throw WorkspaceReadError.unsupportedAction }
        try WorkspaceReadAccess.validateRoot(entry.root)
        guard let ticket = approvals.request(proposal, scope: entry.scope) else { throw WorkspaceReadError.approvalRequired }
        return ticket
    }

    /// Approval presentation must not perform filesystem I/O on the UI actor.
    /// Root/path validation occurs in the worker only after consumption.
    func requestPreviewApproval(for proposal: WorkspaceActionProposal) throws -> UUID {
        let entry = try authorizedEntry(for: proposal)
        guard proposal.action.isReadOnly else { throw WorkspaceReadError.unsupportedAction }
        guard let ticket = approvals.request(proposal, scope: entry.scope) else { throw WorkspaceReadError.approvalRequired }
        return ticket
    }

    @discardableResult
    func resolveApproval(_ ticket: UUID, approve: Bool) -> Bool {
        approvals.resolve(ticket, approve: approve)
    }

    /// Bounded synchronous prototype: no awaits between host-scope validation,
    /// consumption and I/O, so same-actor revocation cannot interleave. This
    /// is not a hard I/O timeout; do not wire slow/network filesystems to UI.
    func execute(_ proposal: WorkspaceActionProposal, ticket: UUID) throws -> WorkspaceReadResult {
        if Task.isCancelled { approvals.cancel(sessionID: proposal.sessionID) }
        try Task.checkCancellation()
        let entry = try authorizedEntry(for: proposal)
        guard approvals.consume(ticket, for: proposal, scope: entry.scope) else { throw WorkspaceReadError.approvalRequired }
        switch proposal.action {
        case .readFile(let path): return try WorkspaceReadAccess.read(path, root: entry.root)
        case .listDirectory(let path): return try WorkspaceReadAccess.list(path, root: entry.root)
        default: throw WorkspaceReadError.unsupportedAction
        }
    }

    func executePreview(_ proposal: WorkspaceActionProposal, ticket: UUID) async throws -> WorkspaceReadResult {
        if Task.isCancelled { approvals.cancel(sessionID: proposal.sessionID) }
        try Task.checkCancellation()
        guard !pendingReads.contains(proposal.sessionID), pendingReads.count < 4 else { throw WorkspaceReadError.registryFull }
        let entry = try authorizedEntry(for: proposal)
        guard approvals.consume(ticket, for: proposal, scope: entry.scope) else { throw WorkspaceReadError.approvalRequired }
        pendingReads.insert(proposal.sessionID)
        let bindingGeneration = bindingGenerations[proposal.sessionID]
        defer { pendingReads.remove(proposal.sessionID) }
        // Keep the lease alive across revoke/unbind while the worker is using
        // the handle, then suppress the result if authority changed.
        defer { withExtendedLifetime(entry.lease) {} }
        let result = try await worker.execute(proposal.action, root: entry.root)
        try Task.checkCancellation()
        let current = try authorizedEntry(for: proposal)
        guard current.scope == entry.scope,
              bindingGenerations[proposal.sessionID] == bindingGeneration else { throw WorkspaceReadError.revokedWorkspace }
        return result
    }

    private func authorizedEntry(for proposal: WorkspaceActionProposal) throws -> Entry {
        guard let entry = entries[proposal.workspaceID] else { throw WorkspaceReadError.unknownWorkspace }
        guard sessions[proposal.sessionID] == proposal.workspaceID else { throw WorkspaceReadError.unboundSession }
        guard WorkspacePermissionPolicy.evaluate(proposal, in: entry.scope) == .requiresApproval else {
            throw WorkspaceReadError.approvalRequired
        }
        return entry
    }
}