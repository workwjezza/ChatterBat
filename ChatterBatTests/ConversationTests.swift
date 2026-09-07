import XCTest
@testable import ChatterBat

final class ConversationTests: XCTestCase {
    func testConversationsWithDifferentIDsAreNotEqual() {
        let a = Conversation(title: "Same Title", lastMessagePreview: "a")
        let b = Conversation(title: "Same Title", lastMessagePreview: "a")

        XCTAssertNotEqual(a, b, "Identity is by UUID, not by title/preview content.")
    }

    func testDemoFixturesProduceNonEmptyLabeledData() {
        // Guards against accidentally wiring an empty or unlabeled fixture
        // into production paths later; Stage 0 only requires that the demo
        // data used by previews/tests is present and sane.
        XCTAssertFalse(DemoFixtures.conversations.isEmpty)
        for conversation in DemoFixtures.conversations {
            XCTAssertFalse(conversation.title.isEmpty)
        }
    }
}
