import Foundation

/// Synced lyrics from LRCLIB (a free, open lyrics database). Only fetches while lyrics are turned on.
final class LyricsService: ObservableObject {
    struct Line: Identifiable, Equatable {
        let id: Int
        let time: Double
        let text: String
    }

    enum State: Equatable { case idle, loading, synced, plain, notFound, failed }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var plainText: String?
    @Published private(set) var state: State = .idle

    var isEnabled = false {
        didSet { if isEnabled && !oldValue, let t = pending { load(t) } }
    }

    private struct Track: Equatable { var title, artist, album: String; var duration: Double }
    private var pending: Track?
    private var loadedKey = ""
    private var cache: [String: (lines: [Line], plain: String?)] = [:]
    private var task: URLSessionDataTask?

    /// Called whenever the playing track changes.
    func update(title: String, artist: String, album: String, duration: Double) {
        guard !isDemoMode else { return }
        let t = Track(title: title, artist: artist, album: album, duration: duration)
        pending = title.isEmpty ? nil : t
        if title.isEmpty {
            task?.cancel()
            lines = []; plainText = nil; state = .idle; loadedKey = ""
            return
        }
        if isEnabled { load(t) }
    }

    /// Index of the line being sung at `position` seconds.
    func index(at position: Double) -> Int? {
        guard !lines.isEmpty else { return nil }
        var lo = 0, hi = lines.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= position + 0.25 { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found
    }

    func line(at position: Double) -> String? {
        index(at: position).map { lines[$0].text }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private func load(_ t: Track) {
        let key = "\(t.artist)|\(t.title)".lowercased()
        guard key != loadedKey else { return }
        loadedKey = key
        task?.cancel()
        if let hit = cache[key] { show(hit.lines, hit.plain); return }
        lines = []; plainText = nil; state = .loading

        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [.init(name: "track_name", value: t.title), .init(name: "artist_name", value: t.artist),
                        .init(name: "album_name", value: t.album)]
        if t.duration > 0 { c.queryItems?.append(.init(name: "duration", value: String(Int(t.duration.rounded())))) }
        request(c.url!) { [weak self] record in
            guard let self, self.loadedKey == key else { return }
            if let record, record.hasLyrics {
                self.finish(key, record)
                return
            }
            // Exact match failed (album/duration mismatch is common): fall back to a search.
            var s = URLComponents(string: "https://lrclib.net/api/search")!
            s.queryItems = [.init(name: "track_name", value: t.title), .init(name: "artist_name", value: t.artist)]
            self.requestList(s.url!) { [weak self] records in
                guard let self, self.loadedKey == key else { return }
                let best = records?.first { $0.syncedLyrics?.isEmpty == false } ?? records?.first { $0.hasLyrics }
                if let best { self.finish(key, best) } else { self.state = records == nil ? .failed : .notFound }
            }
        }
    }

    private func finish(_ key: String, _ r: Record) {
        let parsed = Self.parse(r.syncedLyrics ?? "")
        cache[key] = (parsed, r.plainLyrics)
        if cache.count > 50 { cache.removeAll() }
        show(parsed, r.plainLyrics)
    }

    private func show(_ l: [Line], _ plain: String?) {
        lines = l
        plainText = plain
        state = !l.isEmpty ? .synced : (plain?.isEmpty == false ? .plain : .notFound)
    }

    // MARK: Network

    private struct Record: Decodable {
        let plainLyrics: String?
        let syncedLyrics: String?
        let instrumental: Bool?
        var hasLyrics: Bool { syncedLyrics?.isEmpty == false || plainLyrics?.isEmpty == false }
    }

    private func makeRequest(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 10)
        r.setValue("Notchy/1.2 (macOS app)", forHTTPHeaderField: "User-Agent")
        return r
    }

    private func request(_ url: URL, completion: @escaping (Record?) -> Void) {
        task = URLSession.shared.dataTask(with: makeRequest(url)) { data, _, _ in
            let r = data.flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
            DispatchQueue.main.async { completion(r) }
        }
        task?.resume()
    }

    private func requestList(_ url: URL, completion: @escaping ([Record]?) -> Void) {
        task = URLSession.shared.dataTask(with: makeRequest(url)) { data, _, _ in
            let r = data.flatMap { try? JSONDecoder().decode([Record].self, from: $0) }
            DispatchQueue.main.async { completion(r) }
        }
        task?.resume()
    }

    /// Parses LRC: "[01:23.45] line" (a line may carry several timestamps).
    static func parse(_ lrc: String) -> [Line] {
        let regex = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:[.:]\d+)?)\]"#)
        var out: [(Double, String)] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let s = String(raw)
            let ns = s as NSString
            let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let text = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for m in matches {
                let min = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let sec = Double(ns.substring(with: m.range(at: 2)).replacingOccurrences(of: ":", with: ".")) ?? 0
                out.append((min * 60 + sec, text))
            }
        }
        return out.sorted { $0.0 < $1.0 }.enumerated().map { Line(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    func applyDemo() {
        // Original placeholder lyrics for screenshots.
        let demo = ["Streetlights hum a quiet tune", "We're driving home beneath the moon",
                    "Windows down and nothing planned", "Your heartbeat racing in my hand",
                    "Hold on, the night is young", "Every song is still unsung",
                    "Hold on, we're almost there", "Neon dreams and summer air"]
        lines = demo.enumerated().map { Line(id: $0.offset, time: Double($0.offset) * 4 + 60, text: $0.element) }
        state = .synced
    }
}
