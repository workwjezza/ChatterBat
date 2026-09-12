import Foundation

/// Injectable worker boundary. Actor implementation keeps blocking POSIX
/// operations off MainActor and serializes reads. Cancellation is cooperative,
/// not a guarantee that a filesystem syscall returns within a deadline.
protocol WorkspaceReadWorking: Sendable {
    func openRoot(_ url: URL) async throws -> WorkspaceReadAccess.Root
    func execute(_ action: WorkspaceProposedAction, root: WorkspaceReadAccess.Root) async throws -> WorkspaceReadResult
}

actor WorkspaceReadWorker: WorkspaceReadWorking {
    static let shared = WorkspaceReadWorker()

    func openRoot(_ url: URL) throws -> WorkspaceReadAccess.Root {
        try Task.checkCancellation()
        let root = try WorkspaceReadAccess.openRoot(url)
        try Task.checkCancellation()
        return root
    }

    func execute(_ action: WorkspaceProposedAction, root: WorkspaceReadAccess.Root) throws -> WorkspaceReadResult {
        try Task.checkCancellation()
        switch action {
        case .readFile(let path): return try WorkspaceReadAccess.read(path, root: root)
        case .listDirectory(let path): return try WorkspaceReadAccess.list(path, root: root)
        default: throw WorkspaceReadError.unsupportedAction
        }
    }
}

/// Retains the user-selected URL's sandbox extension until the last worker
/// reference is released, even when the UI revokes while I/O is outstanding.
/// A false start result does not mean denial: some already-accessible URLs
/// need no extension. The actual open remains authoritative.
final class WorkspaceSecurityLease: @unchecked Sendable {
    let url: URL
    private let started: Bool
    init(url: URL) {
        self.url = url
        self.started = url.startAccessingSecurityScopedResource()
    }
    deinit {
        if started { url.stopAccessingSecurityScopedResource() }
    }
}