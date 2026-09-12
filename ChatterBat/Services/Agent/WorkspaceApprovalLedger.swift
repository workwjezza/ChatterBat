import Foundation

/// Host-local, in-memory single-use approvals. This is NOT authentication or
/// a wire protocol. Only a future authenticated human-control boundary may
/// call resolve; neither model tool output nor a caller-supplied boolean is
/// sufficient proof of consent. Nothing here executes an action.
@MainActor
final class WorkspaceApprovalLedger {
    private enum State { case pending, approved }
    private struct Entry {
        let proposal: WorkspaceActionProposal
        let issuedAt: Date
        let expiresAt: Date
        var state: State = .pending
    }
    private var entries: [UUID: Entry] = [:]
    private let now: () -> Date
    private let capacity: Int
    private var lastObservedTime: Date?

    init(capacity: Int = 128, now: @escaping () -> Date = Date.init) {
        self.capacity = max(1, min(1024, capacity))
        self.now = now
    }

    /// Opaque ticket is scoped to the exact immutable proposal and expires
    /// in at most five minutes. Caller must render that proposal for review.
    func request(_ proposal: WorkspaceActionProposal, scope: WorkspacePermissionScope,
                 lifetime: TimeInterval = 120) -> UUID? {
        guard lifetime.isFinite, lifetime > 0, lifetime <= 300,
              WorkspacePermissionPolicy.evaluate(proposal, in: scope) == .requiresApproval else { return nil }
        let timestamp = now()
        prune(at: timestamp)
        guard entries.count < capacity,
              !entries.values.contains(where: { $0.proposal.actionID == proposal.actionID }) else { return nil }
        let ticket = UUID()
        entries[ticket] = Entry(proposal: proposal, issuedAt: timestamp,
                                expiresAt: timestamp.addingTimeInterval(lifetime))
        return ticket
    }

    /// Only the first human decision counts; denial removes the ticket.
    /// Repeated approval cannot renew expiry or revive a denial.
    @discardableResult
    func resolve(_ ticket: UUID, approve: Bool) -> Bool {
        prune(at: now())
        guard var entry = entries[ticket], entry.state == .pending else { return false }
        if approve {
            entry.state = .approved
            entries[ticket] = entry
        } else {
            entries[ticket] = nil
        }
        return true
    }

    /// Atomically consume before execution, rechecking current host scope.
    /// Mismatch burns an approved ticket. False must never execute/retry.
    /// An early attempt on a pending ticket also invalidates it (fail closed).
    func consume(_ ticket: UUID, for proposal: WorkspaceActionProposal,
                 scope: WorkspacePermissionScope) -> Bool {
        prune(at: now())
        guard let entry = entries.removeValue(forKey: ticket), entry.state == .approved,
              entry.proposal == proposal else { return false }
        return WorkspacePermissionPolicy.evaluate(proposal, in: scope) == .requiresApproval
    }

    func revoke(workspaceID: UUID) {
        entries = entries.filter { $0.value.proposal.workspaceID != workspaceID }
    }

    func cancel(sessionID: UUID) {
        entries = entries.filter { $0.value.proposal.sessionID != sessionID }
    }

    private func prune(at timestamp: Date) {
        // A backwards wall-clock jump fails closed rather than extending
        // previously issued consent. Persistent approval is not supported.
        if let lastObservedTime, timestamp < lastObservedTime { entries.removeAll() }
        lastObservedTime = timestamp
        entries = entries.filter { timestamp >= $0.value.issuedAt && timestamp < $0.value.expiresAt }
    }
}