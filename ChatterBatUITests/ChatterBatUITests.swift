import XCTest

/// Minimal Stage 0 UI test: confirms the app launches and the main window
/// shell (sidebar + New Chat control) is present. Deeper UI flows arrive as
/// each feature stage lands.
final class ChatterBatUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesAndShowsSidebar() throws {
        let app = XCUIApplication()
        app.launch()

        let newChatButton = app.buttons["New Chat"]
        XCTAssertTrue(newChatButton.waitForExistence(timeout: 5))
    }
}
