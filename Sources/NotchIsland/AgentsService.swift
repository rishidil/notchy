import AppKit
import SQLite3

/// Shows and prompts T3 Code agents. Everything goes through T3 Code's own `t3 thread` CLI
/// (list / show / send / start); the project list is read from T3 Code's local database (read-only),
/// with extra folders addable in Settings. To stay light, the CLI only runs when T3 Code's data has changed.
final class AgentsService: ObservableObject {
    struct Project: Identifiable, Hashable {
        let id: String
        let title: String
        let path: String
    }

    struct AgentThread: Identifiable, Equatable {
        let id: String
        let projectID: String
        let projectTitle: String
        let projectPath: String
        let title: String
        var status: String
        let model: String
        let updatedAt: Date
        /// T3 Code marks a finished thread "settled" once you've reviewed it.
        var settled: Bool
        /// Open requests waiting on the user (tool approvals / questions).
        var pendingRequests: Int = 0
        /// How many of those are questions (the rest are approvals).
        var pendingQuestions: Int = 0
        var isWaitingOnQuestion: Bool { pendingRequests > 0 && pendingQuestions == pendingRequests }

        /// Working, and not blocked on the user.
        var isRunning: Bool { pendingRequests == 0 && ["running", "starting", "queued", "in_progress"].contains(status) }
        var isDone: Bool { status == "completed" }
        var isFailed: Bool { ["failed", "error", "errored", "interrupted", "cancelled", "canceled"].contains(status) }
        /// Waiting on the user (an answer or an approval).
        var needsAttention: Bool {
            if pendingRequests > 0 { return true }
            let s = status.lowercased()
            return ["waiting", "awaiting", "input", "approval", "blocked", "pending", "requires"].contains { s.contains($0) }
        }
        /// Finished but not yet reviewed in T3 Code.
        var isUnreadDone: Bool { isDone && !settled }
    }

    /// Something an agent is waiting on: a tool approval, or questions to answer.
    struct PendingRequest: Identifiable, Equatable {
        struct ApprovalOption: Equatable, Hashable {
            let decision: String
            let label: String
            var warning: String?
        }
        struct Question: Identifiable, Equatable {
            struct Option: Equatable, Hashable { let label: String; let description: String; var value: String? }
            let id: String
            let header: String
            let question: String
            let options: [Option]
            var multiSelect = false
            var allowCustom = true
        }
        enum Kind: Equatable {
            case approval(requestKind: String, prompt: String?, reason: String?, options: [ApprovalOption])
            case questions([Question])
        }
        let id: String
        let threadID: String
        let kind: Kind

        var isApproval: Bool { if case .approval = kind { true } else { false } }

        static let defaultApprovalOptions = [
            ApprovalOption(decision: "accept", label: "Approve"),
            ApprovalOption(decision: "acceptForSession", label: "Approve for Session"),
            ApprovalOption(decision: "decline", label: "Decline"),
        ]

        /// Builds a request from a T3 Code turn item (`approval_request` / `user_input_request`).
        static func parse(_ item: [String: Any], threadID: String) -> PendingRequest? {
            guard let id = item["requestId"] as? String else { return nil }
            switch item["type"] as? String {
            case "approval_request":
                let opts = (item["options"] as? [[String: Any]] ?? []).compactMap { o -> ApprovalOption? in
                    guard let d = o["decision"] as? String, let l = o["label"] as? String else { return nil }
                    return ApprovalOption(decision: d, label: l, warning: o["warning"] as? String)
                }
                return PendingRequest(id: id, threadID: threadID,
                                      kind: .approval(requestKind: item["requestKind"] as? String ?? "permission",
                                                      prompt: (item["prompt"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                                      reason: (item["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                                      options: opts.isEmpty ? defaultApprovalOptions : opts))
            case "user_input_request":
                let qs = (item["questions"] as? [[String: Any]] ?? []).compactMap { q -> Question? in
                    guard let qid = q["id"] as? String else { return nil }
                    let options = (q["options"] as? [[String: Any]] ?? []).compactMap { o -> Question.Option? in
                        guard let l = o["label"] as? String else { return nil }
                        return Question.Option(label: l, description: o["description"] as? String ?? "", value: o["value"] as? String)
                    }
                    return Question(id: qid, header: q["header"] as? String ?? "Question", question: q["question"] as? String ?? qid,
                                    options: options, multiSelect: q["multiSelect"] as? Bool ?? false,
                                    allowCustom: q["allowCustomAnswer"] as? Bool ?? true)
                }
                return qs.isEmpty ? nil : PendingRequest(id: id, threadID: threadID, kind: .questions(qs))
            default:
                return nil
            }
        }
    }

    struct Message: Identifiable, Equatable {
        let id: Int
        let role: String
        let text: String
        var isUser: Bool { role == "user" }
    }

    @Published private(set) var cliPath: String?
    @Published private(set) var projects: [Project] = []
    @Published private(set) var threads: [AgentThread] = []
    @Published private(set) var loaded = false
    @Published var selectedID: String? {
        didSet {
            guard selectedID != oldValue, !isDemoMode else { return }
            messages = []
            pending = []
            if visible { loadMessagesIfChanged(force: true) }
            loadPending()
        }
    }
    @Published private(set) var messages: [Message] = []
    @Published private(set) var pendingRequests = 0
    @Published private(set) var sending = false
    @Published private(set) var lastError: String?
    /// Pending approvals/questions of the selected thread (read from T3 Code's database).
    @Published private(set) var pending: [PendingRequest] = []
    /// The request being answered right now.
    @Published private(set) var responding: String?
    @Published private(set) var remoteConnected = T3Remote.shared.isConnected
    @Published private(set) var extraFolders: [String] = UserDefaults.standard.stringArray(forKey: "t3ExtraFolders") ?? []

    /// Fired when a thread stops running, or starts needing input.
    var onFinished: ((AgentThread) -> Void)?
    var onNeedsInput: ((AgentThread) -> Void)?

    var runningCount: Int { threads.filter(\.isRunning).count }
    var runningThreads: [AgentThread] { threads.filter(\.isRunning) }
    var waitingThreads: [AgentThread] { threads.filter(\.needsAttention) }
    /// When each thread was first seen running (for "Working · 3m").
    private(set) var runningSince: [String: Date] = [:]
    var attentionCount: Int { threads.filter(\.needsAttention).count }
    var selected: AgentThread? { threads.first { $0.id == selectedID } }
    var isInstalled: Bool { cliPath != nil }

    private let queue = DispatchQueue(label: "notchy.agents", qos: .utility)
    private var timer: Timer?
    private var lastStamp: Date?
    private var lastRefresh = Date.distantPast
    private var refreshing = false
    private var visible = false
    private(set) var isRunning = false

    private static let home = NSHomeDirectory() + "/.t3"
    private static let dbPath = home + "/userdata/statev2.sqlite"

    init() { cliPath = Self.findCLI() }

    // MARK: Lifecycle

    func start() {
        guard !isRunning, !isDemoMode else { return }
        isRunning = true
        cliPath = Self.findCLI()
        refresh(force: true)
        // A cheap file-timestamp check every 2s; the CLI only runs when T3 Code's data actually changed.
        timer = Timer.every(3) { [weak self] _ in self?.tick() }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    /// Faster updates while the Agents tab is on screen.
    func setVisible(_ v: Bool) {
        guard !isDemoMode else { return }
        visible = v
        guard v else { return }
        if Date().timeIntervalSince(lastRefresh) > 30 { refresh(force: true) }
        loadMessagesIfChanged(force: messagesLoadedFor != selectedID)
    }

    // Messages come from the CLI (≈0.4s CPU per call), so only reload when the selected thread really has
    // something new (checked in T3 Code's database) and at most every 10s (20s in efficiency mode).
    private var messagesLoadedFor: String?
    private var messagesStamp: String?
    private var lastMessagesLoad = Date.distantPast

    private func loadMessagesIfChanged(force: Bool = false) {
        guard let id = selectedID else { return }
        queue.async { [weak self] in
            let stamp = Self.messageStamp(threadID: id)
            DispatchQueue.main.async {
                guard let self, self.selectedID == id else { return }
                let changed = stamp == nil || stamp != self.messagesStamp
                let gap: TimeInterval = Efficiency.shared.isActive ? 20 : 10
                guard force || (changed && Date().timeIntervalSince(self.lastMessagesLoad) >= gap) else { return }
                self.messagesStamp = stamp
                self.loadMessages()
            }
        }
    }

    /// Latest message update for a thread, from T3 Code's database (read-only). nil if unavailable.
    private static func messageStamp(threadID: String) -> String? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        var stmt: OpaquePointer?
        let sql = "SELECT MAX(updated_at) || ':' || COUNT(*) FROM orchestration_v2_projection_messages WHERE thread_id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, threadID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    /// Every 2s: if T3 Code's data changed, read thread status straight from its database (read-only, <1ms).
    /// The CLI (≈0.4s of CPU per call) only runs for new threads, details, or every minute or so.
    private func tick() {
        let stamp = Self.dataStamp()
        let changed = stamp != lastStamp
        let sinceCLI = Date().timeIntervalSince(lastRefresh)
        guard changed || sinceCLI > 90 else { return }
        lastStamp = stamp
        queue.async { [weak self] in
            let fast = Self.fastStatus()
            DispatchQueue.main.async {
                guard let self else { return }
                guard let fast else {
                    // Database layout unknown (T3 Code changed it): fall back to the CLI, less often.
                    if sinceCLI >= (self.visible ? 15 : 60) { self.refresh(force: false) }
                    return
                }
                let known = Set(self.threads.map(\.id))
                let hasNew = fast.keys.contains { !known.contains($0) }
                if hasNew || sinceCLI > (self.visible ? 60 : 180) {
                    self.refresh(force: false)
                } else {
                    self.publish(Self.overlay(fast, on: self.threads))
                }
                if self.visible { self.loadMessagesIfChanged() }
                if self.selected?.pendingRequests ?? 0 > 0 || !self.pending.isEmpty { self.loadPending() }
            }
        }
    }

    private struct FastStatus { var running: Bool; var pending: Int; var questions: Int }

    /// Thread status from T3 Code's database: is the latest run going, and are requests waiting on the user?
    private static func fastStatus() -> [String: FastStatus]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        let sql = """
        SELECT t.thread_id,
               (SELECT r.status FROM orchestration_v2_projection_runs r WHERE r.thread_id = t.thread_id ORDER BY r.ordinal DESC LIMIT 1),
               (SELECT COUNT(*) FROM orchestration_v2_projection_runtime_requests q WHERE q.thread_id = t.thread_id AND q.status = 'pending'),
               (SELECT COUNT(*) FROM orchestration_v2_projection_runtime_requests q WHERE q.thread_id = t.thread_id AND q.status = 'pending' AND q.kind = 'user_input')
        FROM orchestration_v2_projection_threads t
        WHERE t.deleted_at IS NULL AND t.archived_at IS NULL
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        var result: [String: FastStatus] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }) else { continue }
            let run = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            result[id] = FastStatus(running: run == "running", pending: Int(sqlite3_column_int(stmt, 2)),
                                    questions: Int(sqlite3_column_int(stmt, 3)))
        }
        return result
    }

    /// Applies database status on top of the CLI's thread list (the CLI reports "running" even while blocked on an approval).
    private static func overlay(_ fast: [String: FastStatus]?, on list: [AgentThread]) -> [AgentThread] {
        guard let fast else { return list }
        return list.map { t in
            guard let f = fast[t.id] else { return t }
            var t = t
            t.pendingRequests = f.pending
            t.pendingQuestions = f.questions
            if f.running { t.status = "running" }
            else if t.status == "running" { t.status = "completed"; t.settled = false } // just finished
            return t
        }
    }

    private static func rank(_ t: AgentThread) -> Int {
        t.needsAttention ? 0 : t.isRunning ? 1 : (t.isUnreadDone || t.isFailed && !t.settled) ? 2 : 3
    }

    /// Publishes a new thread list: announces transitions, tracks run times, keeps the selection valid.
    private func publish(_ list: [AgentThread]) {
        let all = list.sorted { Self.rank($0) != Self.rank($1) ? Self.rank($0) < Self.rank($1) : $0.updatedAt > $1.updatedAt }
        detectTransitions(from: threads, to: all)
        for t in all where t.isRunning && runningSince[t.id] == nil {
            runningSince[t.id] = loaded ? Date() : min(Date(), t.updatedAt)
        }
        runningSince = runningSince.filter { id, _ in all.contains { $0.id == id && ($0.isRunning || $0.needsAttention) } }
        if threads != all { threads = all }
        loaded = true
        if selectedID == nil || !all.contains(where: { $0.id == selectedID }) { selectedID = all.first?.id }
    }

    /// Latest modification time of T3 Code's database files (the write-ahead log changes while agents work).
    private static func dataStamp() -> Date? {
        [dbPath, dbPath + "-wal"].compactMap {
            (try? FileManager.default.attributesOfItem(atPath: $0))?[.modificationDate] as? Date
        }.max()
    }

    // MARK: Reading

    func refresh(force: Bool) {
        guard !isDemoMode else { return }
        guard let cli = cliPath, !refreshing else { if cliPath == nil { loaded = true }; return }
        refreshing = true
        lastRefresh = Date()
        let extras = extraFolders
        queue.async { [weak self] in
            let projects = Self.discoverProjects(extraFolders: extras)
            var all: [AgentThread] = []
            for p in projects {
                guard let data = Self.run(cli, ["thread", "list", "--json", "--project", p.path]),
                      let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
                for t in list {
                    guard let id = t["threadId"] as? String else { continue }
                    all.append(AgentThread(id: id, projectID: t["projectId"] as? String ?? p.id, projectTitle: p.title,
                                           projectPath: p.path, title: (t["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled",
                                           status: t["status"] as? String ?? "idle", model: t["model"] as? String ?? "",
                                           updatedAt: Self.date(t["updatedAt"]) ?? .distantPast,
                                           settled: t["settled"] as? Bool ?? true))
                }
            }
            let merged = Self.overlay(Self.fastStatus(), on: all)
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                if self.projects != projects { self.projects = projects }
                self.publish(merged)
            }
        }
    }

    private func detectTransitions(from old: [AgentThread], to new: [AgentThread]) {
        guard loaded else { return } // don't announce what was already going on at launch
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for t in new {
            guard let prev = before[t.id] else { continue }
            if t.needsAttention && !prev.needsAttention { onNeedsInput?(t) }
            else if prev.isRunning && !t.isRunning && !t.needsAttention { onFinished?(t) }
        }
    }

    func loadMessages() {
        guard !isDemoMode else { return }
        guard let cli = cliPath, let id = selectedID else { return }
        lastMessagesLoad = Date()
        messagesLoadedFor = id
        queue.async { [weak self] in
            guard let data = Self.run(cli, ["thread", "show", id, "--json", "--messages", "6"]),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            let msgs = (obj["messages"] as? [[String: Any]] ?? []).enumerated().compactMap { i, m -> Message? in
                guard let text = m["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                return Message(id: i, role: m["role"] as? String ?? "assistant", text: text)
            }
            let pending = (obj["thread"] as? [String: Any])?["pendingRequestCount"] as? Int ?? 0
            DispatchQueue.main.async {
                guard let self, self.selectedID == id else { return }
                if self.messages != msgs { self.messages = msgs }
                if self.pendingRequests != pending { self.pendingRequests = pending }
            }
        }
    }

    // MARK: Actions

    /// Sends a message to a thread. A busy agent gets it as its next turn (nothing is interrupted).
    func send(_ text: String, to threadID: String) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cli = cliPath, !message.isEmpty else { return }
        sending = true
        lastError = nil
        queue.async { [weak self] in
            let ok = Self.run(cli, ["thread", "send", threadID, "-"], stdin: message) != nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.sending = false
                if !ok { self.lastError = "Couldn't send. Is T3 Code running?" }
                self.refresh(force: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.loadMessages() }
            }
        }
    }

    /// Starts a new thread in a project and selects it.
    func startThread(_ text: String, in project: Project) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cli = cliPath, !message.isEmpty else { return }
        sending = true
        lastError = nil
        queue.async { [weak self] in
            let out = Self.run(cli, ["thread", "start", "--json", project.path, "-"], stdin: message)
            var newID: String?
            if let out {
                if let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any] {
                    newID = obj["threadId"] as? String ?? (obj["thread"] as? [String: Any])?["threadId"] as? String
                } else {
                    newID = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.sending = false
                if out == nil { self.lastError = "Couldn't start a thread. Is T3 Code running?" }
                self.refresh(force: true)
                if let newID, !newID.isEmpty { self.selectedID = newID }
            }
        }
    }

    /// Opens the thread's project in the T3 Code desktop app.
    func openInT3(_ thread: AgentThread?) {
        if let cli = cliPath, let path = thread?.projectPath {
            queue.async { _ = Self.run(cli, ["app", path]) }
        } else if let app = Self.appURL() {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
    }

    // MARK: Approvals & questions

    /// Reads the selected thread's pending requests from T3 Code's database (read-only).
    func loadPending() {
        guard !isDemoMode, let id = selectedID else { return }
        queue.async { [weak self] in
            let list = Self.pendingRequests(threadID: id)
            DispatchQueue.main.async {
                guard let self, self.selectedID == id, self.pending != list else { return }
                self.pending = list
            }
        }
    }

    static func pendingRequests(threadID: String) -> [PendingRequest] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        let sql = """
        SELECT ti.payload_json FROM orchestration_v2_projection_turn_items ti
        JOIN orchestration_v2_projection_runtime_requests r ON r.runtime_request_id = json_extract(ti.payload_json, '$.requestId')
        WHERE ti.thread_id = ? AND ti.type IN ('approval_request', 'user_input_request') AND r.status = 'pending'
        ORDER BY ti.ordinal
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, threadID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        var result: [PendingRequest] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let text = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }),
                  let obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
                  let req = PendingRequest.parse(obj, threadID: threadID),
                  !result.contains(where: { $0.id == req.id }) else { continue }
            result.append(req)
        }
        return result
    }

    /// Approves/declines an approval (`decision`) or answers questions (`answers`: question id → label, labels or text).
    func respond(to request: PendingRequest, decision: String? = nil, answers: [String: Any]? = nil) {
        guard let cli = cliPath, responding == nil else { return }
        if isDemoMode { pending.removeAll { $0.id == request.id }; return }
        responding = request.id
        lastError = nil
        queue.async { [weak self] in
            var failure: String?
            do {
                try T3Remote.shared.respond(cli: cli, threadID: request.threadID, requestID: request.id,
                                            decision: decision, answers: answers)
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.responding = nil
                self.remoteConnected = T3Remote.shared.isConnected
                if let failure { self.lastError = failure; return }
                self.pending.removeAll { $0.id == request.id }
                self.refresh(force: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.loadPending(); self.loadMessages() }
            }
        }
    }

    /// Revokes the token Notchy uses to answer requests.
    func disconnectRemote() {
        let cli = cliPath
        queue.async { [weak self] in
            T3Remote.shared.disconnect(cli: cli)
            DispatchQueue.main.async { self?.remoteConnected = false }
        }
    }

    // MARK: Settings

    func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose T3 Code project folders to show in Notchy"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        extraFolders = Array(Set(extraFolders + panel.urls.map(\.path))).sorted()
        UserDefaults.standard.set(extraFolders, forKey: "t3ExtraFolders")
        refresh(force: true)
    }

    func removeFolder(_ path: String) {
        extraFolders.removeAll { $0 == path }
        UserDefaults.standard.set(extraFolders, forKey: "t3ExtraFolders")
        refresh(force: true)
    }

    func applyDemo() {
        cliPath = "/demo"
        let now = Date()
        projects = [Project(id: "p1", title: "webapp", path: "/demo/webapp"), Project(id: "p2", title: "api", path: "/demo/api")]
        threads = [
            AgentThread(id: "t1", projectID: "p1", projectTitle: "webapp", projectPath: "/demo/webapp", title: "Fix the checkout flow bug",
                        status: "running", model: "claude-opus-5-5", updatedAt: now, settled: false),
            AgentThread(id: "t2", projectID: "p2", projectTitle: "api", projectPath: "/demo/api", title: "Add rate limiting to /login",
                        status: "completed", model: "claude-sonnet-5-5", updatedAt: now.addingTimeInterval(-600), settled: false),
            AgentThread(id: "t3", projectID: "p1", projectTitle: "webapp", projectPath: "/demo/webapp", title: "Write tests for the cart",
                        status: "idle", model: "claude-opus-5-5", updatedAt: now.addingTimeInterval(-86400), settled: true),
        ]
        runningSince = ["t1": now.addingTimeInterval(-4 * 60)]
        selectedID = "t1"
        messages = [Message(id: 0, role: "user", text: "Checkout fails when a coupon is applied twice. Can you fix it?"),
                    Message(id: 1, role: "assistant", text: "Found it: the discount is applied before the cart is re-validated. Patching CartService and adding a regression test now.")]
        loaded = true
    }

    /// Demo: a thread waiting for approval (or with a question), selected.
    func applyDemoWaiting(question: Bool) {
        let now = Date()
        var t = AgentThread(id: "t0", projectID: "p2", projectTitle: "api", projectPath: "/demo/api",
                            title: question ? "Migrate the users table" : "Upgrade to Postgres 17",
                            status: "running", model: "claude-opus-5-5", updatedAt: now, settled: false)
        t.pendingRequests = 1
        t.pendingQuestions = question ? 1 : 0
        threads.removeAll { $0.id == "t0" }
        threads.insert(t, at: 0)
        runningSince["t0"] = now.addingTimeInterval(-6 * 60)
        selectedID = "t0"
        messages = [Message(id: 0, role: "user", text: question ? "Add a migration for the new users.plan column." : "Upgrade the dev database to Postgres 17."),
                    Message(id: 1, role: "assistant", text: question ? "The migration is ready. One decision before I run it:"
                                : "Docker Compose is updated. I need to recreate the database container to finish.")]
        pending = [question
            ? PendingRequest(id: "r1", threadID: "t0", kind: .questions([
                .init(id: "q1", header: "Backfill", question: "What should existing users get for plan?",
                      options: [.init(label: "free", description: "Everyone starts on the free plan"),
                                .init(label: "pro", description: "Grandfather current users into pro"),
                                .init(label: "null", description: "Leave it empty and decide later")])]))
            : PendingRequest(id: "r1", threadID: "t0", kind: .approval(requestKind: "command",
                prompt: "docker compose up -d --force-recreate db", reason: "Recreate the database container",
                options: PendingRequest.defaultApprovalOptions))]
    }

    // MARK: Helpers

    static func appURL() -> URL? {
        let fm = FileManager.default
        for dir in ["/Applications", NSHomeDirectory() + "/Applications"] {
            if let name = (try? fm.contentsOfDirectory(atPath: dir))?.first(where: { $0.hasPrefix("T3 Code") && $0.hasSuffix(".app") }) {
                return URL(fileURLWithPath: dir).appendingPathComponent(name)
            }
        }
        return nil
    }

    private static func findCLI() -> String? {
        let candidates = [NSHomeDirectory() + "/.local/bin/t3", "/opt/homebrew/bin/t3", "/usr/local/bin/t3", home + "/bin/t3"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Projects from T3 Code's database (read-only: id, title and folder only), plus folders added in Settings.
    private static func discoverProjects(extraFolders: [String]) -> [Project] {
        var result: [Project] = []
        let sql = "SELECT project_id, title, workspace_root FROM projection_projects WHERE deleted_at IS NULL AND archived_at IS NULL ORDER BY pinned_at DESC, updated_at DESC;"
        if FileManager.default.fileExists(atPath: dbPath),
           let out = run("/usr/bin/sqlite3", ["-readonly", "-separator", "\u{1f}", dbPath, sql]),
           let text = String(data: out, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                let parts = line.components(separatedBy: "\u{1f}")
                guard parts.count >= 3, !parts[2].isEmpty else { continue }
                result.append(Project(id: parts[0], title: parts[1].isEmpty ? URL(fileURLWithPath: parts[2]).lastPathComponent : parts[1], path: parts[2]))
            }
        }
        for folder in extraFolders where !result.contains(where: { $0.path == folder }) {
            result.append(Project(id: folder, title: URL(fileURLWithPath: folder).lastPathComponent, path: folder))
        }
        return result
    }

    /// Runs a command and returns stdout on success (exit 0), nil otherwise. Off the main thread only.
    @discardableResult
    static func run(_ path: String, _ args: [String], stdin input: String? = nil) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let inPipe = Pipe()
        if input != nil { p.standardInput = inPipe }
        do { try p.run() } catch { return nil }
        if let input {
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            try? inPipe.fileHandleForWriting.close()
        }
        // Don't hang forever if the server is unresponsive.
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return p.terminationStatus == 0 ? data : nil
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return isoFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
