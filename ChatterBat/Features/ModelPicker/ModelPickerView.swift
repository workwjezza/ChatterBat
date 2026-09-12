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

            if !viewModel.taskPreset.isAvailable {
                ContentUnavailableView("Not Available Yet", systemImage: "info.circle",
                                       description: Text(viewModel.taskPreset.explanation))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allKnownModelsEmpty {
                emptyState
            } else if viewModel.filteredModels.isEmpty {
                ContentUnavailableView("No Matching Models", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("Try fewer requirements or Reset filters. Unknown capabilities do not satisfy an enabled filter."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !viewModel.searchText.isEmpty {
                        searchResultsSection
                    } else {
                        if !viewModel.filteredRecentModels.isEmpty {
                            modelSection("Recent", models: viewModel.filteredRecentModels)
                        }
                        ForEach(AIService.allCases) { service in
                            serviceSection(service)
                        }
                    }
                }
                .listStyle(.inset)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(AIService.allCases) { service in
                    catalogStatus(service)
                }
                Text("✦ Low listed price, not a quality rating. Picker filters do not change Auto's saved policy or eligible favorites. Save Auto policy explicitly from the bookmark bar.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(width: 640, height: 660)
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
                Button("Refresh") {
                    Task { await viewModel.loadAllConfiguredCatalogs() }
                }
                .disabled(AIService.allCases.contains { viewModel.catalogStates[$0].isLoading })
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
                .pickerToggleStyle()
            }

            HStack {
                Picker("Task preset", selection: Binding(
                    get: { viewModel.taskPreset },
                    set: { viewModel.taskPreset = $0 }
                )) {
                    ForEach(ModelPickerTaskPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Button("Reset filters") { viewModel.resetFilters() }
                    .disabled(!viewModel.hasActiveFilters)
            }
            Text(viewModel.taskPreset.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ForEach(ModelPickerCapability.allCases) { capability in
                    Toggle(capability.title, isOn: Binding(
                        get: { viewModel.requiredCapabilities.contains(capability) },
                        set: { viewModel.setCapability(capability, enabled: $0) }
                    ))
                    .pickerToggleStyle()
                    .disabled(viewModel.taskPreset.suggestedCapabilities.contains(capability))
                    .help(viewModel.taskPreset.suggestedCapabilities.contains(capability)
                          ? "Required by this task preset. Choose All tasks to remove this requirement. " + capability.explanation
                          : capability.explanation)
                    .accessibilityHint(capability.explanation)
                }
            }
            Text("Requirements combine (AND). Only reported support matches; unknown is not unsupported. Image input is catalog metadata only—attachments are not implemented yet.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(viewModel.filteredModels.count) matching models")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        let models = viewModel.filteredModels(for: service)

        if !models.isEmpty {
            Section(service.displayName) {
                ForEach(models) { model in
                    ModelRow(model: model, viewModel: viewModel, onSelect: select)
                }
            }
        } else if viewModel.serviceFilter.matches(service),
                  case .failed(let message, _, _) = viewModel.catalogStates[service] {
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

    @ViewBuilder
    private func catalogStatus(_ service: AIService) -> some View {
        switch viewModel.catalogStates[service] {
        case .loaded(_, let date):
            Text("\(service.displayName) prices fetched \(date.formatted(date: .omitted, time: .shortened)) · Auto/value eligibility expires after 15 min")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed(let message, _, _):
            Text("\(service.displayName): \(message) Cached prices may be stale; Auto/value highlighting unavailable.")
                .font(.caption2)
                .foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }
}

private extension View {
    @ViewBuilder
    func pickerToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        toggleStyle(.switch)
        #endif
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
