import SwiftUI

/// iOS application entry point.
///
/// iOS has no macOS Settings scene, so account settings are presented as an
/// in-app sheet from the root navigation shell.
@main
struct ChatterBatIOSApp: App {
    private let dependencies = AppDependencies.live()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}