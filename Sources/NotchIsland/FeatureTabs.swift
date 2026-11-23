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
            if let c = weather.current { content(c) } else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
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
