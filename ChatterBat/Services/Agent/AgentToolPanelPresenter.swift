import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Abstraction over "present the native panel for this tool and return
/// what the user picked," so `ChatCoordinator` can be unit-tested with
/// a scripted fake instead of ever popping a real system panel during
/// automated tests — per the brief's testing contract.
@MainActor
protocol AgentToolPanelPresenting: Sendable {
    /// Returns `nil` if the user cancelled/dismissed the panel without
    /// picking anything.
    func presentPanel(for tool: AgentTool) async -> URL?
}

/// The real, `NSOpenPanel`-backed presenter used by the running app.
///
/// This is the only place in ChatterBat that ever presents this panel
/// for the agent-tools beta — kept separate from `AgentToolExecutor`
/// (which does the actual read once a URL exists) so the executor
/// itself can be unit-tested without any AppKit/UI dependency, by
/// injecting a fake "panel result" closure instead.
struct AgentToolPanelPresenter: AgentToolPanelPresenting {
    func presentPanel(for tool: AgentTool) async -> URL? {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        switch tool {
        case .readFile:
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.prompt = "Allow Read"
            panel.message = "Choose the one file ChatterBat may read for this request."
        case .listDirectory:
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.prompt = "Allow List"
            panel.message = "Choose the one folder ChatterBat may list for this request."
        }
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        let response = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: NSApplication.ModalResponse.cancel); return }
                panel.begin { result in
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            Task { @MainActor in panel.cancel(nil) }
        }
        guard !Task.isCancelled, response == .OK, let url = panel.url else { return nil }
        return url
        #else
        return nil
        #endif
    }
}
