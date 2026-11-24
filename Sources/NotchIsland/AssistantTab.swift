import AppKit
import SwiftUI

// MARK: - Claude tab

struct AssistantTab: View {
    @ObservedObject var claude: AssistantService
    @EnvironmentObject var vm: NotchViewModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if !claude.isConfigured {
            if claude.checking {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyTabMessage(symbol: "sparkle", title: "Set up AI",
                                subtitle: "Turn on Apple Intelligence for free on-device answers, or connect Claude through T3 Code or an API key.",
                                button: "Set Up…") { vm.openSettings(page: .connections) }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                conversation
                if !claude.attachments.isEmpty { attachmentRow }
                composer
            }
            .onChange(of: claude.focusRequest) { _ in focusSoon() }
            .onChange(of: focused) { vm.composerActive = $0 }
            .onAppear {
                claude.prewarm()
                if !claude.attachments.isEmpty { focusSoon() }
            }
            .onDisappear { vm.composerActive = false }
        }
    }

    private func focusSoon() {
        // The panel only accepts keyboard focus once this tab is showing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("AI").font(.system(size: 13, weight: .semibold))
            Menu {
                Picker("Answer with", selection: $claude.choice) {
                    ForEach(EngineChoice.allCases) { c in
                        Text(c.title).tag(c)
                            .disabled(c.engine.map { !claude.available.contains($0) } ?? false)
                    }
                }
                if claude.available.contains(.claudeT3) {
                    Picker("Claude model (T3 Code)", selection: $claude.t3Model) {
                        ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) }
                    }
                }
                if claude.available.contains(.claudeAPI) {
                    Picker("Claude API model", selection: $claude.model) {
                        ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Web Search (Claude API)", isOn: $claude.webSearch)
                }
                Divider()
                Button("AI Settings…") { vm.openSettings(page: .connections) }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: engineSymbol).font(.system(size: 8.5))
                    Text(engineLabel)
                }
                .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.08)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Which AI answers")
            Spacer()
            if claude.isStreaming {
                PillButton(title: "Stop", symbol: "stop.fill") { claude.cancel() }
            }
            if !claude.messages.isEmpty {
                PillButton(title: "New Chat", symbol: "square.and.pencil") { claude.clear(); draft = "" }
            }
        }
    }

    private var engineLabel: String {
        if claude.choice == .auto { return "Auto" + (claude.activeEngine.map { " · \($0.shortName)" } ?? "") }
        return claude.choice.engine?.shortName ?? "Auto"
    }

    private var engineSymbol: String { (claude.choice.engine ?? claude.activeEngine)?.symbol ?? "sparkle" }

    // MARK: Conversation

    @ViewBuilder private var conversation: some View {
        if claude.messages.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 22)).foregroundStyle(Color.claude)
                Text("Ask anything").font(.system(size: 13, weight: .semibold))
                Text(emptyHint)
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(claude.messages) { m in
                            MessageRow(message: m, streaming: claude.isStreaming && m.id == claude.messages.last?.id,
                                       activity: claude.activity,
                                       offerClaude: !claude.isStreaming && claude.hasClaude && m.engine == .onDevice
                                           && m.id == claude.messages.last?.id,
                                       askClaude: { claude.askClaudeInstead() })
                                .id(m.id)
                        }
                        if let r = claude.pending { PendingCard(request: r, agents: vm.agents) }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: claude.messages.last?.text) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: claude.messages.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var emptyHint: String {
        let quick = claude.available.contains(.onDevice)
        if quick && claude.hasClaude && claude.choice == .auto {
            return "Quick questions are answered on your Mac for free. Files and bigger questions go to Claude."
        }
        if quick && !claude.hasClaude { return "Answered on your Mac by Apple's model: free and private. Connect Claude for files and harder questions." }
        return "Drop files on the notch and pick Ask AI to ask about them."
    }

    // MARK: Attachments

    private var attachmentRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(claude.attachments) { a in
                    HStack(spacing: 4) {
                        Image(systemName: a.symbol).font(.system(size: 9.5))
                            .foregroundStyle(a.isUsable ? Color.claude : .orange)
                        Text(a.name).font(.system(size: 10.5, weight: .medium)).lineLimit(1).frame(maxWidth: 150)
                        Button { claude.removeAttachment(a) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(PressableStyle())
                    }
                    .padding(.horizontal, 7).frame(height: 22)
                    .background(Capsule().fill(.white.opacity(0.08)))
                    .help(helpText(a))
                }
            }
        }
        .frame(height: 22)
    }

    private func helpText(_ a: ClaudeAttachment) -> String {
        if case .unsupported(let why) = a.kind { return "\(why). It won't be sent." }
        return a.url.path
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(claude.attachments.isEmpty ? "Ask anything…" : "Ask about \(claude.attachments.count == 1 ? "this file" : "these files")…",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...3)
                .focused($focused)
                .onSubmit(submit)
            Button(action: claude.isStreaming ? claude.cancel : submit) {
                Image(systemName: claude.isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: claude.isStreaming ? 9 : 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(canSend || claude.isStreaming ? Color.claude : Color.white.opacity(0.12)))
            }
            .buttonStyle(PressableStyle())
            .disabled(!canSend && !claude.isStreaming)
            .help(claude.isStreaming ? "Stop" : "Send (Return)")
        }
        .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 4)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(focused ? 0.12 : 0.07)))
    }

    private var canSend: Bool {
        !claude.isStreaming && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || claude.attachments.contains(where: \.isUsable))
    }

    private func submit() {
        guard canSend else { return }
        claude.send(draft)
        draft = ""
    }
}

// MARK: - Message

private struct MessageRow: View {
    let message: AssistantService.ChatMessage
    let streaming: Bool
    let activity: StreamAccumulator.Activity
    var offerClaude = false
    var askClaude: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: message.role == .user ? "person.fill" : (message.engine?.symbol ?? "sparkle"))
                .font(.system(size: 9.5))
                .foregroundStyle(message.role == .user ? Color.white.opacity(0.5) : (message.engine == .onDevice ? Color.cyan : Color.claude))
                .frame(width: 12).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                if message.role == .user {
                    Text(message.text).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6))
                        .textSelection(.enabled)
                    if !message.attachmentNames.isEmpty {
                        Text(message.attachmentNames.joined(separator: " · "))
                            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(Color.claude.opacity(0.85)).lineLimit(1)
                    }
                } else if message.text.isEmpty && streaming {
                    ActivityLabel(activity: activity)
                } else {
                    Text(Markdown.render(message.text))
                        .font(.system(size: 12))
                        .foregroundStyle(message.isError ? Color.orange : .white.opacity(0.92))
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if streaming, activity != .writing { ActivityLabel(activity: activity) }
                    if !message.sources.isEmpty { sources }
                    HStack(spacing: 8) {
                        if let e = message.engine, !streaming {
                            Text(e.shortName).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.35))
                        }
                        if let note = message.note {
                            Text(note).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
                        }
                        if offerClaude {
                            Button(action: askClaude) {
                                Label("Ask Claude instead", systemImage: "sparkle").font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(Color.claude)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            if !message.text.isEmpty {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.text, forType: .string)
                }
            }
        }
    }

    private var sources: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(message.sources.prefix(6)) { s in
                    Button { NSWorkspace.shared.open(s.url) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "globe").font(.system(size: 8))
                            Text(s.host).font(.system(size: 9.5, weight: .medium)).lineLimit(1)
                        }
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.07)))
                    }
                    .buttonStyle(PressableStyle())
                    .help(s.title)
                }
            }
        }
    }
}

/// "Thinking…" / "Searching the web for …"
struct ActivityLabel: View {
    let activity: StreamAccumulator.Activity

    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(Self.text(activity)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
        }
    }

    static func text(_ activity: StreamAccumulator.Activity) -> String {
        switch activity {
        case .thinking: "Thinking…"
        case .searching(let q): q.map { "Searching the web for “\($0)”…" } ?? "Searching the web…"
        case .working(let what): "\(what)…"
        case .writing: "Writing…"
        }
    }
}

// MARK: - Live activity

/// Under the closed notch while Claude works: what it's doing, then the answer as it streams in.
struct AssistantLiveRow: View {
    @ObservedObject var claude: AssistantService

    var body: some View {
        HStack(spacing: 6) {
            let text = claude.streamingText
            if text.isEmpty {
                Text(Self.status(speaker: claude.speaker, activity: claude.activity, waiting: claude.pending != nil))
                    .font(.system(size: 12, weight: .semibold)).fixedSize()
                    .foregroundStyle(claude.pending != nil ? Color.orange : .white)
                if case .searching(let q?) = claude.activity {
                    Text("· \(q)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
            } else {
                Text(Self.tail(text)).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1).truncationMode(.head)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 22)
    }

    static func status(speaker: String, activity: StreamAccumulator.Activity, waiting: Bool) -> String {
        if waiting { return "\(speaker) needs your OK" }
        switch activity {
        case .searching: return "\(speaker) is searching the web"
        case .working(let what): return "\(speaker) · \(what)"
        default: return "\(speaker) is thinking"
        }
    }

    static func tail(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "**", with: "").split(whereSeparator: \.isNewline).joined(separator: " ")
        return String(flat.suffix(140))
    }
}

// MARK: - Markdown

enum Markdown {
    /// Inline Markdown (bold, italics, code, links), keeping line breaks so "- " lists read as lists.
    static func render(_ s: String) -> AttributedString {
        let cleaned = s.replacingOccurrences(of: "\n* ", with: "\n• ").replacingOccurrences(of: "\n- ", with: "\n• ")
        let text = cleaned.hasPrefix("- ") || cleaned.hasPrefix("* ") ? "• " + cleaned.dropFirst(2) : cleaned
        return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

// MARK: - Approvals in a T3 Code chat

/// When Claude (via T3 Code) needs an approval or asks a question mid-answer, answer it right in the chat.
private struct PendingCard: View {
    let request: AgentsService.PendingRequest
    @ObservedObject var agents: AgentsService

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            switch request.kind {
            case .approval(_, let prompt, let reason, let options):
                Label("Claude wants to do something", systemImage: "hand.raised.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange)
                if let text = prompt ?? reason {
                    Text(text).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                }
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { o in
                        PillButton(title: o.label, tint: o.decision == options.first?.decision ? .orange.opacity(0.9) : .white.opacity(0.14),
                                   foreground: o.decision == options.first?.decision ? .black : .white) {
                            agents.respond(to: request, decision: o.decision)
                        }
                        .disabled(agents.responding == request.id)
                    }
                }
            case .questions(let qs):
                if let q = qs.first {
                    Text(q.question).font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange).lineLimit(2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(q.options, id: \.self) { o in
                                PillButton(title: o.label) {
                                    var answers: [String: Any] = [:]
                                    for other in qs { answers[other.id] = other.id == q.id ? (o.value ?? o.label) : (other.options.first?.label ?? "") }
                                    agents.respond(to: request, answers: answers)
                                }
                                .help(o.description)
                                .disabled(agents.responding == request.id)
                            }
                        }
                    }
                }
            }
            if let err = agents.lastError { Text(err).font(.system(size: 10)).foregroundStyle(.orange) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.08)))
    }
}
