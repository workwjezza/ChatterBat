import Foundation

/// Small shared helpers for leniently decoding catalog JSON with
/// `JSONSerialization` rather than `Decodable`.
///
/// `JSONSerialization` is used deliberately here instead of `Decodable`
/// structs: both providers' catalog entries have many optional,
/// evolving fields, and the brief requires that one malformed entry never
/// discards the rest of the list. Decoding entry-by-entry into `[String:
/// Any]` dictionaries and pulling only the specific fields ChatterBat
/// currently displays makes "skip this one bad entry" trivial, whereas a
/// single `Decodable` array would fail the whole decode on one bad
/// element. This is a deliberate, narrow exception to Swift's usual
/// preference for `Decodable`.
enum ModelCatalogDecoding {
    /// Parses `data` as JSON and returns the top-level `"data"` array as
    /// `[[String: Any]]`, or `nil` if the body isn't valid JSON or doesn't
    /// have that shape at all (a genuinely unrecognized response, as
    /// opposed to one bad entry within an otherwise-valid array).
    static func topLevelDataArray(from data: Data) -> [[String: Any]]? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data),
            let object = json as? [String: Any],
            let array = object["data"] as? [[String: Any]]
        else {
            return nil
        }
        return array
    }

    /// Reads an integer from a JSON value that may be a `NSNumber`
    /// (from JSONSerialization) or absent/null.
    static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    /// Reads a `Decimal` from a JSON value that may be a numeric
    /// `NSNumber` or a numeric `String` (OpenRouter reports prices as
    /// strings, e.g. `"0.00003"`, to avoid floating-point rounding).
    static func decimal(_ value: Any?) -> Decimal? {
        if let number = value as? NSNumber {
            return number.decimalValue
        }
        if let string = value as? String {
            return Decimal(string: string)
        }
        return nil
    }
}
