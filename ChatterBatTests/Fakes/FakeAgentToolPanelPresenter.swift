import Foundation
@testable import ChatterBat

/// Scripted `AgentToolPanelPresenting` double. Never presents a real
/// `NSOpenPanel` — per the brief's testing contract, ChatCoordinator's
/// agent-tools tests must never pop a real system panel.
final class FakeAgentToolPanelPresenter: AgentToolPanelPresenting, @unchecked Sendable {
    /// The URL to return on the next call, or `nil` to simulate the
    /// user cancelling the panel.
    var urlToReturn: URL?
    private(set) var presentedForTools: [AgentTool] = []

    func presentPanel(for tool: AgentTool) async -> URL? {
        presentedForTools.append(tool)
        return urlToReturn
    }
}
