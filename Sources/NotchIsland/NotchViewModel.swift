import AppKit
import Combine
import os
import ServiceManagement
import SwiftUI

enum NotchTab: String, CaseIterable {
    case home, calendar, timer, shelf

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .calendar: "calendar"
        case .timer: "timer"
        case .shelf: "tray.full.fill"
        }
    }
}

enum HUDKind: Equatable { case volume, brightness }

/// Short-lived things that pop out of the notch.
enum Transient: Equatable {
    case battery
    case hud(HUDKind)
    case notification(NotificationItem)
    case timerDone
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
}

final class NotchViewModel: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var tab: NotchTab = .home
    @Published private(set) var transient: Transient?
    @Published private(set) var isDropTargeted = false
    @Published private(set) var replaceSystemHUD = UserDefaults.standard.bool(forKey: "replaceSystemHUD")
    @Published private(set) var showIdleBadge = UserDefaults.standard.object(forKey: "showIdleBadge") as? Bool ?? true

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

    init() {
        // Re-render whenever any service changes.
        Publishers.MergeMany(music.objectWillChange, battery.objectWillChange, calendar.objectWillChange,
                             toggles.objectWillChange, shelf.objectWillChange, volume.objectWillChange,
                             brightness.objectWillChange, timer.objectWillChange, notifications.objectWillChange,
                             files.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)

        battery.onPowerSourceChange = { [weak self] in self?.show(.battery, for: 3) }
        volume.onChange = { [weak self] in self?.show(.hud(.volume), for: 1.6) }
        brightness.onChange = { [weak self] in self?.show(.hud(.brightness), for: 1.6) }
        timer.onFinish = { [weak self] in self?.show(.timerDone, for: 10) }
        notifications.onNotification = { [weak self] item in self?.show(.notification(item), for: 5) }
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
    }

    // MARK: Activity & geometry

    var activity: LiveActivity {
        switch transient {
        case .notification(let n): return .notification(n)
        case .hud(let kind): return .hud(kind)
        case .battery: return .battery(level: battery.level, onAC: battery.onAC)
        case .timerDone: return .timerDone
        case nil: break
        }
        if timer.isActive { return .timer }
        if music.isPlaying && music.hasTrack { return .music }
        if let e = calendar.nextEvent {
            let minutes = Int(ceil(e.start.timeIntervalSinceNow / 60))
            if (0...10).contains(minutes) { return .event(minutes: minutes) }
        }
        return .none
    }

    var expandedSize: CGSize { CGSize(width: 640, height: notchSize.height + 162) }
    var sideWidth: CGFloat { notchSize.height + 14 }

    /// Small always-visible box to the left of the notch, so there's something to aim for when idle.
    var idleBadgeWidth: CGFloat { notchSize.height + 8 }
    private var showsIdleBadge: Bool { !isExpanded && showIdleBadge && activity == .none }
    /// Shifts the island left when only the left-hand idle badge is showing.
    var bodyOffsetX: CGFloat { showsIdleBadge ? -idleBadgeWidth / 2 : 0 }

    var collapsedSize: CGSize {
        let n = notchSize
        let wide = n.width + 2 * sideWidth
        switch activity {
        case .none: return showIdleBadge ? CGSize(width: n.width + idleBadgeWidth, height: n.height) : n
        case .hud: return CGSize(width: wide, height: n.height + 26)
        case .notification: return CGSize(width: max(wide, 420), height: n.height + 62)
        case .timerDone: return CGSize(width: max(wide, 360), height: n.height + 44)
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
            } else if self.menuOpen || NSEvent.pressedMouseButtons & 1 != 0 {
                self.scheduleHover(false) // a menu is open or a drag is in progress: check again shortly
            } else {
                self.collapse()
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (hovering ? 0.12 : 0.3), execute: work)
    }

    func expand() {
        guard !isExpanded else { return }
        withAnimation(Self.spring) { isExpanded = true }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        music.refresh()
        calendar.refresh()
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(Self.spring) { isExpanded = false }
    }

    func handleTap() {
        switch transient {
        case .notification(let n):
            if let url = n.appURL { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
            dismissTransient()
        case .timerDone:
            dismissTransient()
        default:
            expand()
        }
    }

    // MARK: Transients

    func show(_ t: Transient, for seconds: Double) {
        Self.log.info("show transient: \(String(describing: t), privacy: .private)")
        withAnimation(Self.spring) { transient = t }
        scheduleTransientDismiss(after: seconds)
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

    /// Called while a file drag hovers over the notch.
    func beginFileDrag() {
        if tab != .shelf { tab = .shelf }
    }

    func dropTargetChanged(_ targeted: Bool) {
        isDropTargeted = targeted
        if targeted {
            tab = .shelf
            expand()
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
            show(.hud(.volume), for: 1.6)
            return true
        case .brightnessUp, .brightnessDown:
            guard brightness.canSet else { return false }
            guard isDown else { return true }
            brightness.step(up: key == .brightnessUp, fine: fine)
            show(.hud(.brightness), for: 1.6)
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
        }
    }

    /// Starts intercepting volume/brightness keys. Needs Accessibility permission: if it's missing,
    /// shows the system prompt and starts the tap as soon as permission is granted.
    private func enableKeyTap() {
        trustTimer?.invalidate()
        trustTimer = nil
        if keyTap.start() { return }
        MediaKeyTap.requestTrust()
        var attempts = 0
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            attempts += 1
            if self?.keyTap.start() == true || attempts > 150 { t.invalidate() }
        }
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
}
