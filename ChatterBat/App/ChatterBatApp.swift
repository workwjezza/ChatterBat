import SwiftUI

/// Application entry point for the Stage 0 native shell.
///
/// Stage 0 intentionally contains no provider networking, no credential
/// storage, and no persistence. Those arrive in Stages 1, 2/3, and 4
/// respectively. This file wires up only the window shell and the Settings
/// scene so the app is buildable, launchable, and navigable end to end.
@main
struct ChatterBatApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }
}
