import AppKit
import SQLite3
#if canImport(FoundationModels)
import FoundationModels
#endif

// The AI tab can answer with three engines behind one interface:
//
//   • On-device: Apple's built-in model (macOS 26+ with Apple Intelligence). Free, private, works offline; small.
//   • Claude via T3 Code: each chat is a T3 Code thread in a dedicated "Notchy" project, so it runs on the user's own
//     Claude plan through the Claude Code that T3 Code hosts. Notchy never sees Claude credentials.
//   • Claude API: the Messages API with the user's API key or Anthropic Console sign-in (pay per use).
//
// AssistantService picks an engine per question and owns the conversation shown in the notch.

enum ChatEngineKind: String, CaseIterable, Identifiable, Codable {
    case onDevice, claudeT3, claudeAPI
    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: "On-device model (Apple)"
        case .claudeT3: "Claude via T3 Code"
        case .claudeAPI: "Claude API"
        }
    }

    var shortName: String {
        switch self {
        case .onDevice: "On-device"
        case .claudeT3: "Claude · T3"
        case .claudeAPI: "Claude · API"
        }
    }

    /// Who's answering, for the live activity ("Claude is thinking").
    var speaker: String { self == .onDevice ? "Apple's model" : "Claude" }
    var isClaude: Bool { self != .onDevice }
    var symbol: String { self == .onDevice ? "apple.intelligence" : "sparkle" }
}

/// What the user wants answering their questions.
enum EngineChoice: String, CaseIterable, Identifiable {
    case auto, onDevice, claudeT3, claudeAPI
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: "Automatic"
        case .onDevice: ChatEngineKind.onDevice.title
        case .claudeT3: ChatEngineKind.claudeT3.title
        case .claudeAPI: ChatEngineKind.claudeAPI.title
        }
    }
    var engine: ChatEngineKind? { ChatEngineKind(rawValue: rawValue) }
}

/// Picks the engine for one question.
///
/// Automatic: short questions without files go to the on-device model (free and private); files and long questions
/// go to Claude (T3 Code first, then the API). A chat keeps its engine unless the question needs a different one.
enum EngineRouter {
    static let longQuestion = 600

    static func pick(choice: EngineChoice, available: Set<ChatEngineKind>, hasFiles: Bool, questionLength: Int,
                     current: ChatEngineKind?, preferClaude: Bool = false) -> ChatEngineKind? {
        if let forced = choice.engine { return available.contains(forced) ? forced : nil }
        let claude: ChatEngineKind? = available.contains(.claudeT3) ? .claudeT3 : (available.contains(.claudeAPI) ? .claudeAPI : nil)
        let needsClaude = preferClaude || hasFiles || questionLength > longQuestion
        if needsClaude, let claude { return claude }
        // Stay with the chat's engine when it can handle the question.
        if let current, available.contains(current), !(current == .onDevice && needsClaude) { return current }
        if available.contains(.onDevice) && !hasFiles { return .onDevice }
        return claude ?? (available.contains(.onDevice) ? .onDevice : nil)
    }

    /// The conversation so far, for an engine that joins mid-chat (it hasn't seen the earlier turns).
    static func transcript(_ messages: [AssistantService.ChatMessage], limit: Int = 6) -> String? {
        let turns = messages.filter { !$0.isError && !$0.text.isEmpty }.suffix(limit)
        guard !turns.isEmpty else { return nil }
        let lines = turns.map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
        return "Earlier in this chat:\n" + lines.joined(separator: "\n\n")
    }
}

struct EngineUpdate {
    var text = ""
    var activity: StreamAccumulator.Activity = .thinking
    var sources: [ClaudeSource] = []
    var pending: AgentsService.PendingRequest?
}

enum EngineResult: Equatable {
    case answer(text: String, sources: [ClaudeSource], note: String?)
    case failure(String)
}

@MainActor
protocol ChatEngine: AnyObject {
    var kind: ChatEngineKind { get }
    /// Answers one question, reporting progress through `update`. Cancel the calling Task to stop.
    func ask(_ question: String, files: [ClaudeAttachment], context: String?,
             update: @escaping (EngineUpdate) -> Void) async -> EngineResult
    /// Forgets the conversation (New Chat).
    func reset()
}

// MARK: - On-device (Apple Foundation Models)

@MainActor
final class OnDeviceEngine: ChatEngine {
    let kind = ChatEngineKind.onDevice
    /// Text files are pasted into the prompt up to this many characters (the model's whole context is ~4,000 tokens).
    nonisolated static let maxInlineCharacters = 6_000
    static let instructions = """
    You answer quick questions in Notchy, a small panel under the Mac's notch. Be brief: a sentence or a few short \
    lines. Use plain text with light Markdown (bold, lists starting with "- "). If you don't know something or it \
    needs current information, say so in one line.
    """

    private var session: AnyObject?

    /// Whether Apple's model can run here, and why not if it can't.
    nonisolated static var status: (available: Bool, note: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return (true, "Ready · free, private and works offline")
            case .unavailable(.appleIntelligenceNotEnabled): return (false, "Turn on Apple Intelligence in System Settings to use it")
            case .unavailable(.modelNotReady): return (false, "Apple's model is still downloading")
            case .unavailable(.deviceNotEligible): return (false, "This Mac doesn't support Apple Intelligence")
            case .unavailable: return (false, "Not available on this Mac")
            }
        }
        #endif
        return (false, "Needs macOS 26 or later with Apple Intelligence")
    }

    func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), Self.status.available { currentSession().prewarm() }
        #endif
    }

    func reset() { session = nil }

    /// The prompt for one question: earlier chat (if this engine just joined), small text files, then the question.
    nonisolated static func prompt(_ question: String, files: [ClaudeAttachment], context: String?) throws -> String {
        var parts: [String] = []
        if let context { parts.append(context) }
        var budget = maxInlineCharacters
        for f in files {
            guard f.kind == .text, let text = try? String(contentsOf: f.url, encoding: .utf8) else {
                throw EngineError("The on-device model can only read short text files. Ask Claude about \(f.name) instead.")
            }
            guard text.count <= budget else {
                throw EngineError("\(f.name) is too long for the on-device model. Ask Claude about it instead.")
            }
            budget -= text.count
            parts.append("File \(f.name):\n\(text)")
        }
        parts.append(question)
        return parts.joined(separator: "\n\n")
    }

    func ask(_ question: String, files: [ClaudeAttachment], context: String?,
             update: @escaping (EngineUpdate) -> Void) async -> EngineResult {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), Self.status.available else { return .failure(Self.status.note) }
        let prompt: String
        do { prompt = try Self.prompt(question, files: files, context: context) } catch { return .failure(error.localizedDescription) }
        let s = currentSession()
        var text = ""
        do {
            for try await snapshot in s.streamResponse(to: prompt) {
                if Task.isCancelled { break }
                text = snapshot.content
                update(EngineUpdate(text: text, activity: .writing))
            }
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error {
                reset() // start fresh next time; this chat is too long for the small model
                return .failure("This chat got too long for the on-device model. Start a New Chat, or ask Claude.")
            }
            if case .guardrailViolation = error { return .failure("Apple's model won't answer that one. Try asking Claude.") }
            return .failure("The on-device model couldn't answer: \(error.localizedDescription)")
        } catch {
            return .failure("The on-device model couldn't answer: \(error.localizedDescription)")
        }
        return .answer(text: text, sources: [], note: nil)
        #else
        return .failure(Self.status.note)
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func currentSession() -> LanguageModelSession {
        if let s = session as? LanguageModelSession { return s }
        let s = LanguageModelSession(instructions: Self.instructions)
        session = s
        return s
    }
    #endif
}

struct EngineError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - Claude via T3 Code

/// Runs each chat as a T3 Code thread in Notchy's own project, on the user's Claude plan.
/// Replies are read from T3 Code's local database (read-only) a few times a second while Claude works.
@MainActor
final class T3ChatEngine: ChatEngine {
    let kind = ChatEngineKind.claudeT3
    nonisolated(unsafe) static var folder = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Notchy/Chats", isDirectory: true)
    nonisolated static let providerID = "claudeAgent"
    static let pollInterval: UInt64 = 350_000_000
    static let timeout: TimeInterval = 15 * 60

    let agents: AgentsService
    var model: String
    private(set) var threadID: String?
    private var chatID = UUID()

    init(agents: AgentsService, model: String) {
        self.agents = agents
        self.model = model
    }

    func reset() {
        threadID = nil
        chatID = UUID()
    }

    /// Whether T3 Code is installed and its Claude provider is signed in, from T3 Code's provider cache.
    nonisolated static func status(cliPath: String?) -> (available: Bool, note: String) {
        guard cliPath != nil else { return (false, "Install T3 Code and open it once") }
        let cache = AgentsService.home + "/caches/claudeAgent.json"
        guard let data = FileManager.default.contents(atPath: cache),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (false, "Open T3 Code and set up Claude in it")
        }
        return providerStatus(obj)
    }

    nonisolated static func providerStatus(_ obj: [String: Any]) -> (available: Bool, note: String) {
        let auth = (obj["auth"] as? [String: Any])?["status"] as? String
        if obj["enabled"] as? Bool == false { return (false, "Claude is turned off in T3 Code") }
        if obj["installed"] as? Bool == false { return (false, "Claude Code isn't installed in T3 Code") }
        guard auth == "authenticated" else { return (false, "Sign in to Claude in T3 Code") }
        let plan = (obj["auth"] as? [String: Any])?["label"] as? String
        return (true, plan.map { "Connected · \($0)" } ?? "Connected")
    }

    /// The first message of a chat tells Claude Code it's a chat, not a coding task.
    nonisolated static func preamble(filesFolder: String?) -> String {
        var s = """
        [Notchy] The user is asking from Notchy, a small chat panel under their Mac's notch. Answer like a chat \
        assistant: lead with the answer, keep it short, use light Markdown. You can search the web when the question \
        needs current information. Don't create or edit files or run commands unless the user asks for that.
        """
        if let filesFolder { s += " Files the user attaches are saved in \(filesFolder)." }
        return s
    }

    nonisolated static func message(_ question: String, fileNames: [String], context: String?, preamble: String?) -> String {
        var parts: [String] = []
        if let preamble { parts.append(preamble) }
        if let context { parts.append(context) }
        if !fileNames.isEmpty {
            parts.append("Attached: " + fileNames.map { "files/\($0)" }.joined(separator: ", "))
        }
        parts.append(question)
        return parts.joined(separator: "\n\n")
    }

    func ask(_ question: String, files: [ClaudeAttachment], context: String?,
             update: @escaping (EngineUpdate) -> Void) async -> EngineResult {
        guard let cli = agents.cliPath else { return .failure("T3 Code isn't installed.") }
        let folder = Self.folder, chat = chatID, model = self.model, existing = threadID
        update(EngineUpdate(activity: .working("Starting Claude")))

        let started: Result<(thread: String, afterOrdinal: Int), EngineError> = await Task.detached(priority: .userInitiated) {
            do {
                try Self.ensureProject(cli: cli, folder: folder)
                let names = try Self.copy(files, into: folder.appendingPathComponent("files/\(chat.uuidString)", isDirectory: true))
                let shown = names.map { "\(chat.uuidString)/\($0)" }
                if let thread = existing {
                    let before = T3ChatDB.latestOrdinal(threadID: thread) ?? 0
                    let text = Self.message(question, fileNames: shown, context: context, preamble: nil)
                    guard AgentsService.run(cli, ["thread", "send", thread, "-"], stdin: text) != nil else {
                        throw EngineError("Couldn't send to T3 Code. Is it running?")
                    }
                    return .success((thread, before))
                }
                let text = Self.message(question, fileNames: shown, context: context, preamble: Self.preamble(filesFolder: "files/"))
                let title = String(question.split(whereSeparator: \.isNewline).first ?? "Notchy chat").prefix(60)
                guard let out = AgentsService.run(cli, ["thread", "start", "--json", "--title", String(title),
                                                        "--provider", Self.providerID, "--model", model, folder.path, "-"], stdin: text),
                      let obj = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any],
                      let thread = obj["threadId"] as? String else {
                    throw EngineError("Couldn't start a chat in T3 Code. Is it running, with Claude signed in?")
                }
                return .success((thread, 0))
            } catch let e as EngineError {
                return .failure(e)
            } catch {
                return .failure(EngineError(error.localizedDescription))
            }
        }.value

        guard case .success(let (thread, afterOrdinal)) = started else {
            if case .failure(let e) = started { return .failure(e.message) }
            return .failure("Couldn't reach T3 Code.")
        }
        threadID = thread

        let deadline = Date().addingTimeInterval(Self.timeout)
        var last = EngineUpdate()
        while !Task.isCancelled && Date() < deadline {
            try? await Task.sleep(nanoseconds: Self.pollInterval)
            let snap = await Task.detached { T3ChatDB.snapshot(threadID: thread, afterOrdinal: afterOrdinal) }.value
            guard let snap else { continue } // the run hasn't been created yet
            var u = EngineUpdate(text: snap.text, activity: snap.activity, sources: [], pending: snap.pending)
            if u.text.isEmpty && u.activity == .writing { u.activity = .thinking }
            if u.text != last.text || u.activity != last.activity || u.pending != last.pending { update(u); last = u }
            if snap.finished {
                if snap.failed && snap.text.isEmpty { return .failure("Claude stopped without answering. Open the chat in T3 Code for details.") }
                return .answer(text: snap.text, sources: [], note: snap.failed ? "The run ended early" : nil)
            }
        }
        if Task.isCancelled { return .failure("Stopped") }
        return .failure("Claude is taking a long time. The chat keeps going in T3 Code.")
    }

    /// Creates Notchy's chat folder and registers it as a T3 Code project once.
    nonisolated static func ensureProject(cli: String, folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if T3ChatDB.projectExists(path: folder.path) { return }
        guard AgentsService.run(cli, ["project", "add", "--title", "Notchy", folder.path]) != nil
                || T3ChatDB.projectExists(path: folder.path) else {
            throw EngineError("Couldn't set up Notchy's chats in T3 Code. Is it running?")
        }
    }

    /// Copies attachments into the chat's folder (so Claude can read them without asking) and returns their names.
    nonisolated static func copy(_ files: [ClaudeAttachment], into dir: URL) throws -> [String] {
        guard !files.isEmpty else { return [] }
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return try files.map { f in
            var dest = dir.appendingPathComponent(f.name)
            var n = 2
            while fm.fileExists(atPath: dest.path) {
                dest = dir.appendingPathComponent("\(f.url.deletingPathExtension().lastPathComponent) \(n)" +
                                                  (f.url.pathExtension.isEmpty ? "" : ".\(f.url.pathExtension)"))
                n += 1
            }
            try fm.copyItem(at: f.url, to: dest)
            return dest.lastPathComponent
        }
    }
}

/// Read-only queries against T3 Code's database for chat threads.
enum T3ChatDB {
    struct Snapshot: Equatable {
        var text: String
        var activity: StreamAccumulator.Activity
        var finished: Bool
        var failed: Bool
        var pending: AgentsService.PendingRequest?
    }

    nonisolated(unsafe) static var path = AgentsService.dbPath

    private static func open() -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        sqlite3_busy_timeout(db, 200)
        return db
    }

    private static func rows(_ db: OpaquePointer?, _ sql: String, _ args: [String]) -> [[String?]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, a) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), a, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        var out: [[String?]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((0..<sqlite3_column_count(stmt)).map { c in sqlite3_column_text(stmt, c).map { String(cString: $0) } })
        }
        return out
    }

    static func projectExists(path folder: String) -> Bool {
        guard let db = open() else { return false }
        defer { sqlite3_close(db) }
        return !rows(db, "SELECT project_id FROM projection_projects WHERE workspace_root = ? AND deleted_at IS NULL", [folder]).isEmpty
    }

    static func latestOrdinal(threadID: String) -> Int? {
        guard let db = open() else { return nil }
        defer { sqlite3_close(db) }
        guard let value = rows(db, "SELECT MAX(ordinal) FROM orchestration_v2_projection_runs WHERE thread_id = ?", [threadID]).first?.first,
              let v = value else { return nil }
        return Int(v)
    }

    /// The newest run after `afterOrdinal`: its assistant text so far, what Claude is doing, and whether it's done.
    static func snapshot(threadID: String, afterOrdinal: Int) -> Snapshot? {
        guard let db = open() else { return nil }
        defer { sqlite3_close(db) }
        guard let run = rows(db, """
            SELECT run_id, status FROM orchestration_v2_projection_runs
            WHERE thread_id = ? AND ordinal > ? ORDER BY ordinal DESC LIMIT 1
            """, [threadID, String(afterOrdinal)]).first, let runID = run[0] else { return nil }
        let status = run[1] ?? ""
        let messages = rows(db, """
            SELECT json_extract(payload_json, '$.text'), streaming FROM orchestration_v2_projection_messages
            WHERE run_id = ? AND role = 'assistant' ORDER BY created_at, message_id
            """, [runID])
        let text = messages.compactMap { $0[0] }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        let streaming = messages.contains { $0[1] == "1" }
        let items = rows(db, """
            SELECT type, status, payload_json FROM orchestration_v2_projection_turn_items
            WHERE run_id = ? ORDER BY ordinal DESC LIMIT 1
            """, [runID])
        let pending = AgentsService.pendingRequests(threadID: threadID, databasePath: path).first
        return Snapshot(text: text, activity: activity(latestItem: items.first), finished: isFinished(status) && !streaming,
                        failed: ["failed", "interrupted", "cancelled"].contains(status), pending: pending)
    }

    static func isFinished(_ runStatus: String) -> Bool {
        ["completed", "failed", "interrupted", "cancelled"].contains(runStatus)
    }

    /// Maps T3 Code's latest turn item to what the notch says Claude is doing.
    static func activity(latestItem: [String?]?) -> StreamAccumulator.Activity {
        guard let item = latestItem, let type = item[0] else { return .thinking }
        let payload = item.count > 2 ? item[2].flatMap { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] } : nil
        switch type {
        case "assistant_message": return .writing
        case "web_search": return .searching((payload?["patterns"] as? [String])?.first)
        case "command_execution": return .working("Running a command")
        case "file_change": return .working("Editing a file")
        case "file_search": return .working("Looking through files")
        case "dynamic_tool", "subagent": return .working("Using a tool")
        case "approval_request", "user_input_request": return .working("Waiting for you")
        default: return .thinking
        }
    }
}

// MARK: - Claude API

/// The Messages API engine (streaming, web search, attachments, refusal fallbacks, paused turns).
@MainActor
final class ClaudeAPIEngine: ChatEngine {
    let kind = ChatEngineKind.claudeAPI
    var resolver: ClaudeCredentialResolver
    var session: URLSession
    var model: ClaudeModel
    var effort: ClaudeEffort
    var webSearch: Bool
    /// What's sent to the API: user turns with their files, assistant turns as plain text.
    private(set) var history: [[String: Any]] = []

    init(resolver: ClaudeCredentialResolver, session: URLSession, model: ClaudeModel, effort: ClaudeEffort, webSearch: Bool) {
        self.resolver = resolver
        self.session = session
        self.model = model
        self.effort = effort
        self.webSearch = webSearch
    }

    func reset() { history = [] }

    func ask(_ question: String, files: [ClaudeAttachment], context: String?,
             update: @escaping (EngineUpdate) -> Void) async -> EngineResult {
        let resolver = self.resolver
        let text = [context, question].compactMap { $0 }.joined(separator: "\n\n")
        // Reading and encoding files happens off the main thread.
        let prepared: Result<([String: Any], ClaudeCredential?), Error> = await Task.detached(priority: .userInitiated) {
            do {
                var content: [[String: Any]] = try files.map { try $0.contentBlock() }
                content.append(["type": "text", "text": text])
                return .success((["role": "user", "content": content], resolver.resolve()))
            } catch { return .failure(error) }
        }.value
        guard !Task.isCancelled else { return .failure("Stopped") }
        let userTurn: [String: Any], credential: ClaudeCredential
        switch prepared {
        case .failure(let error): return .failure(error.localizedDescription)
        case .success(let (turn, cred)):
            guard let cred else { return .failure("Connect the Claude API first: Settings → Connections → AI.") }
            userTurn = turn
            credential = cred
        }

        var requestMessages = history + [userTurn]
        var shownText = ""
        var sources: [ClaudeSource] = []
        let system = ClaudeAPI.systemPrompt()
        var lastPublish = Date.distantPast

        for continuation in 0...ClaudeAPI.maxContinuations {
            var acc = StreamAccumulator()
            do {
                let body = ClaudeAPI.body(model: model, effort: effort, webSearch: webSearch, system: system, messages: requestMessages)
                let request = try ClaudeAPI.request(body: body, credential: credential, model: model)
                let (bytes, response) = try await session.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    var data = Data()
                    for try await b in bytes { data.append(b); if data.count > 64_000 { break } }
                    return .failure(ClaudeAPI.errorMessage(status: status, body: data))
                }
                var lastActivity = acc.activity
                for try await line in bytes.lines {
                    guard let event = SSEParser.event(fromLine: line) else { continue }
                    acc.apply(event)
                    // Publishing every token re-renders the island; ~20 updates a second is plenty.
                    if acc.activity != lastActivity || Date().timeIntervalSince(lastPublish) > 0.05 {
                        lastPublish = Date()
                        lastActivity = acc.activity
                        update(EngineUpdate(text: shownText + acc.text, activity: acc.activity, sources: sources + acc.sources))
                    }
                }
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return .failure("Stopped") }
                return .failure("Lost the connection to Claude: \(error.localizedDescription)")
            }
            if Task.isCancelled { return .failure("Stopped") }
            if let err = acc.errorMessage { return .failure(err) }
            shownText += acc.text
            sources += acc.sources.filter { s in !sources.contains(s) }

            switch acc.stopReason {
            case "pause_turn" where continuation < ClaudeAPI.maxContinuations:
                // Web searches can pause a long turn; send it back unchanged and the server carries on.
                requestMessages.append(["role": "assistant", "content": acc.contentForResume])
                continue
            case "refusal":
                // Partial output from a declined request isn't a real answer, and the turn isn't kept.
                return .failure("Claude can't help with that one. Try rephrasing the question.")
            default:
                var note: String?
                if acc.stopReason == "max_tokens" { note = "Answer cut off (too long)" }
                if acc.usedFallback { note = [note, "Answered by a fallback model"].compactMap { $0 }.joined(separator: " · ") }
                return keep(userTurn, answer: shownText, sources: sources, note: note)
            }
        }
        return keep(userTurn, answer: shownText, sources: sources, note: "Stopped after several searches")
    }

    private func keep(_ userTurn: [String: Any], answer: String, sources: [ClaudeSource], note: String?) -> EngineResult {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        history.append(userTurn)
        history.append(["role": "assistant", "content": text.isEmpty ? "(No answer)" : text])
        return .answer(text: text, sources: sources, note: note)
    }
}
