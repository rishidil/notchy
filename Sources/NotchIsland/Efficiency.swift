import AppKit

/// Keeps Notchy's CPU use low: shared timer helper (coalescing + pausing while the screen is off),
/// a self CPU monitor that switches on an efficiency mode, and anonymous diagnostics for bug reports.
final class Efficiency: ObservableObject {
    static let shared = Efficiency()

    enum Mode: String, CaseIterable, Identifiable {
        case automatic, on, off
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .on: "Always On"
            case .off: "Off"
            }
        }
    }

    /// Display awake and session active. Background work pauses otherwise.
    @Published private(set) var isAwake = true
    /// Average CPU use of this process over the last 30s (0–100, may exceed 100 on multi-core).
    @Published private(set) var cpuPercent: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var autoTripped = false
    @Published var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "efficiencyMode") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "efficiencyMode") }
    }

    /// When true, periodic work runs at half rate and optional animations are skipped.
    var isActive: Bool {
        switch mode {
        case .on: true
        case .off: false
        case .automatic: autoTripped || ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    static let cpuLimit: Double = 10
    private var lastUsage: (cpu: Double, wall: Date)?
    private var monitor: Timer?
    private var observers: [NSObjectProtocol] = []

    private init() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.isAwake = false })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.isAwake = true })
        }
        let dnc = DistributedNotificationCenter.default()
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.isAwake = false })
        observers.append(dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.isAwake = true })
        observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.objectWillChange.send()
        })
        lastUsage = (Self.processCPUSeconds(), Date())
        let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.sampleCPU() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        monitor = t
    }

    // MARK: CPU self-monitoring

    private func sampleCPU() {
        let now = Date(), cpu = Self.processCPUSeconds()
        defer { lastUsage = (cpu, now) }
        guard let last = lastUsage, isAwake else { return }
        let wall = now.timeIntervalSince(last.wall)
        guard wall > 1 else { return }
        let pct = max(0, (cpu - last.cpu) / wall * 100)
        cpuPercent = pct
        cpuHistory.append(pct)
        if cpuHistory.count > 20 { cpuHistory.removeFirst(cpuHistory.count - 20) }
        // Trip after a full minute over the limit; recover after two minutes comfortably under it.
        let recent = cpuHistory.suffix(2), calm = cpuHistory.suffix(4)
        if !autoTripped, recent.count == 2, recent.allSatisfy({ $0 > Self.cpuLimit }) {
            autoTripped = true
            NotchViewModel.log.notice("Efficiency mode on: CPU averaged \(pct, format: .fixed(precision: 1))%")
        } else if autoTripped, calm.count == 4, calm.allSatisfy({ $0 < Self.cpuLimit / 2 }) {
            autoTripped = false
        }
    }

    /// Total user + system CPU time used by this process, in seconds.
    static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func secs(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return secs(usage.ru_utime) + secs(usage.ru_stime)
    }

    // MARK: Diagnostics

    /// Anonymous report for bug reports: hardware, displays, which features are on, CPU history. No personal data.
    func diagnostics(vm: NotchViewModel) -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let screens = NSScreen.screens.enumerated().map { i, s in
            "  display \(i + 1): \(Int(s.frame.width))×\(Int(s.frame.height)) @\(s.maximumFramesPerSecond)Hz, notch: \(s.safeAreaInsets.top > 0 ? "yes" : "no")"
        }
        let history = cpuHistory.map { String(format: "%.1f", $0) }.joined(separator: ", ")
        return """
        Notchy \(vm.updater.currentVersion) diagnostics
        Mac: \(String(cString: model)), macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), \(ProcessInfo.processInfo.activeProcessorCount) cores
        \(screens.joined(separator: "\n"))
        CPU now: \(String(format: "%.1f", cpuPercent))%  (last \(cpuHistory.count) × 30s: \(history))
        Efficiency mode: \(mode.rawValue), active: \(isActive), auto-tripped: \(autoTripped), Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled)
        Tabs on: \(vm.tabs.map(\.rawValue).joined(separator: ", "))
        HUD replacement: \(vm.replaceSystemHUD) (key tap active: \(vm.keyTapActive))
        Notification previews: \(vm.notifications.enabled) (access: \(vm.notifications.hasAccess))
        Lyrics under notch: \(vm.lyricsInNotch), drop actions: \(vm.dropActionsEnabled)
        Music: \(vm.music.player?.name ?? "none"), playing: \(vm.music.isPlaying)
        T3 Code: installed \(vm.agents.isInstalled), projects \(vm.agents.projects.count), threads \(vm.agents.threads.count), running \(vm.agents.runningCount)
        Live activity: \(String(describing: vm.activity).prefix(40)), expanded: \(vm.isExpanded)
        """
    }
}

extension Timer {
    /// A repeating main-thread timer for background work: lets macOS coalesce wake-ups (20% tolerance),
    /// skips ticks while the display is off, and runs at half rate in efficiency mode.
    @discardableResult
    static func every(_ interval: TimeInterval, _ block: @escaping (Timer) -> Void) -> Timer {
        var tick = 0
        let t = Timer(timeInterval: interval, repeats: true) { timer in
            let eff = Efficiency.shared
            guard eff.isAwake else { return }
            tick &+= 1
            if eff.isActive && tick % 2 == 0 { return }
            block(timer)
        }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        return t
    }
}
