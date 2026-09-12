import Foundation

/// A host-issued workspace identity and authorization revision, not a path
/// supplied by a model. Increment revision on root/permission changes.
/// E2 provides an in-process read registry; no persistent OS grant exists yet.
struct WorkspacePermissionScope: Equatable, Sendable {
    let workspaceID: UUID
    let revision: UInt64
    var mode: WorkspacePermissionMode = .readOnly
    var isRevoked = false
}

enum WorkspacePermissionMode: Sendable {
    case readOnly
    case editWithApproval
}

/// Exact bytes make a write approval conditional on the content reviewed.
/// nil expectedContent means creation and requires absence at execution.
/// E2/F must verify these preconditions against safe file handles.
struct WorkspaceFileEdit: Equatable, Sendable {
    let relativePath: String
    let expectedContent: Data?
    let replacementContent: Data
}

/// Typed, finite proposal vocabulary. No shell text is parsed into actions.
/// These describe future operations; E1 does not register them as LLM tools.
enum WorkspaceProposedAction: Equatable, Sendable {
    case readFile(relativePath: String)
    case listDirectory(relativePath: String)
    case applyEdits([WorkspaceFileEdit])
    /// executable is an absolute path; workingDirectory is workspace-relative.
    /// Tests/builds are arbitrary-code execution, never classified read-only.
    case runCommand(executable: String, arguments: [String], workingDirectory: String)
    /// Kept explicit so unsupported authority cannot accidentally fall through
    /// to a permissive default as the vocabulary grows.
    case accessCredentials
    case elevatePrivileges

    var isReadOnly: Bool {
        switch self {
        case .readFile, .listDirectory: return true
        default: return false
        }
    }

    var isWellFormed: Bool {
        switch self {
        case .readFile(let path):
            return WorkspaceRelativePath.isValid(path)
        case .listDirectory(let path):
            return WorkspaceRelativePath.isValid(path, allowsRoot: true)
        case .applyEdits(let edits):
            guard !edits.isEmpty, edits.count <= 100,
                  Set(edits.map(\.relativePath)).count == edits.count else { return false }
            var byteCount = 0
            for edit in edits {
                guard WorkspaceRelativePath.isValid(edit.relativePath) else { return false }
                let expected = edit.expectedContent?.count ?? 0
                guard expected <= 1_000_000, edit.replacementContent.count <= 1_000_000 else { return false }
                byteCount += expected + edit.replacementContent.count
                guard byteCount <= 2_000_000 else { return false }
            }
            return true
        case .runCommand(let executable, let arguments, let directory):
            guard executable.hasPrefix("/"),
                  WorkspaceRelativePath.isValid(String(executable.dropFirst())),
                  WorkspaceRelativePath.isValid(directory, allowsRoot: true),
                  arguments.count <= 256 else { return false }
            var byteCount = 0
            for argument in arguments {
                guard !argument.contains("\0"), argument.utf8.count <= 32_768 else { return false }
                byteCount += argument.utf8.count
                guard byteCount <= 65_536 else { return false }
            }
            return true
        case .accessCredentials, .elevatePrivileges:
            return true // Well-formed but always denied by policy below.
        }
    }
}

/// Lexical validation ONLY, not filesystem containment. It does not inspect
/// symlinks, hard links, case aliases, mounts, file types or race conditions.
enum WorkspaceRelativePath {
    static func isValid(_ path: String, allowsRoot: Bool = false) -> Bool {
        if path == "." { return allowsRoot }
        guard !path.isEmpty, path.utf8.count <= 4096, !path.hasPrefix("/"),
              !path.hasPrefix("~"), !path.contains("\\"),
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".."
        }
    }
}

struct WorkspaceActionProposal: Equatable, Sendable {
    let actionID: UUID
    let sessionID: UUID
    let workspaceID: UUID
    let workspaceRevision: UInt64
    let action: WorkspaceProposedAction
}

enum WorkspacePolicyDecision: Equatable, Sendable {
    case requiresApproval
    case denied(WorkspacePolicyDenial)
}

enum WorkspacePolicyDenial: Equatable, Sendable {
    case revokedWorkspace
    case wrongWorkspace
    case staleWorkspaceRevision
    case malformedAction
    case forbiddenAuthority
    case readOnlyMode
}

/// Conservative E1 policy. Even reads require approval; workspace-wide read
/// consent must be an explicit later feature, never inferred from a path.
enum WorkspacePermissionPolicy {
    static func evaluate(_ proposal: WorkspaceActionProposal, in scope: WorkspacePermissionScope) -> WorkspacePolicyDecision {
        guard !scope.isRevoked else { return .denied(.revokedWorkspace) }
        guard proposal.workspaceID == scope.workspaceID else { return .denied(.wrongWorkspace) }
        guard proposal.workspaceRevision == scope.revision else { return .denied(.staleWorkspaceRevision) }
        guard proposal.action.isWellFormed else { return .denied(.malformedAction) }
        switch proposal.action {
        case .accessCredentials, .elevatePrivileges: return .denied(.forbiddenAuthority)
        default: break
        }
        guard scope.mode == .editWithApproval || proposal.action.isReadOnly else { return .denied(.readOnlyMode) }
        return .requiresApproval
    }
}