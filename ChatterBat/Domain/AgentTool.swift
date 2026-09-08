import Foundation

/// A single, read-only tool the agent beta may request. Per the brief
/// and `docs/DEVELOPMENT_PLAN.md`, Stage 7 is explicitly scoped to
/// read-only tools — there is deliberately no tool that writes,
/// deletes, or executes anything. Both tools below only ever read
/// from a location the user *personally* picks via a native
/// `NSOpenPanel` at approval time (see `AgentToolExecutor`); the model
/// never receives filesystem access beyond that one, explicitly
/// user-chosen item.
enum AgentTool: String, CaseIterable, Hashable, Sendable {
    case readFile = "read_file"
    case listDirectory = "list_directory"

    var displayName: String {
        switch self {
        case .readFile: return "Read File"
        case .listDirectory: return "List Directory"
        }
    }

    var description: String {
        switch self {
        case .readFile:
            return "Reads the text contents of a single file that the user selects."
        case .listDirectory:
            return "Lists the names of files and folders inside a single folder that the user selects."
        }
    }

    /// The JSON Schema describing this tool's arguments, in the exact
    /// shape both Venice and OpenRouter document for `tools[].function.parameters`
    /// (verified during Stage 7 implementation). Both tools take a
    /// single, human-readable `reason` string the model fills in to
    /// explain *why* it wants the tool — shown to the user in the
    /// approval sheet so approval is an informed decision, not a blind
    /// "Allow?" click. Neither tool accepts a path/argument from the
    /// model itself: the model can never specify *which* file or
    /// folder, only ask "may I read a file" / "may I list a folder" —
    /// the user picks the actual location via the native panel. This
    /// is what makes "never silently expanding scope beyond what's
    /// shown" structurally true rather than merely a UI convention.
    var parametersJSONSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "reason": [
                    "type": "string",
                    "description": "A short, human-readable explanation of why this tool is needed right now."
                ]
            ],
            "required": ["reason"]
        ]
    }

    /// The full `tools[]` entry for a chat completion request body.
    func requestDefinition() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": rawValue,
                "description": description,
                "parameters": parametersJSONSchema
            ]
        ]
    }
}
