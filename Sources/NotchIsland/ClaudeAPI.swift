import AppKit
import UniformTypeIdentifiers

// The pieces of the Claude integration that don't touch the UI: credentials, request building, the streaming
// (SSE) parser and attachment encoding. Swift has no official Anthropic SDK, so Notchy speaks the Messages API
// over HTTPS directly (https://platform.claude.com/docs/en/api/messages).

// MARK: - Models

enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-5-5"
    case opus = "claude-opus-5-5"
    case haiku = "claude-haiku-5-5"

    static let `default`: ClaudeModel = .sonnet
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sonnet: "Claude Sonnet 5.5"
        case .opus: "Claude Opus 5.5"
        case .haiku: "Claude Haiku 5.5"
        }
    }

    var shortName: String {
        switch self {
        case .sonnet: "Sonnet 5.5"
        case .opus: "Opus 5.5"
        case .haiku: "Haiku 5.5"
        }
    }

    var blurb: String {
        switch self {
        case .sonnet: "Fast and capable. Best for everyday questions ($2 / $10 per million tokens)"
        case .opus: "Most capable. Best for hard questions and long files ($4 / $20 per million tokens)"
        case .haiku: "Fastest and cheapest. Best for quick one-liners ($0.10 / $0.50 per million tokens)"
        }
    }

    /// Server-side refusal fallbacks are available on Sonnet 5.5 and Opus 5.5 (not Haiku 5.5).
    var supportsFallbacks: Bool { self != .haiku }
}

/// How hard Claude thinks before answering (the API's `output_config.effort`).
enum ClaudeEffort: String, CaseIterable, Identifiable {
    case low, medium, high
    static let `default`: ClaudeEffort = .low
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: "Quick"
        case .medium: "Balanced"
        case .high: "Thorough"
        }
    }
}

// MARK: - Credentials

/// Where the credential for the Claude API came from.
enum ClaudeCredentialSource: String, Equatable {
    case keychain, environment, antCLI

    var title: String {
        switch self {
        case .keychain: "API key saved in Notchy"
        case .environment: "ANTHROPIC_API_KEY"
        case .antCLI: "Anthropic CLI sign-in (ant)"
        }
    }
}

struct ClaudeCredential: Equatable {
    enum Kind: Equatable { case apiKey, oauthToken }
    let kind: Kind
    let secret: String
    let source: ClaudeCredentialSource

    /// HTTP headers for this credential (API keys use x-api-key; sign-in tokens use a Bearer header plus the OAuth beta).
    var authHeaders: [String: String] {
        switch kind {
        case .apiKey: ["x-api-key": secret]
        case .oauthToken: ["authorization": "Bearer \(secret)"]
        }
    }

    var betas: [String] { kind == .oauthToken ? ["oauth-2025-04-20"] : [] }
}

/// Finds a credential, in order: a key saved in Notchy's keychain, ANTHROPIC_API_KEY, then an `ant auth login` sign-in.
struct ClaudeCredentialResolver {
    static let keychainAccount = "claude-api-key"

    var keychainKey: () -> String? = { Keychain.read(keychainAccount) }
    var environment: () -> [String: String] = { ProcessInfo.processInfo.environment }
    var antToken: () -> String? = { ClaudeCredentialResolver.tokenFromAntCLI() }

    func resolve() -> ClaudeCredential? {
        if let key = keychainKey()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return ClaudeCredential(kind: .apiKey, secret: key, source: .keychain)
        }
        if let key = environment()["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            return ClaudeCredential(kind: .apiKey, secret: key, source: .environment)
        }
        if let token = antToken() {
            return ClaudeCredential(kind: .oauthToken, secret: token, source: .antCLI)
        }
        return nil
    }

    static func antPath() -> String? {
        let home = NSHomeDirectory()
        let candidates = ["/opt/homebrew/bin/ant", "/usr/local/bin/ant", home + "/go/bin/ant", home + "/.local/bin/ant"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// `ant auth print-credentials --access-token` prints a short-lived token (refreshing it if needed). Off the main thread only.
    static func tokenFromAntCLI() -> String? {
        guard let path = antPath() else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = ["auth", "print-credentials", "--access-token"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: killer)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        guard p.terminationStatus == 0 else { return nil }
        return validToken(String(data: data, encoding: .utf8))
    }

    /// Accepts one line that looks like a token (guards against another tool named `ant`, such as Apache Ant).
    static func validToken(_ output: String?) -> String? {
        guard let s = output?.trimmingCharacters(in: .whitespacesAndNewlines), s.count >= 20,
              !s.contains(where: { $0.isWhitespace }), !s.hasPrefix("{") else { return nil }
        return s
    }
}

// MARK: - Requests

enum ClaudeAPI {
    static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let modelsURL = URL(string: "https://api.anthropic.com/v1/models?limit=1")!
    static let apiVersion = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    static let maxTokens = 32_000
    static let maxContinuations = 5

    static func systemPrompt(today: Date = Date()) -> String {
        let day = today.formatted(date: .complete, time: .omitted)
        return """
        You are Claude, answering inside Notchy: a small panel that drops down from the notch at the top of the user's Mac screen.
        The panel is about 600 points wide and shows a few lines at a time, so lead with the answer and keep it short: \
        usually one to three short paragraphs or a brief list. Go longer only when the user asks for detail.
        Format with light Markdown only (bold, italics, `inline code`, and lines starting with "- " for lists). \
        Don't use headings, tables or code blocks longer than a few lines.
        When files are attached, the user dropped them onto the notch; refer to them by file name.
        Today is \(day).
        """
    }

    /// The JSON body for one streaming Messages request.
    static func body(model: ClaudeModel, effort: ClaudeEffort, webSearch: Bool, system: String,
                     messages: [[String: Any]]) -> [String: Any] {
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "messages": messages,
            "output_config": ["effort": effort.rawValue],
            // Caches the conversation so far (including attachments) between turns.
            "cache_control": ["type": "ephemeral"],
        ]
        if webSearch {
            body["tools"] = [["type": "web_search_20260209", "name": "web_search", "max_uses": 5]]
        }
        if model.supportsFallbacks {
            // If a safety classifier declines, the API retries on a suitable fallback model in the same call.
            body["fallbacks"] = "default"
        }
        return body
    }

    static func headers(credential: ClaudeCredential, model: ClaudeModel) -> [String: String] {
        var h = credential.authHeaders
        h["content-type"] = "application/json"
        h["anthropic-version"] = apiVersion
        var betas = credential.betas
        if model.supportsFallbacks { betas.append(fallbackBeta) }
        if !betas.isEmpty { h["anthropic-beta"] = betas.joined(separator: ",") }
        return h
    }

    static func request(body: [String: Any], credential: ClaudeCredential, model: ClaudeModel) throws -> URLRequest {
        var r = URLRequest(url: messagesURL, timeoutInterval: 300)
        r.httpMethod = "POST"
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        for (k, v) in headers(credential: credential, model: model) { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }

    /// A short message for an HTTP error from the API.
    static func errorMessage(status: Int, body: Data?) -> String {
        var apiMessage: String?
        if let body, let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let err = obj["error"] as? [String: Any] {
            apiMessage = err["message"] as? String
        }
        if let m = apiMessage, m.localizedCaseInsensitiveContains("credit balance") {
            return "Your Anthropic account is out of credits. Add some at platform.claude.com → Billing."
        }
        switch status {
        case 401: return "Claude didn't accept your API key. Check it in Settings → Connections → Claude."
        case 403: return "This API key can't use \(apiMessage.map { "that model: \($0)" } ?? "that model")."
        case 404: return apiMessage ?? "That model isn't available on your account."
        case 413: return "The attached files are too large for one request. Try fewer or smaller files."
        case 429: return "Rate limited by the Claude API. Try again in a moment."
        case 500...599: return "Claude is overloaded right now. Try again in a moment."
        default: return apiMessage ?? "The Claude API returned an error (\(status))."
        }
    }
}

// MARK: - Streaming

/// Anthropic's SSE stream sends one JSON object per `data:` line, each with a `type` field, so lines can be
/// handled one at a time (event names and blank lines carry nothing extra).
enum SSEParser {
    static func event(fromLine line: String) -> [String: Any]? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, let data = payload.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// A web page Claude cited.
struct ClaudeSource: Identifiable, Equatable, Hashable {
    let url: URL
    let title: String
    var id: URL { url }
    var host: String { url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString }
}

/// Rebuilds the assistant message from stream events: the text shown live, the raw content blocks (needed to
/// resume a `pause_turn`), cited sources and what Claude is doing right now.
struct StreamAccumulator {
    enum Activity: Equatable { case thinking, searching(String?), working(String), writing }

    private(set) var blocks: [Int: [String: Any]] = [:]
    private var partialJSON: [Int: String] = [:]
    private(set) var model: String?
    private(set) var stopReason: String?
    private(set) var errorMessage: String?
    private(set) var activity: Activity = .thinking
    private(set) var sources: [ClaudeSource] = []
    private(set) var searches = 0
    private(set) var usedFallback = false

    /// All text so far, in block order.
    var text: String {
        blocks.keys.sorted().compactMap { i -> String? in
            guard blocks[i]?["type"] as? String == "text" else { return nil }
            return blocks[i]?["text"] as? String
        }.joined()
    }

    /// The content blocks to send back when resuming a paused turn. After a fallback, model-internal blocks from
    /// before the switch are left out (the fallback model can't use them); the fallback marker keeps its place.
    var contentForResume: [[String: Any]] {
        let ordered = blocks.keys.sorted().compactMap { blocks[$0] }
        guard let lastFallback = ordered.lastIndex(where: { $0["type"] as? String == "fallback" }) else { return ordered }
        let resultIDs = Set(ordered.compactMap { $0["tool_use_id"] as? String })
        return ordered.enumerated().compactMap { i, b in
            guard i < lastFallback else { return b }
            switch b["type"] as? String {
            case "thinking", "redacted_thinking", "tool_use": return nil
            case "server_tool_use": return resultIDs.contains(b["id"] as? String ?? "") ? b : nil
            default: return b
            }
        }
    }

    mutating func apply(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "message_start":
            model = (event["message"] as? [String: Any])?["model"] as? String
        case "content_block_start":
            guard let i = event["index"] as? Int, var block = event["content_block"] as? [String: Any] else { return }
            let type = block["type"] as? String
            if type == "server_tool_use" { block["input"] = block["input"] ?? [String: Any](); partialJSON[i] = "" }
            if type == "fallback" { usedFallback = true }
            blocks[i] = block
            switch type {
            case "text": if activity != .writing { activity = .writing }
            case "thinking", "redacted_thinking": activity = .thinking
            case "server_tool_use": activity = .searching(nil); searches += 1
            case "web_search_tool_result": collectSources(fromResult: block)
            default: break
            }
        case "content_block_delta":
            guard let i = event["index"] as? Int, let delta = event["delta"] as? [String: Any], var block = blocks[i] else { return }
            switch delta["type"] as? String {
            case "text_delta":
                block["text"] = (block["text"] as? String ?? "") + (delta["text"] as? String ?? "")
                activity = .writing
            case "thinking_delta":
                block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta":
                block["signature"] = (block["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
            case "input_json_delta":
                partialJSON[i, default: ""] += delta["partial_json"] as? String ?? ""
            case "citations_delta":
                if let c = delta["citation"] as? [String: Any] {
                    var list = block["citations"] as? [[String: Any]] ?? []
                    list.append(c)
                    block["citations"] = list
                    addSource(url: c["url"] as? String, title: c["title"] as? String)
                }
            default: break
            }
            blocks[i] = block
        case "content_block_stop":
            guard let i = event["index"] as? Int, let json = partialJSON.removeValue(forKey: i), var block = blocks[i] else { return }
            if let data = json.data(using: .utf8), let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                block["input"] = input
                if block["type"] as? String == "server_tool_use" { activity = .searching(input["query"] as? String) }
            }
            blocks[i] = block
        case "message_delta":
            if let d = event["delta"] as? [String: Any], let r = d["stop_reason"] as? String { stopReason = r }
        case "error":
            let err = event["error"] as? [String: Any]
            let type = err?["type"] as? String
            errorMessage = type == "overloaded_error" ? "Claude is overloaded right now. Try again in a moment."
                : (err?["message"] as? String ?? "The stream was interrupted.")
        default:
            break
        }
    }

    private mutating func collectSources(fromResult block: [String: Any]) {
        // On success `content` is a list of results; on failure it's a single error object.
        guard let results = block["content"] as? [[String: Any]] else { return }
        for r in results.prefix(3) { addSource(url: r["url"] as? String, title: r["title"] as? String) }
    }

    private mutating func addSource(url: String?, title: String?) {
        guard let url, let u = URL(string: url), u.scheme?.hasPrefix("http") == true,
              !sources.contains(where: { $0.url == u }) else { return }
        sources.append(ClaudeSource(url: u, title: title ?? u.host ?? url))
    }
}

// MARK: - Attachments

/// A file dropped onto the notch for Claude to read.
struct ClaudeAttachment: Identifiable, Equatable {
    enum Kind: Equatable { case image, pdf, text, folder, unsupported(String) }

    let url: URL
    let kind: Kind
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var isUsable: Bool { if case .unsupported = kind { false } else { true } }

    var symbol: String {
        switch kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "doc.text"
        case .folder: "folder"
        case .unsupported: "exclamationmark.triangle.fill"
        }
    }

    static let maxImageBytes = 3_750_000
    static let maxPDFBytes = 25_000_000
    static let maxTextBytes = 2_000_000
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp"]

    static func make(_ url: URL) -> ClaudeAttachment {
        ClaudeAttachment(url: url, kind: classify(url))
    }

    static func classify(_ url: URL) -> Kind {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return .unsupported("File not found") }
        if isDir.boolValue {
            // Bundles like .app or .pages are directories too, but listing them isn't useful.
            return NSWorkspace.shared.isFilePackage(atPath: url.path) ? .unsupported("Claude can't read this kind of file") : .folder
        }
        let ext = url.pathExtension.lowercased()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        if imageExtensions.contains(ext) { return .image }
        if ext == "pdf" { return size <= maxPDFBytes ? .pdf : .unsupported("PDF is over 25 MB") }
        let type = UTType(filenameExtension: ext)
        let textLike = type.map { $0.conforms(to: .text) || $0.conforms(to: .sourceCode) || $0.conforms(to: .json)
            || $0.conforms(to: .xml) || $0.conforms(to: .propertyList) } ?? false
        if textLike || isUTF8Text(url) {
            return size <= maxTextBytes ? .text : .unsupported("Text file is over 2 MB")
        }
        return .unsupported("Claude can't read .\(ext.isEmpty ? "this kind of" : ext) files")
    }

    /// Small files with no known type (Makefile, .env.example, …) count as text if they decode as UTF-8.
    private static func isUTF8Text(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 8192), !head.isEmpty, !head.contains(0) else { return false }
        return String(data: head, encoding: .utf8) != nil
    }

    /// The API content block for this file. Images are scaled down to fit the API's size limit.
    func contentBlock() throws -> [String: Any] {
        switch kind {
        case .image:
            let (data, mediaType) = try Self.imageData(url)
            return ["type": "image", "source": ["type": "base64", "media_type": mediaType, "data": data.base64EncodedString()]]
        case .pdf:
            let data = try Data(contentsOf: url)
            return ["type": "document", "title": name,
                    "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()]]
        case .text:
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return ["type": "document", "title": name,
                    "source": ["type": "text", "media_type": "text/plain", "data": text.isEmpty ? "(empty file)" : text]]
        case .folder:
            return ["type": "document", "title": name + "/",
                    "source": ["type": "text", "media_type": "text/plain", "data": Self.folderListing(url)]]
        case .unsupported(let why):
            throw NSError(domain: "Notchy", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name): \(why)"])
        }
    }

    /// A folder is sent as a listing of what's inside (two levels deep), not the files themselves.
    static func folderListing(_ url: URL, limit: Int = 300) -> String {
        var lines = ["Folder \(url.path) contains:"]
        let fm = FileManager.default
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return lines[0] + " (unreadable)" }
        var count = 0
        for case let item as URL in e {
            if e.level > 2 { e.skipDescendants(); continue }
            count += 1
            if count > limit { lines.append("… and more"); break }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let rel = item.path.replacingOccurrences(of: url.path + "/", with: "")
            if values?.isDirectory == true { lines.append("\(rel)/") }
            else { lines.append("\(rel) (\(ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)))") }
        }
        if count == 0 { lines.append("(empty)") }
        return lines.joined(separator: "\n")
    }

    static func imageData(_ url: URL) throws -> (Data, String) {
        let raw = try Data(contentsOf: url)
        let ext = url.pathExtension.lowercased()
        let native: [String: String] = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"]
        if let type = native[ext], raw.count <= maxImageBytes, let rep = NSBitmapImageRep(data: raw),
           max(rep.pixelsWide, rep.pixelsHigh) <= 2400 {
            return (raw, type)
        }
        // Convert (HEIC, TIFF…) and/or shrink to JPEG, longest side ≤ 1568 px (what the API uses anyway).
        guard let image = NSImage(data: raw), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "Notchy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't read the image \(url.lastPathComponent)"])
        }
        let scale = min(1, 1568 / CGFloat(max(cg.width, cg.height)))
        let w = max(1, Int(CGFloat(cg.width) * scale)), h = max(1, Int(CGFloat(cg.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw NSError(domain: "Notchy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't resize \(url.lastPathComponent)"])
        }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage(),
              let jpeg = NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw NSError(domain: "Notchy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Couldn't resize \(url.lastPathComponent)"])
        }
        return (jpeg, "image/jpeg")
    }
}
