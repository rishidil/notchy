import Foundation

/// Answers T3 Code approvals and questions from the notch.
///
/// T3 Code's `t3` CLI can list, read and message threads but can't respond to a pending request, so Notchy does what
/// T3 Code's own remote clients do: it asks the CLI for a scoped access token (`t3 auth session issue`, kept in the
/// keychain and revocable in Settings), exchanges it for a one-time WebSocket ticket, and sends a single
/// `runtime-request.respond` command to the local T3 Code server. Nothing leaves your Mac.
final class T3Remote {
    static let shared = T3Remote()

    struct Session: Codable, Equatable {
        let token: String
        let sessionId: String
        let expiresAt: Date?
    }

    enum RemoteError: LocalizedError {
        case notRunning, noToken, unauthorized, timeout, server(String)
        var errorDescription: String? {
            switch self {
            case .notRunning: "T3 Code isn't running. Open it and try again."
            case .noToken: "Couldn't get access from T3 Code. Is it up to date?"
            case .unauthorized: "T3 Code rejected Notchy's access. Reconnect it in Settings → Connections."
            case .timeout: "T3 Code didn't answer in time."
            case .server(let m): m
            }
        }
    }

    static let keychainAccount = "t3-session"
    static let scopes = ["orchestration:read", "orchestration:operate"]
    private static var runtimePath: String { NSHomeDirectory() + "/.t3/userdata/server-runtime.json" }

    var session: Session? {
        guard let s = Keychain.read(Self.keychainAccount), let data = s.data(using: .utf8) else { return nil }
        return try? Self.decoder.decode(Session.self, from: data)
    }
    var isConnected: Bool { session != nil }

    // MARK: Respond

    /// Approves/declines (`decision`) or answers questions (`answers`, keyed by question id). Off the main thread.
    func respond(cli: String, threadID: String, requestID: String, decision: String?, answers: [String: Any]?) throws {
        let command = Self.respondCommand(threadID: threadID, requestID: requestID, decision: decision, answers: answers)
        try dispatch(command, cli: cli, retryAuth: true)
    }

    private func dispatch(_ command: [String: Any], cli: String, retryAuth: Bool) throws {
        guard let origin = Self.serverOrigin() else { throw RemoteError.notRunning }
        let session = try ensureSession(cli: cli)
        do {
            let ticket = try Self.ticket(origin: origin, token: session.token)
            try Self.send(command, origin: origin, ticket: ticket)
        } catch RemoteError.unauthorized where retryAuth {
            // The token expired or was revoked in T3 Code: get a fresh one once.
            Keychain.delete(Self.keychainAccount)
            try dispatch(command, cli: cli, retryAuth: false)
        }
    }

    static func respondCommand(threadID: String, requestID: String, decision: String?, answers: [String: Any]?,
                               commandID: String = UUID().uuidString.lowercased()) -> [String: Any] {
        var c: [String: Any] = ["type": "runtime-request.respond", "commandId": commandID, "threadId": threadID, "requestId": requestID]
        if let decision { c["decision"] = decision }
        if let answers { c["answers"] = answers }
        return c
    }

    // MARK: Access token

    func ensureSession(cli: String) throws -> Session {
        if let s = session, (s.expiresAt ?? .distantFuture) > Date().addingTimeInterval(3600) { return s }
        var args = ["auth", "session", "issue", "--ttl", "90d", "--label", "Notchy", "--json"]
        for s in Self.scopes { args += ["--scope", s] }
        guard let out = AgentsService.run(cli, args), let s = Self.parseIssued(out) else { throw RemoteError.noToken }
        if let data = try? Self.encoder.encode(s), let json = String(data: data, encoding: .utf8) {
            Keychain.write(json, for: Self.keychainAccount)
        }
        return s
    }

    /// Revokes Notchy's access token in T3 Code and forgets it.
    func disconnect(cli: String?) {
        if let cli, let id = session?.sessionId { AgentsService.run(cli, ["auth", "session", "revoke", id]) }
        Keychain.delete(Self.keychainAccount)
    }

    /// `t3 auth session issue --json` prints one JSON object (sometimes followed by blank lines or log output).
    static func parseIssued(_ data: Data) -> Session? {
        guard let text = String(data: data, encoding: .utf8), let obj = firstJSONObject(in: text),
              let token = obj["token"] as? String, !token.isEmpty, let id = obj["sessionId"] as? String else { return nil }
        let expires = (obj["expiresAt"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        return Session(token: token, sessionId: id, expiresAt: expires)
    }

    static func firstJSONObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        var i = start
        while i < text.endIndex {
            let c = text[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 {
                    let slice = String(text[start...i])
                    return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
                }
            }
            i = text.index(after: i)
        }
        return nil
    }

    // MARK: Server

    static func serverOrigin() -> URL? {
        guard let data = FileManager.default.contents(atPath: runtimePath) else { return nil }
        return originFromRuntime(data)
    }

    static func originFromRuntime(_ data: Data) -> URL? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let origin = obj["origin"] as? String, let url = URL(string: origin), url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }

    static func socketURL(origin: URL, ticket: String) -> URL? {
        guard var c = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = c.scheme == "https" ? "wss" : "ws"
        c.path = "/ws"
        c.queryItems = [URLQueryItem(name: "orchestrationProtocol", value: "2"), URLQueryItem(name: "wsTicket", value: ticket)]
        return c.url
    }

    private static func ticket(origin: URL, token: String) throws -> String {
        var r = URLRequest(url: origin.appendingPathComponent("api/auth/websocket-ticket/rpc"), timeoutInterval: 10)
        r.httpMethod = "POST"
        r.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
        let (data, status) = try blockingData(r)
        if status == 401 || status == 403 { throw RemoteError.unauthorized }
        guard status == 200, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let ticket = obj["ticket"] as? String else { throw RemoteError.server("T3 Code answered \(status).") }
        return ticket
    }

    /// Sends one RPC request over T3 Code's WebSocket and waits for its result.
    private static func send(_ command: [String: Any], origin: URL, ticket: String) throws {
        guard let url = socketURL(origin: origin, ticket: ticket) else { throw RemoteError.notRunning }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        let envelope: [String: Any] = ["_tag": "Request", "id": "1", "tag": "orchestration.dispatchCommand",
                                       "payload": command, "headers": [Any]()]
        let text = String(data: try JSONSerialization.data(withJSONObject: envelope), encoding: .utf8) ?? ""

        let done = DispatchSemaphore(value: 0)
        var outcome: Result<Void, Error> = .failure(RemoteError.timeout)
        socket.send(.string(text)) { error in
            if let error { outcome = .failure(error); done.signal() }
        }
        func receive() {
            socket.receive { result in
                switch result {
                case .failure(let error):
                    outcome = .failure(error); done.signal()
                case .success(let message):
                    let raw: String? = switch message {
                    case .string(let s): s
                    case .data(let d): String(data: d, encoding: .utf8)
                    @unknown default: nil
                    }
                    if let raw, let exit = parseExit(raw, requestID: "1") {
                        switch exit {
                        case .success: outcome = .success(())
                        case .failure(let message): outcome = .failure(RemoteError.server(message))
                        }
                        done.signal()
                    } else {
                        receive() // pings, chunks or other requests' messages
                    }
                }
            }
        }
        receive()
        if done.wait(timeout: .now() + 15) == .timedOut { throw RemoteError.timeout }
        try outcome.get()
    }

    /// Reads an RPC `Exit` message for our request: nil if the message is about something else.
    enum ExitOutcome: Equatable { case success, failure(String) }

    static func parseExit(_ raw: String, requestID: String) -> ExitOutcome? {
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
              obj["_tag"] as? String == "Exit", obj["requestId"] as? String == requestID else { return nil }
        let exit = obj["exit"] as? [String: Any]
        if exit?["_tag"] as? String == "Success" { return .success }
        let causes = exit?["cause"] as? [[String: Any]] ?? []
        let error = causes.compactMap { $0["error"] as? [String: Any] }.first
        let message = error?["message"] as? String ?? error?["detail"] as? String ?? "T3 Code couldn't take that answer."
        return .failure(message)
    }

    private static func blockingData(_ request: URLRequest) throws -> (Data, Int) {
        let done = DispatchSemaphore(value: 0)
        var result: Result<(Data, Int), Error> = .failure(RemoteError.timeout)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { result = .failure(error) } else {
                result = .success((data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0))
            }
            done.signal()
        }.resume()
        if done.wait(timeout: .now() + 12) == .timedOut { throw RemoteError.timeout }
        do { return try result.get() } catch { throw RemoteError.notRunning }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()
    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
}
