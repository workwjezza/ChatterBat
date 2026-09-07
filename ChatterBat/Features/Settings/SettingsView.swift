import SwiftUI

/// Native Settings scene.
///
/// Stage 0 ships only a General pane confirming the Settings scene opens
/// via ⌘, and the standard menu item. Stage 1 adds Venice/OpenRouter
/// account panes with Keychain-backed key entry; no credential UI exists
/// yet.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 420, height: 220)
    }
}

private struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: appVersionString)
            }
            Section {
                Text(
                    "Account connections for Venice and OpenRouter will appear " +
                    "here in Stage 1."
                )
                .foregroundStyle(.secondary)
                .font(.callout)
            }
        }
        .padding(20)
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
}
