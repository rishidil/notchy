import AppKit
import CoreGraphics

/// Tracks how long each app is frontmost, entirely on this Mac. Pauses while the Mac is idle, asleep or locked.
/// (macOS doesn't offer a public Screen Time API, so Notchy keeps its own tally from the moment it's enabled.)
final class ScreenTimeTracker: ObservableObject {
    struct Usage: Identifiable {
        let bundleID: String
        let seconds: Double
        var id: String { bundleID }
        var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
        var name: String {
            appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
        }
        var icon: NSImage? { appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } }
    }

    /// "yyyy-MM-dd" → bundle ID → seconds
    @Published private(set) var days: [String: [String: Double]] = [:]
    @Published private(set) var since: Date?
    private(set) var isRunning = false

    private var currentApp: String?
    private var segmentStart: Date?
    private var paused = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var dirty = false
    private var lastSave = Date()
    private static let ignored: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine", "dev.notchisland.app"]
    private static let idleLimit: TimeInterval = 120

    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("screentime.json")
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { dayFormatter.string(from: date) }

    // MARK: Lifecycle

    func start() {
        guard !isRunning, !isDemoMode else { return }
        isRunning = true
        load()
        if since == nil { since = Date(); dirty = true }

        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.didActivateApplicationNotification) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.switchTo(app?.bundleIdentifier)
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(ws, name) { [weak self] _ in self?.setPaused(true) }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(ws, name) { [weak self] _ in self?.setPaused(false) }
        }
        let dnc = DistributedNotificationCenter.default()
        observe(dnc, .init("com.apple.screenIsLocked")) { [weak self] _ in self?.setPaused(true) }
        observe(dnc, .init("com.apple.screenIsUnlocked")) { [weak self] _ in self?.setPaused(false) }

        currentApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        segmentStart = Date()
        timer = Timer.every(30) { [weak self] _ in self?.checkpoint() }
    }

    func stop() {
        guard isRunning else { return }
        checkpoint()
        save()
        for (center, o) in observers { center.removeObserver(o) }
        observers = []
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    func saveNow() { if isRunning { checkpoint(); save() } }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ block: @escaping (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: block)))
    }

    // MARK: Tracking

    private func switchTo(_ bundleID: String?) {
        commit(until: Date())
        currentApp = bundleID
        segmentStart = Date()
    }

    private func setPaused(_ p: Bool) {
        guard p != paused else { return }
        commit(until: Date())
        paused = p
        segmentStart = Date()
        if p { save() }
    }

    private func checkpoint() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let now = Date()
        if idle > Self.idleLimit {
            // Count up to the last input, then wait for activity.
            commit(until: now.addingTimeInterval(-idle))
        } else {
            commit(until: now)
        }
        segmentStart = now
        if dirty && now.timeIntervalSince(lastSave) > 120 { save() }
    }

    private func commit(until end: Date) {
        defer { segmentStart = end }
        guard !paused, let app = currentApp, !Self.ignored.contains(app), let start = segmentStart, end > start else { return }
        let seconds = min(end.timeIntervalSince(start), 600) // never more than one sample's worth at once
        let key = Self.key(for: start)
        days[key, default: [:]][app, default: 0] += seconds
        dirty = true
    }

    // MARK: Queries

    func usage(for date: Date = Date()) -> [Usage] {
        (days[Self.key(for: date)] ?? [:]).map { Usage(bundleID: $0.key, seconds: $0.value) }
            .filter { $0.seconds >= 30 }
            .sorted { $0.seconds > $1.seconds }
    }

    func total(for date: Date = Date()) -> Double {
        (days[Self.key(for: date)] ?? [:]).values.reduce(0, +)
    }

    /// Totals for the last 7 days, oldest first.
    var week: [(date: Date, seconds: Double)] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let d = Calendar.current.date(byAdding: .day, value: -offset, to: today)!
            return (d, total(for: d))
        }
    }

    static func format(_ s: Double) -> String {
        let m = Int(s / 60)
        if m < 1 { return "<1m" }
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }

    // MARK: Persistence

    private struct Stored: Codable { var since: Date?; var days: [String: [String: Double]] }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let s = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        days = s.days
        since = s.since
    }

    private func save() {
        guard !isDemoMode else { return }
        // Keep 30 days.
        let cutoff = Self.key(for: Date().addingTimeInterval(-30 * 86400))
        days = days.filter { $0.key >= cutoff }
        if let data = try? JSONEncoder().encode(Stored(since: since, days: days)) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
        dirty = false
        lastSave = Date()
    }

    func reset() {
        days = [:]
        since = Date()
        segmentStart = Date()
        save()
    }

    func applyDemo() {
        let today = Self.key(for: Date())
        days[today] = ["com.todesktop.230313mzl4w4u92": 9840, "com.google.Chrome": 6120, "com.tinyspeck.slackmacgap": 3300,
                       "com.spotify.client": 1500]
        let totals: [Double] = [6.1, 7.4, 5.2, 8.0, 6.6, 3.1]
        for (i, h) in totals.enumerated() {
            let d = Calendar.current.date(byAdding: .day, value: -(6 - i), to: Date())!
            days[Self.key(for: d)] = ["com.google.Chrome": h * 3600]
        }
        since = Date().addingTimeInterval(-14 * 86400)
    }
}
