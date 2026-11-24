import Foundation
import Testing
@testable import NotchIsland

/// Builds SSE `data:` lines the way the API sends them.
func sse(_ events: [[String: Any]]) -> [String] {
    events.flatMap { e -> [String] in
        let json = String(data: try! JSONSerialization.data(withJSONObject: e), encoding: .utf8)!
        return ["event: \(e["type"] as! String)", "data: \(json)", ""]
    }
}

func accumulate(_ events: [[String: Any]]) -> StreamAccumulator {
    var acc = StreamAccumulator()
    for line in sse(events) { if let e = SSEParser.event(fromLine: line) { acc.apply(e) } }
    return acc
}

enum Events {
    static func start(_ model: String = "claude-sonnet-5-5") -> [String: Any] {
        ["type": "message_start", "message": ["id": "msg_1", "type": "message", "role": "assistant", "model": model, "content": [Any]()]]
    }
    static func blockStart(_ i: Int, _ block: [String: Any]) -> [String: Any] { ["type": "content_block_start", "index": i, "content_block": block] }
    static func text(_ i: Int, _ t: String) -> [String: Any] { ["type": "content_block_delta", "index": i, "delta": ["type": "text_delta", "text": t]] }
    static func stop(_ i: Int) -> [String: Any] { ["type": "content_block_stop", "index": i] }
    static func done(_ reason: String) -> [String: Any] {
        ["type": "message_delta", "delta": ["stop_reason": reason], "usage": ["output_tokens": 12]]
    }
    static let end: [String: Any] = ["type": "message_stop"]
    static let ping: [String: Any] = ["type": "ping"]

    static func simpleAnswer(_ parts: [String], reason: String = "end_turn") -> [[String: Any]] {
        [start(), ping, blockStart(0, ["type": "text", "text": ""])] + parts.map { text(0, $0) } + [stop(0), done(reason), end]
    }
}

@Suite("SSE parsing")
struct SSEParserTests {
    @Test func parsesDataLinesOnly() {
        #expect(SSEParser.event(fromLine: "event: message_start") == nil)
        #expect(SSEParser.event(fromLine: "") == nil)
        #expect(SSEParser.event(fromLine: ": keep-alive") == nil)
        #expect(SSEParser.event(fromLine: "data: {not json") == nil)
        #expect(SSEParser.event(fromLine: #"data: {"type":"ping"}"#)?["type"] as? String == "ping")
        #expect(SSEParser.event(fromLine: #"data:{"type":"ping"}"#)?["type"] as? String == "ping")
    }
}

@Suite("Stream accumulation")
struct StreamAccumulatorTests {
    @Test func plainTextAnswer() {
        let acc = accumulate(Events.simpleAnswer(["Hel", "lo", " there"]))
        #expect(acc.text == "Hello there")
        #expect(acc.stopReason == "end_turn")
        #expect(acc.model == "claude-sonnet-5-5")
        #expect(acc.activity == .writing)
        #expect(acc.errorMessage == nil)
        #expect(!acc.usedFallback)
    }

    @Test func thinkingThenTextKeepsSignatureForResume() {
        let acc = accumulate([
            Events.start(),
            Events.blockStart(0, ["type": "thinking", "thinking": ""]),
            ["type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "sig-abc"]],
            Events.stop(0),
            Events.blockStart(1, ["type": "text", "text": ""]),
            Events.text(1, "Answer"),
            Events.stop(1), Events.done("end_turn"), Events.end,
        ])
        #expect(acc.text == "Answer")
        let resume = acc.contentForResume
        #expect(resume.count == 2)
        #expect(resume[0]["type"] as? String == "thinking")
        #expect(resume[0]["signature"] as? String == "sig-abc")
    }

    @Test func webSearchShowsQueryAndCollectsSources() {
        var acc = StreamAccumulator()
        let events: [[String: Any]] = [
            Events.start(),
            Events.blockStart(0, ["type": "server_tool_use", "id": "srvtoolu_1", "name": "web_search", "input": [String: Any]()]),
            ["type": "content_block_delta", "index": 0, "delta": ["type": "input_json_delta", "partial_json": #"{"query": "tahoe "#]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "input_json_delta", "partial_json": #"weather"}"#]],
            Events.stop(0),
        ]
        for line in sse(events) { if let e = SSEParser.event(fromLine: line) { acc.apply(e) } }
        #expect(acc.activity == .searching("tahoe weather"))
        #expect(acc.searches == 1)

        let rest: [[String: Any]] = [
            Events.blockStart(1, ["type": "web_search_tool_result", "tool_use_id": "srvtoolu_1", "content": [
                ["type": "web_search_result", "url": "https://www.weather.gov/rev", "title": "NWS Reno", "encrypted_content": "x"],
                ["type": "web_search_result", "url": "https://example.com/a", "title": "Example", "encrypted_content": "y"],
            ]]),
            Events.stop(1),
            Events.blockStart(2, ["type": "text", "text": ""]),
            Events.text(2, "Snow Saturday."),
            ["type": "content_block_delta", "index": 2, "delta": ["type": "citations_delta", "citation": [
                "type": "web_search_result_location", "url": "https://www.weather.gov/rev", "title": "NWS Reno", "cited_text": "snow"]]],
            ["type": "content_block_delta", "index": 2, "delta": ["type": "citations_delta", "citation": [
                "type": "web_search_result_location", "url": "https://news.example.org/x", "title": "News", "cited_text": "snow"]]],
            Events.stop(2), Events.done("end_turn"), Events.end,
        ]
        for line in sse(rest) { if let e = SSEParser.event(fromLine: line) { acc.apply(e) } }
        #expect(acc.text == "Snow Saturday.")
        #expect(acc.sources.map(\.host) == ["weather.gov", "example.com", "news.example.org"]) // deduplicated, in order
        #expect(acc.sources.first?.title == "NWS Reno")
        // The search block keeps its parsed input for resuming a paused turn.
        #expect((acc.contentForResume[0]["input"] as? [String: Any])?["query"] as? String == "tahoe weather")
        #expect((acc.contentForResume[2]["citations"] as? [[String: Any]])?.count == 2)
    }

    @Test func failedSearchResultIsIgnored() {
        let acc = accumulate([
            Events.start(),
            Events.blockStart(0, ["type": "web_search_tool_result", "tool_use_id": "t",
                                  "content": ["type": "web_search_tool_result_error", "error_code": "max_uses_exceeded"]]),
            Events.stop(0), Events.done("end_turn"),
        ])
        #expect(acc.sources.isEmpty)
    }

    @Test func pauseTurnIsReported() {
        #expect(accumulate(Events.simpleAnswer(["Looking"], reason: "pause_turn")).stopReason == "pause_turn")
    }

    @Test func overloadedErrorEvent() {
        let acc = accumulate([Events.start(), ["type": "error", "error": ["type": "overloaded_error", "message": "Overloaded"]]])
        #expect(acc.errorMessage?.contains("overloaded") == true)
    }

    @Test func fallbackDropsModelInternalBlocksBeforeTheSwitch() {
        let acc = accumulate([
            Events.start(),
            Events.blockStart(0, ["type": "thinking", "thinking": "", "signature": "s1"]), Events.stop(0),
            Events.blockStart(1, ["type": "server_tool_use", "id": "unpaired", "name": "web_search", "input": [String: Any]()]), Events.stop(1),
            Events.blockStart(2, ["type": "server_tool_use", "id": "paired", "name": "web_search", "input": [String: Any]()]), Events.stop(2),
            Events.blockStart(3, ["type": "web_search_tool_result", "tool_use_id": "paired", "content": [Any]()]), Events.stop(3),
            Events.blockStart(4, ["type": "text", "text": "partial "]), Events.stop(4),
            Events.blockStart(5, ["type": "fallback", "from": ["model": "claude-sonnet-5-5"], "to": ["model": "claude-sonnet-5"]]), Events.stop(5),
            Events.blockStart(6, ["type": "thinking", "thinking": "", "signature": "s2"]), Events.stop(6),
            Events.blockStart(7, ["type": "text", "text": ""]), Events.text(7, "rest"), Events.stop(7),
            Events.done("end_turn"),
        ])
        #expect(acc.usedFallback)
        #expect(acc.text == "partial rest")
        let types = acc.contentForResume.map { $0["type"] as? String ?? "" }
        let ids = acc.contentForResume.compactMap { $0["id"] as? String }
        #expect(types == ["server_tool_use", "web_search_tool_result", "text", "fallback", "thinking", "text"])
        #expect(ids == ["paired"])
    }
}
