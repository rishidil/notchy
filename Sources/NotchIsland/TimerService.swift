import AppKit

final class TimerService: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0
    private(set) var lastDuration: TimeInterval = 300
    var onFinish: (() -> Void)?
    private var timer: Timer?

    var isActive: Bool { endDate != nil || pausedRemaining != nil }
    var isRunning: Bool { endDate != nil }

    func remaining(at date: Date) -> TimeInterval {
        if let p = pausedRemaining { return p }
        if let e = endDate { return max(0, e.timeIntervalSince(date)) }
        return 0
    }

    func progress(at date: Date) -> Double {
        total > 0 ? remaining(at: date) / total : 0
    }

    func start(seconds: TimeInterval) {
        total = seconds
        lastDuration = seconds
        pausedRemaining = nil
        endDate = Date().addingTimeInterval(seconds)
        schedule()
    }

    func restart() { start(seconds: lastDuration) }

    func pause() {
        guard let e = endDate else { return }
        pausedRemaining = max(0, e.timeIntervalSinceNow)
        endDate = nil
        timer?.invalidate()
    }

    func resume() {
        guard let p = pausedRemaining else { return }
        endDate = Date().addingTimeInterval(p)
        pausedRemaining = nil
        schedule()
    }

    func addMinute() {
        if let e = endDate { endDate = e.addingTimeInterval(60) } else if let p = pausedRemaining { pausedRemaining = p + 60 }
        total += 60
        schedule()
    }

    func cancel() {
        endDate = nil
        pausedRemaining = nil
        timer?.invalidate()
    }

    private func schedule() {
        timer?.invalidate()
        guard let e = endDate else { return }
        let t = Timer(fire: e, interval: 0, repeats: false) { [weak self] _ in self?.fire() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fire() {
        endDate = nil
        pausedRemaining = nil
        NSSound(named: "Glass")?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { NSSound(named: "Glass")?.play() }
        onFinish?()
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Compact form for the collapsed island.
    static func shortFormat(_ t: TimeInterval) -> String {
        let s = Int(t.rounded(.up))
        if s >= 3600 { return String(format: "%dh%02d", s / 3600, (s % 3600) / 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
