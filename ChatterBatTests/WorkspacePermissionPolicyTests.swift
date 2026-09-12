import XCTest
@testable import ChatterBat

@MainActor
final class WorkspacePermissionPolicyTests: XCTestCase {
    private let workspaceID = UUID()
    private let sessionID = UUID()

    private func scope(_ mode: WorkspacePermissionMode = .readOnly, revision: UInt64 = 1,
                       revoked: Bool = false) -> WorkspacePermissionScope {
        WorkspacePermissionScope(workspaceID: workspaceID, revision: revision, mode: mode, isRevoked: revoked)
    }

    private func proposal(_ action: WorkspaceProposedAction = .readFile(relativePath: "Sources/App.swift"),
                          actionID: UUID = UUID(), session: UUID? = nil, revision: UInt64 = 1) -> WorkspaceActionProposal {
        WorkspaceActionProposal(actionID: actionID, sessionID: session ?? sessionID, workspaceID: workspaceID,
                                workspaceRevision: revision, action: action)
    }

    private func edit(_ text: String = "new", expected: String? = "old") -> WorkspaceProposedAction {
        .applyEdits([WorkspaceFileEdit(relativePath: "Sources/App.swift", expectedContent: expected.map { Data($0.utf8) },
                                       replacementContent: Data(text.utf8))])
    }

    func testReadsStillRequireExplicitApproval() {
        XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(), in: scope()), .requiresApproval)
        XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(.listDirectory(relativePath: ".")), in: scope()), .requiresApproval)
    }

    func testReadOnlyDeniesEditsAndTestCommands() {
        for action in [edit(), .runCommand(executable: "/usr/bin/swift", arguments: ["test"], workingDirectory: ".")] {
            XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(action), in: scope()), .denied(.readOnlyMode))
            XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(action), in: scope(.editWithApproval)), .requiresApproval)
        }
    }

    func testCredentialsAndPrivilegeElevationAlwaysDenied() {
        for mode in [WorkspacePermissionMode.readOnly, .editWithApproval] {
            for action in [WorkspaceProposedAction.accessCredentials, .elevatePrivileges] {
                XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(action), in: scope(mode)), .denied(.forbiddenAuthority))
            }
        }
    }

    func testWorkspaceMismatchRevocationAndRevisionFailClosed() {
        let other = WorkspacePermissionScope(workspaceID: UUID(), revision: 1)
        XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(), in: other), .denied(.wrongWorkspace))
        XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(), in: scope(revoked: true)), .denied(.revokedWorkspace))
        XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(), in: scope(revision: 2)), .denied(.staleWorkspaceRevision))
    }

    func testLexicalPathValidationRejectsTraversalAbsoluteAndAmbiguousForms() {
        for path in ["", "/tmp/a", "../a", "a/../b", "a/./b", "a//b", "a/", "~/a", "a\\b", "a\0b", "a\nb", "."] {
            XCTAssertFalse(WorkspaceRelativePath.isValid(path), path)
            XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(.readFile(relativePath: path)), in: scope()), .denied(.malformedAction))
        }
        XCTAssertTrue(WorkspaceRelativePath.isValid("Sources/My File.swift"))
        XCTAssertTrue(WorkspaceRelativePath.isValid("資料/メモ.txt"))
        XCTAssertTrue(WorkspaceRelativePath.isValid(".", allowsRoot: true))
        XCTAssertFalse(WorkspaceRelativePath.isValid(String(repeating: "a", count: 4097)))
    }

    func testEditLimitsAndDuplicateTargetsRejected() {
        let change = WorkspaceFileEdit(relativePath: "a", expectedContent: nil, replacementContent: Data())
        for action in [WorkspaceProposedAction.applyEdits([]), .applyEdits([change, change]),
                       .applyEdits([WorkspaceFileEdit(relativePath: "a", expectedContent: nil,
                                                      replacementContent: Data(count: 1_000_001))])] {
            XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(action), in: scope(.editWithApproval)), .denied(.malformedAction))
        }
    }

    func testCommandShapeDoesNotTreatArgumentsAsSafeCode() {
        let approvedShape = proposal(.runCommand(executable: "/bin/sh", arguments: ["-c", "arbitrary script"], workingDirectory: "."))
        XCTAssertEqual(WorkspacePermissionPolicy.evaluate(approvedShape, in: scope()), .denied(.readOnlyMode))
        XCTAssertEqual(WorkspacePermissionPolicy.evaluate(approvedShape, in: scope(.editWithApproval)), .requiresApproval)
        for action in [WorkspaceProposedAction.runCommand(executable: "swift", arguments: [], workingDirectory: "."),
                       .runCommand(executable: "/usr/bin/swift", arguments: ["x\0y"], workingDirectory: "."),
                       .runCommand(executable: "/usr/bin/swift", arguments: [], workingDirectory: "../other")] {
            XCTAssertEqual(WorkspacePermissionPolicy.evaluate(proposal(action), in: scope(.editWithApproval)), .denied(.malformedAction))
        }
    }

    func testApprovedTicketIsSingleUse() throws {
        let ledger = WorkspaceApprovalLedger()
        let action = proposal(edit())
        let ticket = try XCTUnwrap(ledger.request(action, scope: scope(.editWithApproval)))
        XCTAssertTrue(ledger.resolve(ticket, approve: true))
        XCTAssertFalse(ledger.resolve(ticket, approve: true))
        XCTAssertTrue(ledger.consume(ticket, for: action, scope: scope(.editWithApproval)))
        XCTAssertFalse(ledger.consume(ticket, for: action, scope: scope(.editWithApproval)))
    }

    func testPendingAndDeniedTicketsCannotExecuteOrBeRevived() throws {
        let ledger = WorkspaceApprovalLedger()
        let action = proposal()
        let pending = try XCTUnwrap(ledger.request(action, scope: scope()))
        XCTAssertFalse(ledger.consume(pending, for: action, scope: scope()))
        XCTAssertFalse(ledger.resolve(pending, approve: true))
        let denied = try XCTUnwrap(ledger.request(action, scope: scope()))
        XCTAssertTrue(ledger.resolve(denied, approve: false))
        XCTAssertFalse(ledger.resolve(denied, approve: true))
        XCTAssertFalse(ledger.consume(denied, for: action, scope: scope()))
    }

    func testChangedSessionActionOrFileBytesBurnApproval() throws {
        for change in 0..<4 {
            let ledger = WorkspaceApprovalLedger()
            let original = proposal(edit())
            let ticket = try XCTUnwrap(ledger.request(original, scope: scope(.editWithApproval)))
            ledger.resolve(ticket, approve: true)
            let altered: WorkspaceActionProposal
            switch change {
            case 0: altered = proposal(edit(), actionID: original.actionID, session: UUID())
            case 1: altered = proposal(edit(), actionID: UUID())
            case 2: altered = proposal(edit("different"), actionID: original.actionID)
            default: altered = proposal(edit(expected: "changed on disk"), actionID: original.actionID)
            }
            XCTAssertFalse(ledger.consume(ticket, for: altered, scope: scope(.editWithApproval)))
            XCTAssertFalse(ledger.consume(ticket, for: original, scope: scope(.editWithApproval)))
        }
    }

    func testChangedCommandArgumentsCannotReuseApproval() throws {
        let ledger = WorkspaceApprovalLedger()
        let original = proposal(.runCommand(executable: "/usr/bin/git", arguments: ["status"], workingDirectory: "."))
        let ticket = try XCTUnwrap(ledger.request(original, scope: scope(.editWithApproval)))
        ledger.resolve(ticket, approve: true)
        let altered = proposal(.runCommand(executable: "/usr/bin/git", arguments: ["push"], workingDirectory: "."), actionID: original.actionID)
        XCTAssertFalse(ledger.consume(ticket, for: altered, scope: scope(.editWithApproval)))
    }

    func testCurrentScopeIsRecheckedAtConsumption() throws {
        for changed in [scope(.readOnly), scope(.editWithApproval, revision: 2), scope(.editWithApproval, revoked: true)] {
            let ledger = WorkspaceApprovalLedger()
            let action = proposal(edit())
            let ticket = try XCTUnwrap(ledger.request(action, scope: scope(.editWithApproval)))
            ledger.resolve(ticket, approve: true)
            XCTAssertFalse(ledger.consume(ticket, for: action, scope: changed))
        }
    }

    func testExpiryIsExclusiveAndClockRollbackFailsClosed() throws {
        for interval in [10.0, -1.0] {
            var now = Date(timeIntervalSince1970: 1000)
            let ledger = WorkspaceApprovalLedger(now: { now })
            let action = proposal()
            let ticket = try XCTUnwrap(ledger.request(action, scope: scope(), lifetime: 10))
            ledger.resolve(ticket, approve: true)
            now = now.addingTimeInterval(interval)
            XCTAssertFalse(ledger.consume(ticket, for: action, scope: scope()))
        }
    }

    func testExpiryDoesNotRenewWhenApproved() throws {
        var now = Date(timeIntervalSince1970: 1000)
        let ledger = WorkspaceApprovalLedger(now: { now })
        let action = proposal()
        let ticket = try XCTUnwrap(ledger.request(action, scope: scope(), lifetime: 10))
        now = now.addingTimeInterval(9)
        ledger.resolve(ticket, approve: true)
        now = now.addingTimeInterval(1)
        XCTAssertFalse(ledger.consume(ticket, for: action, scope: scope()))
    }

    func testObservedClockRollbackWithinOriginalLifetimeInvalidatesApproval() throws {
        var now = Date(timeIntervalSince1970: 1000)
        let ledger = WorkspaceApprovalLedger(now: { now })
        let action = proposal()
        let ticket = try XCTUnwrap(ledger.request(action, scope: scope(), lifetime: 100))
        now = now.addingTimeInterval(50)
        XCTAssertTrue(ledger.resolve(ticket, approve: true))
        now = now.addingTimeInterval(-10)
        XCTAssertFalse(ledger.consume(ticket, for: action, scope: scope()))
    }

    func testRevocationAndSessionCancellationRemoveOnlyMatchingTickets() throws {
        let ledger = WorkspaceApprovalLedger()
        let first = proposal()
        let second = proposal(session: UUID())
        let a = try XCTUnwrap(ledger.request(first, scope: scope()))
        let b = try XCTUnwrap(ledger.request(second, scope: scope()))
        ledger.resolve(a, approve: true)
        ledger.resolve(b, approve: true)
        ledger.cancel(sessionID: first.sessionID)
        XCTAssertFalse(ledger.consume(a, for: first, scope: scope()))
        XCTAssertTrue(ledger.consume(b, for: second, scope: scope()))
        let c = try XCTUnwrap(ledger.request(first, scope: scope()))
        ledger.resolve(c, approve: true)
        ledger.revoke(workspaceID: workspaceID)
        XCTAssertFalse(ledger.consume(c, for: first, scope: scope()))
    }

    func testCapacityDuplicateIDsAndInvalidLifetimeFailClosed() throws {
        let ledger = WorkspaceApprovalLedger(capacity: 1)
        let action = proposal()
        for lifetime in [0.0, -1, 301, .infinity, .nan] {
            XCTAssertNil(ledger.request(action, scope: scope(), lifetime: lifetime))
        }
        let ticket = try XCTUnwrap(ledger.request(action, scope: scope()))
        XCTAssertNil(ledger.request(action, scope: scope()))
        XCTAssertNil(ledger.request(proposal(), scope: scope()))
        ledger.resolve(ticket, approve: false)
        XCTAssertNotNil(ledger.request(proposal(), scope: scope()))
    }

    func testRestartDoesNotRestoreApprovalsAndForbiddenActionsCannotRequestTickets() throws {
        let original = WorkspaceApprovalLedger()
        let action = proposal()
        let ticket = try XCTUnwrap(original.request(action, scope: scope()))
        original.resolve(ticket, approve: true)
        XCTAssertFalse(WorkspaceApprovalLedger().consume(ticket, for: action, scope: scope()))
        XCTAssertNil(original.request(proposal(edit()), scope: scope()))
        XCTAssertNil(original.request(proposal(.accessCredentials), scope: scope(.editWithApproval)))
    }
}