import XCTest
@testable import ChatterBat

private actor SuspendedReadWorker: WorkspaceReadWorking {
    var started = false
    var continuation: CheckedContinuation<WorkspaceReadResult, Never>?
    func openRoot(_ url: URL) throws -> WorkspaceReadAccess.Root { try WorkspaceReadAccess.openRoot(url) }
    func execute(_ action: WorkspaceProposedAction, root: WorkspaceReadAccess.Root) async throws -> WorkspaceReadResult {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume(returning: .text(relativePath: "file", content: "late result"))
        continuation = nil
    }
}

@MainActor
final class WorkspacePreviewTests: XCTestCase {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("local contents".utf8).write(to: root.appendingPathComponent("file"))
        return root
    }

    private func wait(_ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(3)
        while !condition() && Date() < end { try? await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }

    private func waitForWorker(_ worker: SuspendedReadWorker) async {
        let end = Date().addingTimeInterval(3)
        while !(await worker.started) && Date() < end { try? await Task.sleep(for: .milliseconds(5)) }
        let started = await worker.started
        XCTAssertTrue(started)
    }

    func testLocalPreviewRequiresApprovalAndStaysOutsideChat() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = ConversationSessionState()
        session.draftText = "Unchanged prompt"
        let preview = session.workspacePreview
        preview.connect(to: root)
        await wait { !preview.isBusy }
        XCTAssertTrue(preview.isConnected)
        preview.relativePath = "file"
        preview.proposeRead(listDirectory: false)
        XCTAssertEqual(preview.phase, .awaitingApproval)
        XCTAssertNil(preview.result)
        preview.decide(approve: true)
        await wait { !preview.isBusy }
        XCTAssertEqual(preview.result, .text(relativePath: "file", content: "local contents"))
        XCTAssertEqual(session.draftText, "Unchanged prompt")
        XCTAssertFalse(session.agentToolsEnabled)
        XCTAssertEqual(preview.events.suffix(2), ["approval.approved", "read.completed"])
        preview.disconnect()
        XCTAssertNil(preview.result)
        XCTAssertFalse(preview.isConnected)
    }

    func testDenyAndExpiredApprovalDoNotRead() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        var now = Date()
        let registry = WorkspaceReadRegistry(approvals: WorkspaceApprovalLedger(now: { now }))
        let preview = WorkspacePreviewModel(registry: registry)
        preview.connect(to: root)
        await wait { !preview.isBusy }
        preview.relativePath = "file"
        preview.proposeRead(listDirectory: false)
        preview.decide(approve: false)
        XCTAssertNil(preview.result)
        XCTAssertEqual(preview.phase, .ready)
        preview.proposeRead(listDirectory: false)
        now = now.addingTimeInterval(121)
        preview.decide(approve: true)
        XCTAssertEqual(preview.phase, .failed)
        XCTAssertNil(preview.result)
        preview.disconnect()
    }

    func testMainActorRemainsResponsiveAndRevocationDropsLateRead() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = SuspendedReadWorker()
        let registry = WorkspaceReadRegistry(worker: worker)
        let scope = try await registry.registerForPreview(userSelectedRoot: root)
        let session = UUID()
        try registry.bind(sessionID: session, to: scope.workspaceID)
        let proposal = WorkspaceActionProposal(actionID: UUID(), sessionID: session, workspaceID: scope.workspaceID,
            workspaceRevision: scope.revision, action: .readFile(relativePath: "file"))
        let ticket = try registry.requestPreviewApproval(for: proposal)
        registry.resolveApproval(ticket, approve: true)
        let task = Task { try await registry.executePreview(proposal, ticket: ticket) }
        await waitForWorker(worker)
        // This runs while I/O is suspended on another actor.
        registry.revoke(workspaceID: scope.workspaceID)
        await worker.release()
        do { _ = try await task.value; XCTFail("Revoked result escaped") }
        catch { XCTAssertEqual(error as? WorkspaceReadError, .unknownWorkspace) }
    }

    func testRevisionChangeDropsLateRead() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = SuspendedReadWorker()
        let registry = WorkspaceReadRegistry(worker: worker)
        let scope = try await registry.registerForPreview(userSelectedRoot: root)
        let session = UUID()
        try registry.bind(sessionID: session, to: scope.workspaceID)
        let proposal = WorkspaceActionProposal(actionID: UUID(), sessionID: session, workspaceID: scope.workspaceID,
            workspaceRevision: scope.revision, action: .readFile(relativePath: "file"))
        let ticket = try registry.requestPreviewApproval(for: proposal)
        registry.resolveApproval(ticket, approve: true)
        let task = Task { try await registry.executePreview(proposal, ticket: ticket) }
        await waitForWorker(worker)
        _ = try registry.invalidateApprovals(workspaceID: scope.workspaceID)
        await worker.release()
        do { _ = try await task.value; XCTFail("Stale result escaped") }
        catch { XCTAssertEqual(error as? WorkspaceReadError, .approvalRequired) }
    }

    func testDisconnectDuringReadPreventsLatePreviewAndNewOperation() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = SuspendedReadWorker()
        let preview = WorkspacePreviewModel(registry: WorkspaceReadRegistry(worker: worker))
        preview.connect(to: root)
        await wait { !preview.isBusy }
        preview.relativePath = "file"
        preview.proposeRead(listDirectory: false)
        preview.decide(approve: true)
        await waitForWorker(worker)
        preview.disconnect()
        XCTAssertEqual(preview.phase, .stopping)
        preview.connect(to: root) // must not replace still-unwinding work
        XCTAssertFalse(preview.isConnected)
        await worker.release()
        await wait { !preview.isBusy }
        XCTAssertNil(preview.result)
        XCTAssertEqual(preview.phase, .disconnected)
    }

    func testCapturedProposalNotEditableAndProtectedPathFailsLocally() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = WorkspacePreviewModel()
        preview.connect(to: root)
        await wait { !preview.isBusy }
        preview.relativePath = "file"
        preview.proposeRead(listDirectory: false)
        preview.relativePath = "different"
        preview.decide(approve: true)
        await wait { !preview.isBusy }
        XCTAssertEqual(preview.result, .text(relativePath: "file", content: "local contents"))
        preview.relativePath = ".env"
        preview.proposeRead(listDirectory: false)
        preview.decide(approve: true)
        await wait { !preview.isBusy }
        XCTAssertNil(preview.result)
        XCTAssertTrue(preview.errorMessage?.contains("protectedPath") == true)
        preview.disconnect()
    }

    func testChatSwitchIsolatesPreviewAndDeletionDisconnects() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = AppViewModel()
        app.startNewConversation()
        let first = try XCTUnwrap(app.selectedConversation)
        let preview = app.currentSession.workspacePreview
        preview.connect(to: root)
        await wait { !preview.isBusy }
        app.startNewConversation()
        XCTAssertFalse(app.currentSession.workspacePreview === preview)
        XCTAssertFalse(app.currentSession.workspacePreview.isConnected)
        XCTAssertTrue(preview.isConnected)
        app.delete(first)
        XCTAssertFalse(preview.isConnected)
    }

    func testCancelledRegistrationAndInvalidRootFailClosed() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = WorkspacePreviewModel()
        preview.connect(to: root)
        preview.disconnect()
        await wait { !preview.isBusy }
        XCTAssertFalse(preview.isConnected)
        preview.connect(to: root.appendingPathComponent("missing"))
        await wait { !preview.isBusy }
        XCTAssertEqual(preview.phase, .failed)
        XCTAssertFalse(preview.isConnected)
    }

    func testRebindingSameWorkspaceDuringReadInvalidatesResult() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let worker = SuspendedReadWorker()
        let registry = WorkspaceReadRegistry(worker: worker)
        let scope = try await registry.registerForPreview(userSelectedRoot: root)
        let session = UUID()
        try registry.bind(sessionID: session, to: scope.workspaceID)
        let proposal = WorkspaceActionProposal(actionID: UUID(), sessionID: session, workspaceID: scope.workspaceID,
            workspaceRevision: scope.revision, action: .readFile(relativePath: "file"))
        let ticket = try registry.requestPreviewApproval(for: proposal)
        registry.resolveApproval(ticket, approve: true)
        let task = Task { try await registry.executePreview(proposal, ticket: ticket) }
        await waitForWorker(worker)
        registry.unbind(sessionID: session)
        try registry.bind(sessionID: session, to: scope.workspaceID)
        await worker.release()
        do { _ = try await task.value; XCTFail("Rebound session received stale read") }
        catch { XCTAssertEqual(error as? WorkspaceReadError, .revokedWorkspace) }
        registry.revoke(workspaceID: scope.workspaceID)
    }
}