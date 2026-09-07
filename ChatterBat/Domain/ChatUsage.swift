import Foundation

/// Provider-reported token usage for one completion.
///
/// Per the brief: "Provider-reported usage is authoritative when
/// supplied. Missing usage is unknown, not zero." All fields are
/// optional for exactly that reason — a `nil` field must never be
/// displayed as `0`.
struct ChatUsage: Hashable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
}
