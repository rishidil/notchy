import AppKit
import Combine

/// Claude in the notch: one running conversation with your own Anthropic account, files dropped on the notch as
/// context, optional web search, and a live activity while Claude works.
/// All state changes happen on the main thread (work is started from UI actions; async work hops back with `@MainActor`).
final class ClaudeService: ObservableObject {
    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
        var attachmentNames: [String] = []
        var sources: [ClaudeSource] = []
        var isError = false
        var note: String?
    }

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var attachments: [ClaudeAttachment] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var activity: StreamAccumulator.Activity = .thinking
    @Published private(set) var credentialSource: ClaudeCredentialSource?
    @Published private(set) var checkingCredential = false
    @Published private(set) var hasSavedKey = Keychain.read(ClaudeCredentialResolver.keychainAccount) != nil
    @Published private(set) var testResult: (ok: Bool, message: String)?
    @Published var focusRequest = 0

    @Published var model: ClaudeModel = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "claudeModel") ?? "") ?? .default {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: "claudeModel") }
    }
    @Published var effort: ClaudeEffort = ClaudeEffort(rawValue: UserDefaults.standard.string(forKey: "claudeEffort") ?? "") ?? .default {
        didSet { UserDefaults.standard.set(effort.rawValue, forKey: "claudeEffort") }
    }
    @Published var webSearch: Bool = UserDefaults.standard.object(forKey: "claudeWebSearch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(webSearch, forKey: "claudeWebSearch") }
    }

    /// Called when an answer finishes (with its first line), so the notch can announce it if you're not looking.
    var onAnswer: ((String) -> Void)?

    var isConfigured: Bool { credentialSource != nil }
    var lastAnswer: ChatMessage? { messages.last { $0.role == .assistant } }
    /// The text currently streaming in (for the live activity).
    var streamingText: String { isStreaming ? (messages.last?.role == .assistant ? messages.last?.text ?? "" : "") : "" }

    /// What's sent to the API: user turns with their files, assistant turns as plain text.
    private var history: [[String: Any]] = []
    private var task: Task<Void, Never>?
    var resolver = ClaudeCredentialResolver()
    var session: URLSession = .shared

    init() {
        guard !isDemoMode else { return }
        refreshCredential()
    }

    // MARK: Credentials

    func refreshCredential() {
        checkingCredential = true
        let resolver = self.resolver
        Task.detached(priority: .utility) {
            let source = resolver.resolve()?.source
            await MainActor.run {
                self.credentialSource = source
                self.checkingCredential = false
                self.hasSavedKey = Keychain.read(ClaudeCredentialResolver.keychainAccount) != nil
            }
        }
    }

    func saveKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        Keychain.write(k, for: ClaudeCredentialResolver.keychainAccount)
        testResult = nil
        refreshCredential()
        testConnection()
    }

    func removeKey() {
        Keychain.delete(ClaudeCredentialResolver.keychainAccount)
        testResult = nil
        refreshCredential()
    }

    /// Lists one model: free, and proves the credential works.
    func testConnection() {
        testResult = nil
        let resolver = self.resolver, session = self.session
        Task { @MainActor in
            let credential = await Task.detached { resolver.resolve() }.value
            guard let credential else { testResult = (false, "No API key or sign-in found."); return }
            var r = URLRequest(url: ClaudeAPI.modelsURL, timeoutInterval: 20)
            for (k, v) in credential.authHeaders { r.setValue(v, forHTTPHeaderField: k) }
            r.setValue(ClaudeAPI.apiVersion, forHTTPHeaderField: "anthropic-version")
            if !credential.betas.isEmpty { r.setValue(credential.betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }
            do {
                let (data, response) = try await session.data(for: r)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                testResult = status == 200 ? (true, "Connected · \(credential.source.title)")
                    : (false, ClaudeAPI.errorMessage(status: status, body: data))
            } catch {
                testResult = (false, "Couldn't reach api.anthropic.com: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Attachments

    func attach(_ urls: [URL]) {
        for url in urls where url.isFileURL && !attachments.contains(where: { $0.url == url }) {
            attachments.append(.make(url))
        }
        focusRequest &+= 1
    }

    func removeAttachment(_ a: ClaudeAttachment) { attachments.removeAll { $0 == a } }

    // MARK: Conversation

    func clear() {
        cancel()
        messages = []
        history = []
        attachments = []
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isStreaming, let i = messages.indices.last, messages[i].role == .assistant {
            messages[i].note = "Stopped"
            if messages[i].text.isEmpty { messages.remove(at: i) }
        }
        isStreaming = false
    }

    func send(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments.filter(\.isUsable)
        guard !isStreaming, !text.isEmpty || !files.isEmpty else { return }
        let question = text.isEmpty ? "What's in \(files.count == 1 ? "this file" : "these files")?" : text
        attachments = []
        messages.append(ChatMessage(role: .user, text: question, attachmentNames: files.map(\.name)))
        messages.append(ChatMessage(role: .assistant, text: ""))
        isStreaming = true
        activity = .thinking

        let resolver = self.resolver, model = self.model, effort = self.effort, webSearch = self.webSearch
        let priorHistory = history
        task = Task { @MainActor [weak self] in
            // Reading and encoding files happens off the main thread.
            let prepared: Result<([String: Any], ClaudeCredential?), Error> = await Task.detached(priority: .userInitiated) {
                do {
                    var content: [[String: Any]] = try files.map { try $0.contentBlock() }
                    content.append(["type": "text", "text": question])
                    return .success((["role": "user", "content": content], resolver.resolve()))
                } catch { return .failure(error) }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch prepared {
            case .failure(let error):
                self.finish(error: error.localizedDescription)
            case .success(let (userTurn, credential)):
                guard let credential else {
                    self.credentialSource = nil
                    self.finish(error: "Connect Claude first: add your API key in Settings → Connections → Claude.")
                    return
                }
                self.credentialSource = credential.source
                await self.stream(messages: priorHistory + [userTurn], userTurn: userTurn, credential: credential,
                                  model: model, effort: effort, webSearch: webSearch)
            }
        }
    }

    @MainActor
    private func stream(messages base: [[String: Any]], userTurn: [String: Any], credential: ClaudeCredential,
                        model: ClaudeModel, effort: ClaudeEffort, webSearch: Bool) async {
        var requestMessages = base
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
                    finish(error: ClaudeAPI.errorMessage(status: status, body: data))
                    return
                }
                for try await line in bytes.lines {
                    guard let event = SSEParser.event(fromLine: line) else { continue }
                    acc.apply(event)
                    if acc.activity != activity { activity = acc.activity }
                    // Publishing every token re-renders the island; ~20 updates a second is plenty.
                    if Date().timeIntervalSince(lastPublish) > 0.05 {
                        lastPublish = Date()
                        updateStreaming(text: shownText + acc.text, sources: sources + acc.sources)
                    }
                }
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
                finish(error: "Lost the connection to Claude: \(error.localizedDescription)")
                return
            }
            if Task.isCancelled { return }
            if let err = acc.errorMessage { finish(error: err); return }
            shownText += acc.text
            sources += acc.sources.filter { s in !sources.contains(s) }

            switch acc.stopReason {
            case "pause_turn" where continuation < ClaudeAPI.maxContinuations:
                // Web searches can pause a long turn; send it back unchanged and the server carries on.
                requestMessages.append(["role": "assistant", "content": acc.contentForResume])
                continue
            case "refusal":
                // Partial output from a declined request isn't a real answer.
                finish(error: "Claude can't help with that one. Try rephrasing the question.")
                return
            default:
                var note: String?
                if acc.stopReason == "max_tokens" { note = "Answer cut off (too long)" }
                if acc.usedFallback { note = [note, "Answered by a fallback model"].compactMap { $0 }.joined(separator: " · ") }
                finish(text: shownText, sources: sources, userTurn: userTurn, note: note)
                return
            }
        }
        finish(text: shownText, sources: sources, userTurn: userTurn, note: "Stopped after several searches")
    }

    private func updateStreaming(text: String, sources: [ClaudeSource]) {
        guard let i = messages.indices.last, messages[i].role == .assistant else { return }
        messages[i].text = text
        if messages[i].sources != sources { messages[i].sources = sources }
    }

    private func finish(text: String, sources: [ClaudeSource], userTurn: [String: Any], note: String?) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updateStreaming(text: answer.isEmpty ? "(No answer)" : answer, sources: sources)
        if let i = messages.indices.last { messages[i].note = note }
        history.append(userTurn)
        history.append(["role": "assistant", "content": answer.isEmpty ? "(No answer)" : answer])
        isStreaming = false
        task = nil
        onAnswer?(Self.firstLine(answer))
    }

    /// Shows an error in place of the answer. The failed question isn't kept in the history sent to Claude.
    private func finish(error: String) {
        if let i = messages.indices.last, messages[i].role == .assistant {
            messages[i].text = error
            messages[i].isError = true
            messages[i].sources = []
        }
        isStreaming = false
        task = nil
    }

    static func firstLine(_ s: String) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        return line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: Demo

    func applyDemo(files: [URL]) {
        credentialSource = .keychain
        messages = [
            ChatMessage(role: .user, text: "Summarize this and list anything I need to do", attachmentNames: ["Q3 Planning.pdf"]),
            ChatMessage(role: .assistant, text: """
            **Q3 plan in one line:** ship the redesigned onboarding by Aug 15, then move the team to the pricing page.
            - **You own:** the onboarding copy review (due **Jul 28**) and the launch email
            - **Decide by Friday:** whether the beta keeps the old dashboard
            - Budget is flat, and hiring for the second designer starts in September
            """),
        ]
        attachments = files.prefix(1).map { ClaudeAttachment(url: $0, kind: .image) }
    }

    func demoStreaming() {
        messages.append(ChatMessage(role: .user, text: "What's the weather looking like for the Tahoe trip this weekend?"))
        messages.append(ChatMessage(role: .assistant, text: ""))
        isStreaming = true
        activity = .searching("Lake Tahoe weather this weekend")
    }
}
