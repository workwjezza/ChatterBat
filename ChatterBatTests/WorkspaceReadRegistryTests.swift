import Darwin
import XCTest
@testable import ChatterBat

@MainActor
final class WorkspaceReadRegistryTests: XCTestCase {
    private func withDirectory(_ body: (URL) throws -> Void) throws {
        // /var is a system symlink on macOS. Canonicalize the trusted temp
        // fixture parent before creating a root, never model-supplied paths.
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func setup(_ root: URL) throws -> (WorkspaceReadRegistry, WorkspacePermissionScope, UUID) {
        let registry = WorkspaceReadRegistry()
        let scope = try registry.register(userSelectedRoot: root)
        let session = UUID()
        try registry.bind(sessionID: session, to: scope.workspaceID)
        return (registry, scope, session)
    }

    private func proposal(_ scope: WorkspacePermissionScope, _ session: UUID,
                          _ action: WorkspaceProposedAction) -> WorkspaceActionProposal {
        WorkspaceActionProposal(actionID: UUID(), sessionID: session, workspaceID: scope.workspaceID,
                                workspaceRevision: scope.revision, action: action)
    }

    private func run(_ registry: WorkspaceReadRegistry, _ proposal: WorkspaceActionProposal) throws -> WorkspaceReadResult {
        let ticket = try registry.requestApproval(for: proposal)
        XCTAssertTrue(registry.resolveApproval(ticket, approve: true))
        return try registry.execute(proposal, ticket: ticket)
    }

    func testApprovedReadIsRelativeAndSingleUse() throws {
        try withDirectory { root in
            try "hello".write(to: root.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
            let (registry, scope, session) = try setup(root)
            let action = proposal(scope, session, .readFile(relativePath: "file.txt"))
            let ticket = try registry.requestApproval(for: action)
            registry.resolveApproval(ticket, approve: true)
            XCTAssertEqual(try registry.execute(action, ticket: ticket), .text(relativePath: "file.txt", content: "hello"))
            XCTAssertThrowsError(try registry.execute(action, ticket: ticket))
        }
    }

    func testDeniedPendingAndUnboundRequestsNeverRead() throws {
        try withDirectory { root in
            let (registry, scope, session) = try setup(root)
            let action = proposal(scope, session, .readFile(relativePath: "does-not-exist"))
            let ticket = try registry.requestApproval(for: action)
            XCTAssertThrowsError(try registry.execute(action, ticket: ticket)) { XCTAssertEqual($0 as? WorkspaceReadError, .approvalRequired) }
            let denied = try registry.requestApproval(for: action)
            registry.resolveApproval(denied, approve: false)
            XCTAssertThrowsError(try registry.execute(action, ticket: denied))
            XCTAssertThrowsError(try registry.requestApproval(for: proposal(scope, UUID(), .listDirectory(relativePath: "."))))
        }
    }

    func testRevocationRevisionAndRebindingInvalidateApproval() throws {
        try withDirectory { root in
            let (registry, scope, session) = try setup(root)
            let action = proposal(scope, session, .listDirectory(relativePath: "."))
            let ticket = try registry.requestApproval(for: action)
            registry.resolveApproval(ticket, approve: true)
            let revised = try registry.invalidateApprovals(workspaceID: scope.workspaceID)
            XCTAssertEqual(revised.revision, 2)
            XCTAssertThrowsError(try registry.execute(action, ticket: ticket))
            let newAction = proposal(revised, session, .listDirectory(relativePath: "."))
            let second = try registry.requestApproval(for: newAction)
            registry.resolveApproval(second, approve: true)
            try registry.bind(sessionID: session, to: scope.workspaceID)
            XCTAssertThrowsError(try registry.execute(newAction, ticket: second))
            let third = try registry.requestApproval(for: newAction)
            registry.resolveApproval(third, approve: true)
            registry.revoke(workspaceID: scope.workspaceID)
            XCTAssertThrowsError(try registry.execute(newAction, ticket: third))
        }
    }

    func testListSortedRepeatedAndOmissionsDisclosed() throws {
        try withDirectory { root in
            try "x".write(to: root.appendingPathComponent("z.txt"), atomically: true, encoding: .utf8)
            try "secret".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: false)
            let (registry, scope, session) = try setup(root)
            for _ in 0..<2 {
                XCTAssertEqual(try run(registry, proposal(scope, session, .listDirectory(relativePath: "."))),
                               .directory(relativePath: ".", entries: ["a/", "z.txt"], hasOmissions: true))
            }
            XCTAssertEqual(try run(registry, proposal(scope, session, .listDirectory(relativePath: "a"))),
                           .directory(relativePath: "a", entries: [], hasOmissions: false))
        }
    }

    func testAbsoluteTraversalAndProtectedPathsDenied() throws {
        try withDirectory { root in
            let (registry, scope, session) = try setup(root)
            for path in ["../escape", "/etc/passwd", "a/../b", "a//b"] {
                XCTAssertThrowsError(try registry.requestApproval(for: proposal(scope, session, .readFile(relativePath: path))))
            }
            for path in [".env", ".ENV", "node_modules/file", "Secrets/file", "cert.PEM", ".git/config"] {
                XCTAssertThrowsError(try run(registry, proposal(scope, session, .readFile(relativePath: path)))) {
                    XCTAssertEqual($0 as? WorkspaceReadError, .protectedPath)
                }
            }
            XCTAssertThrowsError(try registry.requestApproval(for: proposal(scope, session,
                .runCommand(executable: "/usr/bin/true", arguments: [], workingDirectory: "."))))
        }
    }

    func testSymlinkRootFinalAndIntermediateComponentsRejected() throws {
        try withDirectory { parent in
            let real = parent.appendingPathComponent("real")
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
            try "outside".write(to: parent.appendingPathComponent("outside"), atomically: true, encoding: .utf8)
            let alias = parent.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
            XCTAssertThrowsError(try WorkspaceReadRegistry().register(userSelectedRoot: alias))
            try FileManager.default.createSymbolicLink(at: real.appendingPathComponent("link"), withDestinationURL: parent.appendingPathComponent("outside"))
            try FileManager.default.createSymbolicLink(at: real.appendingPathComponent("dir"), withDestinationURL: parent)
            let (registry, scope, session) = try setup(real)
            for path in ["link", "dir/outside"] {
                XCTAssertThrowsError(try run(registry, proposal(scope, session, .readFile(relativePath: path))))
            }
        }
    }

    func testHardLinksFIFOAndWrongFileTypeRejectedWithoutBlocking() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("file")
            try "hello".write(to: file, atomically: true, encoding: .utf8)
            XCTAssertEqual(link(file.path, root.appendingPathComponent("hardlink").path), 0)
            XCTAssertEqual(mkfifo(root.appendingPathComponent("fifo").path, 0o600), 0)
            let (registry, scope, session) = try setup(root)
            for path in ["file", "hardlink", "fifo"] {
                XCTAssertThrowsError(try run(registry, proposal(scope, session, .readFile(relativePath: path))))
            }
            XCTAssertThrowsError(try run(registry, proposal(scope, session, .listDirectory(relativePath: "file"))))
            XCTAssertEqual(try run(registry, proposal(scope, session, .listDirectory(relativePath: "."))),
                           .directory(relativePath: ".", entries: [], hasOmissions: true))
        }
    }

    func testReadLimitExactBoundaryAndBinaryRejection() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("file")
            let (registry, scope, session) = try setup(root)
            try Data(repeating: 65, count: WorkspaceReadAccess.maxReadBytes).write(to: file)
            guard case .text(_, let text) = try run(registry, proposal(scope, session, .readFile(relativePath: "file"))) else {
                return XCTFail("Expected bounded text")
            }
            XCTAssertEqual(text.utf8.count, WorkspaceReadAccess.maxReadBytes)
            try Data(repeating: 65, count: WorkspaceReadAccess.maxReadBytes + 1).write(to: file)
            XCTAssertThrowsError(try run(registry, proposal(scope, session, .readFile(relativePath: "file")))) {
                XCTAssertEqual($0 as? WorkspaceReadError, .tooLarge)
            }
            for bytes: [UInt8] in [[0xFF], [0]] {
                try Data(bytes).write(to: file)
                XCTAssertThrowsError(try run(registry, proposal(scope, session, .readFile(relativePath: "file")))) {
                    XCTAssertEqual($0 as? WorkspaceReadError, .notUTF8)
                }
            }
        }
    }

    func testRootReplacementAfterApprovalDoesNotReadReplacement() throws {
        try withDirectory { parent in
            let root = parent.appendingPathComponent("root")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let (registry, scope, session) = try setup(root)
            let action = proposal(scope, session, .listDirectory(relativePath: "."))
            let ticket = try registry.requestApproval(for: action)
            registry.resolveApproval(ticket, approve: true)
            try FileManager.default.moveItem(at: root, to: parent.appendingPathComponent("old"))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            XCTAssertThrowsError(try registry.execute(action, ticket: ticket)) {
                XCTAssertEqual($0 as? WorkspaceReadError, .changedDuringAccess)
            }
        }
    }

    func testDeterministicIntermediateRenameRaceFailsClosed() throws {
        try withDirectory { root in
            let directory = root.appendingPathComponent("directory")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try "original".write(to: directory.appendingPathComponent("file"), atomically: true, encoding: .utf8)
            let handle = try WorkspaceReadAccess.openRoot(root)
            XCTAssertThrowsError(try WorkspaceReadAccess.read("directory/file", root: handle, beforeIO: {
                XCTAssertNoThrow(try FileManager.default.moveItem(at: directory, to: root.appendingPathComponent("moved")))
                XCTAssertNoThrow(try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: root.appendingPathComponent("moved")))
            })) { XCTAssertEqual($0 as? WorkspaceReadError, .changedDuringAccess) }
        }
    }

    func testDeterministicFileMutationIsDetected() throws {
        try withDirectory { root in
            let file = root.appendingPathComponent("file")
            try "original".write(to: file, atomically: true, encoding: .utf8)
            let handle = try WorkspaceReadAccess.openRoot(root)
            XCTAssertThrowsError(try WorkspaceReadAccess.read("file", root: handle, beforeIO: {
                XCTAssertNoThrow(try Data("changed length".utf8).write(to: file))
            })) { XCTAssertEqual($0 as? WorkspaceReadError, .changedDuringAccess) }
        }
    }

    func testDirectoryEntryCountIsBounded() throws {
        try withDirectory { root in
            for index in 0...WorkspaceReadAccess.maxDirectoryEntries {
                try Data().write(to: root.appendingPathComponent("file\(index)"))
            }
            let (registry, scope, session) = try setup(root)
            guard case .directory(_, let entries, let omitted) = try run(registry, proposal(scope, session, .listDirectory(relativePath: "."))) else {
                return XCTFail("Expected listing")
            }
            XCTAssertLessThanOrEqual(entries.count, WorkspaceReadAccess.maxDirectoryEntries)
            XCTAssertTrue(omitted)
        }
    }

    func testDirectoryByteLimitAndMutationDetection() throws {
        try withDirectory { root in
            for index in 0..<400 {
                try Data().write(to: root.appendingPathComponent(String(repeating: "a", count: 180) + "\(index)"))
            }
            let (registry, scope, session) = try setup(root)
            guard case .directory(_, let entries, let omitted) = try run(registry, proposal(scope, session, .listDirectory(relativePath: "."))) else {
                return XCTFail("Expected listing")
            }
            XCTAssertLessThanOrEqual(entries.reduce(0) { $0 + $1.utf8.count + 1 }, WorkspaceReadAccess.maxListingBytes)
            XCTAssertTrue(omitted)
            let handle = try WorkspaceReadAccess.openRoot(root)
            XCTAssertThrowsError(try WorkspaceReadAccess.list(".", root: handle, beforeIO: {
                try Data().write(to: root.appendingPathComponent("added"))
            })) { XCTAssertEqual($0 as? WorkspaceReadError, .changedDuringAccess) }
        }
    }

    func testMissingAndPermissionDeniedFilesReturnNoContent() throws {
        try withDirectory { root in
            let (registry, scope, session) = try setup(root)
            XCTAssertThrowsError(try run(registry, proposal(scope, session, .readFile(relativePath: "missing")))) {
                XCTAssertEqual($0 as? WorkspaceReadError, .inaccessible)
            }
            let file = root.appendingPathComponent("denied")
            try Data("sensitive".utf8).write(to: file)
            XCTAssertEqual(chmod(file.path, 0), 0)
            defer { _ = chmod(file.path, 0o600) }
            if geteuid() != 0 {
                XCTAssertThrowsError(try run(registry, proposal(scope, session, .readFile(relativePath: "denied")))) {
                    XCTAssertEqual($0 as? WorkspaceReadError, .inaccessible)
                }
            }
        }
    }

    func testUnicodeFilenameAndEmptyFileAreReadable() throws {
        try withDirectory { root in
            let name = "メモ-é.txt"
            try Data().write(to: root.appendingPathComponent(name))
            let (registry, scope, session) = try setup(root)
            XCTAssertEqual(try run(registry, proposal(scope, session, .readFile(relativePath: name))),
                           .text(relativePath: name, content: ""))
        }
    }

    func testRegistryCapacityAndDescriptorOwnership() throws {
        try withDirectory { root in
            let registry = WorkspaceReadRegistry()
            var scopes: [WorkspacePermissionScope] = []
            for _ in 0..<32 { scopes.append(try registry.register(userSelectedRoot: root)) }
            XCTAssertThrowsError(try registry.register(userSelectedRoot: root)) {
                XCTAssertEqual($0 as? WorkspaceReadError, .registryFull)
            }
            registry.revoke(workspaceID: scopes[0].workspaceID)
            XCTAssertNoThrow(try registry.register(userSelectedRoot: root))
            var handle: WorkspaceReadAccess.Root? = try WorkspaceReadAccess.openRoot(root)
            let fd = try XCTUnwrap(handle).handle.descriptor
            XCTAssertNotEqual(fcntl(fd, F_GETFD), -1)
            XCTAssertNotEqual(fcntl(fd, F_GETFD) & FD_CLOEXEC, 0)
            handle = nil
            XCTAssertEqual(fcntl(fd, F_GETFD), -1)
            XCTAssertEqual(errno, EBADF)
        }
    }

    func testMismatchedApprovedPathAndUnbindCannotExecute() throws {
        try withDirectory { root in
            let (registry, scope, session) = try setup(root)
            let action = proposal(scope, session, .readFile(relativePath: "first"))
            let ticket = try registry.requestApproval(for: action)
            registry.resolveApproval(ticket, approve: true)
            let altered = WorkspaceActionProposal(actionID: action.actionID, sessionID: session,
                workspaceID: scope.workspaceID, workspaceRevision: scope.revision, action: .readFile(relativePath: "second"))
            XCTAssertThrowsError(try registry.execute(altered, ticket: ticket)) {
                XCTAssertEqual($0 as? WorkspaceReadError, .approvalRequired)
            }
            let newTicket = try registry.requestApproval(for: action)
            registry.resolveApproval(newTicket, approve: true)
            registry.unbind(sessionID: session)
            XCTAssertThrowsError(try registry.execute(action, ticket: newTicket)) {
                XCTAssertEqual($0 as? WorkspaceReadError, .unboundSession)
            }
        }
    }

    func testCancelledTaskDoesNotRead() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let (registry, scope, session) = try setup(root)
        let action = proposal(scope, session, .readFile(relativePath: "missing"))
        let ticket = try registry.requestApproval(for: action)
        registry.resolveApproval(ticket, approve: true)
        let task = Task { @MainActor in
            do {
                _ = try registry.execute(action, ticket: ticket)
                XCTFail("Cancelled task must not execute")
            } catch {
                XCTAssertTrue(error is CancellationError)
            }
        }
        task.cancel()
        await task.value
        XCTAssertThrowsError(try registry.execute(action, ticket: ticket)) {
            XCTAssertEqual($0 as? WorkspaceReadError, .approvalRequired)
        }
    }
}