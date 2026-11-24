import AppKit
import SwiftUI

// MARK: - Shared

/// Rounded dark card used across the feature tabs.
struct Card<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = .mint
    var maxValue: Double?

    var body: some View {
        GeometryReader { geo in
            let top = max(maxValue ?? (values.max() ?? 1), 0.0001)
            let step = geo.size.width / CGFloat(max(values.count - 1, 1))
            let points = values.enumerated().map { i, v in
                CGPoint(x: CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(min(v / top, 1))))
            }
            ZStack {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    points.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: points.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    points.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct EmptyTabMessage: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var button: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.white.opacity(0.8))
            Text(title).font(.system(size: 13, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).multilineTextAlignment(.center)
            }
            if let button, let action { PillButton(title: button, action: action).padding(.top, 2) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Weather

struct WeatherTab: View {
    @ObservedObject var weather: WeatherService
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        switch weather.status {
        case .needsLocation where weather.current == nil:
            EmptyTabMessage(symbol: "location.slash.fill", title: "Where are you?",
                            subtitle: "Allow location access, or pick a city in Settings.", button: "Choose a City") {
                vm.openSettings()
            }
        case .failed(let msg) where weather.current == nil:
            EmptyTabMessage(symbol: "cloud.fill", title: msg, button: "Try Again") { weather.refresh() }
        default:
            if let c = weather.current { content(c) } else {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(weather.manualPlace == nil ? "Finding your location…" : "Loading the forecast…")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                    if weather.manualPlace == nil {
                        Text("If macOS asked for your location, allow it, or pick a city instead.")
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                        PillButton(title: "Choose a City") { vm.openSettings(page: .features) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func content(_ c: WeatherService.Current) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: weather.manualPlace == nil ? "location.fill" : "mappin").font(.system(size: 9))
                    Text(weather.placeName ?? "—").lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: WeatherService.symbol(code: c.code, isDay: c.isDay))
                        .symbolRenderingMode(.multicolor).font(.system(size: 34))
                    Text(weather.format(c.temperature)).font(.system(size: 44, weight: .light, design: .rounded))
                }
                Text(WeatherService.describe(code: c.code)).font(.system(size: 12, weight: .semibold))
                if let today = weather.days.first {
                    Text("H \(weather.format(today.high))  L \(weather.format(today.low))  ·  Feels \(weather.format(c.feelsLike))")
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 176, alignment: .leading)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 124)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(weather.hours.prefix(7)) { h in
                        VStack(spacing: 4) {
                            Text(hourLabel(h.time)).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                            Image(systemName: WeatherService.symbol(code: h.code, isDay: h.isDay))
                                .symbolRenderingMode(.multicolor).font(.system(size: 15)).frame(height: 18)
                            Text(weather.format(h.temperature)).font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Divider().overlay(.white.opacity(0.08))
                HStack(spacing: 6) {
                    ForEach(weather.days.prefix(4)) { d in
                        HStack(spacing: 6) {
                            Text(dayLabel(d.date)).font(.system(size: 10.5, weight: .semibold)).fixedSize()
                            Image(systemName: WeatherService.symbol(code: d.code, isDay: true))
                                .symbolRenderingMode(.multicolor).font(.system(size: 12))
                            Text("\(weather.format(d.high)) / \(weather.format(d.low))")
                                .font(.system(size: 10.5, weight: .medium).monospacedDigit()).fixedSize()
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func hourLabel(_ d: Date) -> String {
        Calendar.current.isDate(d, equalTo: Date(), toGranularity: .hour) ? "Now" : d.formatted(.dateTime.hour())
    }

    private func dayLabel(_ d: Date) -> String {
        Calendar.current.isDateInToday(d) ? "Today" : d.formatted(.dateTime.weekday(.abbreviated))
    }
}

// MARK: - To-Do

struct TodoTab: View {
    @ObservedObject var todos: TodoStore
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.green).font(.system(size: 15))
                TextField("Add a to-do and press Return", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($focused)
                    .onSubmit {
                        todos.add(draft)
                        draft = ""
                    }
                if todos.items.contains(where: \.done) {
                    PillButton(title: "Clear Done", symbol: "checkmark") { todos.clearDone() }
                }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(focused ? 0.12 : 0.07)))

            if todos.items.isEmpty {
                Text("Nothing to do. Enjoy it ✨").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 4) {
                        ForEach(todos.items) { item in row(item) }
                    }
                }
            }
        }
    }

    private func row(_ item: TodoStore.Item) -> some View {
        HStack(spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { todos.toggle(item) } } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.done ? Color.green : Color.white.opacity(0.5))
            }
            .buttonStyle(PressableStyle())
            Text(item.title)
                .font(.system(size: 12))
                .strikethrough(item.done)
                .foregroundStyle(.white.opacity(item.done ? 0.4 : 0.92))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.04)))
        .contextMenu { Button("Delete") { todos.delete(item) } }
    }
}

// MARK: - Lyrics

struct LyricsTab: View {
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var music: MusicController

    var body: some View {
        if !music.hasTrack {
            EmptyTabMessage(symbol: "music.note", title: "Nothing playing",
                            subtitle: "Play a song in Spotify or Music to see its lyrics here.")
        } else {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    ArtworkView(image: music.artwork, size: 64, radius: 12)
                    Text(music.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    Text(music.artist).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                .frame(width: 120, alignment: .leading)
                lyricsBody.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder private var lyricsBody: some View {
        switch lyrics.state {
        case .synced:
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                SyncedLyricsView(lines: lyrics.lines, current: lyrics.index(at: music.position(at: ctx.date)),
                                 accent: music.accent) { music.seek(to: $0) }
            }
        case .plain:
            ScrollView(.vertical, showsIndicators: false) {
                Text(lyrics.plainText ?? "").font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .loading, .idle:
            ProgressView().controlSize(.small)
        case .notFound:
            EmptyTabMessage(symbol: "text.badge.xmark", title: "No lyrics found", subtitle: "LRCLIB doesn't have this song yet.")
        case .failed:
            EmptyTabMessage(symbol: "wifi.slash", title: "Couldn't load lyrics", subtitle: "Check your internet connection.")
        }
    }
}

struct SyncedLyricsView: View {
    let lines: [LyricsService.Line]
    let current: Int?
    let accent: Color
    let seek: (Double) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    Color.clear.frame(height: 30)
                    ForEach(lines) { line in
                        let isCurrent = line.id == current
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: isCurrent ? 16 : 13.5, weight: .bold))
                            .foregroundStyle(isCurrent ? accent : .white.opacity(line.id < (current ?? -1) ? 0.3 : 0.45))
                            .id(line.id)
                            .onTapGesture { seek(line.time) }
                    }
                    Color.clear.frame(height: 50)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.25), value: current)
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                         .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onAppear { if let c = current { proxy.scrollTo(c, anchor: .center) } }
            .onChange(of: current) { _, c in
                guard let c else { return }
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(c, anchor: .center) }
            }
        }
    }
}

// MARK: - Bluetooth

struct BluetoothTab: View {
    @ObservedObject var bluetooth: BluetoothService

    var body: some View {
        if BluetoothService.authorization == .denied && !isDemoMode {
            EmptyTabMessage(symbol: "lock.fill", title: "Bluetooth access is off",
                            subtitle: "Allow Notchy in Privacy & Security → Bluetooth.", button: "Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
                    NSWorkspace.shared.open(url)
                }
            }
        } else if !bluetooth.powerOn && !isDemoMode {
            EmptyTabMessage(symbol: "antenna.radiowaves.left.and.right.slash", title: "Bluetooth is off",
                            button: "Bluetooth Settings") { bluetooth.openSettings() }
        } else if bluetooth.devices.isEmpty {
            EmptyTabMessage(symbol: "headphones", title: "No devices yet",
                            subtitle: "Pair a device in System Settings to see it here.", button: "Bluetooth Settings") {
                bluetooth.openSettings()
            }
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(bluetooth.devices) { DeviceCard(device: $0, bluetooth: bluetooth) }
                }
            }
        }
    }
}

struct DeviceCard: View {
    let device: BluetoothService.Device
    @ObservedObject var bluetooth: BluetoothService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(device.isConnected ? .white : .white.opacity(0.4))
                Spacer()
                Button { bluetooth.toggleConnection(device) } label: {
                    Group {
                        if bluetooth.busy.contains(device.id) {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: device.isConnected ? "link" : "link.badge.plus").font(.system(size: 11, weight: .bold))
                        }
                    }
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(device.isConnected ? Color.blue : Color.white.opacity(0.1)))
                }
                .buttonStyle(PressableStyle())
                .help(device.isConnected ? "Disconnect" : "Connect")
            }
            Spacer(minLength: 0)
            Text(device.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            batteryRow
        }
        .padding(10)
        .frame(width: 140, height: 122)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(device.isConnected ? 0.1 : 0.04)))
    }

    @ViewBuilder private var batteryRow: some View {
        if let b = device.battery, device.isConnected {
            HStack(spacing: 8) {
                if b.left != nil || b.right != nil {
                    if let buds = [b.left, b.right].compactMap({ $0 }).min() { level(nil, buds) }
                    if let c = b.caseLevel { level("Case", c) }
                } else if let m = b.main {
                    level(nil, m)
                }
            }
        } else {
            Text(device.isConnected ? "Connected" : "Not connected")
                .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private func level(_ label: String?, _ pct: Int) -> some View {
        HStack(spacing: 3) {
            if let label { Text(label).foregroundStyle(.white.opacity(0.5)) }
            Text("\(pct)%").foregroundStyle(pct <= 20 ? .red : .green)
        }
        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
        .fixedSize()
    }
}

// MARK: - System monitor

struct SystemTab: View {
    @ObservedObject var system: SystemMonitor
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        HStack(spacing: 10) {
            statCard("CPU", symbol: "cpu", value: "\(Int((system.cpu * 100).rounded()))%",
                     detail: "\(system.cpuCores) cores", color: .mint) {
                Sparkline(values: system.cpuHistory, color: .mint, maxValue: 1)
            }
            statCard("Memory", symbol: "memorychip", value: SystemMonitor.bytes(Double(system.memoryUsed)),
                     detail: "of \(SystemMonitor.bytes(Double(system.memoryTotal)))", color: .yellow) {
                Sparkline(values: system.memoryHistory, color: .yellow, maxValue: 1)
            }
            statCard("Network", symbol: "arrow.up.arrow.down", value: "↓ " + SystemMonitor.rate(system.netIn),
                     detail: "↑ " + SystemMonitor.rate(system.netOut), color: .cyan) {
                Sparkline(values: system.netHistory, color: .cyan)
            }
            statCard("Disk", symbol: "internaldrive", value: SystemMonitor.bytes(Double(system.diskFree)) + " free",
                     detail: battery.hasBattery ? "Battery \(battery.level)%\(battery.onAC ? " · charging" : "")" : thermalText,
                     color: .purple) {
                VStack {
                    Spacer()
                    LevelBar(level: system.diskFraction, color: .purple).frame(height: 6)
                }
            }
        }
    }

    private var thermalText: String {
        switch system.thermal {
        case .nominal: "Thermals normal"
        case .fair: "Running warm"
        case .serious: "Running hot"
        case .critical: "Overheating"
        @unknown default: ""
        }
    }

    private func statCard<G: View>(_ title: String, symbol: String, value: String, detail: String, color: Color,
                                   @ViewBuilder graph: () -> G) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(color)
                Text(value).font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit()).lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                graph().frame(height: 40).padding(.top, 4)
            }
        }
    }
}

// MARK: - Screen Time

struct ScreenTimeTab: View {
    @ObservedObject var tracker: ScreenTimeTracker

    var body: some View {
        let apps = tracker.usage()
        let total = tracker.total()
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TODAY").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                Text(ScreenTimeTracker.format(total)).font(.system(size: 30, weight: .semibold, design: .rounded))
                weekChart.frame(height: 56).padding(.top, 4)
                if let since = tracker.since, Date().timeIntervalSince(since) < 7 * 86400 {
                    Text("Tracking since \(since.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 170, alignment: .leading)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 124)
            if apps.isEmpty {
                EmptyTabMessage(symbol: "hourglass", title: "No usage yet today",
                                subtitle: "Notchy tallies which app you're using, right here on your Mac.")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(apps.prefix(10)) { app in appRow(app, max: apps.first?.seconds ?? 1) }
                    }
                }
            }
        }
    }

    private var weekChart: some View {
        let week = tracker.week
        let top = max(week.map(\.seconds).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(week, id: \.date) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isToday ? Color.purple : Color.white.opacity(0.22))
                        .frame(height: max(3, 40 * day.seconds / top))
                    Text(day.date.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.white.opacity(isToday ? 0.9 : 0.4))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func appRow(_ app: ScreenTimeTracker.Usage, max: Double) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon = app.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "app.fill").resizable() }
            }
            .frame(width: 20, height: 20)
            Text(app.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1).frame(width: 110, alignment: .leading)
            LevelBar(level: app.seconds / max, color: .purple).frame(height: 5)
            Text(ScreenTimeTracker.format(app.seconds))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .frame(width: 56, alignment: .trailing)
        }
    }
}

// MARK: - Notifications

struct NotificationsTab: View {
    @ObservedObject var notifications: NotificationWatcher

    var body: some View {
        if !notifications.hasAccess {
            EmptyTabMessage(symbol: "bell.badge", title: "See your notifications here",
                            subtitle: "Notchy needs Full Disk Access to read Notification Center.",
                            button: "Open Privacy Settings") { notifications.openFullDiskAccessSettings() }
        } else if notifications.history.isEmpty {
            EmptyTabMessage(symbol: "bell.slash", title: "No recent notifications")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Recent").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    PillButton(title: "Clear", symbol: "xmark") { notifications.clearHistory() }
                }
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(notifications.history) { row($0) }
                    }
                }
            }
        }
    }

    private func row(_ n: NotificationItem) -> some View {
        Button {
            if let url = n.appURL { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Group {
                    if let icon = n.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "bell.fill").resizable().padding(4) }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(n.title.isEmpty ? n.appName : n.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(n.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    }
                    Text(n.body.isEmpty ? n.subtitle : n.body)
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Drop actions

private struct DropFramesKey: PreferenceKey {
    static var defaultValue: [DropAction: CGRect] = [:]
    static func reduce(value: inout [DropAction: CGRect], nextValue: () -> [DropAction: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct DropActionsView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 10) {
            Text("Drop on an action").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            HStack(spacing: 10) {
                ForEach(vm.availableDropActions) { tile($0) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onPreferenceChange(DropFramesKey.self) { vm.dropTileFrames = $0 }
    }

    private func tile(_ a: DropAction) -> some View {
        let hot = vm.dropHover == a
        return VStack(spacing: 8) {
            Image(systemName: a.symbol).font(.system(size: 24, weight: .semibold))
                .foregroundStyle(hot ? .white : a.tint)
            Text(a.title).font(.system(size: 11.5, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(hot ? a.tint.opacity(0.85) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: hot ? [] : [5, 4]))
                .foregroundStyle(hot ? .clear : a.tint.opacity(0.5))
        )
        .scaleEffect(hot ? 1.05 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hot)
        .background(GeometryReader { geo in
            Color.clear.preference(key: DropFramesKey.self, value: [a: geo.frame(in: .named("island"))])
        })
    }
}

// MARK: - Agents (T3 Code)

struct AgentsTab: View {
    @ObservedObject var agents: AgentsService
    @EnvironmentObject var vm: NotchViewModel
    @State private var draft = ""
    @State private var newIn: AgentsService.Project?
    @FocusState private var focused: Bool
    /// Answers collected so far for the pending questions (question id → label, labels or typed text).
    @State private var answers: [String: Any] = [:]
    @State private var answeringID: String?
    @State private var multiPick: Set<String> = []

    var body: some View {
        if !agents.isInstalled {
            EmptyTabMessage(symbol: "sparkles", title: "T3 Code isn't set up",
                            subtitle: "Install T3 Code and open it once, so its t3 command is available.",
                            button: "Get T3 Code") { NSWorkspace.shared.open(URL(string: "https://t3.codes")!) }
        } else if !agents.loaded {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if agents.projects.isEmpty {
            EmptyTabMessage(symbol: "folder.badge.plus", title: "No T3 Code projects found",
                            subtitle: "Add a project in T3 Code, or add its folder in Settings → Connections.",
                            button: "Open T3 Code") { agents.openInT3(nil) }
        } else {
            HStack(alignment: .top, spacing: 14) {
                threadList.frame(width: 236)
                Rectangle().fill(.white.opacity(0.08)).frame(width: 1)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .onChange(of: focused) { vm.composerActive = $0 }
            .onChange(of: agents.lastError) { if $0 != nil { answers = [:]; answeringID = nil; multiPick = [] } }
            .onDisappear { vm.composerActive = false }
        }
    }

    /// The selected thread's first pending approval or question set.
    private var request: AgentsService.PendingRequest? {
        guard newIn == nil, let id = agents.selectedID else { return nil }
        return agents.pending.first { $0.threadID == id }
    }

    /// The question being asked right now (questions are answered one at a time).
    private var currentQuestion: AgentsService.PendingRequest.Question? {
        guard let r = request, case .questions(let qs) = r.kind else { return nil }
        if answeringID != r.id { return qs.first }
        return qs.first { answers[$0.id] == nil }
    }

    // MARK: List

    private var threadList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Agents").font(.system(size: 13, weight: .semibold))
                if agents.runningCount > 0 {
                    Text("\(agents.runningCount) working").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.green)
                }
                Spacer()
                Menu {
                    ForEach(agents.projects) { p in
                        Button(p.title) { newIn = p; draft = ""; focused = true }
                    }
                } label: {
                    Label("New", systemImage: "plus").font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 3) {
                    if agents.threads.isEmpty {
                        Text("No threads yet. Start one with + New.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 8)
                    }
                    ForEach(agents.threads) { t in row(t) }
                }
            }
        }
    }

    private func row(_ t: AgentsService.AgentThread) -> some View {
        let selected = newIn == nil && agents.selectedID == t.id
        return Button {
            newIn = nil
            agents.selectedID = t.id
        } label: {
            HStack(spacing: 8) {
                statusDot(t)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                    Text("\(t.projectTitle) · \(statusText(t))")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(selected ? 0.12 : 0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private func statusDot(_ t: AgentsService.AgentThread) -> some View {
        let color: Color = t.needsAttention ? .orange : t.isRunning ? .green : t.isFailed ? .red
            : t.isUnreadDone ? .blue : .white.opacity(0.3)
        return Circle().fill(color).frame(width: 7, height: 7)
            .shadow(color: t.isRunning ? .green.opacity(0.8) : .clear, radius: 3)
    }

    private func statusText(_ t: AgentsService.AgentThread) -> String {
        if t.pendingRequests > 0 { return t.isWaitingOnQuestion ? "Has a question for you" : "Waiting for your approval" }
        if t.isRunning { return "Working" }
        if t.needsAttention { return "Needs you" }
        let when = t.updatedAt.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
        if t.isFailed { return "Failed · \(when)" }
        if t.isDone { return "Done · \(when)" }
        return when
    }

    // MARK: Detail + composer

    @ViewBuilder private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = newIn {
                HStack {
                    Label("New thread in \(p.title)", systemImage: "sparkles").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    PillButton(title: "Cancel") { newIn = nil }
                }
                Text("Describe what the agent should do. It starts right away in T3 Code.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
            } else if let t = agents.selected {
                HStack(spacing: 6) {
                    Text(t.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    if !t.model.isEmpty {
                        Text(t.model).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.08))).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    PillButton(title: "Open in T3", symbol: "arrow.up.forward.app") { agents.openInT3(t) }
                }
                messageList(t)
            } else {
                EmptyTabMessage(symbol: "sparkles", title: "Pick a thread")
            }
            if let err = agents.lastError {
                Text(err).font(.system(size: 10.5)).foregroundStyle(.orange)
            }
            composer
        }
    }

    /// The newest messages, pinned to the bottom so the latest reply is always visible.
    private func messageList(_ t: AgentsService.AgentThread) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Spacer(minLength: 0)
            if agents.messages.isEmpty {
                Text(t.isRunning ? "Working…" : "No messages yet.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(agents.messages.suffix(request == nil ? 2 : 1)) { m in
                let isLast = m.id == agents.messages.last?.id
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: m.isUser ? "person.fill" : "sparkles")
                        .font(.system(size: 9)).foregroundStyle(m.isUser ? .white.opacity(0.5) : .purple)
                        .frame(width: 12).padding(.top, 2)
                    Text(m.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(m.isUser ? 0.6 : 0.9))
                        .lineLimit(request != nil ? 1 : (isLast ? 3 : 1))
                        .truncationMode(isLast && request == nil ? .head : .tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let r = request {
                requestCard(r, thread: t)
            } else if t.pendingRequests > 0 || agents.pendingRequests > 0 {
                HStack(spacing: 8) {
                    Label(t.isWaitingOnQuestion ? "Waiting for your answer" : "Waiting for your approval", systemImage: "hand.raised.fill")
                        .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.orange)
                    PillButton(title: "Review in T3", tint: .orange.opacity(0.9), foreground: .black) { agents.openInT3(t) }
                }
            } else if t.isRunning && !agents.messages.isEmpty {
                Label("Working…", systemImage: "ellipsis").font(.system(size: 10.5)).foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .clipped()
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit(submit)
            Button(action: submit) {
                Group {
                    if agents.sending { ProgressView().controlSize(.mini) } else {
                        Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold))
                    }
                }
                .frame(width: 22, height: 22)
                .background(Circle().fill(draft.isEmpty ? Color.white.opacity(0.12) : Color.purple))
            }
            .buttonStyle(PressableStyle())
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || agents.sending)
        }
        .padding(.leading, 10).padding(.trailing, 4).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(focused ? 0.12 : 0.07)))
    }

    private var placeholder: String {
        if newIn != nil { return "What should the agent do?" }
        if let q = currentQuestion, q.allowCustom { return q.options.isEmpty ? "Type your answer…" : "Or type your own answer…" }
        if request?.isApproval == true { return "Or tell the agent what to do instead…" }
        return agents.selected?.isRunning == true ? "Queue a follow-up (sent when it's done)…" : "Message this agent…"
    }

    private func submit() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if let r = request, let q = currentQuestion, q.allowCustom {
            answer(q, with: text.trimmingCharacters(in: .whitespacesAndNewlines), in: r)
            draft = ""
            return
        }
        if let p = newIn {
            agents.startThread(text, in: p)
            newIn = nil
        } else if let id = agents.selectedID {
            agents.send(text, to: id)
        }
        draft = ""
    }

    // MARK: Approvals & questions

    // Not optimized: Swift 6.3's release-mode inliner spins for 20+ minutes on this view builder. It's UI code, so
    // skipping optimization costs nothing noticeable.
    @_optimize(none) @ViewBuilder private func requestCard(_ r: AgentsService.PendingRequest, thread t: AgentsService.AgentThread) -> some View {
        let busy = agents.responding == r.id
        VStack(alignment: .leading, spacing: 5) {
            switch r.kind {
            case .approval(let kind, let prompt, let reason, let options):
                Label(Self.approvalTitle(kind), systemImage: "hand.raised.fill")
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.orange)
                if let main = prompt ?? reason {
                    Text(main)
                        .font(.system(size: 10.5, design: prompt != nil && kind == "command" ? .monospaced : .default))
                        .foregroundStyle(.white.opacity(0.85)).lineLimit(2).truncationMode(.middle)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.06)))
                        .help(main)
                }
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { o in
                        PillButton(title: o.label, tint: Self.isAccept(o.decision) && o.decision == options.first?.decision
                                       ? .orange.opacity(0.9) : .white.opacity(0.14),
                                   foreground: Self.isAccept(o.decision) && o.decision == options.first?.decision ? .black : .white) {
                            agents.respond(to: r, decision: o.decision)
                        }
                        .help(o.warning ?? o.label)
                        .disabled(busy)
                    }
                    if busy { ProgressView().controlSize(.mini) }
                    Spacer(minLength: 0)
                    Button("Review in T3") { agents.openInT3(t) }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
            case .questions(let qs):
                if let q = currentQuestion {
                    HStack(spacing: 5) {
                        Text(q.header.uppercased()).font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                        if qs.count > 1, let i = qs.firstIndex(of: q) {
                            Text("\(i + 1) of \(qs.count)").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                        }
                        if busy { ProgressView().controlSize(.mini) }
                    }
                    Text(q.question).font(.system(size: 11.5, weight: .semibold)).lineLimit(2).help(q.question)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(q.options, id: \.self) { o in
                                let picked = multiPick.contains(o.label)
                                PillButton(title: o.label, symbol: q.multiSelect ? (picked ? "checkmark.square.fill" : "square") : nil,
                                           tint: picked ? .orange.opacity(0.9) : .white.opacity(0.14), foreground: picked ? .black : .white) {
                                    if q.multiSelect {
                                        if picked { multiPick.remove(o.label) } else { multiPick.insert(o.label) }
                                    } else {
                                        answer(q, with: o.value ?? o.label, in: r)
                                    }
                                }
                                .help(o.description)
                                .disabled(busy)
                            }
                            if q.multiSelect {
                                PillButton(title: "Done", symbol: "arrow.right", tint: multiPick.isEmpty ? .white.opacity(0.08) : .orange.opacity(0.9),
                                           foreground: multiPick.isEmpty ? .white.opacity(0.4) : .black) {
                                    answer(q, with: q.options.map(\.label).filter { multiPick.contains($0) }, in: r)
                                }
                                .disabled(multiPick.isEmpty || busy)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Records an answer; once every question has one, sends them all to T3 Code.
    private func answer(_ q: AgentsService.PendingRequest.Question, with value: Any, in r: AgentsService.PendingRequest) {
        guard case .questions(let qs) = r.kind else { return }
        if answeringID != r.id { answers = [:]; answeringID = r.id }
        answers[q.id] = value
        multiPick = []
        if qs.allSatisfy({ answers[$0.id] != nil }) {
            agents.respond(to: r, answers: answers)
        }
    }

    private static func isAccept(_ decision: String) -> Bool { decision.hasPrefix("accept") }

    private static func approvalTitle(_ kind: String) -> String {
        switch kind {
        case "command": "Run this command?"
        case "file-change": "Allow these file changes?"
        case "file-read": "Allow reading these files?"
        case "mcp-elicitation": "A tool needs your input"
        default: "Allow this action?"
        }
    }
}
