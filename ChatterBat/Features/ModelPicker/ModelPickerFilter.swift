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
