import AppKit
import EventKit
import IOKit.ps
import IOKit.pwr_mgt
import UniformTypeIdentifiers

// MARK: - Battery

final class BatteryMonitor: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var onAC = false
    @Published private(set) var hasBattery = false
    /// Fired when the charger is plugged in or unplugged.
    var onPowerSourceChange: (() -> Void)?
    private var source: CFRunLoopSource?

    init() {
        update(initial: true)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue().update(initial: false)
        }, ctx)?.takeRetainedValue() {
            source = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    private func update(initial: Bool) {
        guard let infoRef = IOPSCopyPowerSourcesInfo() else { return }
        let info = infoRef.takeRetainedValue()
        guard let listRef = IOPSCopyPowerSourcesList(info) else { return }
        let list = listRef.takeRetainedValue() as [CFTypeRef]
        for ps in list {
            guard let descRef = IOPSGetPowerSourceDescription(info, ps),
                  let desc = descRef.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let ac = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let wasAC = onAC
            hasBattery = true
            level = max > 0 ? Int((Double(cur) / Double(max) * 100).rounded()) : cur
            isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            onAC = ac
            if !initial && wasAC != ac { onPowerSourceChange?() }
            return
        }
    }
}

// MARK: - Calendar (EventKit: iCloud, Google, Exchange… anything added in Internet Accounts)

final class CalendarService: ObservableObject {
    struct EventInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: NSColor?
        let location: String?
        let meetingURL: URL?
    }

    struct CalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let source: String
        let color: NSColor?
    }

    @Published private(set) var nextEvent: EventInfo?
    @Published private(set) var agenda: [EventInfo] = [] // rest of today + tomorrow
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var excluded: Set<String>
    @Published private(set) var authorized = false
    @Published private(set) var denied = false

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let meetingHosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com",
                                       "webex.com", "facetime.apple.com", "whereby.com", "around.co"]

    /// True if a calendar account looks like Google (Gmail / Google account in Internet Accounts).
    var hasGoogle: Bool {
        calendars.contains { c in
            let s = c.source.lowercased()
            return s.contains("google") || s.contains("gmail")
        }
    }

    init() {
        excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedCalendars") ?? [])
        updateStatus()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        if isDemoMode { return }
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            requestAccess()
        } else {
            refresh()
        }
    }

    func requestAccess() {
        if denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateStatus()
                self?.refresh()
            }
        }
    }

    private func updateStatus() {
        let s = EKEventStore.authorizationStatus(for: .event)
        let a = s == .fullAccess, d = s == .denied || s == .restricted
        if authorized != a { authorized = a }
        if denied != d { denied = d }
    }

    func applyDemo(_ events: [EventInfo]) {
        authorized = true
        denied = false
        calendars = [CalendarInfo(id: "demo", title: "Work", source: "Google", color: .systemBlue)]
        agenda = events
        nextEvent = events.first
    }

    func refresh() {
        guard !isDemoMode else { return }
        updateStatus()
        guard authorized else { nextEvent = nil; agenda = []; return }

        let all = store.calendars(for: .event)
        calendars = all.map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "Other", color: $0.color) }
            .sorted { ($0.source, $0.title) < ($1.source, $1.title) }
        let included = all.filter { !excluded.contains($0.calendarIdentifier) }
        guard !included.isEmpty else { nextEvent = nil; agenda = []; return }

        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let end = Calendar.current.date(byAdding: .day, value: 2, to: startOfToday) ?? now.addingTimeInterval(48 * 3600)
        let predicate = store.predicateForEvents(withStart: startOfToday, end: end, calendars: included)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                EventInfo(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                          title: e.title ?? "Untitled", start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                          color: e.calendar?.color, location: e.location?.isEmpty == false ? e.location : nil,
                          meetingURL: Self.meetingURL(e))
            }
        agenda = events
        nextEvent = events.first { !$0.isAllDay }
    }

    func setCalendar(_ id: String, included: Bool) {
        if included { excluded.remove(id) } else { excluded.insert(id) }
        UserDefaults.standard.set(Array(excluded), forKey: "excludedCalendars")
        refresh()
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    /// Opens System Settings › Internet Accounts, where a Google account can be added.
    func openInternetAccounts() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Finds a Meet / Zoom / Teams link in the event's URL, location or notes.
    private static func meetingURL(_ e: EKEvent) -> URL? {
        let texts = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }
        for text in texts {
            let matches = linkDetector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
            for m in matches {
                guard let url = m.url, let host = url.host?.lowercased() else { continue }
                if meetingHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return url }
            }
        }
        return nil
    }
}

// MARK: - Quick toggles

final class SystemToggles: ObservableObject {
    @Published private(set) var darkMode = false
    @Published private(set) var keepAwake = false
    private var assertionID: IOPMAssertionID = 0
    private var observers: [NSObjectProtocol] = []
    private var keepAwakeTimer: Timer?

    private static let amphetamineID = "com.if.Amphetamine"
    /// Keep Awake drives Amphetamine when it's installed, otherwise a built-in power assertion.
    var usesAmphetamine: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.amphetamineID) != nil }
    private var amphetamineRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.amphetamineID).isEmpty
    }

    init() {
        readDarkMode()
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in self?.readDarkMode() })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Self.amphetamineID { self?.keepAwake = false }
        })
        // Pick up sessions started/ended from Amphetamine's own menu.
        keepAwakeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.refreshKeepAwake()
        }
        refreshKeepAwake()
    }

    func refreshKeepAwake() {
        guard usesAmphetamine, amphetamineRunning else { return }
        AppleScript.run("tell application id \"\(Self.amphetamineID)\" to session is active") { [weak self] d in
            guard let self, let d else { return }
            if self.keepAwake != d.booleanValue { self.keepAwake = d.booleanValue }
        }
    }

    /// Starts a keep-awake session. `minutes == nil` uses Amphetamine's default duration; 0 means indefinitely.
    func startKeepAwake(minutes: Int? = nil) {
        guard usesAmphetamine else {
            if !keepAwake { toggleBuiltInKeepAwake() }
            return
        }
        keepAwake = true
        let options = minutes.map { " with options {duration:\($0), interval:minutes, displaySleepAllowed:false}" } ?? ""
        AppleScript.run("tell application id \"\(Self.amphetamineID)\" to start new session\(options)") { [weak self] _ in
            self?.refreshKeepAwake()
        }
    }

    func stopKeepAwake() {
        guard usesAmphetamine else {
            if keepAwake { toggleBuiltInKeepAwake() }
            return
        }
        keepAwake = false
        guard amphetamineRunning else { return }
        AppleScript.run("tell application id \"\(Self.amphetamineID)\" to end session") { [weak self] _ in
            self?.refreshKeepAwake()
        }
    }

    private func readDarkMode() {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let v = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        darkMode = v == "Dark"
    }

    func toggleDarkMode() {
        darkMode.toggle() // optimistic
        AppleScript.run("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode") { [weak self] _ in
            self?.readDarkMode()
        }
    }

    func toggleKeepAwake() {
        keepAwake ? stopKeepAwake() : startKeepAwake()
    }

    private func toggleBuiltInKeepAwake() {
        if keepAwake {
            IOPMAssertionRelease(assertionID)
            keepAwake = false
        } else {
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "Notchy: Keep Awake" as CFString, &assertionID)
            keepAwake = r == kIOReturnSuccess
        }
    }

    func screenshot() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func sleepDisplay() {
        Shell.run("/usr/bin/pmset", ["displaysleepnow"])
    }
}

// MARK: - App shelf

final class AppShelf: ObservableObject {
    struct ShelfApp: Identifiable, Equatable {
        let id: String // bundle identifier
        let url: URL
        let name: String
        let icon: NSImage
    }

    @Published private(set) var apps: [ShelfApp] = []
    @Published private(set) var running: Set<String> = []
    private let key = "shelfBundleIDs"
    private var observers: [NSObjectProtocol] = []

    static let defaultIDs = [
        "com.apple.finder", "com.google.Chrome", "com.spotify.client", "com.tinyspeck.slackmacgap",
        "com.hnc.Discord", "com.todesktop.230313mzl4w4u92", "notion.id", "com.apple.MobileSMS",
        "com.apple.Safari", "com.apple.Notes",
    ]

    init() {
        load()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateRunning()
            })
        }
        updateRunning()
    }

    private func load() {
        if let ids = UserDefaults.standard.stringArray(forKey: key) {
            apps = ids.compactMap(Self.makeApp)
        } else {
            apps = Array(Self.defaultIDs.compactMap(Self.makeApp).prefix(7))
        }
    }

    private func save() {
        UserDefaults.standard.set(apps.map(\.id), forKey: key)
    }

    private func updateRunning() {
        running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    private static func makeApp(_ bundleID: String) -> ShelfApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return ShelfApp(id: bundleID, url: url, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
    }

    func open(_ app: ShelfApp) {
        NSWorkspace.shared.openApplication(at: app.url, configuration: .init())
    }

    func remove(_ app: ShelfApp) {
        apps.removeAll { $0.id == app.id }
        save()
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        load()
    }

    func addApps() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Add apps to the Notch shelf"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { [weak self] response in
            guard let self, response == .OK else { return }
            for url in panel.urls {
                guard let id = Bundle(url: url)?.bundleIdentifier,
                      !self.apps.contains(where: { $0.id == id }),
                      let app = Self.makeApp(id) else { continue }
                self.apps.append(app)
            }
            self.save()
        }
    }
}
