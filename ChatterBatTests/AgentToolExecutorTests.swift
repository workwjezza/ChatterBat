import XCTest
@testable import ChatterBat

/// Exercises `AgentToolExecutor` against real temp-directory fixtures
/// (never a real user-facing `NSOpenPanel` — the panel presenter is
/// injected as a fake here) per the brief's testing contract.
final class AgentToolExecutorTests: XCTestCase {
    @MainActor
    func testCancelledPanelReturnsCancelledWithoutTouchingFilesystem() async throws {
        let presenter = FakeAgentToolPanelPresenter()
        presenter.urlToReturn = nil

        let result = await AgentToolExecutor.run(.readFile, using: presenter)

        guard case .cancelled = result else { return XCTFail("Expected .cancelled") }
    }

    @MainActor
    func testReadFileReturnsContentsAndLastPathComponentOnly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("notes.txt")
        try "hello world".write(to: fileURL, atomically: true, encoding: .utf8)

        let presenter = FakeAgentToolPanelPresenter()
        presenter.urlToReturn = fileURL

        let result = await AgentToolExecutor.run(.readFile, using: presenter)

        guard case .success(let itemName, let resultText) = result else { return XCTFail("Expected .success") }
        XCTAssertEqual(itemName, "notes.txt")
        XCTAssertEqual(resultText, "hello world")
        XCTAssertFalse(resultText.contains(directory.path), "Result text must never include the full local path.")
    }

    @MainActor
    func testListDirectoryReturnsSortedNamesWithTrailingSlashForSubdirectories() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "x".write(to: directory.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("a-folder"), withIntermediateDirectories: true)

        let presenter = FakeAgentToolPanelPresenter()
        presenter.urlToReturn = directory

        let result = await AgentToolExecutor.run(.listDirectory, using: presenter)

        guard case .success(_, let resultText) = result else { return XCTFail("Expected .success") }
        XCTAssertEqual(resultText, "a-folder/\nb.txt")
    }

    @MainActor
    func testListEmptyDirectoryReportsEmptyRatherThanBlankText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let presenter = FakeAgentToolPanelPresenter()
        presenter.urlToReturn = directory

        let result = await AgentToolExecutor.run(.listDirectory, using: presenter)

        guard case .success(let itemName, let resultText) = result else { return XCTFail("Expected .success") }
        XCTAssertTrue(resultText.contains("empty"))
        XCTAssertTrue(resultText.contains(itemName))
    }

    @MainActor
    func testReadingNonUTF8FileReturnsFailureRatherThanCrashing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("binary.dat")
        try Data([0xFF, 0xFE, 0x00, 0xD8, 0x00]).write(to: fileURL)

        let presenter = FakeAgentToolPanelPresenter()
        presenter.urlToReturn = fileURL

        let result = await AgentToolExecutor.run(.readFile, using: presenter)

        guard case .failure = result else { return XCTFail("Expected .failure for non-UTF8 content") }
    }
}
