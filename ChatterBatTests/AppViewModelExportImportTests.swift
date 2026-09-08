import XCTest
@testable import ChatterBat

final class AppViewModelExportImportTests: XCTestCase {
    @MainActor
    func testExportDataProducesDecodableExportForRepositoryBackedConversation() throws {
        let repository = InMemoryConversationRepository()
        let conversation = try repository.createConversation(title: "Exportable")
        try repository.appendMessage(TranscriptMessage(role: .user, content: "Hi", status: .completed), toConversation: conversation.id)
        let viewModel = AppViewModel()
        viewModel.loadFromRepository(repository)

        guard let data = viewModel.exportData(for: conversation) else {
            return XCTFail("Expected export data")
        }
        let export = try ConversationExportCoding.decode(data)
        XCTAssertEqual(export.title, "Exportable")
        XCTAssertEqual(export.messages.map(\.content), ["Hi"])
    }

    @MainActor
    func testExportDataReturnsNilWithoutARepository() {
        let viewModel = AppViewModel()
        let conversation = Conversation(title: "No Repo")
        XCTAssertNil(viewModel.exportData(for: conversation))
    }

    @MainActor
    func testImportConversationCreatesANewConversationThroughRepository() throws {
        let repository = InMemoryConversationRepository()
        let viewModel = AppViewModel()
        viewModel.loadFromRepository(repository)

        let original = Conversation(title: "Imported Chat")
        let export = ConversationExportCoding.export(
            conversation: original,
            messages: [TranscriptMessage(role: .user, content: "Hello", status: .completed)]
        )
        let data = try ConversationExportCoding.encode(export)

        let success = viewModel.importConversation(from: data)

        XCTAssertTrue(success)
        XCTAssertNil(viewModel.lastExportImportError)
        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertEqual(viewModel.conversations.first?.title, "Imported Chat")
        XCTAssertEqual(viewModel.selectedConversationID, viewModel.conversations.first?.id)
        let persistedMessages = try repository.loadMessages(for: viewModel.conversations.first!.id)
        XCTAssertEqual(persistedMessages.map(\.content), ["Hello"])
    }

    @MainActor
    func testImportingTheSameFileTwiceCreatesTwoIndependentConversations() throws {
        let repository = InMemoryConversationRepository()
        let viewModel = AppViewModel()
        viewModel.loadFromRepository(repository)

        let export = ConversationExportCoding.export(conversation: Conversation(title: "Dup"), messages: [])
        let data = try ConversationExportCoding.encode(export)

        viewModel.importConversation(from: data)
        viewModel.importConversation(from: data)

        XCTAssertEqual(viewModel.conversations.count, 2)
        XCTAssertNotEqual(viewModel.conversations[0].id, viewModel.conversations[1].id)
    }

    @MainActor
    func testImportOfInvalidDataSetsDecodingFailedError() {
        let viewModel = AppViewModel()
        let success = viewModel.importConversation(from: Data("not json".utf8))
        XCTAssertFalse(success)
        XCTAssertEqual(viewModel.lastExportImportError, .decodingFailed)
    }

    @MainActor
    func testImportOfNewerSchemaVersionSetsUnsupportedSchemaVersionError() throws {
        let viewModel = AppViewModel()
        let export = ConversationExportCoding.export(conversation: Conversation(title: "Future"), messages: [])
        let futureExport = ConversationExport(
            schemaVersion: ConversationExport.currentSchemaVersion + 1,
            id: export.id,
            title: export.title,
            updatedAt: export.updatedAt,
            messages: export.messages
        )
        let data = try ConversationExportCoding.encode(futureExport)

        let success = viewModel.importConversation(from: data)

        XCTAssertFalse(success)
        XCTAssertEqual(viewModel.lastExportImportError, .unsupportedSchemaVersion(ConversationExport.currentSchemaVersion + 1))
    }
}
