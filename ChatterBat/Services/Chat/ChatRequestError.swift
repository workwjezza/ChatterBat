import Foundation

/// A user-actionable classification of a chat request failure.
///
/// Deliberately mirrors the brief's list of error categories to map to
/// useful user actions, rather than exposing raw HTTP status codes or
/// provider error bodies directly in the UI.
enum ChatRequestError: Error, Equatable, Sendable {
    case invalidCredential
    case insufficientCredit
    case rateLimited
    case modelUnavailable
    case contextOverflow
    case unsupportedParameter(String)
    case offlineOrTimeout(String)
    case providerFailure(String)
    case malformedResponse(String)
    /// A mid-stream error delivered inside an HTTP 200 response.
    case streamError(String)
    /// The stream ended (EOF) before any `finish_reason` or usage frame
    /// was observed — a premature disconnect, distinct from a clean
    /// `[DONE]`/finish.
    case prematureDisconnect

    var userMessage: String {
        switch self {
        case .invalidCredential:
            return "This API key was rejected. Check it in Settings → Accounts."
        case .insufficientCredit:
            return "Insufficient credit on this account."
        case .rateLimited:
            return "Rate limited. Please wait and try again."
        case .modelUnavailable:
            return "This model is currently unavailable."
        case .contextOverflow:
            return "This conversation is too long for the selected model's context window."
        case .unsupportedParameter(let detail):
            return "Unsupported request parameter: \(detail)"
        case .offlineOrTimeout(let detail):
            return "Network error: \(detail)"
        case .providerFailure(let detail):
            return "Provider error: \(detail)"
        case .malformedResponse(let detail):
            return "Unexpected response: \(detail)"
        case .streamError(let detail):
            return "Stream error: \(detail)"
        case .prematureDisconnect:
            return "The connection was lost before the response finished."
        }
    }

    /// Maps a pre-stream (committed status code known before any body
    /// content) HTTP status to an error, using the provider's parsed
    /// error message when available. Per the brief's documented status
    /// codes: 400/401/402/403/404/422/429/502/503 are the ones both
    /// providers' docs call out; anything else falls back to
    /// `.providerFailure` with the raw status included.
    static func from(httpStatus: Int, providerMessage: String?) -> ChatRequestError {
        switch httpStatus {
        case 401, 403:
            return .invalidCredential
        case 402:
            return .insufficientCredit
        case 429:
            return .rateLimited
        case 404:
            return .modelUnavailable
        case 400:
            if let providerMessage, providerMessage.localizedCaseInsensitiveContains("context") {
                return .contextOverflow
            }
            return .unsupportedParameter(providerMessage ?? "Bad request")
        case 502, 503:
            return .providerFailure(providerMessage ?? "The provider is temporarily unavailable (\(httpStatus)).")
        default:
            return .providerFailure(providerMessage ?? "HTTP \(httpStatus)")
        }
    }
}
