import AppKit
import SwiftUI

enum PlayerApp: String, CaseIterable, Identifiable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"

    var id: String { rawValue }
    var name: String { self == .spotify ? "Spotify" : "Music" }
    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty }
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue) }
}

/// Tracks Spotify / Apple Music via their distributed notifications, and controls them via AppleScript.
final class MusicController: ObservableObject {
    @Published private(set) var player: PlayerApp?
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var positionAnchor: Double = 0
    private var anchorDate = Date()
    private var artworkKey = ""
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    var hasTrack: Bool { player != nil && !title.isEmpty }
    var installedPlayers: [PlayerApp] { PlayerApp.allCases.filter { $0.appURL != nil } }

    struct Snapshot {
        var state: String
        var title = "", artist = "", album = ""
        var duration: Double = 0
        var position: Double?
        var artURL: String?
        var isPlaying: Bool { state == "playing" }
        var isStopped: Bool { state == "stopped" || title.isEmpty }
    }

    init() {
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            self?.handle(n, from: .spotify)
        })
        observers.append(dnc.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            self?.handle(n, from: .music)
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            guard let self,
                  let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == self.player?.rawValue else { return }
            self.clear()
            self.refreshAll()
        })
        // Light periodic resync to correct position drift while playing (state changes arrive via notifications).
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, self.isPlaying else { return }
            self.refresh()
        }
        refreshAll()
    }

    // MARK: Position

    func position(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let p = isPlaying ? positionAnchor + date.timeIntervalSince(anchorDate) : positionAnchor
        return min(max(p, 0), duration)
    }

    // MARK: Controls

    func playPause() { command("playpause", optimisticToggle: true) }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: Double) {
        guard let p = player else { return }
        positionAnchor = seconds
        anchorDate = Date()
        AppleScript.run("tell application id \"\(p.rawValue)\" to set player position to \(seconds)")
    }

    func openPlayer() {
        guard let url = (player ?? installedPlayers.first)?.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func launch(_ app: PlayerApp) {
        guard let url = app.appURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private func command(_ cmd: String, optimisticToggle: Bool = false) {
        guard let p = player ?? PlayerApp.allCases.first(where: \.isRunning) else { return }
        if optimisticToggle, player == p {
            positionAnchor = position(at: Date())
            anchorDate = Date()
            isPlaying.toggle()
        }
        AppleScript.run("tell application id \"\(p.rawValue)\" to \(cmd)") { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.fetch(p) }
        }
    }

    // MARK: State

    func refresh() {
        if let p = player { fetch(p) } else { refreshAll() }
    }

    private func refreshAll() {
        for p in PlayerApp.allCases where p.isRunning { fetch(p) }
    }

    private func handle(_ n: Notification, from app: PlayerApp) {
        let info = n.userInfo ?? [:]
        var s = Snapshot(state: ((info["Player State"] as? String) ?? "stopped").lowercased())
        s.title = (info["Name"] as? String) ?? ""
        s.artist = (info["Artist"] as? String) ?? ""
        s.album = (info["Album"] as? String) ?? ""
        let ms = ((info["Duration"] as? NSNumber) ?? (info["Total Time"] as? NSNumber))?.doubleValue ?? 0
        s.duration = ms / 1000
        s.position = (info["Playback Position"] as? NSNumber)?.doubleValue
        apply(s, from: app)
        // Follow up with a full fetch for exact position + artwork.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.fetch(app) }
    }

    private func fetch(_ app: PlayerApp) {
        guard app.isRunning else { return } // never launch the app by accident
        let dur = app == .spotify ? "(duration of t) / 1000" : "duration of t"
        let art = app == .spotify ? ", artwork url of t" : ""
        let script = """
        tell application id "\(app.rawValue)"
            set s to player state as string
            if s is "stopped" then return {s}
            try
                set t to current track
                return {s, name of t, artist of t, album of t, \(dur), player position\(art)}
            on error
                return {s}
            end try
        end tell
        """
        AppleScript.run(script) { [weak self] d in
            guard let self, let d else { return }
            func item(_ i: Int) -> NSAppleEventDescriptor? { i <= d.numberOfItems ? d.atIndex(i) : nil }
            var s = Snapshot(state: item(1)?.stringValue?.lowercased() ?? "stopped")
            s.title = item(2)?.stringValue ?? ""
            s.artist = item(3)?.stringValue ?? ""
            s.album = item(4)?.stringValue ?? ""
            s.duration = item(5)?.doubleValue ?? 0
            s.position = item(6)?.doubleValue
            s.artURL = item(7)?.stringValue
            self.apply(s, from: app)
        }
    }

    private func apply(_ s: Snapshot, from app: PlayerApp) {
        let isCurrent = player == app
        if s.isStopped {
            if isCurrent { clear() }
            return
        }
        // A paused player shouldn't steal the island from one that's playing.
        guard isCurrent || s.isPlaying || !isPlaying else { return }

        let now = Date()
        let trackChanged = !isCurrent || s.title != title || s.album != album
        let currentPos = position(at: now)

        player = app
        title = s.title
        artist = s.artist
        album = s.album
        if s.duration > 0 { duration = s.duration } else if trackChanged { duration = 0 }
        isPlaying = s.isPlaying
        if let pos = s.position {
            positionAnchor = pos
        } else {
            positionAnchor = trackChanged ? 0 : currentPos
        }
        anchorDate = now
        updateArtwork(s, app)
    }

    private func clear() {
        player = nil
        title = ""; artist = ""; album = ""
        isPlaying = false
        duration = 0
        positionAnchor = 0
        artworkKey = ""
        setArtwork(nil)
    }

    private func updateArtwork(_ s: Snapshot, _ app: PlayerApp) {
        let key = "\(app.rawValue)|\(s.title)|\(s.album)"
        guard key != artworkKey else { return }
        switch app {
        case .spotify:
            guard let str = s.artURL, let url = URL(string: str) else { setArtwork(nil); return }
            artworkKey = key
            URLSession.shared.dataTask(with: url) { data, _, _ in
                let img = data.flatMap { NSImage(data: $0) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.artworkKey == key else { return }
                    self.setArtwork(img)
                }
            }.resume()
        case .music:
            artworkKey = key
            let script = """
            tell application id "com.apple.Music"
                try
                    return raw data of artwork 1 of current track
                end try
            end tell
            """
            AppleScript.run(script) { [weak self] d in
                guard let self, self.artworkKey == key else { return }
                self.setArtwork(d.flatMap { NSImage(data: $0.data) })
            }
        }
    }

    private func setArtwork(_ img: NSImage?) {
        artwork = img
        accent = img?.vibrantAverageColor.map { Color(nsColor: $0) } ?? .white
    }
}
