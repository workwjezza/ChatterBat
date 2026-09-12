import Foundation

/// Service filter shown as segmented control in the model picker.
enum ModelPickerServiceFilter: String, CaseIterable, Identifiable {
    case all
    case venice
    case openRouter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .venice: return "Venice"
        case .openRouter: return "OpenRouter"
        }
    }

    func matches(_ service: AIService) -> Bool {
        switch self {
        case .all: return true
        case .venice: return service == .venice
        case .openRouter: return service == .openRouter
        }
    }
}

/// Catalog metadata only. These filters do not enable tools or attachments.
enum ModelPickerCapability: String, CaseIterable, Identifiable {
    case tools
    case reasoning
    case vision

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tools: return "Tool calling"
        case .reasoning: return "Reasoning"
        case .vision: return "Image understanding"
        }
    }

    var explanation: String {
        switch self {
        case .tools: return "Provider reports tool calling. Does not enable tools or grant permissions."
        case .reasoning: return "Provider reports reasoning support. Not a coding-quality or accuracy rating."
        case .vision: return "Provider reports image input. Not image editing; ChatterBat attachments are not implemented yet."
        }
    }

    func support(in model: ModelInfo) -> CapabilitySupport {
        switch self {
        case .tools: return model.supportsTools
        case .reasoning: return model.supportsReasoning
        case .vision: return model.supportsVision
        }
    }

    func status(in model: ModelInfo) -> String {
        switch support(in: model) {
        case .supported: return "Reported supported"
        case .unsupported: return "Reported unsupported"
        case .unknown: return "Unknown"
        }
    }
}

/// Local browsing aids, never prompts, routing policies or benchmark scores.
enum ModelPickerTaskPreset: String, CaseIterable, Identifiable {
    case all
    case coding
    case ideating
    case historicalReferences
    case webBrowsing
    case imageEditing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All tasks"
        case .coding: return "Coding"
        case .ideating: return "Ideating"
        case .historicalReferences: return "Historical references"
        case .webBrowsing: return "Web browsing — not available yet"
        case .imageEditing: return "Image editing — not available yet"
        }
    }

    var isAvailable: Bool {
        self != .webBrowsing && self != .imageEditing
    }

    var suggestedCapabilities: Set<ModelPickerCapability> {
        self == .coding ? [.reasoning] : []
    }

    var explanation: String {
        switch self {
        case .all:
            return "Browse catalog capabilities. Filters affect this picker only, not your model, saved defaults, Auto policy or prompts."
        case .coding:
            return "Heuristic shortlist: requires reported reasoning support, not proven coding quality. Add Tool calling for tool-capable models; this does not enable tools or terminal execution. Other models may also code well."
        case .ideating:
            return "Guidance only: the catalog has no reliable creativity rating, so no models are excluded or ranked by this preset. Compare ideas using models you trust."
        case .historicalReferences:
            return "Guidance only: the catalog has no historical-accuracy rating, so no models are excluded or ranked. Verify claims against primary sources; this preset does not retrieve sources or browse the web."
        case .webBrowsing:
            return "Web browsing is not implemented in ChatterBat. Tool calling does not establish web access. No model matches are claimed until a supported research/browser integration exists."
        case .imageEditing:
            return "Image editing is not implemented in ChatterBat. Image understanding is a separate input capability, not an editing endpoint. No editing matches are claimed."
        }
    }
}
