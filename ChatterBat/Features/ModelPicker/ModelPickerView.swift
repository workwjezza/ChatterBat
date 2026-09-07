import SwiftUI

/// The unified, searchable Venice/OpenRouter model picker.
///
/// Presented as a sheet from the conversation toolbar (⌘K). Selecting a
/// model only calls `onSelect` and dismisses — it never sends a chat
/// request, per the brief.
struct ModelPickerView: View {
    var viewModel: ModelPickerViewModel
    let onSelect: (ModelInfo) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if allKnownModelsEmpty {
                emptyState
            } else {
                List {
                    if !viewModel.searchText.isEmpty {
                        searchResultsSection
                    } else {
                        if !viewModel.recentModels.isEmpty {
                            modelSection("Recent", models: viewModel.recentModels)
                        }
                        ForEach(AIService.allCases) { service in
                            serviceSection(service)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 520, height: 480)
        .task {
            await viewModel.loadAllConfiguredCatalogs()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Select a Model")
                    .font(.title3.bold())
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            TextField("Search models", text: Binding(
                get: { viewModel.searchText },
                set: { viewModel.searchText = $0 }
            ))
            .textFieldStyle(.roundedBorder)

            HStack {
                Picker("Service", selection: Binding(
                    get: { viewModel.serviceFilter },
                    set: { viewModel.serviceFilter = $0 }
                )) {
                    ForEach(ModelPickerServiceFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Toggle("Favorites only", isOn: Binding(
                    get: { viewModel.showFavoritesOnly },
                    set: { viewModel.showFavoritesOnly = $0 }
                ))
                .toggleStyle(.checkbox)
            }
        }
        .padding()
    }

    private var allKnownModelsEmpty: Bool {
        AIService.allCases.allSatisfy { viewModel.catalogStates[$0]?.displayableModels.isEmpty ?? true }
    }

    @ViewBuilder
    private var emptyState: some View {
        if AIService.allCases.allSatisfy({ viewModel.catalogStates[$0].isNotConfigured }) {
            ContentUnavailableView(
                "No Accounts Connected",
                systemImage: "person.badge.key",
                description: Text("Connect Venice or OpenRouter in Settings → Accounts to see models here.")
            )
        } else if AIService.allCases.contains(where: { viewModel.catalogStates[$0].isLoading }) {
            ProgressView("Loading models…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "No Models Available",
                systemImage: "exclamationmark.triangle",
                description: Text(firstErrorMessage ?? "No models were returned.")
            )
        }
    }

    private var firstErrorMessage: String? {
        for service in AIService.allCases {
            if case .failed(let message, _, _) = viewModel.catalogStates[service] {
                return message
            }
        }
        return nil
    }

    private var searchResultsSection: some View {
        Section("Results") {
            ForEach(viewModel.filteredModels) { model in
                ModelRow(model: model, viewModel: viewModel, onSelect: select)
            }
        }
    }

    private func modelSection(_ title: String, models: [ModelInfo]) -> some View {
        Section(title) {
            ForEach(models) { model in
                ModelRow(model: model, viewModel: viewModel, onSelect: select)
            }
        }
    }

    @ViewBuilder
    private func serviceSection(_ service: AIService) -> some View {
        let models = (viewModel.catalogStates[service]?.displayableModels ?? [])
            .filter { viewModel.serviceFilter.matches($0.service) }
            .filter { !viewModel.showFavoritesOnly || viewModel.isFavorite($0.identity) }

        if !models.isEmpty {
            Section(service.displayName) {
                ForEach(models) { model in
                    ModelRow(model: model, viewModel: viewModel, onSelect: select)
                }
            }
        } else if case .failed(let message, _, _) = viewModel.catalogStates[service] {
            Section(service.displayName) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
    }

    private func select(_ model: ModelInfo) {
        viewModel.recordSelection(model.identity)
        onSelect(model)
        dismiss()
    }
}

private extension CatalogLoadState? {
    var isNotConfigured: Bool {
        if case .notConfigured = self { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
