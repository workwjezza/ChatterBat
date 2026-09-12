import SwiftUI

/// iOS settings shell. It deliberately uses grouped navigation rather than
/// the macOS fixed-size tab panel so it remains readable on every iPhone size.
struct MobileSettingsView: View {
    let dependencies: AppDependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        MobileGeneralSettingsView()
                    } label: {
                        Label("General", systemImage: "gearshape.fill")
                    }
                    NavigationLink {
                        AccountsSettingsView(viewModel: dependencies.makeAccountSettingsViewModel())
                    } label: {
                        Label("Accounts", systemImage: "person.badge.key.fill")
                    }
                }

                Section {
                    Text("ChatterBat connects directly to your Venice and OpenRouter accounts. Your API keys stay in this device's Keychain.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct MobileGeneralSettingsView: View {
    var body: some View {
        List {
            Section("App") {
                LabeledContent("Version", value: appVersionString)
            }
            Section {
                Text("Conversation history is stored locally on this device. ChatterBat does not provide an account or subscription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}