import AppKit
import SwiftUI

// MARK: - Claude tab

struct ClaudeTab: View {
    @ObservedObject var claude: ClaudeService
    @EnvironmentObject var vm: NotchViewModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        if !claude.isConfigured {
            if claude.checkingCredential {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyTabMessage(symbol: "sparkle", title: "Connect Claude",
                                subtitle: "Add your Anthropic API key once to ask Claude from the notch, with web search and files you drop on it.",
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
            .onAppear { if !claude.attachments.isEmpty { focusSoon() } }
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
            Text("Claude").font(.system(size: 13, weight: .semibold))
            Menu {
                Picker("Model", selection: $claude.model) {
                    ForEach(ClaudeModel.allCases) { Text($0.title).tag($0) }
                }
                Picker("Answers", selection: $claude.effort) {
                    ForEach(ClaudeEffort.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Search the Web", isOn: $claude.webSearch)
            } label: {
                HStack(spacing: 3) {
                    Text(claude.model.shortName)
                    if claude.webSearch { Image(systemName: "globe").font(.system(size: 8.5)) }
                }
                .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.08)))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Model, answer style and web search")
            Spacer()
            if claude.isStreaming {
                PillButton(title: "Stop", symbol: "stop.fill") { claude.cancel() }
            }
            if !claude.messages.isEmpty {
                PillButton(title: "New Chat", symbol: "square.and.pencil") { claude.clear(); draft = "" }
            }
        }
    }

    // MARK: Conversation

    @ViewBuilder private var conversation: some View {
        if claude.messages.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 22)).foregroundStyle(Color.claude)
                Text("Ask Claude anything").font(.system(size: 13, weight: .semibold))
                Text(claude.webSearch ? "Answers can use the web. Drop files on the notch and pick Ask Claude to ask about them."
                     : "Drop files on the notch and pick Ask Claude to ask about them.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(claude.messages) { m in
                            MessageRow(message: m, streaming: claude.isStreaming && m.id == claude.messages.last?.id,
                                       activity: claude.activity)
                                .id(m.id)
                        }
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
            TextField(claude.attachments.isEmpty ? "Ask Claude…" : "Ask about \(claude.attachments.count == 1 ? "this file" : "these files")…",
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
    let message: ClaudeService.ChatMessage
    let streaming: Bool
    let activity: StreamAccumulator.Activity

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: message.role == .user ? "person.fill" : "sparkle")
                .font(.system(size: 9.5))
                .foregroundStyle(message.role == .user ? Color.white.opacity(0.5) : Color.claude)
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
                    if streaming, case .searching = activity { ActivityLabel(activity: activity) }
                    if !message.sources.isEmpty { sources }
                    if let note = message.note {
                        Text(note).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
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
        case .writing: "Writing…"
        }
    }
}

// MARK: - Live activity

/// Under the closed notch while Claude works: what it's doing, then the answer as it streams in.
struct ClaudeLiveRow: View {
    @ObservedObject var claude: ClaudeService

    var body: some View {
        HStack(spacing: 6) {
            let text = claude.streamingText
            if text.isEmpty {
                Text(claude.activity == .thinking ? "Claude is thinking" : "Claude is searching the web")
                    .font(.system(size: 12, weight: .semibold)).fixedSize()
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
