import Foundation

/// Encodes/decodes `MessageStatus` to/from the plain-string columns
/// SwiftData stores (`statusRaw` + `failureMessage`).
///
/// `MessageStatus` itself stays a clean domain enum with no persistence
/// awareness; this mapping lives in `Persistence/` instead.
enum MessageStatusCoding {
    static func rawValue(for status: MessageStatus) -> String {
        switch status {
        case .streaming: return "streaming"
        case .completed: return "completed"
        case .cancelled: return "cancelled"
        case .failed: return "failed"
        case .interrupted: return "interrupted"
        }
    }

    static func failureMessage(for status: MessageStatus) -> String? {
        if case .failed(let message) = status { return message }
        return nil
    }

    /// Decodes a status from its stored raw value. An unrecognized raw
    /// value (e.g. from a future schema version read by an older build)
    /// maps to `.interrupted` rather than crashing or silently treating
    /// unknown data as `.completed` — an honest "something needs
    /// attention" state rather than a guess.
    static func status(fromRaw raw: String, failureMessage: String?) -> MessageStatus {
        switch raw {
        case "streaming": return .streaming
        case "completed": return .completed
        case "cancelled": return .cancelled
        case "failed": return .failed(failureMessage ?? "Unknown error.")
        case "interrupted": return .interrupted
        default: return .interrupted
        }
    }
}
