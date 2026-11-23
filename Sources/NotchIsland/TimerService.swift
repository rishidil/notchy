import AppKit
import SwiftUI

enum PomodoroPhase: String, Equatable {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var symbol: String { self == .focus ? "brain.head.profile" : "cup.and.saucer.fill" }
    var color: Color { self == .focus ? Color(red: 1, green: 0.42, blue: 0.36) : .green }
}

final class TimerService: ObservableObject {
    @Published private(set) var endDate: Date?
    @Published private(set) var pausedRemaining: TimeInterval?
    @Published private(set) var total: TimeInterval = 0
    private(set) var lastDuration: TimeInterval = 300
    /// Non-nil while a Pomodoro session is running.
    @Published private(set) var phase: PomodoroPhase?
    @Published private(set) var completedFocus = 0
    @Published var focusMinutes = UserDefaults.standard.object(forKey: "pomodoroFocus") as? Int ?? 25 {
        didSet { UserDefaults.standard.set(focusMinutes, forKey: "pomodoroFocus") }
    }
    @Published var shortBreakMinutes = UserDefaults.standard.object(forKey: "pomodoroShort") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(shortBreakMinutes, forKey: "pomodoroShort") }
    }
    @Published var longBreakMinutes = UserDefaults.standard.object(forKey: "pomodoroLong") as? Int ?? 15 {
        didSet { UserDefaults.standard.set(longBreakMinutes, forKey: "pomodoroLong") }
    }
    @Published var cyclesBeforeLongBreak = UserDefaults.standard.object(forKey: "pomodoroCycles") as? Int ?? 4 {
        didSet { UserDefaults.standard.set(cyclesBeforeLongBreak, forKey: "pomodoroCycles") }
    }
    var onFinish: (() -> Void)?
    /// Fired when a Pomodoro phase ends and the next one begins.
    var onPhaseChange: ((PomodoroPhase) -> Void)?
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
        phase = nil
        run(seconds: seconds)
    }

    private func run(seconds: TimeInterval) {
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

    // MARK: Pomodoro

    func startPomodoro() {
        completedFocus = 0
        begin(.focus)
    }

    /// Ends the current phase early and moves on to the next one.
    func skipPhase() {
        guard phase != nil else { return }
        advance()
    }

    private func minutes(for p: PomodoroPhase) -> Int {
        switch p {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    private func begin(_ p: PomodoroPhase) {
        phase = p
        run(seconds: Double(minutes(for: p)) * 60)
    }

    private func advance() {
        guard let p = phase else { return }
        let next: PomodoroPhase
        if p == .focus {
            completedFocus += 1
            next = completedFocus % max(1, cyclesBeforeLongBreak) == 0 ? .longBreak : .shortBreak
        } else {
            next = .focus
        }
        begin(next)
        onPhaseChange?(next)
    }

    func cancel() {
        phase = nil
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
        if phase != nil {
            NSSound(named: "Glass")?.play()
            advance()
            return
        }
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
