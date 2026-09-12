import SwiftUI

/// Selection and favorite are sibling controls, not nested buttons.
/// Capability badges show reported support; the details popover and
/// accessibility value explicitly distinguish unknown from unsupported.
struct ModelRow: View {
    let model: ModelInfo
    var viewModel: ModelPickerViewModel
    let onSelect: (ModelInfo) -> Void

    var body: some View {
        HStack(alignment: .top) {
            Button {
                onSelect(model)
            } label: {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(model.displayName), \(model.service.displayName)")
            .accessibilityValue(viewModel.capabilitySummary(for: model))
            .accessibilityHint("Selects this model for the next message; does not enable capabilities")
            capabilityDetailsButton
            favoriteButton
        }
    }

    @State private var showsCapabilities = false

    private var capabilityDetailsButton: some View {
        Button {
            showsCapabilities = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capabilities for \(model.displayName), \(model.service.displayName)")
        .help(viewModel.capabilitySummary(for: model))
        .popover(isPresented: $showsCapabilities) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Provider-reported capabilities").font(.headline)
                ForEach(ModelPickerCapability.allCases) { capability in
                    Text("\(capability.title): \(capability.status(in: model))")
                }
                Text("Metadata may be cached. This does not enable attachments, web browsing, image editing or coding execution in ChatterBat.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Close") { showsCapabilities = false }
            }
            .padding()
            .frame(width: 320)
        }
    }

    private var detailRow: some View {
        HStack(spacing: 8) {
            if let contextLength = model.contextLength {
                Text("\(contextLength.formatted()) ctx")
            }
            ValuePriceLabel(text: priceText, highlighted: viewModel.isGoodValue(model))
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
        .accessibilityLabel("\(viewModel.isFavorite(model.identity) ? "Remove from favorites" : "Add to favorites"): \(model.displayName), \(model.service.displayName)")
    }

    /// Formats known input/output pricing as USD per 1M tokens. Shows
    /// "Price unknown" rather than any numeric placeholder when the
    /// provider didn't report a price, per the brief's rule that unknown
    /// pricing must never be displayed as free or zero.
    private var priceText: String {
        guard
            ModelValuePolicy.score(model) != nil,
            let input = model.pricing.inputPerMillionTokensUSD,
            let output = model.pricing.outputPerMillionTokensUSD
        else {
            return "Price unknown"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 6
        let inputString = formatter.string(from: input as NSDecimalNumber) ?? "$\(input)"
        let outputString = formatter.string(from: output as NSDecimalNumber) ?? "$\(output)"
        return "\(inputString) in / \(outputString) out · 1M tok"
    }
}

/// One slow, low-opacity border animation; never animates layout or text.
/// Only visible highlighted rows schedule updates. Inactive windows and
/// Reduce Motion render a static gradient instead.
private struct ValuePriceLabel: View {
    let text: String
    let highlighted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 3) {
            if highlighted { Text("✦").accessibilityHidden(true) }
            Text(text)
        }
        .padding(.horizontal, highlighted ? 5 : 0)
        .padding(.vertical, highlighted ? 3 : 0)
        .overlay {
            if highlighted {
                if reduceMotion || scenePhase != .active {
                    border(angle: 0)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
                        border(angle: timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) * 30)
                    }
                }
            }
        }
        .help(highlighted
              ? "Low listed price: cheapest quarter (up to 3) among models with similar capabilities, context range, service and privacy. Uses 3 input tokens : 1 output token. Not a quality benchmark or billing quote."
              : "Listed USD per million input/output tokens. Actual charges may differ with caching, context tiers or provider routing.")
        .accessibilityLabel((highlighted ? "Low listed price. " : "") + text)
    }

    private func border(angle: Double) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(AngularGradient(colors: [.pink, .purple, .blue, .mint, .yellow, .pink],
                                          center: .center, angle: .degrees(angle)), lineWidth: 1)
            .opacity(0.55)
            .allowsHitTesting(false)
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
