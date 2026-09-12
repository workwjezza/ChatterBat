import Foundation

/// The true identity of a selectable model: the service it lives on, plus
/// that service's exact model ID string.
///
/// Per the brief: "Model identity is the pair (service, modelID). Never
/// merge models just because their names look alike." Two models with the
/// same display name on different services are always distinct.
struct ModelIdentity: Hashable, Sendable, Codable {
    let service: AIService
    let modelID: String
}
