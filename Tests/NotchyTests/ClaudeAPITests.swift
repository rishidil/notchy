import Foundation
import Testing
@testable import NotchIsland

@Suite("Claude request building")
struct ClaudeRequestTests {
    let apiKey = ClaudeCredential(kind: .apiKey, secret: "sk-ant-test", source: .keychain)
    let oauth = ClaudeCredential(kind: .oauthToken, secret: "oauth-token-abcdefghijklmnop", source: .antCLI)
    let messages: [[String: Any]] = [["role": "user", "content": "Hi"]]

    @Test func defaultsAreSonnetAndQuick() {
        #expect(ClaudeModel.default == .sonnet)
        #expect(ClaudeModel.sonnet.rawValue == "claude-sonnet-5-5")
        #expect(ClaudeEffort.default == .low)
    }

    @Test func bodyHasStreamingModelEffortAndCache() {
        let b = ClaudeAPI.body(model: .sonnet, effort: .medium, webSearch: false, system: "sys", messages: messages)
        #expect(b["model"] as? String == "claude-sonnet-5-5")
        #expect(b["stream"] as? Bool == true)
        #expect(b["max_tokens"] as? Int == ClaudeAPI.maxTokens)
        #expect(b["system"] as? String == "sys")
        #expect((b["output_config"] as? [String: String])?["effort"] == "medium")
        #expect((b["cache_control"] as? [String: String])?["type"] == "ephemeral")
        #expect(b["tools"] == nil)
        // Current models reject sampling parameters and explicit thinking budgets: never send them.
        for key in ["temperature", "top_p", "top_k", "thinking"] { #expect(b[key] == nil) }
        #expect((b["messages"] as? [[String: Any]])?.count == 1)
    }

    @Test func webSearchAddsCurrentServerTool() throws {
        let b = ClaudeAPI.body(model: .opus, effort: .low, webSearch: true, system: "s", messages: messages)
        let tools = try #require(b["tools"] as? [[String: Any]])
        #expect(tools.count == 1)
        #expect(tools[0]["type"] as? String == "web_search_20260209")
        #expect(tools[0]["name"] as? String == "web_search")
        #expect(tools[0]["max_uses"] as? Int == 5)
    }

    @Test func fallbacksOnlyWhereSupported() {
        #expect(ClaudeAPI.body(model: .sonnet, effort: .low, webSearch: false, system: "", messages: messages)["fallbacks"] as? String == "default")
        #expect(ClaudeAPI.body(model: .opus, effort: .low, webSearch: false, system: "", messages: messages)["fallbacks"] as? String == "default")
        #expect(ClaudeAPI.body(model: .haiku, effort: .low, webSearch: false, system: "", messages: messages)["fallbacks"] == nil)
    }

    @Test func apiKeyHeaders() {
        let h = ClaudeAPI.headers(credential: apiKey, model: .sonnet)
        #expect(h["x-api-key"] == "sk-ant-test")
        #expect(h["authorization"] == nil)
        #expect(h["anthropic-version"] == "2026-10-21")
        #expect(h["content-type"] == "application/json")
        #expect(h["anthropic-beta"] == "server-side-fallback-2026-07-01")
        #expect(ClaudeAPI.headers(credential: apiKey, model: .haiku)["anthropic-beta"] == nil)
    }

    @Test func oauthHeadersUseBearerAndBeta() {
        let h = ClaudeAPI.headers(credential: oauth, model: .sonnet)
        #expect(h["authorization"] == "Bearer oauth-token-abcdefghijklmnop")
        #expect(h["x-api-key"] == nil)
        #expect(h["anthropic-beta"] == "oauth-2025-04-20,server-side-fallback-2026-07-01")
        #expect(ClaudeAPI.headers(credential: oauth, model: .haiku)["anthropic-beta"] == "oauth-2025-04-20")
    }

    @Test func urlRequestIsAPostWithJSONBody() throws {
        let body = ClaudeAPI.body(model: .sonnet, effort: .low, webSearch: true, system: "s", messages: messages)
        let r = try ClaudeAPI.request(body: body, credential: apiKey, model: .sonnet)
        #expect(r.httpMethod == "POST")
        #expect(r.url == ClaudeAPI.messagesURL)
        #expect(r.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        let decoded = try #require(try JSONSerialization.jsonObject(with: r.httpBody ?? Data()) as? [String: Any])
        #expect(decoded["model"] as? String == "claude-sonnet-5-5")
    }

    @Test func systemPromptMentionsNotchAndDate() {
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let p = ClaudeAPI.systemPrompt(today: date)
        #expect(p.contains("Notchy"))
        #expect(p.contains(date.formatted(date: .complete, time: .omitted)))
    }

    @Test(arguments: [
        (401, #"{"error":{"type":"authentication_error","message":"invalid x-api-key"}}"#, "didn't accept your API key"),
        (400, #"{"error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API."}}"#, "out of credits"),
        (429, #"{"error":{"type":"rate_limit_error","message":"slow down"}}"#, "Rate limited"),
        (529, #"{"error":{"type":"overloaded_error","message":"Overloaded"}}"#, "overloaded"),
        (400, #"{"error":{"type":"invalid_request_error","message":"messages: text content blocks must be non-empty"}}"#, "must be non-empty"),
        (418, "not json", "(418)"),
    ])
    func errorMessages(status: Int, body: String, expected: String) {
        #expect(ClaudeAPI.errorMessage(status: status, body: Data(body.utf8)).contains(expected))
    }
}

@Suite("Claude credentials")
struct ClaudeCredentialTests {
    @Test func keychainWinsOverEverything() {
        let r = ClaudeCredentialResolver(keychainKey: { "sk-ant-keychain" }, environment: { ["ANTHROPIC_API_KEY": "sk-ant-env"] },
                                         antToken: { "token-from-ant-cli-xxxxxxxx" })
        #expect(r.resolve() == ClaudeCredential(kind: .apiKey, secret: "sk-ant-keychain", source: .keychain))
    }

    @Test func environmentThenAntCLI() {
        let env = ClaudeCredentialResolver(keychainKey: { nil }, environment: { ["ANTHROPIC_API_KEY": " sk-ant-env \n"] },
                                           antToken: { "token-from-ant-cli-xxxxxxxx" })
        #expect(env.resolve() == ClaudeCredential(kind: .apiKey, secret: "sk-ant-env", source: .environment))
        let ant = ClaudeCredentialResolver(keychainKey: { "  " }, environment: { ["ANTHROPIC_API_KEY": ""] },
                                           antToken: { "token-from-ant-cli-xxxxxxxx" })
        #expect(ant.resolve() == ClaudeCredential(kind: .oauthToken, secret: "token-from-ant-cli-xxxxxxxx", source: .antCLI))
    }

    @Test func noneFound() {
        let r = ClaudeCredentialResolver(keychainKey: { nil }, environment: { [:] }, antToken: { nil })
        #expect(r.resolve() == nil)
    }

    @Test(arguments: [
        ("sk-ant-oat01-abcdefghijklmnopqrstuvwxyz\n", "sk-ant-oat01-abcdefghijklmnopqrstuvwxyz"),
        ("Buildfile: build.xml does not exist!\nBUILD FAILED", nil),
        (#"{"access_token":"abc"}"#, nil),
        ("short", nil),
        ("", nil),
    ] as [(String, String?)])
    func antOutputValidation(output: String, expected: String?) {
        #expect(ClaudeCredentialResolver.validToken(output) == expected)
    }
}
