import Foundation
import Observation

#if os(macOS)

enum WorkspacePreviewPhase: String {
    case disconnected = "No workspace selected"
    case opening = "Opening workspace"
    case ready = "Ready — local only"
    case awaitingApproval = "Waiting for approval"
    case reading = "Reading locally"
    case stopping = "Stopping — waiting for filesystem"
    case completed = "Local preview ready"
    case failed = "Workspace operation failed"
}

/// Per-chat local-only control surface. No reference to providers, request
/// builders or transcript storage: a preview can never implicitly upload.
@Observable
@MainActor
final class WorkspacePreviewModel {
    let sessionID = UUID()
    private(set) var phase: WorkspacePreviewPhase = .disconnected
    private(set) var workspaceName: String?
    private(set) var result: WorkspaceReadResult?
    private(set) var errorMessage: String?
    private(set) var pendingProposal: WorkspaceActionProposal?
    private(set) var events: [String] = []
    var relativePath = "."
    private var scope: WorkspacePermissionScope?
    private var ticket: UUID?
    private let registry: WorkspaceReadRegistry
    private var operation: Task<Void, Never>?

    init(registry: WorkspaceReadRegistry = .previewShared) { self.registry = registry }

    var isBusy: Bool { operation != nil }
    var isConnected: Bool { scope != nil }

    func connect(to url: URL) {
        guard !isBusy else { return }
        disconnect()
        phase = .opening
        record("workspace.opening")
        operation = Task { [weak self, registry] in
            defer { self?.operation = nil }
            do {
                let scope = try await registry.registerForPreview(userSelectedRoot: url)
                guard let self, !Task.isCancelled else {
                    registry.revoke(workspaceID: scope.workspaceID)
                    return
                }
                try registry.bind(sessionID: self.sessionID, to: scope.workspaceID)
                self.scope = scope
                self.workspaceName = url.lastPathComponent
                self.relativePath = "."
                self.phase = .ready
                self.record("workspace.ready")
            } catch {
                self?.finishFailure(error)
            }
        }
    }

    func proposeRead(listDirectory: Bool) {
        guard !isBusy, pendingProposal == nil, let scope else { return }
        result = nil
        errorMessage = nil
        let action: WorkspaceProposedAction = listDirectory
            ? .listDirectory(relativePath: relativePath) : .readFile(relativePath: relativePath)
        let proposal = WorkspaceActionProposal(actionID: UUID(), sessionID: sessionID,
            workspaceID: scope.workspaceID, workspaceRevision: scope.revision, action: action)
        do {
            ticket = try registry.requestPreviewApproval(for: proposal)
            pendingProposal = proposal
            phase = .awaitingApproval
            record("approval.required")
        } catch { finishFailure(error) }
    }

    func decide(approve: Bool) {
        guard !isBusy, let proposal = pendingProposal, let ticket else { return }
        pendingProposal = nil
        self.ticket = nil
        guard registry.resolveApproval(ticket, approve: approve) else {
            finishFailure(WorkspaceReadError.approvalRequired)
            return
        }
        record(approve ? "approval.approved" : "approval.denied")
        guard approve else { phase = .ready; return }
        phase = .reading
        operation = Task { [weak self, registry] in
            defer { self?.operation = nil }
            do {
                let result = try await registry.executePreview(proposal, ticket: ticket)
                guard let self, !Task.isCancelled else { return }
                self.result = result
                self.phase = .completed
                self.record("read.completed")
            } catch { self?.finishFailure(error) }
        }
    }

    func stop() {
        if pendingProposal != nil { decide(approve: false) }
        guard isBusy else { return }
        operation?.cancel()
        phase = .stopping
        result = nil
        record("operation.cancelled")
    }

    /// Called on explicit disconnect and chat deletion. Revocation is immediate
    /// on MainActor; any outstanding worker result is discarded on return.
    func disconnect() {
        operation?.cancel()
        registry.unbind(sessionID: sessionID)
        if let scope { registry.revoke(workspaceID: scope.workspaceID) }
        scope = nil
        workspaceName = nil
        ticket = nil
        pendingProposal = nil
        result = nil
        errorMessage = nil
        phase = isBusy ? .stopping : .disconnected
        record("workspace.disconnected")
    }

    private func finishFailure(_ error: Error) {
        if Task.isCancelled || error is CancellationError {
            phase = isConnected ? .ready : .disconnected
            result = nil
            return
        }
        phase = .failed
        // Use only typed path-free descriptions; never localizedError from OS.
        if let failure = error as? WorkspaceReadError {
            errorMessage = "\(failure). Check the relative path, permissions and workspace. Reapprove to retry."
        } else {
            errorMessage = "Unable to read this workspace. No data was sent."
        }
        record("operation.failed")
    }

    private func record(_ event: String) {
        events.append(event)
        if events.count > 30 { events.removeFirst(events.count - 30) }
    }
}

#else

/// iOS does not expose the macOS local-workspace preview. This lightweight
/// state object keeps the shared per-conversation session model portable while
/// ensuring no workspace/filesystem feature is reachable in the iOS build.
@Observable
@MainActor
final class WorkspacePreviewModel {
    init() {}

    func disconnect() {}
}

#endif