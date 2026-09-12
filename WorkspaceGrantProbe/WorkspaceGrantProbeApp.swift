import SwiftUI

/// Isolated live grant verification; shares the production preview/read path,
/// but never constructs chat persistence, provider clients or credentials.
@main
struct WorkspaceGrantProbeApp: App {
    @State private var preview = WorkspacePreviewModel()

    var body: some Scene {
        WindowGroup("Workspace Grant Probe") {
            WorkspacePreviewView(model: preview)
        }
    }
}