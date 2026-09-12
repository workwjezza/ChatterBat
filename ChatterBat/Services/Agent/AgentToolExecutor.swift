import Foundation

/// The outcome of running one approved agent tool.
enum AgentToolExecutionResult: Sendable {
    /// Succeeded. `itemName` is the last path component only (see
    /// `AgentToolExecutor`'s doc comment); `resultText` is what gets
    /// sent back to the model as the tool's result content.
    case success(itemName: String, resultText: String)
    /// The user cancelled the native panel — treated the same as a
    /// denial from the model's perspective (no data is returned), but
    /// reported distinctly so the UI/transcript can say "cancelled"
    /// rather than "denied."
    case cancelled
    /// The read itself failed (e.g. the file was deleted between
    /// being picked and being read, or isn't valid UTF-8 text).
    case failure(String)
}

/// Executes one already-user-approved `AgentTool` by presenting a
/// native `NSOpenPanel` and reading only what the user actually picks.
///
/// This is the structural enforcement of Stage 7's "never silently
/// expanding scope beyond what's shown" requirement: the model's
/// request only ever says *which kind* of tool it wants (read a file,
/// or list a folder) and *why* — never a path. The path itself is
/// determined exclusively by the human, live, via the same system
/// panel every other macOS app uses to grant sandboxed file access.
/// There is no code path anywhere in ChatterBat that resolves a
/// model-supplied path string against the filesystem.
///
/// Only the last path component (file/folder *name*, never the full
/// path) is ever shown in the transcript or sent back to the model —
/// full local paths can leak machine-specific usernames/directory
/// structure to a third-party API, which the brief's privacy posture
/// treats as exactly the kind of incidental disclosure to avoid.
@MainActor
enum AgentToolExecutor {
    /// Maximum bytes read from a file, to keep a single tool result
    /// from ballooning the request context (and cost) unboundedly —
    /// deliberately generous for ordinary text/code files while still
    /// bounded. Truncation is always disclosed in the result text
    /// itself, never silent.
    static let maxReadBytes = 200_000

    static func run(_ tool: AgentTool, using presenter: AgentToolPanelPresenting) async -> AgentToolExecutionResult {
        guard !Task.isCancelled else { return .cancelled }
        guard let picked = await presenter.presentPanel(for: tool), !Task.isCancelled else {
            return .cancelled
        }
        let didStartAccessing = picked.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing { picked.stopAccessingSecurityScopedResource() }
        }

        switch tool {
        case .readFile:
            return readFile(at: picked)
        case .listDirectory:
            return listDirectory(at: picked)
        }
    }

    private static func readFile(at url: URL) -> AgentToolExecutionResult {
        let itemName = url.lastPathComponent
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let truncated = data.count > maxReadBytes
            let usedData = truncated ? data.prefix(maxReadBytes) : data
            guard let text = String(data: Data(usedData), encoding: .utf8) else {
                return .failure("\"\(itemName)\" isn't readable as text (not valid UTF-8).")
            }
            let resultText = truncated
                ? text + "\n\n[Truncated: file is larger than \(maxReadBytes) bytes; only the first \(maxReadBytes) bytes were read.]"
                : text
            return .success(itemName: itemName, resultText: resultText)
        } catch {
            return .failure("Couldn't read \"\(itemName)\": \(error.localizedDescription)")
        }
    }

    private static func listDirectory(at url: URL) -> AgentToolExecutionResult {
        let itemName = url.lastPathComponent
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let names = contents
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map { entry -> String in
                    let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    return isDirectory ? "\(entry.lastPathComponent)/" : entry.lastPathComponent
                }
            let resultText = names.isEmpty
                ? "\"\(itemName)\" is empty."
                : names.joined(separator: "\n")
            return .success(itemName: itemName, resultText: resultText)
        } catch {
            return .failure("Couldn't list \"\(itemName)\": \(error.localizedDescription)")
        }
    }
}
