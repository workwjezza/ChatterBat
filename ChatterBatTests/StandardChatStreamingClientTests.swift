import XCTest
@testable import ChatterBat

final class StandardChatStreamingClientTests: XCTestCase {
    private func collect(_ stream: AsyncThrowingStream<ChatStreamEvent, Error>) async throws -> [ChatStreamEvent] {
        var events: [ChatStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    func testHappyPathYieldsContentThenFinishThenUsage() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}

        data: {"choices":[{"delta":{"content":"lo"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: {"choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7}}

        data: [DONE]

        """
        let http = FakeStreamingHTTPClient(statusCode: 200, chunks: [Data(sse.utf8)])
        let client = StandardChatStreamingClient(
            service: .venice,
            httpClient: http,
            endpointURL: URL(string: "https://api.venice.ai/api/v1/chat/completions")!
        )

        let events = try await collect(
            client.streamChatCompletion(apiKey: "key", modelID: "model", messages: [])
        )

        XCTAssertEqual(events, [
            .contentDelta("Hel"),
            .contentDelta("lo"),
            .finished(reason: "stop"),
            .usage(ChatUsage(promptTokens: 5, completionTokens: 2, totalTokens: 7))
        ])
    }

    func testFragmentedChunksAcrossMultipleNetworkReadsStillDecodeCorrectly() async throws {
        let fullSSE = """
        data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}


        """
        let fullData = Data(fullSSE.utf8)
        let midpoint = fullData.count / 2
        let firstHalf = fullData[fullData.startIndex..<fullData.index(fullData.startIndex, offsetBy: midpoint)]
        let secondHalf = fullData[fullData.index(fullData.startIndex, offsetBy: midpoint)...]

        let http = FakeStreamingHTTPClient(statusCode: 200, chunks: [Data(firstHalf), Data(secondHalf)])
        let client = StandardChatStreamingClient(
            service: .venice,
            httpClient: http,
            endpointURL: URL(string: "https://api.venice.ai/api/v1/chat/completions")!
        )

        let events = try await collect(
            client.streamChatCompletion(apiKey: "key", modelID: "model", messages: [])
        )

        XCTAssertEqual(events, [.contentDelta("Hello"), .finished(reason: "stop")])
    }

    func testMidStreamErrorThrowsChatRequestError() async throws {
        let sse = """
        data: {"error":{"code":"server_error","message":"Provider disconnected"},"choices":[{"delta":{"content":""},"finish_reason":"error"}]}


        """
        let http = FakeStreamingHTTPClient(statusCode: 200, chunks: [Data(sse.utf8)])
        let client = StandardChatStreamingClient(
            service: .openRouter,
            httpClient: http,
            endpointURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        )

        do {
            _ = try await collect(client.streamChatCompletion(apiKey: "key", modelID: "model", messages: []))
            XCTFail("Expected an error to be thrown")
        } catch let error as ChatRequestError {
            XCTAssertEqual(error, .streamError("Provider disconnected"))
        }
    }

    func testMidStreamErrorAsFirstAndOnlyEventIsTreatedAsFailure() async throws {
        // Per the brief: "The error can be the first and only event in
        // the stream, so treat a 200 carrying an error chunk with no
        // content as a failure, not a success."
        let sse = """
        data: {"error":{"message":"Immediate failure"},"choices":[{"finish_reason":"error"}]}


        """
        let http = FakeStreamingHTTPClient(statusCode: 200, chunks: [Data(sse.utf8)])
        let client = StandardChatStreamingClient(
            service: .venice,
            httpClient: http,
            endpointURL: URL(string: "https://api.venice.ai/api/v1/chat/completions")!
        )

        do {
            _ = try await collect(client.streamChatCompletion(apiKey: "key", modelID: "model", messages: []))
            XCTFail("Expected an error to be thrown")
        } catch let error as ChatRequestError {
            XCTAssertEqual(error, .streamError("Immediate failure"))
        }
    }

    func testNonStreamingErrorStatusIsMappedFromBufferedJSONBody() async throws {
        let errorBody = Data(#"{"error":{"message":"Invalid model specified"}}"#.utf8)
        let http = FakeStreamingHTTPClient(statusCode: 400, chunks: [errorBody])
        let client = StandardChatStreamingClient(
            service: .venice,
            httpClient: http,
            endpointURL: URL(string: "https://api.venice.ai/api/v1/chat/completions")!
        )

        do {
            _ = try await collect(client.streamChatCompletion(apiKey: "key", modelID: "model", messages: []))
            XCTFail("Expected an error to be thrown")
        } catch let error as ChatRequestError {
            XCTAssertEqual(error, .unsupportedParameter("Invalid model specified"))
        }
    }

    func test401MapsToInvalidCredential() async throws {
        let http = FakeStreamingHTTPClient(statusCode: 401, chunks: [Data()])
        let client = StandardChatStreamingClient(
            service: .venice,
            httpClient: http,
            endpointURL: URL(string: "https://api.venice.ai/api/v1/chat/completions")!
        )

        do {
            _ = try await collect(client.streamChatCompletion(apiKey: "key", modelID: "model", messages: []))
            XCTFail("Expected an error to be thrown")
        } catch let error as ChatRequestError {
            XCTAssertEqual(error, .invalidCredential)
        }
    }

    func testPrematureDisconnectWithNoFinishOrUsageThrows() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}

        """
        let http = FakeStreamingHTTPClient(statusCode: 200, chunks: [Data(sse.utf8)])
        let client = StandardChatStreamingClient(
            service: .venice,
            httpClient: http,
            endpointURL: URL(string: "https://api.venice.ai/api/v1/chat/completions")!
        )

        do {
            _ = try await collect(client.streamChatCompletion(apiKey: "key", modelID: "model", messages: []))
            XCTFail("Expected an error to be thrown")
        } catch let error as ChatRequestError {
            XCTAssertEqual(error, .prematureDisconnect)
        }
    }

    func testRequestBodyIncludesModelMessagesAndStreamOptions() async throws {
        let sse = "data: {\"choices\":[{\"finish_reason\":\"stop\"}]}\n\n"
        let http = FakeStreamingHTTPClient(statusCode: 200, chunks: [Data(sse.utf8)])
        let client = StandardChatStreamingClient(
            service: .venice,
            httpClient: http,
            endpointURL: URL(string: "https://api.venice.ai/api/v1/chat/completions")!
        )

        _ = try? await collect(
            client.streamChatCompletion(
                apiKey: "my-key",
                modelID: "llama-3.2-3b",
                messages: [OutgoingChatMessage(role: .user, content: "Hi")]
            )
        )

        let request = http.lastRequest
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer my-key")
        let body = try JSONSerialization.jsonObject(with: request!.httpBody!) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "llama-3.2-3b")
        XCTAssertEqual(body?["stream"] as? Bool, true)
        let messages = body?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.first?["role"] as? String, "user")
        XCTAssertEqual(messages?.first?["content"] as? String, "Hi")
    }
}
