import Foundation

/// Incremental Server-Sent Events parser.
///
/// Feed raw network bytes via `feed(_:)` as they arrive; it returns
/// whatever complete events those bytes completed, buffering any
/// incomplete trailing line for the next call. This handles, per the
/// brief's streaming requirements:
///
/// - Fragmented network chunks: `feed` may be called many times per
///   event; only complete lines are ever decoded.
/// - Split UTF-8 characters: buffering happens at the byte level and
///   lines are only decoded once a full `\n`-terminated line exists, so
///   a multi-byte UTF-8 character split across two `feed` calls is never
///   decoded until it's whole.
/// - LF and CRLF: a trailing `\r` before `\n` is stripped.
/// - Blank-line event boundaries: an empty line terminates the current
///   event and emits it (if it had any `data:` lines).
/// - Multiple `data:` lines per event: joined with `\n`, per the SSE
///   spec.
/// - SSE comments (lines starting with `:`, e.g. `: OPENROUTER
///   PROCESSING`): silently skipped, never passed to a JSON decoder.
/// - Other SSE fields (`event:`, `id:`, `retry:`): currently ignored,
///   since neither provider's chat streaming uses them, but they don't
///   break parsing of the surrounding event.
///
/// This type does not itself decode JSON or know about `[DONE]` — that is
/// the caller's responsibility once it has a plain `SSEEvent.data`
/// string, keeping this parser provider-agnostic.
struct SSEParser {
    private var byteBuffer = Data()
    private var currentDataLines: [String] = []

    /// Feeds raw bytes and returns any complete events they produced.
    /// May return zero, one, or multiple events per call.
    mutating func feed(_ data: Data) -> [SSEEvent] {
        byteBuffer.append(data)

        var events: [SSEEvent] = []
        // 0x0A is LF. Splitting on the raw byte is always safe even mid
        // multi-byte UTF-8 sequence, because continuation bytes in UTF-8
        // never equal 0x0A.
        while let newlineIndex = byteBuffer.firstIndex(of: 0x0A) {
            var lineData = byteBuffer[byteBuffer.startIndex..<newlineIndex]
            byteBuffer.removeSubrange(byteBuffer.startIndex...newlineIndex)

            // Strip a trailing CR (CRLF line ending).
            if lineData.last == 0x0D {
                lineData = lineData[lineData.startIndex..<lineData.index(before: lineData.endIndex)]
            }

            let line = String(decoding: lineData, as: UTF8.self)
            if let event = processLine(line) {
                events.append(event)
            }
        }
        return events
    }

    /// Processes one complete, already-CRLF-stripped line. Returns an
    /// `SSEEvent` if this line was a blank line that terminated a
    /// non-empty event.
    private mutating func processLine(_ line: String) -> SSEEvent? {
        if line.isEmpty {
            guard !currentDataLines.isEmpty else { return nil }
            let event = SSEEvent(data: currentDataLines.joined(separator: "\n"))
            currentDataLines = []
            return event
        }

        if line.hasPrefix(":") {
            // SSE comment/keep-alive (e.g. ": OPENROUTER PROCESSING").
            return nil
        }

        if line.hasPrefix("data:") {
            var value = String(line.dropFirst("data:".count))
            if value.hasPrefix(" ") {
                value.removeFirst()
            }
            currentDataLines.append(value)
            return nil
        }

        // Other SSE fields (event:, id:, retry:) are intentionally
        // ignored; they don't affect data-line accumulation.
        return nil
    }
}
