import Foundation
import Testing
@testable import NotchIsland

/// Serves canned API responses and records every request Notchy sends.
final class MockAPI: URLProtocol {
    struct Reply { var status = 200; var body: String }
    nonisolated(unsafe) static var replies: [Reply] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [[String: Any]] = []
    static let lock = NSLock()

    static func reset(_ r: [Reply]) { lock.lock(); replies = r; requests = []; bodies = []; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var d = Data(); var buf = [UInt8](repeating: 0, count: 65_536)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; d.append(buf, count: n) }
            stream.close(); data = d
        }
        Self.lock.lock()
        Self.requests.append(request)
        if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { Self.bodies.append(obj) }
        let reply = Self.replies.isEmpty ? Reply(status: 500, body: "{}") : Self.replies.removeFirst()
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["content-type": reply.status == 200 ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    static func stream(_ events: [[String: Any]]) -> Reply { Reply(body: sse(events).joined(separator: "\n") + "\n") }
}

@MainActor
func makeService(credential: ClaudeCredential? = ClaudeCredential(kind: .apiKey, secret: "sk-ant-test", source: .keychain)) -> ClaudeService {
    let s = ClaudeService()
    s.resolver = ClaudeCredentialResolver(keychainKey: { credential?.secret }, environment: { [:] }, antToken: { nil })
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockAPI.self]
    s.session = URLSession(configuration: config)
    s.model = .sonnet
    s.webSearch = true
    return s
}

@MainActor
func waitUntilIdle(_ s: ClaudeService, timeout: TimeInterval = 5) async {
    let deadline = Date().addingTimeInterval(timeout)
    try? await Task.sleep(nanoseconds: 20_000_000)
    while s.isStreaming && Date() < deadline { try? await Task.sleep(nanoseconds: 20_000_000) }
}

@Suite("Claude conversation", .serialized)
@MainActor
struct ClaudeServiceTests {
    @Test func streamsAnAnswerAndKeepsTheConversation() async throws {
        MockAPI.reset([MockAPI.stream(Events.simpleAnswer(["Hello", " there"])), MockAPI.stream(Events.simpleAnswer(["Again"]))])
        let s = makeService()
        var announced: String?
        s.onAnswer = { announced = $0 }

        s.send("  Hi Claude  ")
        #expect(s.isStreaming)
        await waitUntilIdle(s)
        #expect(!s.isStreaming)
        #expect(s.messages.count == 2)
        #expect(s.messages[0].text == "Hi Claude")
        #expect(s.messages[1].text == "Hello there")
        #expect(!s.messages[1].isError)
        #expect(announced == "Hello there")

        let first = try #require(MockAPI.bodies.first)
        #expect(first["model"] as? String == "claude-sonnet-5-5")
        #expect((first["tools"] as? [[String: Any]])?.first?["type"] as? String == "web_search_20260209")
        #expect(MockAPI.requests.first?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")

        s.send("And again?")
        await waitUntilIdle(s)
        let second = try #require(MockAPI.bodies.last?["messages"] as? [[String: Any]])
        #expect(second.count == 3)
        #expect(second[1]["role"] as? String == "assistant")
        #expect(second[1]["content"] as? String == "Hello there")
        #expect(((second[2]["content"] as? [[String: Any]])?.last?["text"]) as? String == "And again?")
        #expect(s.messages.last?.text == "Again")
    }

    @Test func attachmentsAreSentBeforeTheQuestion() async throws {
        let t = TempDir()
        let notes = t.file("notes.txt", "Buy milk")
        let blob = t.file("x.bin", Data([0, 0, 1]))
        MockAPI.reset([MockAPI.stream(Events.simpleAnswer(["Milk."]))])
        let s = makeService()
        s.attach([notes, blob, notes])
        #expect(s.attachments.count == 2) // no duplicates
        s.send("")
        await waitUntilIdle(s)
        #expect(s.attachments.isEmpty)
        #expect(s.messages[0].text == "What's in this file?")
        #expect(s.messages[0].attachmentNames == ["notes.txt"]) // the unreadable file isn't sent
        let content = try #require((MockAPI.bodies.first?["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        #expect(content.map { $0["type"] as? String } == ["document", "text"])
        #expect(content[0]["title"] as? String == "notes.txt")
    }

    @Test func apiErrorIsShownAndTheTurnIsDropped() async throws {
        MockAPI.reset([MockAPI.Reply(status: 401, body: #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#),
                       MockAPI.stream(Events.simpleAnswer(["ok"]))])
        let s = makeService()
        s.send("Hi")
        await waitUntilIdle(s)
        #expect(s.messages[1].isError)
        #expect(s.messages[1].text.contains("API key"))
        s.send("Hi again")
        await waitUntilIdle(s)
        #expect((MockAPI.bodies.last?["messages"] as? [[String: Any]])?.count == 1)
    }

    @Test func pausedTurnIsResumed() async throws {
        let paused: [[String: Any]] = [
            Events.start(),
            Events.blockStart(0, ["type": "text", "text": ""]), Events.text(0, "Let me check. "), Events.stop(0),
            Events.blockStart(1, ["type": "server_tool_use", "id": "srv1", "name": "web_search", "input": [String: Any]()]),
            ["type": "content_block_delta", "index": 1, "delta": ["type": "input_json_delta", "partial_json": #"{"query":"q"}"#]],
            Events.stop(1),
            Events.done("pause_turn"), Events.end,
        ]
        MockAPI.reset([MockAPI.stream(paused), MockAPI.stream(Events.simpleAnswer(["It's sunny."]))])
        let s = makeService()
        s.send("Weather?")
        await waitUntilIdle(s)
        #expect(MockAPI.bodies.count == 2)
        let resumed = try #require(MockAPI.bodies.last?["messages"] as? [[String: Any]])
        #expect(resumed.count == 2)
        let assistant = try #require(resumed[1]["content"] as? [[String: Any]])
        #expect(assistant.map { $0["type"] as? String } == ["text", "server_tool_use"])
        #expect((assistant[1]["input"] as? [String: Any])?["query"] as? String == "q")
        #expect(s.messages.last?.text == "Let me check. It's sunny.")
    }

    @Test func refusalIsNotShownAsAnAnswer() async {
        MockAPI.reset([MockAPI.stream(Events.simpleAnswer(["Partial"], reason: "refusal")), MockAPI.stream(Events.simpleAnswer(["ok"]))])
        let s = makeService()
        s.send("Something")
        await waitUntilIdle(s)
        #expect(s.messages[1].isError)
        #expect(!s.messages[1].text.contains("Partial"))
        s.send("Next")
        await waitUntilIdle(s)
        #expect((MockAPI.bodies.last?["messages"] as? [[String: Any]])?.count == 1)
    }

    @Test func cutOffAnswerGetsANote() async {
        MockAPI.reset([MockAPI.stream(Events.simpleAnswer(["Long"], reason: "max_tokens"))])
        let s = makeService()
        s.send("Write a lot")
        await waitUntilIdle(s)
        #expect(s.messages[1].text == "Long")
        #expect(s.messages[1].note?.contains("cut off") == true)
    }

    @Test func noCredentialAsksToConnect() async {
        MockAPI.reset([])
        let s = makeService(credential: nil)
        s.send("Hi")
        await waitUntilIdle(s)
        #expect(s.messages[1].isError)
        #expect(s.messages[1].text.contains("Connect Claude"))
        #expect(MockAPI.requests.isEmpty)
    }

    @Test func emptyPromptDoesNothingAndClearResets() async {
        MockAPI.reset([MockAPI.stream(Events.simpleAnswer(["ok"]))])
        let s = makeService()
        s.send("   ")
        #expect(s.messages.isEmpty)
        s.send("Hi")
        await waitUntilIdle(s)
        s.clear()
        #expect(s.messages.isEmpty)
        #expect(s.attachments.isEmpty)
    }
}
