import XCTest
@testable import ChatterBat

final class AgentToolTests: XCTestCase {
    func testRequestDefinitionUsesFunctionTypeAndRawValueAsName() {
        let definition = AgentTool.readFile.requestDefinition()
        XCTAssertEqual(definition["type"] as? String, "function")
        let function = definition["function"] as? [String: Any]
        XCTAssertEqual(function?["name"] as? String, "read_file")
        XCTAssertNotNil(function?["description"])
        XCTAssertNotNil(function?["parameters"])
    }

    func testParametersJSONSchemaRequiresReasonAndTakesNoPathArgument() {
        let schema = AgentTool.readFile.parametersJSONSchema
        XCTAssertEqual(schema["type"] as? String, "object")
        let properties = schema["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["reason"])
        // Structural guarantee: the model can never specify a path —
        // only "reason" is ever a defined property.
        XCTAssertEqual(properties?.count, 1)
        XCTAssertEqual(schema["required"] as? [String], ["reason"])
    }

    func testListDirectoryHasItsOwnDistinctNameAndDescription() {
        XCTAssertEqual(AgentTool.listDirectory.rawValue, "list_directory")
        XCTAssertNotEqual(AgentTool.listDirectory.description, AgentTool.readFile.description)
    }

    func testAllCasesContainsExactlyTheTwoDefinedReadOnlyTools() {
        XCTAssertEqual(Set(AgentTool.allCases), [.readFile, .listDirectory])
    }
}
