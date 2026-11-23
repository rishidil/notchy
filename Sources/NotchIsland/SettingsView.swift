import AppKit
import CoreBluetooth
import CoreLocation
import EventKit
import SwiftUI

// MARK: - Window

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(vm: NotchViewModel, welcome: Bool) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let root = SettingsView(welcome: welcome) { [weak self] in self?.window?.close() }
            .environmentObject(vm)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Notchy Settings"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.contentViewController = NSHostingController(rootView: root)
        w.setContentSize(NSSize(width: 780, height: 580))
        w.center()
        w.delegate = self
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        window = nil
    }
}

// MARK: - Root

enum SettingsPage: String, CaseIterable, Identifiable {
    case tabs, features, permissions, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tabs: "Tabs"
        case .features: "Features"
        case .permissions: "Permissions"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .tabs: "square.grid.2x2.fill"
        case .features: "slider.horizontal.3"
        case .permissions: "lock.shield.fill"
        case .about: "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    let welcome: Bool
    let close: () -> Void
    @EnvironmentObject var vm: NotchViewModel
    @State private var page: SettingsPage = .tabs

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if welcome && page == .tabs { welcomeBanner }
                        switch page {
                        case .tabs: TabsPage()
                        case .features: FeaturesPage()
                        case .permissions: PermissionsPage()
                        case .about: AboutPage()
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 36)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if welcome { footer }
            }
        }
        .frame(width: 780, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                NotchLogo(size: 26)
                Text("Notchy").font(.system(size: 15, weight: .bold))
            }
            .padding(.bottom, 18)
            .padding(.leading, 6)
            ForEach(SettingsPage.allCases) { p in
                Button { page = p } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.symbol).frame(width: 18)
                        Text(p.title)
                        Spacer()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 10).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(page == p ? Color.accentColor.opacity(0.18) : .clear))
                    .foregroundStyle(page == p ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 44)
        .padding(.bottom, 16)
        .frame(width: 200)
        .background(.ultraThinMaterial)
    }

    private var welcomeBanner: some View {
        HStack(spacing: 16) {
            NotchLogo(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Notchy").font(.system(size: 20, weight: .bold))
                Text("Pick what your notch shows. Hover over the notch any time to open it. You can come back here from ⚙︎ → Settings.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [.cyan.opacity(0.18), .purple.opacity(0.18), .pink.opacity(0.14)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
    }

    private var footer: some View {
        HStack {
            Text("\(vm.tabs.count) tab\(vm.tabs.count == 1 ? "" : "s") selected").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            if page != .permissions {
                Button("Next: Permissions") { page = .permissions }
            }
            Button("Done") { close() }
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

private struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold))
            Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tabs

private struct TabsPage: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Your tabs",
                       subtitle: "Turn on the tabs you want in the expanded notch, and drag to change their order.")
            preview
            List {
                ForEach(vm.tabOrder) { t in row(t) }
                    .onMove { vm.moveTabs(from: $0, to: $1) }
            }
            .listStyle(.inset)
            .scrollDisabled(true)
            .frame(height: CGFloat(vm.tabOrder.count) * 52 + 12)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                Spacer()
                Button("Reset to Defaults") { vm.resetTabs() }.controlSize(.small)
            }
        }
    }

    /// Miniature of the expanded notch header.
    private var preview: some View {
        HStack(spacing: 4) {
            ForEach(vm.tabs) { t in
                Image(systemName: t.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 22)
                    .background(Capsule().fill(t == vm.tabs.first ? Color.white.opacity(0.18) : .clear))
                    .foregroundStyle(t == vm.tabs.first ? .white : .white.opacity(0.55))
            }
        }
        .padding(.horizontal, 14).frame(height: 38)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16).fill(.black))
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: vm.tabs)
    }

    private func row(_ t: NotchTab) -> some View {
        let on = vm.isTabEnabled(t)
        return HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Image(systemName: t.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.tint.gradient))
                .opacity(on ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(.system(size: 13, weight: .semibold))
                Text(t.blurb).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { on }, set: { vm.setTab(t, enabled: $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(on && vm.tabs.count == 1)
        }
        .frame(height: 44)
    }
}

// MARK: - Features

private struct FeaturesPage: View {
    @EnvironmentObject var vm: NotchViewModel
    @State private var cityQuery = ""
    @State private var results: [WeatherService.Place] = []
    @State private var searching = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Features", subtitle: "Fine-tune how the island behaves.")
            Form {
                Section("Notch") {
                    if vm.hasNotch {
                        Toggle("Show logo next to the notch when idle", isOn: Binding(get: { vm.showIdleBadge }, set: { vm.setShowIdleBadge($0) }))
                    } else {
                        Toggle("Show music & timer in the menu bar", isOn: Binding(get: { vm.showMenuBarActivities }, set: { vm.setShowMenuBarActivities($0) }))
                    }
                    Toggle("Show the current lyric under the notch", isOn: Binding(get: { vm.lyricsInNotch }, set: { vm.setLyricsInNotch($0) }))
                    Toggle("Drop actions when dragging files onto the notch", isOn: Binding(get: { vm.dropActionsEnabled }, set: { vm.setDropActions($0) }))
                    Toggle("Launch at login", isOn: Binding(get: { vm.launchAtLogin }, set: { _ in vm.toggleLaunchAtLogin() }))
                }
                Section {
                    Toggle("Replace Apple's volume & brightness pop-up", isOn: Binding(get: { vm.replaceSystemHUD }, set: { vm.setReplaceSystemHUD($0) }))
                    if vm.replaceSystemHUD && !vm.keyTapActive {
                        Label { Text("Needs Accessibility permission") } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                            .font(.system(size: 12))
                        Button("Allow Accessibility…") { vm.openAccessibilitySettings() }
                    }
                } header: { Text("Volume & Brightness") }
                Section("Notifications") {
                    Toggle("Pop up new notifications in the notch", isOn: Binding(get: { vm.notifications.enabled }, set: { vm.notifications.setEnabled($0) }))
                    if !vm.notifications.hasAccess {
                        Button("Grant Full Disk Access…") { vm.notifications.openFullDiskAccessSettings() }
                    }
                    if !vm.notifications.mutedApps.isEmpty {
                        Button("Unmute \(vm.notifications.mutedApps.count) muted app\(vm.notifications.mutedApps.count == 1 ? "" : "s")") { vm.notifications.unmuteAll() }
                    }
                }
                Section("Weather") {
                    Picker("Units", selection: Binding(get: { vm.weather.useFahrenheit }, set: { vm.weather.setFahrenheit($0) })) {
                        Text("°F").tag(true)
                        Text("°C").tag(false)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Location") {
                        if let p = vm.weather.manualPlace {
                            HStack {
                                Text(p.name)
                                Button("Use My Location") { vm.weather.setPlace(nil) }
                            }
                        } else {
                            Text("Automatic").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        TextField("Search for a city", text: $cityQuery).onSubmit(search)
                        Button(searching ? "Searching…" : "Search", action: search).disabled(cityQuery.isEmpty)
                    }
                    ForEach(results) { place in
                        Button {
                            vm.weather.setPlace(place)
                            results = []
                            cityQuery = ""
                        } label: {
                            HStack {
                                Text(place.name)
                                Text(place.detail).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("Pomodoro") {
                    Stepper("Focus: \(vm.timer.focusMinutes) min", value: Binding(get: { vm.timer.focusMinutes }, set: { vm.timer.focusMinutes = $0 }), in: 5...120, step: 5)
                    Stepper("Short break: \(vm.timer.shortBreakMinutes) min", value: Binding(get: { vm.timer.shortBreakMinutes }, set: { vm.timer.shortBreakMinutes = $0 }), in: 1...30)
                    Stepper("Long break: \(vm.timer.longBreakMinutes) min", value: Binding(get: { vm.timer.longBreakMinutes }, set: { vm.timer.longBreakMinutes = $0 }), in: 5...60, step: 5)
                    Stepper("Long break every \(vm.timer.cyclesBeforeLongBreak) sessions", value: Binding(get: { vm.timer.cyclesBeforeLongBreak }, set: { vm.timer.cyclesBeforeLongBreak = $0 }), in: 2...8)
                }
                Section("Screen Time") {
                    Button("Reset Screen Time History") { vm.screenTime.reset() }
                        .disabled(!vm.isTabEnabled(.screenTime))
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(minHeight: 1180)
            .padding(.horizontal, -20)
        }
    }

    private func search() {
        guard !cityQuery.isEmpty else { return }
        searching = true
        vm.weather.search(cityQuery) { places in
            results = places
            searching = false
        }
    }
}

// MARK: - Permissions

private struct PermissionsPage: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(title: "Permissions",
                       subtitle: "Notchy only asks for what your tabs need. Everything stays on your Mac.")
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                VStack(spacing: 10) {
                    row("Calendar", symbol: "calendar", tint: .red, needed: vm.isTabEnabled(.calendar) || vm.isTabEnabled(.home),
                        purpose: "Shows your next meetings (including Google Calendar)", state: calendarState) {
                        vm.calendar.requestAccess()
                    }
                    row("Location", symbol: "location.fill", tint: .blue, needed: vm.isTabEnabled(.weather),
                        purpose: "Local weather. Or pick a city in Features instead", state: locationState) {
                        if vm.weather.locationStatus == .notDetermined {
                            vm.weather.start()
                            vm.weather.requestLocation()
                        } else {
                            open("Privacy_LocationServices")
                        }
                    }
                    row("Bluetooth", symbol: "headphones", tint: .blue, needed: vm.isTabEnabled(.bluetooth),
                        purpose: "Lists your devices and their battery levels", state: bluetoothState) {
                        if CBManager.authorization == .notDetermined { vm.bluetooth.start() } else { open("Privacy_Bluetooth") }
                    }
                    row("Accessibility", symbol: "accessibility", tint: .purple, needed: vm.replaceSystemHUD,
                        purpose: "Replaces Apple's volume & brightness pop-up", state: AXIsProcessTrusted() ? .granted : .missing) {
                        vm.openAccessibilitySettings()
                    }
                    row("Full Disk Access", symbol: "externaldrive.fill", tint: .gray,
                        needed: vm.notifications.enabled || vm.isTabEnabled(.notifications),
                        purpose: "Notification previews and history (read-only)",
                        state: vm.notifications.hasAccess ? .granted : .missing) {
                        vm.notifications.openFullDiskAccessSettings()
                    }
                    row("Automation", symbol: "gearshape.2.fill", tint: .orange, needed: true,
                        purpose: "Controls Spotify, Music, Dark Mode and Amphetamine. macOS asks the first time", state: .info) {}
                }
            }
            Text("For Full Disk Access and Accessibility, click the button, then turn on Notchy in the list (use + to add it if it's missing).")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }

    enum PermState { case granted, missing, denied, info }

    private var calendarState: PermState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .denied, .restricted: .denied
        default: .missing
        }
    }

    private var locationState: PermState {
        if vm.weather.manualPlace != nil { return .granted }
        switch vm.weather.locationStatus {
        case .notDetermined: return .missing
        case .denied, .restricted: return .denied
        default: return .granted
        }
    }

    private var bluetoothState: PermState {
        switch CBManager.authorization {
        case .allowedAlways: .granted
        case .denied, .restricted: .denied
        default: .missing
        }
    }

    private func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func row(_ title: String, symbol: String, tint: Color, needed: Bool, purpose: String, state: PermState,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if !needed && state != .granted {
                        Text("Not needed").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                }
                Text(purpose).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12, weight: .medium))
            case .info:
                EmptyView()
            case .missing, .denied:
                Button(state == .denied ? "Open Settings" : "Allow", action: action).controlSize(.regular)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .opacity(needed || state == .granted ? 1 : 0.65)
    }
}

// MARK: - About

private struct AboutPage: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                NotchLogo(size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Notchy").font(.system(size: 24, weight: .bold))
                    Text("A Dynamic Island for your Mac. Free and open source.").foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Link("Website", destination: URL(string: "https://rishidil.github.io/notchy/")!)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/rishidil/notchy")!)
                Link("Check for updates", destination: URL(string: "https://github.com/rishidil/notchy/releases/latest")!)
            }
            Text("Weather by Open-Meteo · Lyrics by LRCLIB · Notification content, screen time and your files never leave your Mac.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            HStack {
                Button("Show Welcome Again") {
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                }
                Button("Quit Notchy") { NSApp.terminate(nil) }
            }
        }
    }
}
