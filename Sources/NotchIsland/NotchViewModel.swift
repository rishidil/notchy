import AppKit
import Combine
import os
import ServiceManagement
import SwiftUI

enum HUDKind: Equatable { case volume, brightness }

/// Short-lived things that pop out of the notch.
enum Transient: Equatable {
    case battery
    case hud(HUDKind)
    case notification(NotificationItem)
    case timerDone
    case device(BluetoothService.Device)
    case toast(symbol: String, text: String, tint: Color)
}

/// What the collapsed island is currently showing.
enum LiveActivity: Equatable {
    case none
    case music
    case battery(level: Int, onAC: Bool)
    case event(minutes: Int)
    case timer
    case timerDone
    case hud(HUDKind)
    case notification(NotificationItem)
    case device(BluetoothService.Device)
    case toast(symbol: String, text: String, tint: Color)
    case agents(running: Int, waiting: Int)
}

final class NotchViewModel: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var tab: NotchTab = .home { didSet { if tab != oldValue { tabDidChange() } } }
    @Published private(set) var transient: Transient?
    /// Direction of the latest volume/brightness change (drives the sweep direction) and a counter bumped on every change.
    @Published private(set) var hudUp = true
    @Published private(set) var hudPulse = 0
    private var lastHUDLevels: [HUDKind: Double] = [:]
    @Published private(set) var isDropTargeted = false
    @Published private(set) var dropHover: DropAction?
    /// Forces the drop-actions view on screen (used for screenshots).
    @Published var dropPreview = false
    @Published private(set) var replaceSystemHUD = UserDefaults.standard.bool(forKey: "replaceSystemHUD")
    @Published private(set) var showIdleBadge = UserDefaults.standard.object(forKey: "showIdleBadge") as? Bool ?? true
    /// False on Macs/displays without a camera notch: the island then hides until it has something to show.
    @Published var hasNotch = true
    @Published private(set) var showMenuBarActivities = UserDefaults.standard.object(forKey: "showMenuBarActivities") as? Bool ?? true
    /// Whether volume/brightness keys are currently being intercepted (false if Accessibility is missing).
    @Published private(set) var keyTapActive = false
    @Published private(set) var lyricsInNotch = UserDefaults.standard.bool(forKey: "lyricsInNotch")
    @Published private(set) var dropActionsEnabled = UserDefaults.standard.object(forKey: "dropActions") as? Bool ?? true
    /// All tabs in the user's order, and which of them are switched on.
    @Published private(set) var tabOrder: [NotchTab]
    @Published private(set) var enabledTabs: Set<NotchTab>

    let music = MusicController()
    let battery = BatteryMonitor()
    let calendar = CalendarService()
    let toggles = SystemToggles()
    let shelf = AppShelf()
    let volume = VolumeController()
    let brightness = BrightnessController()
    let timer = TimerService()
    let notifications = NotificationWatcher()
    let files = FileShelf()
    let weather = WeatherService()
    let todos = TodoStore()
    let lyrics = LyricsService()
    let bluetooth = BluetoothService()
    let system = SystemMonitor()
    let screenTime = ScreenTimeTracker()
    let agents = AgentsService()
    let updater = UpdateService()
    /// Something to do when the user clicks the current pop-up (e.g. open the update screen).
    private var actionForTransient: (() -> Void)?
    /// Tab to open when the user clicks the current pop-up (e.g. an agent finished).
    private var tabForTransient: NotchTab?
    private let keyTap = MediaKeyTap()

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let log = Logger(subsystem: "dev.notchisland.app", category: "island")

    private var bag = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var hoverWork: DispatchWorkItem?
    private var transientWork: DispatchWorkItem?
    private var trustTimer: Timer?
    private var isHovering = false
    private var menuOpen = false
    /// Frames of the drop-action tiles, in the island's coordinate space.
    var dropTileFrames: [DropAction: CGRect] = [:]

    init() {
        let defaults = UserDefaults.standard
        let savedOrder = (defaults.stringArray(forKey: "tabOrder") ?? []).compactMap(NotchTab.init(rawValue:))
        tabOrder = savedOrder + NotchTab.allCases.filter { !savedOrder.contains($0) }
        if let saved = defaults.stringArray(forKey: "enabledTabs") {
            enabledTabs = Set(saved.compactMap(NotchTab.init(rawValue:)))
        } else {
            enabledTabs = Set(NotchTab.defaultTabs)
        }
        if enabledTabs.isEmpty { enabledTabs = [.home] }
        tab = tabs.first ?? .home

        // Re-render whenever any service changes.
        let services: [AnyPublisher<Void, Never>] = [
            music.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            battery.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            calendar.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            toggles.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            shelf.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            volume.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            brightness.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            timer.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            notifications.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            files.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            weather.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            todos.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            lyrics.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            bluetooth.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            system.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            screenTime.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            agents.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
            updater.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(services)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)

        // Look up lyrics when the track changes.
        Publishers.CombineLatest3(music.$title, music.$artist, music.$duration)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] title, artist, duration in
                guard let self else { return }
                self.lyrics.update(title: title, artist: artist, album: self.music.album, duration: duration)
            }
            .store(in: &bag)

        battery.onPowerSourceChange = { [weak self] in self?.show(.battery, for: 3) }
        volume.onChange = { [weak self] in self?.showHUD(.volume) }
        brightness.onChange = { [weak self] in self?.showHUD(.brightness) }
        timer.onFinish = { [weak self] in self?.show(.timerDone, for: 10) }
        timer.onPhaseChange = { [weak self] phase in
            let text = phase == .focus ? "Break's over — time to focus" : "Nice work! Take a \(phase == .longBreak ? "long " : "")break"
            self?.show(.toast(symbol: phase.symbol, text: text, tint: phase.color), for: 4)
        }
        notifications.onNotification = { [weak self] item in self?.show(.notification(item), for: 5) }
        bluetooth.onConnect = { [weak self] device in self?.show(.device(device), for: 3.5) }
        updater.onUpdateAvailable = { [weak self] release in
            self?.show(.toast(symbol: "arrow.down.circle.fill", text: "Notchy \(release.version) is available · Click to update", tint: .blue),
                       for: 10, action: { [weak self] in self?.openSettings(page: .about) })
        }
        agents.onFinished = { [weak self] t in
            self?.show(.toast(symbol: "checkmark.circle.fill", text: "Agent finished · \(t.title)", tint: .green), for: 5, tab: .agents)
        }
        agents.onNeedsInput = { [weak self] t in
            self?.show(.toast(symbol: "hand.raised.fill", text: "T3 is waiting for your approval · \(t.title)", tint: .orange), for: 8, tab: .agents)
            NSSound(named: "Tink")?.play()
        }
        keyTap.handler = { [weak self] key, fine, isDown, isRepeat in
            self?.handleMediaKey(key, fine: fine, isDown: isDown, isRepeat: isRepeat) ?? false
        }
        if replaceSystemHUD { enableKeyTap() }

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuOpen = true
        })
        observers.append(nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            self?.menuOpen = false
        })
        observers.append(nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screenTime.saveNow()
        })

        if isDemoMode { DemoData.apply(to: self) } else { applyFeatureState() }
    }

    // MARK: Tabs & features

    /// The tabs shown in the header, in order.
    var tabs: [NotchTab] { tabOrder.filter { enabledTabs.contains($0) } }

    func isTabEnabled(_ t: NotchTab) -> Bool { enabledTabs.contains(t) }

    func setTab(_ t: NotchTab, enabled: Bool) {
        if enabled { enabledTabs.insert(t) } else if enabledTabs.count > 1 { enabledTabs.remove(t) }
        saveTabs()
        if !enabledTabs.contains(tab) { tab = tabs.first ?? .home }
        applyFeatureState()
    }

    func moveTabs(from source: IndexSet, to destination: Int) {
        tabOrder.move(fromOffsets: source, toOffset: destination)
        saveTabs()
    }

    func setDemoTabs(_ t: [NotchTab]) {
        tabOrder = t + NotchTab.allCases.filter { !t.contains($0) }
        enabledTabs = Set(t)
    }

    func demoDrop(hover: DropAction) {
        dropPreview = true
        dropHover = hover
        expand()
    }

    func resetTabs() {
        tabOrder = NotchTab.allCases
        enabledTabs = Set(NotchTab.defaultTabs)
        saveTabs()
        tab = tabs.first ?? .home
        applyFeatureState()
    }

    private func saveTabs() {
        guard !isDemoMode else { return }
        UserDefaults.standard.set(tabOrder.map(\.rawValue), forKey: "tabOrder")
        UserDefaults.standard.set(enabledTabs.map(\.rawValue), forKey: "enabledTabs")
    }

    /// Starts only the services the user's tabs need, so nothing asks for permission or uses the network unless it's wanted.
    func applyFeatureState() {
        guard !isDemoMode else { return }
        isTabEnabled(.weather) ? weather.start() : weather.stop()
        isTabEnabled(.bluetooth) ? bluetooth.start() : bluetooth.stop()
        isTabEnabled(.screenTime) ? screenTime.start() : screenTime.stop()
        isTabEnabled(.agents) ? agents.start() : agents.stop()
        lyrics.isEnabled = isTabEnabled(.lyrics) || lyricsInNotch
        notifications.historyEnabled = isTabEnabled(.notifications)
        updateSystemMonitor()
    }

    private func tabDidChange() {
        updateSystemMonitor()
        agents.setVisible(isExpanded && tab == .agents)
        guard isExpanded else { return }
        if tab == .weather { weather.refreshIfStale() }
        if tab == .bluetooth { bluetooth.refreshDetails() }
    }

    private func updateSystemMonitor() {
        if isExpanded && tab == .system { system.start() } else { system.stop() }
    }

    func setLyricsInNotch(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "lyricsInNotch")
        withAnimation(Self.spring) { lyricsInNotch = on }
        applyFeatureState()
    }

    func setDropActions(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "dropActions")
        dropActionsEnabled = on
    }

    // MARK: Activity & geometry

    var activity: LiveActivity {
        switch transient {
        case .notification(let n): return .notification(n)
        case .hud(let kind): return .hud(kind)
        case .battery: return .battery(level: battery.level, onAC: battery.onAC)
        case .timerDone: return .timerDone
        case .device(let d): return .device(d)
        case .toast(let s, let t, let c): return .toast(symbol: s, text: t, tint: c)
        case nil: break
        }
        // Without a notch, persistent activities sit in the menu bar; the user can turn that off.
        if !hasNotch && !showMenuBarActivities { return .none }
        if timer.isActive { return .timer }
        // Agents working in the background are a live activity (like T3 Code's on iOS), ahead of music.
        if isTabEnabled(.agents) && (agents.runningCount > 0 || agents.attentionCount > 0) {
            return .agents(running: agents.runningCount, waiting: agents.attentionCount)
        }
        if music.isPlaying && music.hasTrack { return .music }
        if let e = calendar.nextEvent {
            let minutes = Int(ceil(e.start.timeIntervalSinceNow / 60))
            if (0...10).contains(minutes) { return .event(minutes: minutes) }
        }
        return .none
    }

    /// Show the current lyric line under the notch while music plays.
    var showsLyricLine: Bool { lyricsInNotch && activity == .music && lyrics.state == .synced }

    var expandedSize: CGSize { CGSize(width: expandedWidth, height: notchSize.height + 162) }

    // MARK: Header layout (tabs either side of the notch, battery + ⚙︎ always visible on the right)

    var headerTabWidth: CGFloat { tabs.count > 9 ? 25 : (tabs.count > 7 ? 27 : 30) }
    /// Space reserved on the right of the header for the battery readout and the gear.
    static let headerTrailingReserve: CGFloat = 96
    /// The island grows a little wider when many tabs are on, instead of hiding the battery.
    var expandedWidth: CGFloat {
        let slot = headerTabWidth + 2
        let side = ceil((CGFloat(tabs.count) * slot + Self.headerTrailingReserve) / 2) + slot // room for both groups
        return min(740, max(640, notchSize.width + 2 * (side + 34)))
    }
    var sideWidth: CGFloat { notchSize.height + 14 }

    /// Small always-visible box to the left of the notch, so there's something to aim for when idle.
    var idleBadgeWidth: CGFloat { notchSize.height + 8 }
    private var showsIdleBadge: Bool { hasNotch && !isExpanded && showIdleBadge && activity == .none }
    /// No notch and nothing to show: draw nothing at all, so no screen space is used.
    var isHiddenIdle: Bool { !hasNotch && !isExpanded && activity == .none }
    /// Shifts the island left when only the left-hand idle badge is showing.
    var bodyOffsetX: CGFloat { showsIdleBadge ? -idleBadgeWidth / 2 : 0 }

    var collapsedSize: CGSize {
        let n = notchSize
        let wide = n.width + 2 * sideWidth
        switch activity {
        case .none: return hasNotch && showIdleBadge ? CGSize(width: n.width + idleBadgeWidth, height: n.height) : n
        case .hud: return CGSize(width: hasNotch ? wide : max(wide, 240), height: n.height + 26)
        case .notification: return CGSize(width: max(wide, 420), height: n.height + 62)
        case .timerDone: return CGSize(width: max(wide, 360), height: n.height + 44)
        case .toast: return CGSize(width: max(wide, 360), height: n.height + 34)
        case .device: return CGSize(width: max(wide, 300), height: n.height + 30)
        case .music where showsLyricLine: return CGSize(width: max(wide, 380), height: n.height + 26)
        case .agents: return CGSize(width: max(wide, 340), height: n.height + 26)
        default: return CGSize(width: wide, height: n.height)
        }
    }

    var bodySize: CGSize { isExpanded ? expandedSize : collapsedSize }
    var topRadius: CGFloat { isExpanded ? 14 : 6 }
    var bottomRadius: CGFloat { isExpanded ? 26 : (collapsedSize.height > notchSize.height ? 20 : 10) }
    var shapeSize: CGSize { CGSize(width: bodySize.width + 2 * topRadius, height: bodySize.height) }

    /// Notifications and "timer done" have their own buttons, so hovering them shouldn't expand the island.
    private var transientIsInteractive: Bool {
        switch transient {
        case .notification, .timerDone: return true
        default: return false
        }
    }

    /// The area (in global screen coordinates) that should receive the mouse.
    func interactiveRect(screenFrame: CGRect) -> CGRect {
        if isHiddenIdle {
            // Hidden: a strip along the top edge, so pushing the cursor to the top center opens the island.
            return CGRect(x: screenFrame.midX - 140, y: screenFrame.maxY - 3, width: 280, height: 7)
        }
        let s = shapeSize
        let w = s.width + (isExpanded ? 0 : 24)
        let h = s.height + (isExpanded ? 10 : 8)
        // Extend a few points above the screen: with the cursor pushed to the very top, mouseLocation.y == maxY,
        // which a rect ending exactly at maxY wouldn't contain.
        return CGRect(x: screenFrame.midX + bodyOffsetX - w / 2, y: screenFrame.maxY - h, width: w, height: h + 4)
    }

    // MARK: Hover / expand

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        scheduleHover(hovering)
    }

    private func scheduleHover(_ hovering: Bool) {
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if hovering {
                if !self.transientIsInteractive { self.expand() }
            } else if self.menuOpen || NSEvent.pressedMouseButtons & 1 != 0 || self.dropPreview {
                self.scheduleHover(false) // a menu is open or a drag is in progress: check again shortly
            } else {
                self.collapse()
            }
        }
        hoverWork = work
        // When hidden on a notch-less screen, wait a bit longer so quick trips to the menu bar don't open it.
        let delay = hovering ? (isHiddenIdle ? 0.3 : 0.12) : 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func expand() {
        guard !isExpanded else { return }
        withAnimation(Self.spring) { isExpanded = true }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        guard !isDemoMode else { return }
        // Refresh once the open animation has finished, so the work (and the redraws it causes) can't make it stutter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.isExpanded else { return }
            self.music.refresh()
            self.calendar.refresh()
            self.toggles.refreshKeepAwake()
            self.tabDidChange()
        }
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(Self.spring) { isExpanded = false }
        updateSystemMonitor()
    }

    func handleTap() {
        switch transient {
        case .notification(let n):
            if let url = n.appURL { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
            dismissTransient()
        case .timerDone:
            dismissTransient()
        default:
            if transient != nil, let action = actionForTransient {
                actionForTransient = nil
                dismissTransient()
                action()
                return
            }
            if let t = tabForTransient, isTabEnabled(t) {
                tab = t
                dismissTransient()
            }
            expand()
        }
    }

    // MARK: Transients

    func show(_ t: Transient, for seconds: Double, tab: NotchTab? = nil, action: (() -> Void)? = nil) {
        Self.log.info("show transient: \(String(describing: t), privacy: .private)")
        tabForTransient = tab
        actionForTransient = action
        withAnimation(Self.spring) { transient = t }
        scheduleTransientDismiss(after: seconds)
    }

    /// Volume/brightness feedback: brief pop-up when closed; when open, the level line lingers a little longer.
    func showHUD(_ kind: HUDKind, up: Bool? = nil) {
        let level = hudLevel(kind)
        if let up {
            hudUp = up
        } else if let old = lastHUDLevels[kind], abs(level - old) > 0.001 {
            hudUp = level > old
        } else if up == nil, lastHUDLevels[kind].map({ abs(level - $0) <= 0.001 }) == true {
            return // a duplicate notification for a change we've already shown
        }
        lastHUDLevels[kind] = level
        hudPulse &+= 1
        show(.hud(kind), for: isExpanded ? 2.5 : 1.6)
    }

    func dismissTransient() {
        transientWork?.cancel()
        withAnimation(Self.spring) { transient = nil }
    }

    private func scheduleTransientDismiss(after seconds: Double) {
        transientWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.transientIsInteractive && self.isHovering {
                self.scheduleTransientDismiss(after: 1) // keep it while the user is pointing at it
                return
            }
            withAnimation(Self.spring) { self.transient = nil }
        }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func muteNotifications(from item: NotificationItem) {
        notifications.mute(item.bundleID)
        dismissTransient()
    }

    // MARK: File drag & drop

    /// Whether dropping files on the notch does anything with the current settings.
    var acceptsDrops: Bool { dropActionsEnabled || isTabEnabled(.shelf) }
    var showsDropActions: Bool { dropPreview || (isDropTargeted && dropActionsEnabled) }

    /// Called while a file drag hovers over the notch.
    func beginFileDrag() {
        if !dropActionsEnabled && isTabEnabled(.shelf) && tab != .shelf { tab = .shelf }
    }

    func dropTargetChanged(_ targeted: Bool) {
        isDropTargeted = targeted
        if !targeted { dropHover = nil }
        if targeted {
            if !dropActionsEnabled && isTabEnabled(.shelf) { tab = .shelf }
            expand()
        }
    }

    var availableDropActions: [DropAction] {
        DropAction.allCases.filter { $0 != .shelf || isTabEnabled(.shelf) }
    }

    func updateDropHover(_ location: CGPoint) {
        let hit = dropTileFrames.first { $0.value.insetBy(dx: -4, dy: -4).contains(location) }?.key
        if hit != dropHover { dropHover = hit }
    }

    func performDrop(_ providers: [NSItemProvider], at location: CGPoint) -> Bool {
        updateDropHover(location)
        let action: DropAction? = dropActionsEnabled ? dropHover : (isTabEnabled(.shelf) ? .shelf : nil)
        // Dropped on the island but not on a tile: keep it on the shelf if there is one.
        guard let chosen = action ?? (isTabEnabled(.shelf) ? .shelf : nil) else { return false }
        FileShelf.loadURLs(providers) { [weak self] urls in
            guard let self, !urls.isEmpty else { return }
            self.run(chosen, on: urls)
        }
        isDropTargeted = false
        dropHover = nil
        return true
    }

    private func run(_ action: DropAction, on urls: [URL]) {
        switch action {
        case .shelf:
            files.add(urls)
            tab = .shelf
        case .airDrop:
            NSApp.activate(ignoringOtherApps: true)
            NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
        case .compress:
            FileShelf.compress(urls)
            collapse()
            show(.toast(symbol: "doc.zipper", text: "Compressing \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items")…", tint: .orange), for: 2.5)
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
            collapse()
            show(.toast(symbol: "doc.on.doc.fill", text: urls.count == 1 ? "Path copied" : "\(urls.count) paths copied", tint: .mint), for: 2)
        case .mail:
            NSApp.activate(ignoringOtherApps: true)
            NSSharingService(named: .composeEmail)?.perform(withItems: urls)
        }
    }

    // MARK: Volume / brightness keys

    private func handleMediaKey(_ key: MediaKeyTap.Key, fine: Bool, isDown: Bool, isRepeat: Bool) -> Bool {
        switch key {
        case .volumeUp, .volumeDown, .mute:
            guard volume.canSetVolume else { return false } // e.g. HDMI: let the system handle it
            guard isDown else { return true }
            switch key {
            case .volumeUp: volume.step(up: true, fine: fine)
            case .volumeDown: volume.step(up: false, fine: fine)
            default: if !isRepeat { volume.toggleMute() }
            }
            showHUD(.volume, up: key == .mute ? !volume.muted : key == .volumeUp)
            return true
        case .brightnessUp, .brightnessDown:
            guard brightness.canSet else { return false }
            guard isDown else { return true }
            brightness.step(up: key == .brightnessUp, fine: fine)
            showHUD(.brightness, up: key == .brightnessUp)
            return true
        }
    }

    func setReplaceSystemHUD(_ on: Bool) {
        replaceSystemHUD = on
        UserDefaults.standard.set(on, forKey: "replaceSystemHUD")
        if on { enableKeyTap() } else {
            trustTimer?.invalidate()
            trustTimer = nil
            keyTap.stop()
            keyTapActive = false
        }
    }

    /// Starts intercepting volume/brightness keys. Needs Accessibility permission: if it's missing,
    /// shows the system prompt and starts the tap as soon as permission is granted.
    private func enableKeyTap() {
        trustTimer?.invalidate()
        trustTimer = nil
        if keyTap.start() {
            keyTapActive = true
            Self.log.info("media key tap started")
            return
        }
        keyTapActive = false
        Self.log.info("media key tap waiting for Accessibility permission")
        MediaKeyTap.requestTrust()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self, self.keyTap.start() else { return }
            t.invalidate()
            self.keyTapActive = true
            Self.log.info("media key tap started")
        }
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    func openAccessibilitySettings() {
        MediaKeyTap.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func setShowMenuBarActivities(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "showMenuBarActivities")
        withAnimation(Self.spring) { showMenuBarActivities = on }
    }

    func setShowIdleBadge(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "showIdleBadge")
        withAnimation(Self.spring) { showIdleBadge = on }
    }

    // MARK: Settings

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("[NotchIsland] Launch at login failed: %@", error.localizedDescription)
        }
        objectWillChange.send()
    }

    func openSettings(welcome: Bool = false, page: SettingsPage = .tabs) {
        collapse()
        SettingsWindowController.shared.show(vm: self, welcome: welcome, page: page)
    }

    // MARK: URL commands (notchy://…), handy for Shortcuts / Raycast

    func handle(_ url: URL) {
        guard url.scheme == "notchy" || url.scheme == "notchisland" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch url.host {
        case "open":
            dropPreview = false
            if let t = q("tab").flatMap(NotchTab.init(rawValue:)) { tab = t }
            expand()
        case "collapse":
            dropPreview = false
            collapse()
        case "settings":
            openSettings(welcome: q("welcome") == "1", page: q("page").flatMap(SettingsPage.init(rawValue:)) ?? .tabs)
        case "timer":
            if let m = q("minutes").flatMap(Double.init) { timer.start(seconds: m * 60) }
        case "update":
            if q("install") == "1" { updater.checkAndInstall() } else { updater.check(userInitiated: true); openSettings(page: .about) }
        case "pomodoro":
            timer.startPomodoro()
        case "demo":
            DemoData.showState(q("state") ?? "", on: self)
        default:
            break
        }
    }
}
