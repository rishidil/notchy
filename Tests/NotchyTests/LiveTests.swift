import Foundation
import Testing
@testable import NotchIsland

// Opt-in tests against real services (see scripts/test.sh). They're skipped unless their environment variable is set.

private let env = ProcessInfo.processInfo.environment

@Suite("Live: T3 Code", .serialized, .enabled(if: env["NOTCHY_LIVE_T3"] == "1"))
struct LiveT3Tests {
    let cli = NSHomeDirectory() + "/.local/bin/t3"

    /// Full round trip (token → ticket → WebSocket → dispatch) against the running T3 Code server, using a
    /// thread that doesn't exist so nothing real is answered. The server's "no such thread" reply proves the
    /// command was authenticated, parsed and routed.
    @Test func respondRoundTrip() throws {
        defer { T3Remote.shared.disconnect(cli: cli) }
        #expect(T3Remote.serverOrigin() != nil, "T3 Code must be running")
        do {
            try T3Remote.shared.respond(cli: cli, threadID: "00000000-0000-0000-0000-000000000000",
                                        requestID: "runtime-request:notchy-test", decision: "decline", answers: nil)
            Issue.record("expected the server to reject an unknown thread")
        } catch let T3Remote.RemoteError.server(message) {
            #expect(message.contains("No orchestration projection"))
        }
        #expect(T3Remote.shared.session != nil)
    }

    /// With NOTCHY_T3_ANSWER_THREAD=<thread id>: waits up to 3 minutes for a question in that thread, then answers
    /// it with the first option, the way the notch does.
    @Test(.enabled(if: env["NOTCHY_T3_ANSWER_THREAD"] != nil), .timeLimit(.minutes(4)))
    func answersARealQuestion() async throws {
        defer { T3Remote.shared.disconnect(cli: cli) }
        let thread = env["NOTCHY_T3_ANSWER_THREAD"]!
        var found: AgentsService.PendingRequest?
        for _ in 0..<180 {
            found = AgentsService.pendingRequests(threadID: thread).first { !$0.isApproval }
            if found != nil { break }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        let request = try #require(found, "no question appeared")
        guard case .questions(let qs) = request.kind else { return }
        var answers: [String: Any] = [:]
        for q in qs { answers[q.id] = q.multiSelect ? [q.options[0].label] : q.options[0].label }
        print("Answering \(qs.map(\.question)) with \(answers)")
        try T3Remote.shared.respond(cli: cli, threadID: thread, requestID: request.id, decision: nil, answers: answers)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(!AgentsService.pendingRequests(threadID: thread).contains { $0.id == request.id })
    }
}

@Suite("Live: Claude API", .serialized, .enabled(if: env["NOTCHY_LIVE_CLAUDE"] == "1"))
@MainActor
struct LiveClaudeTests {
    func service(_ model: ClaudeModel, web: Bool) -> ClaudeService {
        let s = ClaudeService()
        s.resolver = ClaudeCredentialResolver(keychainKey: { nil }) // env key or ant sign-in only
        s.model = model
        s.webSearch = web
        s.effort = .low
        return s
    }

    @Test(.timeLimit(.minutes(2)))
    func answersAQuestion() async throws {
        let s = service(.sonnet, web: false)
        s.send("Reply with exactly the word: pineapple")
        await waitUntilIdle(s, timeout: 90)
        #expect(s.messages.last?.isError == false, "\(s.messages.last?.text ?? "")")
        #expect(s.messages.last?.text.lowercased().contains("pineapple") == true)
        s.send("What word did you just say? One word.")
        await waitUntilIdle(s, timeout: 90)
        #expect(s.messages.last?.text.lowercased().contains("pineapple") == true)
    }

    @Test(.timeLimit(.minutes(3)))
    func searchesTheWebWithSources() async throws {
        let s = service(.sonnet, web: true)
        s.send("Search the web: what is the latest stable version of the Swift programming language? One sentence.")
        await waitUntilIdle(s, timeout: 150)
        let m = try #require(s.messages.last)
        #expect(!m.isError, "\(m.text)")
        #expect(!m.sources.isEmpty)
    }

    @Test(.timeLimit(.minutes(2)))
    func readsAnAttachedFile() async throws {
        let t = TempDir()
        let f = t.file("secret.txt", "The launch code word is MARMALADE.")
        let s = service(.haiku, web: false)
        s.attach([f])
        s.send("What is the code word in the file? One word.")
        await waitUntilIdle(s, timeout: 90)
        #expect(s.messages.last?.text.uppercased().contains("MARMALADE") == true, "\(s.messages.last?.text ?? "")")
    }
}
