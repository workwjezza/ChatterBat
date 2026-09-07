import Foundation

/// One parsed Server-Sent Event: the concatenation of all `data:` lines in
/// the event, joined by newlines per the SSE spec. Comment lines (`:` ...)
/// and other SSE fields (`event:`, `id:`, `retry:`) are not currently
/// surfaced — ChatterBat's providers only use bare `data:` events.
struct SSEEvent: Equatable, Sendable {
    let data: String
}
