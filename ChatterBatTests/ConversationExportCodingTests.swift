import XCTest
@testable import ChatterBat

final class ConversationExportCodingTests: XCTestCase {
    private func makeMessages() -> [TranscriptMessage] {
        [
            TranscriptMessage(role: .user, content: "Hello", status: .completed),
            TranscriptMessage(
                role: .assistant,
                content: "Hi there",
                status: .completed,
                attribution: ModelIdentity(service: .venice, modelID: "llama-3.2-3b"),
                usage: ChatUsage(promptTokens: 5, completionTokens: 3, totalTokens: 8)
            )
        ]
    }

    func testExportIncludesCurrentSchemaVersion() {
        let conversation = Conversation(title: "Test")
        let export = ConversationExportCoding.export(conversation: conversation, messages: makeMessages())
        XCTAssertEqual(export.schemaVersion, ConversationExport.currentSchemaVersion)
    }

    func testEncodeDecodeRoundTripPreservesAllFields() throws {
        let conversation = Conversation(title: "Round Trip")
        let messages = makeMessages()
        let export = ConversationExportCoding.export(conversation: conversation, messages: messages)

        let data = try ConversationExportCoding.encode(export)
        let decoded = try ConversationExportCoding.decode(data)

        // `updatedAt` is compared with millisecond tolerance rather
        // than bit-for-bit equality: the on-disk ISO 8601 format
        // preserves only millisecond precision, so a `Date` with
        // finer-grained (e.g. microsecond) precision is expected to
        // lose that excess precision across an encode/decode round
        // trip — a real, documented limitation of the file format,
        // not a bug.
        XCTAssertEqual(decoded.schemaVersion, export.schemaVersion)
        XCTAssertEqual(decoded.id, export.id)
        XCTAssertEqual(decoded.title, export.title)
        XCTAssertEqual(decoded.messages, export.messages)
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, export.updatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testDecodeRejectsNewerSchemaVersionRatherThanMisreadingIt() throws {
        let conversation = Conversation(title: "Future")
        var export = ConversationExportCoding.export(conversation: conversation, messages: [])
        export = ConversationExport(
            schemaVersion: ConversationExport.currentSchemaVersion + 1,
            id: export.id,
            title: export.title,
            updatedAt: export.updatedAt,
            messages: export.messages
        )
        let data = try ConversationExportCoding.encode(export)

        XCTAssertThrowsError(try ConversationExportCoding.decode(data)) { error in
            XCTAssertEqual(
                error as? ConversationExportCoding.ImportError,
                .unsupportedSchemaVersion(ConversationExport.currentSchemaVersion + 1)
            )
        }
    }

    func testImportAsNewConversationAssignsAFreshConversationIDNotTheExportedOne() {
        let conversation = Conversation(title: "Original")
        let export = ConversationExportCoding.export(conversation: conversation, messages: makeMessages())

        let (imported, _) = ConversationExportCoding.importAsNewConversation(export)

        XCTAssertNotEqual(imported.id, export.id)
        XCTAssertEqual(imported.title, "Original")
    }

    func testImportAsNewConversationPreservesMessageContentRoleAndUsage() {
        let conversation = Conversation(title: "Original")
        let export = ConversationExportCoding.export(conversation: conversation, messages: makeMessages())

        let (_, messages) = ConversationExportCoding.importAsNewConversation(export)

        XCTAssertEqual(messages.map(\.content), ["Hello", "Hi there"])
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.last?.attribution, ModelIdentity(service: .venice, modelID: "llama-3.2-3b"))
        XCTAssertEqual(messages.last?.usage, ChatUsage(promptTokens: 5, completionTokens: 3, totalTokens: 8))
    }

    func testImportPreservesFailedMessageStatusAndReason() {
        let conversation = Conversation(title: "Failed Turn")
        let failed = [TranscriptMessage(role: .assistant, content: "", status: .failed("Rate limited."))]
        let export = ConversationExportCoding.export(conversation: conversation, messages: failed)

        let (_, messages) = ConversationExportCoding.importAsNewConversation(export)

        XCTAssertEqual(messages.first?.status, .failed("Rate limited."))
    }

    // MARK: - Stage 7: tool invocation export/import

    func testToolInvocationRecordRoundTripsThroughExportImport() throws {
        let conversation = Conversation(title: "Tools")
        let toolMessage = TranscriptMessage(
            role: .tool,
            content: "file contents",
            status: .completed,
            toolInvocation: ToolInvocationRecord(
                tool: .listDirectory,
                toolCallID: "call_9",
                modelStatedReason: "checking the folder",
                approvedItemName: "Documents"
            )
        )
        let export = ConversationExportCoding.export(conversation: conversation, messages: [toolMessage])
        let data = try ConversationExportCoding.encode(export)
        let decoded = try ConversationExportCoding.decode(data)

        let (_, messages) = ConversationExportCoding.importAsNewConversation(decoded)

        XCTAssertEqual(messages.first?.role, .tool)
        XCTAssertEqual(messages.first?.status, .completed)
        XCTAssertEqual(messages.first?.toolInvocation?.tool, .listDirectory)
        XCTAssertEqual(messages.first?.toolInvocation?.toolCallID, "call_9")
        XCTAssertEqual(messages.first?.toolInvocation?.modelStatedReason, "checking the folder")
        XCTAssertEqual(messages.first?.toolInvocation?.approvedItemName, "Documents")
    }

    func testOrdinaryMessageNeverGainsAToolInvocationAfterExportImport() {
        let conversation = Conversation(title: "Original")
        let export = ConversationExportCoding.export(conversation: conversation, messages: makeMessages())

        let (_, messages) = ConversationExportCoding.importAsNewConversation(export)

        XCTAssertTrue(messages.allSatisfy { $0.toolInvocation == nil })
    }

    func testExportNeverIncludesAnyKeyLikeField() throws {
        // Defensive: the encoded JSON must never contain anything that
        // looks like an API key field name, since export/import must
        // never leak Keychain-held secrets.
        let conversation = Conversation(title: "Safety")
        let export = ConversationExportCoding.export(conversation: conversation, messages: makeMessages())
        let data = try ConversationExportCoding.encode(export)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.localizedCaseInsensitiveContains("apiKey"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("api_key"))
    }
}
