import SwiftUI

/// Application entry point.
///
/// Wires up the window shell and Settings scene, and constructs the
/// single, app-lifetime `AppDependencies` instance (Keychain, network
/// clients, and the SwiftData-backed `ConversationRepository`/
/// `ChatCoordinator`) that both scenes share.
#if os(macOS)
@main
struct ChatterBatApp: App {
    private let dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView(dependencies: dependencies)
        }
    }
}
#endif
