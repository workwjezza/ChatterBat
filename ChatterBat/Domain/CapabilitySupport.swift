import Foundation

/// Whether a model is known to support a given capability.
///
/// Per the brief: "Unknown capability is not the same as unsupported." A
/// provider that omits a capability field entirely must map to `.unknown`,
/// never silently to `.unsupported`. Capability values are only ever
/// derived from fields the provider explicitly documents for this
/// purpose — never inferred from a model's display name.
enum CapabilitySupport: Hashable, Sendable {
    case supported
    case unsupported
    case unknown

    /// Maps an optional provider-reported boolean flag: `true`/`false` map
    /// directly, and a missing flag (the field wasn't present at all) maps
    /// to `.unknown` rather than assuming `.unsupported`.
    static func from(_ flag: Bool?) -> CapabilitySupport {
        switch flag {
        case true: return .supported
        case false: return .unsupported
        case nil: return .unknown
        }
    }
}
