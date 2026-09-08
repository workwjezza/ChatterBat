import Foundation
@testable import ChatterBat

/// Scripted `ChatStreamingClient` double for `ChatCoordinator` tests.
/// Never performs real network requests.
final class FakeChatStreamingClient: ChatStreamingClient, @unchecked Sendable {
    let service: AIService
    /// Events to yield, in order, with an optional delay (in
    /// nanoseconds) before each — used to give cancellation tests a
    /// window to cancel mid-stream.
    var scriptedEvents: [ChatStreamEvent]
    var delayBetweenEventsNanoseconds: UInt64 = 0
    var errorToThrowAfterEvents: Error?
    private(set) var receivedMessages: [[OutgoingChatMessage]] = []
    private(set) var streamCallCount = 0

    init(service: AIService, scriptedEvents: [ChatStreamEvent] = [], errorToThrowAfterEvents: Error? = nil) {
        self.service = service
        self.scriptedEvents = scriptedEvents
        self.errorToThrowAfterEvents = errorToThrowAfterEvents
    }

    private(set) var receivedSettings: [AdvancedChatSettings] = []
    private(set) var receivedTools: [[AgentTool]] = []

    func streamChatCompletion(
        apiKey: String,
        modelID: String,
        messages: [OutgoingChatMessage],
        settings: AdvancedChatSettings,
        tools: [AgentTool]
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        receivedMessages.append(messages)
        receivedSettings.append(settings)
        receivedTools.append(tools)
        streamCallCount += 1
        let events = scriptedEvents
        let delay = delayBetweenEventsNanoseconds
        let error = errorToThrowAfterEvents

        return AsyncThrowingStream { continuation in
            let task = Task {
                for event in events {
                    if Task.isCancelled { break }
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                    if Task.isCancelled { break }
                    continuation.yield(event)
                }
                if Task.isCancelled {
                    continuation.finish(throwing: CancellationError())
                } else if let error {
                    continuation.finish(throwing: error)
                } else {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
