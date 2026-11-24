import Foundation
import Testing
@testable import NotchIsland

@Suite("T3 Code responses")
struct T3RemoteTests {
    @Test func approvalCommand() {
        let c = T3Remote.respondCommand(threadID: "th", requestID: "rq", decision: "acceptForSession", answers: nil, commandID: "cmd")
        #expect(c["type"] as? String == "runtime-request.respond")
        #expect(c["commandId"] as? String == "cmd")
        #expect(c["threadId"] as? String == "th")
        #expect(c["requestId"] as? String == "rq")
        #expect(c["decision"] as? String == "acceptForSession")
        #expect(c["answers"] == nil)
    }

    @Test func answersCommand() throws {
        let c = T3Remote.respondCommand(threadID: "th", requestID: "rq", decision: nil,
                                        answers: ["Which?": "B", "Pick any": ["x", "y"]])
        #expect(c["decision"] == nil)
        let a = try #require(c["answers"] as? [String: Any])
        #expect(a["Which?"] as? String == "B")
        #expect(a["Pick any"] as? [String] == ["x", "y"])
        // Fresh command ids by default.
        #expect(T3Remote.respondCommand(threadID: "a", requestID: "b", decision: nil, answers: nil)["commandId"] as? String
                != T3Remote.respondCommand(threadID: "a", requestID: "b", decision: nil, answers: nil)["commandId"] as? String)
    }

    @Test func parsesIssuedSessionWithTrailingOutput() throws {
        let out = """
        {
          "sessionId": "e621dc54",
          "token": "eyJ2IjoxLCJr.abc",
          "method": "bearer-access-token",
          "scopes": ["orchestration:read", "orchestration:operate"],
          "client": { "label": "Notchy {x}", "deviceType": "bot" },
          "expiresAt": "2027-02-22T11:04:07.540Z"
        }


        some log line { not json
        """
        let s = try #require(T3Remote.parseIssued(Data(out.utf8)))
        #expect(s.sessionId == "e621dc54")
        #expect(s.token == "eyJ2IjoxLCJr.abc")
        #expect(s.expiresAt == ISO8601DateFormatter().date(from: "2027-02-22T11:04:07Z")?.addingTimeInterval(0.54))
        #expect(T3Remote.parseIssued(Data("Error: server not running".utf8)) == nil)
    }

    @Test func runtimeFileAndSocketURL() throws {
        let runtime = #"{"version":1,"pid":2219,"host":"127.0.0.1","port":3773,"origin":"http://127.0.0.1:3773"}"#
        let origin = try #require(T3Remote.originFromRuntime(Data(runtime.utf8)))
        #expect(origin.absoluteString == "http://127.0.0.1:3773")
        let ws = try #require(T3Remote.socketURL(origin: origin, ticket: "a+b/c=="))
        #expect(ws.scheme == "ws")
        #expect(ws.path == "/ws")
        let items = URLComponents(url: ws, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "orchestrationProtocol" }?.value == "2")
        #expect(items.first { $0.name == "wsTicket" }?.value == "a+b/c==")
        #expect(T3Remote.socketURL(origin: URL(string: "https://box.tailnet.ts.net")!, ticket: "t")?.scheme == "wss")
        #expect(T3Remote.originFromRuntime(Data("{}".utf8)) == nil)
    }

    @Test func parsesRPCExit() {
        #expect(T3Remote.parseExit(#"{"_tag":"Exit","requestId":"1","exit":{"_tag":"Success","value":{}}}"#, requestID: "1") == .success)
        let failure = #"{"_tag":"Exit","requestId":"1","exit":{"_tag":"Failure","cause":[{"_tag":"Fail","error":{"_tag":"OrchestrationV2DispatchCommandError","message":"No orchestration projection exists for thread x."}}]}}"#
        #expect(T3Remote.parseExit(failure, requestID: "1") == .failure("No orchestration projection exists for thread x."))
        #expect(T3Remote.parseExit(#"{"_tag":"Exit","requestId":"2","exit":{"_tag":"Success"}}"#, requestID: "1") == nil)
        #expect(T3Remote.parseExit(#"{"_tag":"Chunk","requestId":"1","values":[]}"#, requestID: "1") == nil)
        #expect(T3Remote.parseExit("garbage", requestID: "1") == nil)
    }
}

@Suite("T3 Code pending requests")
struct PendingRequestTests {
    typealias P = AgentsService.PendingRequest

    @Test func approvalWithOptions() throws {
        let item: [String: Any] = [
            "type": "approval_request", "requestId": "rq1", "requestKind": "command",
            "prompt": "rm -rf build", "reason": "Clean the build",
            "options": [["decision": "accept", "label": "Yes"], ["decision": "decline", "label": "No", "warning": "Stops the run"]],
        ]
        let r = try #require(P.parse(item, threadID: "th"))
        #expect(r.id == "rq1")
        #expect(r.threadID == "th")
        #expect(r.isApproval)
        guard case .approval(let kind, let prompt, let reason, let options) = r.kind else { Issue.record("not an approval"); return }
        #expect(kind == "command")
        #expect(prompt == "rm -rf build")
        #expect(reason == "Clean the build")
        #expect(options == [.init(decision: "accept", label: "Yes"), .init(decision: "decline", label: "No", warning: "Stops the run")])
    }

    @Test func approvalWithoutOptionsGetsDefaults() throws {
        let r = try #require(P.parse(["type": "approval_request", "requestId": "rq", "requestKind": "file-change", "prompt": ""], threadID: "t"))
        guard case .approval(_, let prompt, _, let options) = r.kind else { Issue.record("not an approval"); return }
        #expect(prompt == nil)
        #expect(options.map(\.decision) == ["accept", "acceptForSession", "decline"])
    }

    @Test func questions() throws {
        let item: [String: Any] = [
            "type": "user_input_request", "requestId": "rq2",
            "questions": [
                ["id": "Which model?", "header": "Model", "question": "Which model?", "multiSelect": false,
                 "options": [["label": "Sonnet", "description": "Fast"], ["label": "Opus", "description": "Smart", "value": "opus"]]],
                ["id": "Extras", "header": "Extras", "question": "Pick any", "multiSelect": true, "allowCustomAnswer": false,
                 "options": [["label": "A", "description": ""]]],
            ],
        ]
        let r = try #require(P.parse(item, threadID: "th"))
        #expect(!r.isApproval)
        guard case .questions(let qs) = r.kind else { Issue.record("not questions"); return }
        #expect(qs.count == 2)
        #expect(qs[0].id == "Which model?")
        #expect(qs[0].options.map(\.label) == ["Sonnet", "Opus"])
        #expect(qs[0].options[1].value == "opus")
        #expect(qs[0].allowCustom)
        #expect(qs[1].multiSelect)
        #expect(!qs[1].allowCustom)
    }

    @Test func rejectsOtherItems() {
        #expect(P.parse(["type": "command_execution", "requestId": "x"], threadID: "t") == nil)
        #expect(P.parse(["type": "approval_request"], threadID: "t") == nil)
        #expect(P.parse(["type": "user_input_request", "requestId": "x", "questions": [Any]()], threadID: "t") == nil)
    }

    @Test func waitingOnQuestionNeedsOnlyQuestions() {
        var t = AgentsService.AgentThread(id: "1", projectID: "p", projectTitle: "p", projectPath: "/p", title: "T", status: "running",
                                          model: "", updatedAt: Date(), settled: false)
        #expect(!t.isWaitingOnQuestion)
        t.pendingRequests = 2; t.pendingQuestions = 1
        #expect(!t.isWaitingOnQuestion)
        #expect(t.needsAttention)
        t.pendingQuestions = 2
        #expect(t.isWaitingOnQuestion)
    }
}
