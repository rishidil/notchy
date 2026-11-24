import AppKit
import Combine

/// The AI tab: one running conversation in the notch, answered by Apple's on-device model, Claude via T3 Code or the
/// Claude API (see ChatEngines.swift), with files dropped on the notch as context and a live activity while it works.
/// All state changes happen on the main thread.
final class AssistantService: ObservableObject {
    struct ChatMessage: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
        var attachmentNames: [String] = []
        var sources: [ClaudeSource] = []
        var isError = false
        var note: String?
        /// Which engine wrote this answer.
        var engine: ChatEngineKind?
    }

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var attachments: [ClaudeAttachment] = []
    @Published private(set) var isStreaming = false
    @Published private(set) var activity: StreamAccumulator.Activity = .thinking
    /// The engine answering right now (or that answered last).
    @Published private(set) var activeEngine: ChatEngineKind?
    /// Something the T3 Code chat is waiting on (an approval or a question).
    @Published private(set) var pending: AgentsService.PendingRequest?
    @Published private(set) var available: Set<ChatEngineKind> = []
    @Published private(set) var statusNotes: [ChatEngineKind: String] = [:]
    @Published private(set) var checking = false
    @Published private(set) var credentialSource: ClaudeCredentialSource?
    @Published private(set) var hasSavedKey = Keychain.read(ClaudeCredentialResolver.keychainAccount) != nil
    @Published private(set) var testResult: (ok: Bool, message: String)?
    @Published var focusRequest = 0

    @Published var choice: EngineChoice = EngineChoice(rawValue: UserDefaults.standard.string(forKey: "aiEngine") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: "aiEngine") }
    }
    /// Model for Claude via T3 Code.
    @Published var t3Model: ClaudeModel = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "t3ChatModel") ?? "") ?? .default {
        didSet { UserDefaults.standard.set(t3Model.rawValue, forKey: "t3ChatModel"); MainActor.assumeIsolated { t3Engine.model = t3Model.rawValue } }
    }
    /// Model, effort and web search for the Claude API.
    @Published var model: ClaudeModel = ClaudeModel(rawValue: UserDefaults.standard.string(forKey: "claudeModel") ?? "") ?? .default {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: "claudeModel"); MainActor.assumeIsolated { apiEngine.model = model } }
    }
    @Published var effort: ClaudeEffort = ClaudeEffort(rawValue: UserDefaults.standard.string(forKey: "claudeEffort") ?? "") ?? .default {
        didSet { UserDefaults.standard.set(effort.rawValue, forKey: "claudeEffort"); MainActor.assumeIsolated { apiEngine.effort = effort } }
    }
    @Published var webSearch: Bool = UserDefaults.standard.object(forKey: "claudeWebSearch") as? Bool ?? true {
        didSet { UserDefaults.standard.set(webSearch, forKey: "claudeWebSearch"); MainActor.assumeIsolated { apiEngine.webSearch = webSearch } }
    }

    /// Called when an answer finishes (with its first line), so the notch can announce it if you're not looking.
    var onAnswer: ((String) -> Void)?

    var isConfigured: Bool { !available.isEmpty }
    var hasClaude: Bool { available.contains(.claudeT3) || available.contains(.claudeAPI) }
    /// The text currently streaming in (for the live activity).
    var streamingText: String { isStreaming ? (messages.last?.role == .assistant ? messages.last?.text ?? "" : "") : "" }
    /// Who's answering, for the live activity.
    var speaker: String { (activeEngine ?? .claudeT3).speaker }

    let agents: AgentsService
    @MainActor private(set) lazy var onDevice = OnDeviceEngine()
    @MainActor private(set) lazy var t3Engine = T3ChatEngine(agents: agents, model: t3Model.rawValue)
    @MainActor private(set) lazy var apiEngine = ClaudeAPIEngine(resolver: resolver, session: session, model: model,
                                                                 effort: effort, webSearch: webSearch)
    var resolver = ClaudeCredentialResolver() { didSet { MainActor.assumeIsolated { apiEngine.resolver = resolver } } }
    var session: URLSession = .shared { didSet { MainActor.assumeIsolated { apiEngine.session = session } } }
    private var task: Task<Void, Never>?
    private var availabilityOverridden = false
    /// The engine this chat's history lives in.
    private var chatEngine: ChatEngineKind?

    init(agents: AgentsService) {
        self.agents = agents
        guard !isDemoMode else { return }
        refreshAvailability()
    }

    // MARK: Engines

    /// Re-checks which engines can answer (cheap: reads a cache file, the keychain and Apple's model status).
    func refreshAvailability() {
        guard !isDemoMode, !availabilityOverridden else { return }
        checking = true
        let resolver = self.resolver, cli = agents.cliPath
        Task.detached(priority: .utility) {
            let source = resolver.resolve()?.source
            let t3 = T3ChatEngine.status(cliPath: cli)
            await MainActor.run {
                let device = OnDeviceEngine.status
                var set = Set<ChatEngineKind>()
                if device.available { set.insert(.onDevice) }
                if t3.available { set.insert(.claudeT3) }
                if source != nil { set.insert(.claudeAPI) }
                guard !self.availabilityOverridden else { return }
                self.available = set
                self.statusNotes = [.onDevice: device.note, .claudeT3: t3.note,
                                    .claudeAPI: source.map { "Connected · \($0.title)" } ?? "Not connected"]
                self.credentialSource = source
                self.checking = false
                self.hasSavedKey = Keychain.read(ClaudeCredentialResolver.keychainAccount) != nil
            }
        }
    }

    /// Sets which engines can answer without checking (tests and demo mode).
    func overrideAvailability(_ set: Set<ChatEngineKind>) {
        availabilityOverridden = true
        available = set
        checking = false
    }

    @MainActor private func engine(_ kind: ChatEngineKind) -> ChatEngine {
        switch kind {
        case .onDevice: onDevice
        case .claudeT3: t3Engine
        case .claudeAPI: apiEngine
        }
    }

    /// Loads Apple's model ahead of the first question (called when the tab opens).
    @MainActor func prewarm() {
        if available.contains(.onDevice) && choice != .claudeT3 && choice != .claudeAPI { onDevice.prewarm() }
    }

    // MARK: API key

    func saveKey(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        Keychain.write(k, for: ClaudeCredentialResolver.keychainAccount)
        testResult = nil
        refreshAvailability()
        testConnection()
    }

    func removeKey() {
        Keychain.delete(ClaudeCredentialResolver.keychainAccount)
        testResult = nil
        refreshAvailability()
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

    @MainActor func clear() {
        cancel()
        messages = []
        attachments = []
        pending = nil
        chatEngine = nil
        for k in ChatEngineKind.allCases { engine(k).reset() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if isStreaming, let i = messages.indices.last, messages[i].role == .assistant {
            messages[i].note = "Stopped"
            if messages[i].text.isEmpty { messages.remove(at: i) }
        }
        isStreaming = false
        pending = nil
    }

    /// Asks a question. `preferClaude` sends it to Claude even in Automatic mode ("Ask Claude instead").
    func send(_ prompt: String, preferClaude: Bool = false) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments.filter(\.isUsable)
        guard !isStreaming, !text.isEmpty || !files.isEmpty else { return }
        let question = text.isEmpty ? "What's in \(files.count == 1 ? "this file" : "these files")?" : text

        guard let kind = EngineRouter.pick(choice: choice, available: available, hasFiles: !files.isEmpty,
                                           questionLength: question.count, current: chatEngine, preferClaude: preferClaude) else {
            messages.append(ChatMessage(role: .user, text: question, attachmentNames: files.map(\.name)))
            messages.append(ChatMessage(role: .assistant, text: noEngineMessage(hasFiles: !files.isEmpty), isError: true))
            return
        }
        // An engine joining mid-chat hasn't seen the earlier turns: give it the transcript.
        let context = (chatEngine != nil && chatEngine != kind) ? EngineRouter.transcript(messages) : nil
        chatEngine = kind
        activeEngine = kind
        attachments = []
        messages.append(ChatMessage(role: .user, text: question, attachmentNames: files.map(\.name)))
        messages.append(ChatMessage(role: .assistant, text: "", engine: kind))
        isStreaming = true
        activity = .thinking
        pending = nil

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await self.engine(kind).ask(question, files: files, context: context) { [weak self] u in
                self?.apply(u)
            }
            guard !Task.isCancelled else { return }
            switch result {
            case .answer(let text, let sources, let note): self.finish(text: text, sources: sources, note: note)
            case .failure(let message): self.finish(error: message)
            }
        }
    }

    /// Re-asks the last question with Claude (offered under on-device answers).
    @MainActor func askClaudeInstead() {
        guard !isStreaming, hasClaude, let lastUser = messages.lastIndex(where: { $0.role == .user }) else { return }
        let question = messages[lastUser].text
        messages.removeSubrange(lastUser...)
        send(question, preferClaude: true)
    }

    private func noEngineMessage(hasFiles: Bool) -> String {
        if hasFiles && !hasClaude { return "Asking about files needs Claude. Connect T3 Code or a Claude API key in Settings → Connections → AI." }
        if let c = choice.engine { return "\(c.title) isn't available right now. Check Settings → Connections → AI." }
        return "No AI is set up yet. Open Settings → Connections → AI."
    }

    private func apply(_ u: EngineUpdate) {
        if u.activity != activity { activity = u.activity }
        if u.pending != pending { pending = u.pending }
        guard let i = messages.indices.last, messages[i].role == .assistant else { return }
        if messages[i].text != u.text { messages[i].text = u.text }
        if messages[i].sources != u.sources { messages[i].sources = u.sources }
    }

    private func finish(text: String, sources: [ClaudeSource], note: String?) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = messages.indices.last, messages[i].role == .assistant {
            messages[i].text = answer.isEmpty ? "(No answer)" : answer
            messages[i].sources = sources
            messages[i].note = note
        }
        isStreaming = false
        pending = nil
        task = nil
        onAnswer?(Self.firstLine(answer))
    }

    /// Shows an error in place of the answer.
    private func finish(error: String) {
        if let i = messages.indices.last, messages[i].role == .assistant {
            messages[i].text = error
            messages[i].isError = true
            messages[i].sources = []
        }
        isStreaming = false
        pending = nil
        task = nil
    }

    static func firstLine(_ s: String) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? s
        return line.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: Demo

    func applyDemo(files: [URL]) {
        available = [.onDevice, .claudeT3]
        statusNotes = [.onDevice: "Ready · free, private and works offline", .claudeT3: "Connected · Claude Max", .claudeAPI: "Not connected"]
        activeEngine = .claudeT3
        messages = [
            ChatMessage(role: .user, text: "Summarize this and list anything I need to do", attachmentNames: ["Q3 Planning.pdf"]),
            ChatMessage(role: .assistant, text: """
            **Q3 plan in one line:** ship the redesigned onboarding by Aug 15, then move the team to the pricing page.
            - **You own:** the onboarding copy review (due **Jul 28**) and the launch email
            - **Decide by Friday:** whether the beta keeps the old dashboard
            - Budget is flat, and hiring for the second designer starts in September
            """, engine: .claudeT3),
        ]
        attachments = files.prefix(1).map { ClaudeAttachment(url: $0, kind: .image) }
    }

    func demoQuick() {
        activeEngine = .onDevice
        attachments = []
        messages = [
            ChatMessage(role: .user, text: "How many tablespoons are in a quarter cup?"),
            ChatMessage(role: .assistant, text: "**4 tablespoons.** A full cup is 16 tablespoons, so a quarter cup is 4.", engine: .onDevice),
        ]
    }

    func demoStreaming() {
        activeEngine = .claudeT3
        messages.append(ChatMessage(role: .user, text: "What's the weather looking like for the Tahoe trip this weekend?"))
        messages.append(ChatMessage(role: .assistant, text: "", engine: .claudeT3))
        isStreaming = true
        activity = .searching("Lake Tahoe weather this weekend")
    }
}
