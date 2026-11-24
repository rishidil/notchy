import Combine
import Foundation
import SQLite3
import Testing
@testable import NotchIsland

@Suite("Engine routing")
struct EngineRouterTests {
    let all: Set<ChatEngineKind> = [.onDevice, .claudeT3, .claudeAPI]

    @Test func automaticSendsQuickQuestionsOnDevice() {
        #expect(EngineRouter.pick(choice: .auto, available: all, hasFiles: false, questionLength: 30, current: nil) == .onDevice)
    }

    @Test func automaticSendsFilesAndLongQuestionsToClaudeT3First() {
        #expect(EngineRouter.pick(choice: .auto, available: all, hasFiles: true, questionLength: 30, current: nil) == .claudeT3)
        #expect(EngineRouter.pick(choice: .auto, available: all, hasFiles: false, questionLength: 900, current: nil) == .claudeT3)
        #expect(EngineRouter.pick(choice: .auto, available: [.onDevice, .claudeAPI], hasFiles: true, questionLength: 30, current: nil) == .claudeAPI)
        #expect(EngineRouter.pick(choice: .auto, available: all, hasFiles: false, questionLength: 30, current: nil, preferClaude: true) == .claudeT3)
    }

    @Test func automaticKeepsTheChatsEngine() {
        // Once a chat moved to Claude, short follow-ups stay there (Claude has the context).
        #expect(EngineRouter.pick(choice: .auto, available: all, hasFiles: false, questionLength: 20, current: .claudeT3) == .claudeT3)
        // A chat on the on-device model moves to Claude when files arrive.
        #expect(EngineRouter.pick(choice: .auto, available: all, hasFiles: true, questionLength: 20, current: .onDevice) == .claudeT3)
    }

    @Test func automaticFallsBack() {
        #expect(EngineRouter.pick(choice: .auto, available: [.claudeAPI], hasFiles: false, questionLength: 10, current: nil) == .claudeAPI)
        #expect(EngineRouter.pick(choice: .auto, available: [.onDevice], hasFiles: false, questionLength: 900, current: nil) == .onDevice)
        // Files with only the on-device model: it can still read short text files.
        #expect(EngineRouter.pick(choice: .auto, available: [.onDevice], hasFiles: true, questionLength: 10, current: nil) == .onDevice)
        #expect(EngineRouter.pick(choice: .auto, available: [], hasFiles: false, questionLength: 10, current: nil) == nil)
    }

    @Test func forcedChoiceIsRespected() {
        #expect(EngineRouter.pick(choice: .claudeAPI, available: all, hasFiles: false, questionLength: 10, current: .onDevice) == .claudeAPI)
        #expect(EngineRouter.pick(choice: .onDevice, available: all, hasFiles: true, questionLength: 10, current: nil) == .onDevice)
        #expect(EngineRouter.pick(choice: .claudeT3, available: [.onDevice], hasFiles: false, questionLength: 10, current: nil) == nil)
    }

    @Test func transcriptForAnEngineJoiningMidChat() throws {
        typealias M = AssistantService.ChatMessage
        let msgs = [M(role: .user, text: "Hi"), M(role: .assistant, text: "Hello!"), M(role: .user, text: "x"),
                    M(role: .assistant, text: "Oops", isError: true)]
        let t = try #require(EngineRouter.transcript(msgs))
        #expect(t == "Earlier in this chat:\nUser: Hi\n\nAssistant: Hello!\n\nUser: x")
        #expect(EngineRouter.transcript([]) == nil)
    }
}

@Suite("On-device prompts")
struct OnDevicePromptTests {
    @Test func inlinesShortTextFiles() throws {
        let t = TempDir()
        let f = ClaudeAttachment.make(t.file("list.txt", "eggs, milk"))
        let p = try OnDeviceEngine.prompt("What's on the list?", files: [f], context: "Earlier in this chat:\nUser: hi")
        #expect(p == "Earlier in this chat:\nUser: hi\n\nFile list.txt:\neggs, milk\n\nWhat's on the list?")
    }

    @Test func rejectsWhatTheSmallModelCantRead() {
        let t = TempDir()
        let big = ClaudeAttachment.make(t.file("big.txt", String(repeating: "x", count: OnDeviceEngine.maxInlineCharacters + 1)))
        #expect(throws: EngineError.self) { try OnDeviceEngine.prompt("Summarize", files: [big], context: nil) }
        let image = ClaudeAttachment.make(t.png("p.png", width: 4, height: 4))
        #expect(throws: EngineError.self) { try OnDeviceEngine.prompt("What is this?", files: [image], context: nil) }
    }

    @Test func statusAlwaysExplainsItself() {
        #expect(!OnDeviceEngine.status.note.isEmpty)
    }
}

@Suite("Claude via T3 Code: messages and status")
struct T3ChatMessageTests {
    @Test func firstMessageCarriesThePreamble() {
        let m = T3ChatEngine.message("What's 2+2?", fileNames: ["abc/notes.txt"], context: nil,
                                     preamble: T3ChatEngine.preamble(filesFolder: "files/"))
        #expect(m.hasPrefix("[Notchy]"))
        #expect(m.contains("Attached: files/abc/notes.txt"))
        #expect(m.hasSuffix("What's 2+2?"))
        #expect(T3ChatEngine.message("Next?", fileNames: [], context: nil, preamble: nil) == "Next?")
    }

    @Test(arguments: [
        (#"{"enabled":true,"installed":true,"auth":{"status":"authenticated","label":"Claude Max Subscription"}}"#, true, "Claude Max"),
        (#"{"enabled":true,"installed":true,"auth":{"status":"unauthenticated"}}"#, false, "Sign in"),
        (#"{"enabled":false,"installed":true,"auth":{"status":"authenticated"}}"#, false, "turned off"),
        (#"{"enabled":true,"installed":false}"#, false, "isn't installed"),
    ])
    func providerStatus(json: String, available: Bool, note: String) throws {
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let s = T3ChatEngine.providerStatus(obj)
        #expect(s.available == available)
        #expect(s.note.contains(note))
        #expect(!T3ChatEngine.status(cliPath: nil).available)
    }

    @Test func copiesAttachmentsWithoutOverwriting() throws {
        let src = TempDir(), dst = TempDir()
        let a = ClaudeAttachment.make(src.file("notes.txt", "one"))
        #expect(try T3ChatEngine.copy([a], into: dst.url) == ["notes.txt"])
        #expect(try T3ChatEngine.copy([a], into: dst.url) == ["notes 2.txt"])
        #expect(try String(contentsOf: dst.url.appendingPathComponent("notes 2.txt"), encoding: .utf8) == "one")
    }

    @Test(arguments: [
        ("assistant_message", nil, StreamAccumulator.Activity.writing),
        ("web_search", #"{"patterns":["tahoe weather"]}"#, .searching("tahoe weather")),
        ("command_execution", nil, .working("Running a command")),
        ("reasoning", nil, .thinking),
        ("approval_request", nil, .working("Waiting for you")),
    ] as [(String, String?, StreamAccumulator.Activity)])
    func activityFromTurnItems(type: String, payload: String?, expected: StreamAccumulator.Activity) {
        #expect(T3ChatDB.activity(latestItem: [type, "completed", payload]) == expected)
    }
}

// MARK: - End to end against a fake `t3` and a scratch database

/// A scratch copy of the parts of T3 Code's database the chat engine reads, plus a fake `t3` command that writes to it
/// the way T3 Code does: a run, a web search, then an answer that streams in and completes.
final class FakeT3 {
    let dir = TempDir()
    var db: String { dir.url.appendingPathComponent("statev2.sqlite").path }
    var cli: String { dir.url.appendingPathComponent("t3").path }
    var log: String { dir.url.appendingPathComponent("calls.log").path }

    init() {
        let schema = """
        CREATE TABLE projection_projects (project_id TEXT PRIMARY KEY, title TEXT, workspace_root TEXT, deleted_at TEXT, archived_at TEXT);
        CREATE TABLE orchestration_v2_projection_runs (run_id TEXT PRIMARY KEY, thread_id TEXT, ordinal INTEGER, status TEXT);
        CREATE TABLE orchestration_v2_projection_messages (message_id TEXT PRIMARY KEY, thread_id TEXT, run_id TEXT, role TEXT,
            streaming INTEGER, created_at TEXT, payload_json TEXT);
        CREATE TABLE orchestration_v2_projection_turn_items (turn_item_id TEXT PRIMARY KEY, thread_id TEXT, run_id TEXT, ordinal INTEGER,
            type TEXT, status TEXT, payload_json TEXT);
        CREATE TABLE orchestration_v2_projection_runtime_requests (runtime_request_id TEXT PRIMARY KEY, thread_id TEXT, kind TEXT,
            status TEXT, payload_json TEXT);
        """
        var handle: OpaquePointer?
        sqlite3_open(db, &handle)
        sqlite3_exec(handle, schema, nil, nil, nil)
        sqlite3_close(handle)

        let script = """
        #!/bin/bash
        DB='\(db)'
        echo "$*" >> '\(log)'
        msg() { sqlite3 "$DB" "INSERT OR REPLACE INTO orchestration_v2_projection_messages VALUES ('$1','th1','$2','assistant',$3,'$4','{\\"text\\":\\"$5\\"}');"; }
        case "$1 $2" in
          "project add")
            sqlite3 "$DB" "INSERT INTO projection_projects VALUES ('p1','Notchy','${@: -1}',NULL,NULL);" ;;
          "thread start")
            cat > '\(dir.url.path)/first-message.txt'
            sqlite3 "$DB" "INSERT INTO orchestration_v2_projection_runs VALUES ('r1','th1',1,'running');
              INSERT INTO orchestration_v2_projection_turn_items VALUES ('i1','th1','r1',1,'web_search','running','{\\"patterns\\":[\\"capital of japan\\"]}');"
            ( sleep 0.6; msg m1 r1 1 a "Tokyo is"; sleep 0.6; msg m1 r1 0 a "Tokyo is the capital.";
              sqlite3 "$DB" "INSERT INTO orchestration_v2_projection_turn_items VALUES ('i2','th1','r1',2,'assistant_message','completed','{}');
                UPDATE orchestration_v2_projection_runs SET status='completed' WHERE run_id='r1';" ) >/dev/null 2>&1 &
            echo '{"threadId":"th1","projectId":"p1","runId":"r1"}' ;;
          "thread send")
            cat > '\(dir.url.path)/second-message.txt'
            ( sleep 0.4; sqlite3 "$DB" "INSERT INTO orchestration_v2_projection_runs VALUES ('r2','th1',2,'completed');"
              msg m2 r2 0 b "About 14 million people." ) >/dev/null 2>&1 &
            echo '{"runId":"r2"}' ;;
        esac
        """
        FileManager.default.createFile(atPath: cli, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
    }
}

@Suite("Claude via T3 Code: end to end (fake T3)", .serialized)
@MainActor
struct T3ChatEngineTests {
    @Test(.timeLimit(.minutes(1)))
    func startsAChatStreamsTheAnswerAndFollowsUp() async throws {
        let fake = FakeT3()
        let chats = TempDir()
        let oldPath = T3ChatDB.path, oldFolder = T3ChatEngine.folder
        T3ChatDB.path = fake.db
        T3ChatEngine.folder = chats.url
        defer { T3ChatDB.path = oldPath; T3ChatEngine.folder = oldFolder }

        let agents = AgentsService()
        agents.overrideCLI(fake.cli)
        let s = AssistantService(agents: agents)
        s.choice = .claudeT3
        s.t3Model = .sonnet
        s.overrideAvailability([.claudeT3])
        var activities: [StreamAccumulator.Activity] = []
        var texts: [String] = []
        let watcher = s.$activity.sink { activities.append($0) }
        let textWatcher = s.$messages.sink { if let t = $0.last?.text, !t.isEmpty { texts.append(t) } }
        defer { watcher.cancel(); textWatcher.cancel() }

        let attachments = TempDir()
        let notes = attachments.file("notes.txt", "hi")
        s.attach([notes])
        s.send("What's the capital of Japan?")
        await waitUntilIdle(s, timeout: 20)

        #expect(s.messages.last?.text == "Tokyo is the capital.")
        #expect(s.messages.last?.engine == .claudeT3)
        #expect(!(s.messages.last?.isError ?? true))
        #expect(activities.contains(.searching("capital of japan")))
        #expect(texts.contains("Tokyo is")) // streamed before it completed

        let calls = try String(contentsOfFile: fake.log, encoding: .utf8)
        #expect(calls.contains("project add --title Notchy \(chats.url.path)"))
        #expect(calls.contains("thread start --json --title What's the capital of Japan? --provider claudeAgent --model claude-sonnet-5-5"))
        let first = try String(contentsOfFile: fake.dir.url.path + "/first-message.txt", encoding: .utf8)
        #expect(first.hasPrefix("[Notchy]"))
        #expect(first.contains("Attached: files/"))
        // The file was copied into the chat's folder for Claude to read.
        let copied = try FileManager.default.subpathsOfDirectory(atPath: chats.url.appendingPathComponent("files").path)
        #expect(copied.contains { $0.hasSuffix("notes.txt") })

        s.send("How many people live there?")
        await waitUntilIdle(s, timeout: 20)
        #expect(s.messages.last?.text == "About 14 million people.")
        #expect(try String(contentsOfFile: fake.dir.url.path + "/second-message.txt", encoding: .utf8) == "How many people live there?")
        #expect(try String(contentsOfFile: fake.log, encoding: .utf8).contains("thread send th1 -"))
    }

    @Test func noT3ShowsAHelpfulError() async {
        let agents = AgentsService()
        agents.overrideCLI(nil)
        let s = AssistantService(agents: agents)
        s.choice = .claudeT3
        s.overrideAvailability([.claudeT3])
        s.send("Hi")
        await waitUntilIdle(s, timeout: 5)
        #expect(s.messages.last?.isError == true)
        #expect(s.messages.last?.text.contains("T3 Code") == true)
    }
}
