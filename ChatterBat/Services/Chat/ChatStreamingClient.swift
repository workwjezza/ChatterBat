import Foundation

/// Streams a chat completion for one service.
///
/// The returned `AsyncThrowingStream` yields `ChatStreamEvent`s as they
/// arrive and finishes (or throws `ChatRequestError`) when the stream
/// ends. Cancelling the consuming `Task` cancels the underlying network
/// request — see `URLSessionStreamingHTTPClient`.
protocol ChatStreamingClient: Sendable {
    var service: AIService { get }
    func streamChatCompletion(
        apiKey: String,
        modelID: String,
        messages: [OutgoingChatMessage]
    ) -> AsyncThrowingStream<ChatStreamEvent, Error>
}

/// Shared implementation for the OpenAI-compatible SSE chat streaming
/// both providers use. Provider-specific subclassing isn't needed here
/// (unlike catalog/connection-check decoding) because the *streaming
/// chunk shape itself* is genuinely the same OpenAI-compatible format for
/// both services for plain text chat — see `docs/DECISIONS.md`.
struct StandardChatStreamingClient: ChatStreamingClient {
    let service: AIService
    private let httpClient: StreamingHTTPClient
    private let endpointURL: URL

    init(service: AIService, httpClient: StreamingHTTPClient, endpointURL: URL) {
        self.service = service
        self.httpClient = httpClient
        self.endpointURL = endpointURL
    }

    func streamChatCompletion(
        apiKey: String,
        modelID: String,
        messages: [OutgoingChatMessage]
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(apiKey: apiKey, modelID: modelID, messages: messages, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func run(
        apiKey: String,
        modelID: String,
        messages: [OutgoingChatMessage],
        continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try ChatRequestBuilder.requestData(modelID: modelID, messages: messages)

        let response: HTTPURLResponse
        let byteStream: AsyncThrowingStream<Data, Error>
        do {
            (response, byteStream) = try await httpClient.stream(request)
        } catch {
            throw ChatRequestError.offlineOrTimeout(error.localizedDescription)
        }

        guard response.statusCode == 200 else {
            // Errors before the response is committed arrive as a
            // buffered JSON body, not SSE — drain it for a message.
            var collected = Data()
            for try await chunk in byteStream {
                collected.append(chunk)
            }
            let message = Self.extractErrorMessage(from: collected)
            throw ChatRequestError.from(httpStatus: response.statusCode, providerMessage: message)
        }

        var parser = SSEParser()
        var observedFinishOrUsage = false
        var didThrowStreamError = false

        for try await chunk in byteStream {
            for event in parser.feed(chunk) {
                guard let decoded = ChatStreamDecoder.decode(event.data) else { continue }
                switch decoded {
                case .streamError(let message):
                    didThrowStreamError = true
                    continuation.yield(.streamError(message))
                    throw ChatRequestError.streamError(message)
                case .finished, .usage:
                    observedFinishOrUsage = true
                    continuation.yield(decoded)
                case .contentDelta, .ignorable:
                    continuation.yield(decoded)
                }
            }
        }

        if !observedFinishOrUsage && !didThrowStreamError {
            throw ChatRequestError.prematureDisconnect
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        if let errorObject = json["error"] as? [String: Any] {
            return errorObject["message"] as? String
        }
        if let errorString = json["error"] as? String {
            return errorString
        }
        return nil
    }
}
