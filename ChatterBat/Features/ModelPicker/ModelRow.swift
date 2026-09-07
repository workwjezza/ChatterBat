import SwiftUI

/// One row in the model picker: identity, service badge, secondary model
/// ID, capability badges (only shown when actually `.supported` — unknown
/// or unsupported capabilities show nothing, per the brief's rule against
/// conflating "unknown" with "unsupported"), and a favorite toggle.
struct ModelRow: View {
    let model: ModelInfo
    var viewModel: ModelPickerViewModel
    let onSelect: (ModelInfo) -> Void

    var body: some View {
        Button {
            onSelect(model)
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(.body)
                        ServiceBadge(service: model.service)
                    }
                    Text(model.modelID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    detailRow
                }
                Spacer()
                favoriteButton
            }
        }
        .buttonStyle(.plain)
    }

    private var detailRow: some View {
        HStack(spacing: 8) {
            if let contextLength = model.contextLength {
                Text("\(contextLength.formatted()) ctx")
            }
            Text(priceText)
            if model.supportsTools == .supported {
                Text("Tools")
            }
            if model.supportsReasoning == .supported {
                Text("Reasoning")
            }
            if model.supportsVision == .supported {
                Text("Vision")
            }
            if let privacy = model.privacyDescription {
                Text(privacy.capitalized)
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private var favoriteButton: some View {
        Button {
            viewModel.toggleFavorite(model.identity)
        } label: {
            Image(systemName: viewModel.isFavorite(model.identity) ? "star.fill" : "star")
        }
        .buttonStyle(.plain)
        .foregroundStyle(viewModel.isFavorite(model.identity) ? .yellow : .secondary)
    }

    /// Formats known input/output pricing as USD per 1M tokens. Shows
    /// "Price unknown" rather than any numeric placeholder when the
    /// provider didn't report a price, per the brief's rule that unknown
    /// pricing must never be displayed as free or zero.
    private var priceText: String {
        guard
            let input = model.pricing.inputPerMillionTokensUSD,
            let output = model.pricing.outputPerMillionTokensUSD
        else {
            return "Price unknown"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        let inputString = formatter.string(from: input as NSDecimalNumber) ?? "$\(input)"
        let outputString = formatter.string(from: output as NSDecimalNumber) ?? "$\(output)"
        return "\(inputString)/\(outputString) per 1M tok"
    }
}

/// Small capsule badge identifying which service a model belongs to.
struct ServiceBadge: View {
    let service: AIService

    var body: some View {
        Text(service.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15), in: Capsule())
    }
}
