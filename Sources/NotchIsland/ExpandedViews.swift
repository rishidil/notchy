import AppKit
import SwiftUI

// MARK: - Container

struct ExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar().frame(height: vm.notchSize.height)
            Group {
                if vm.showsDropActions {
                    DropActionsView()
                } else {
                    switch vm.tab {
                    case .home: HomeTab()
                    case .claude: AssistantTab(claude: vm.assistant)
                    case .calendar: CalendarTab(calendar: vm.calendar)
                    case .timer: TimerTab(timer: vm.timer)
                    case .shelf: ShelfTab(files: vm.files)
                    case .weather: WeatherTab(weather: vm.weather)
                    case .todo: TodoTab(todos: vm.todos)
                    case .lyrics: LyricsTab(lyrics: vm.lyrics, music: vm.music)
                    case .agents: AgentsTab(agents: vm.agents)
                    case .bluetooth: BluetoothTab(bluetooth: vm.bluetooth)
                    case .system: SystemTab(system: vm.system, battery: vm.battery)
                    case .screenTime: ScreenTimeTab(tracker: vm.screenTime)
                    case .notifications: NotificationsTab(notifications: vm.notifications)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
        // Volume / brightness changes stay visible whichever tab is open.
        .overlay {
            if let kind = vm.activeHUD {
                ExpandedHUDOverlay(kind: kind)
                    .transition(.opacity.animation(.easeInOut(duration: 0.35)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.activeHUD)
    }
}

struct HeaderBar: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        // Tabs fill the space left of the notch first, then continue on the right.
        // With many tabs, slim them down and drop the battery readout (it's also in the System tab).
        let tabs = vm.tabs
        let w = vm.headerTabWidth
        let side = (vm.expandedSize.width - vm.notchSize.width) / 2 - 34
        let rightCapacity = max(0, Int((side - NotchViewModel.headerTrailingReserve) / (w + 2)))
        let leftCount = min(tabs.count, max(1, max(Int(side / (w + 2)), tabs.count - rightCapacity)))
        HStack(spacing: 8) {
            tabGroup(Array(tabs.prefix(leftCount)), width: w)
            Spacer(minLength: vm.notchSize.width + 24)
            if tabs.count > leftCount { tabGroup(Array(tabs.dropFirst(leftCount)), width: w) }
            BatteryBadge(battery: vm.battery).fixedSize()
            Button { vm.openSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .opacity(0.6)
            .help("Settings")
        }
        .padding(.horizontal, 22)
    }

    private func tabGroup(_ tabs: [NotchTab], width: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(tabs) { t in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { vm.tab = t }
                } label: {
                    Image(systemName: t.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: width, height: 22)
                        .background(Capsule().fill(vm.tab == t && !vm.showsDropActions ? Color.white.opacity(0.16) : .clear))
                        .foregroundStyle(vm.tab == t ? Color.white : Color.white.opacity(0.5))
                        .overlay(alignment: .topTrailing) { badge(for: t) }
                }
                .buttonStyle(PressableStyle())
                .help(t.title)
            }
        }
    }

    @ViewBuilder private func badge(for tab: NotchTab) -> some View {
        let color: Color? = switch tab {
        case .timer: vm.timer.isActive ? (vm.timer.phase?.color ?? .orange) : nil
        case .shelf: vm.files.items.isEmpty ? nil : .blue
        case .claude: vm.assistant.isStreaming ? .claude : nil
        case .todo: vm.todos.remaining > 0 ? .green : nil
        case .lyrics: vm.lyrics.state == .synced ? .pink : nil
        case .agents: vm.agents.attentionCount > 0 ? .orange : (vm.agents.runningCount > 0 ? .green
            : (vm.agents.threads.contains(where: \.isUnreadDone) ? .blue : nil))
        default: nil
        }
        if let color {
            Circle().fill(color).frame(width: 5, height: 5).offset(x: -4, y: 3)
        }
    }
}

struct BatteryBadge: View {
    @ObservedObject var battery: BatteryMonitor
    var compact = false

    var body: some View {
        if battery.hasBattery {
            HStack(spacing: 4) {
                if !compact { Text("\(battery.level)%").font(.system(size: 11, weight: .semibold).monospacedDigit()) }
                Image(systemName: symbol).font(.system(size: 14)).symbolRenderingMode(.hierarchical)
            }
            .foregroundStyle(battery.onAC ? Color.green : (battery.level <= 20 ? .red : .white.opacity(0.8)))
        }
    }

    private var symbol: String {
        if battery.onAC { return "battery.100percent.bolt" }
        switch battery.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Home

struct HomeTab: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                NowPlayingCard(music: vm.music)
                LevelSliders(volume: vm.volume, brightness: vm.brightness)
            }
            .frame(width: 268)
            Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 132)
            VStack(alignment: .leading, spacing: 10) {
                NextEventRow(calendar: vm.calendar)
                TogglesRow(toggles: vm.toggles, volume: vm.volume)
                AppShelfRow(shelf: vm.shelf)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct LevelSliders: View {
    @ObservedObject var volume: VolumeController
    @ObservedObject var brightness: BrightnessController

    var body: some View {
        HStack(spacing: 14) {
            MiniSlider(symbol: volume.muted || volume.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
                       value: volume.muted ? 0 : Double(volume.volume)) { volume.setVolume(Float($0)) }
                .help("Volume")
            MiniSlider(symbol: "sun.max.fill", value: Double(brightness.level)) { brightness.set(Float($0)) }
                .help("Brightness")
        }
    }
}

struct MiniSlider: View {
    let symbol: String
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 16)
            GeometryReader { geo in
                LevelBar(level: value)
                    .frame(height: 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                        onChange(min(max(g.location.x / geo.size.width, 0), 1))
                    })
            }
            .frame(height: 18)
        }
    }
}

struct NowPlayingCard: View {
    @ObservedObject var music: MusicController

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ArtworkView(image: music.artwork, size: 76, radius: 14)
                .shadow(color: music.accent.opacity(music.artwork == nil ? 0 : 0.35), radius: 10)
                .onTapGesture { music.openPlayer() }
            if music.hasTrack { trackInfo } else { emptyState }
        }
        .padding(.top, 4)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(music.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(music.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            ProgressBar(music: music).padding(.top, 6)
            HStack(spacing: 24) {
                IconButton(symbol: "backward.fill", size: 14) { music.previous() }
                IconButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 20) { music.playPause() }
                IconButton(symbol: "forward.fill", size: 14) { music.next() }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing playing").font(.system(size: 13, weight: .semibold))
            Text("Play something in Spotify or Music").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            HStack(spacing: 6) {
                ForEach(music.installedPlayers) { p in
                    PillButton(title: p.name) { music.launch(p) }
                }
            }
            .padding(.top, 2)
        }
    }
}

struct ProgressBar: View {
    @ObservedObject var music: MusicController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let pos = music.position(at: ctx.date)
            let frac = music.duration > 0 ? pos / music.duration : 0
            VStack(spacing: 3) {
                GeometryReader { geo in
                    LevelBar(level: frac, color: music.accent)
                        .frame(height: 4)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard music.duration > 0 else { return }
                            music.seek(to: Double(location.x / geo.size.width) * music.duration)
                        }
                }
                .frame(height: 10)
                HStack {
                    Text(Self.format(pos))
                    Spacer()
                    Text("-" + Self.format(music.duration - pos))
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    static func format(_ t: Double) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct NextEventRow: View {
    @ObservedObject var calendar: CalendarService
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(nsColor: calendar.nextEvent?.color ?? .systemOrange))
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = calendar.nextEvent?.meetingURL {
                PillButton(title: "Join", symbol: "video.fill", tint: .green.opacity(0.85)) {
                    NSWorkspace.shared.open(url)
                    vm.collapse()
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
        .contentShape(Rectangle())
        .onTapGesture {
            if calendar.authorized { vm.tab = .calendar } else { calendar.requestAccess() }
        }
    }

    private var title: String {
        if !calendar.authorized { return calendar.denied ? "Calendar access denied" : "Connect your calendar" }
        return calendar.nextEvent?.title ?? "No upcoming events"
    }

    private var subtitle: String {
        if !calendar.authorized { return calendar.denied ? "Click to open System Settings" : "Click to allow access" }
        guard let e = calendar.nextEvent else { return "You're free for the rest of the day" }
        return EventFormat.relative(e)
    }
}

enum EventFormat {
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    static func relative(_ e: CalendarService.EventInfo) -> String {
        let now = Date()
        if e.start <= now { return "Now · until \(time(e.end))" }
        let mins = Int(ceil(e.start.timeIntervalSince(now) / 60))
        if mins < 60 { return "In \(mins) min · \(time(e.start))" }
        if Calendar.current.isDateInToday(e.start) { return "Today · \(time(e.start))" }
        if Calendar.current.isDateInTomorrow(e.start) { return "Tomorrow · \(time(e.start))" }
        return e.start.formatted(date: .abbreviated, time: .shortened)
    }
}

struct TogglesRow: View {
    @ObservedObject var toggles: SystemToggles
    @ObservedObject var volume: VolumeController
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        HStack(spacing: 8) {
            ToggleChip(symbol: "moon.fill", label: "Dark Mode", isOn: toggles.darkMode) { toggles.toggleDarkMode() }
            ToggleChip(symbol: "cup.and.saucer.fill",
                       label: toggles.usesAmphetamine ? "Keep Awake (Amphetamine) — right-click for durations" : "Keep Awake",
                       isOn: toggles.keepAwake) { toggles.toggleKeepAwake() }
                .contextMenu {
                    Button("Keep Awake for 1 Hour") { toggles.startKeepAwake(minutes: 60) }
                    Button("Keep Awake for 2 Hours") { toggles.startKeepAwake(minutes: 120) }
                    Button("Keep Awake for 4 Hours") { toggles.startKeepAwake(minutes: 240) }
                    Button("Keep Awake Indefinitely") { toggles.startKeepAwake(minutes: 0) }
                    if toggles.keepAwake {
                        Divider()
                        Button("Stop Keeping Awake") { toggles.stopKeepAwake() }
                    }
                }
            ToggleChip(symbol: volume.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: "Mute",
                       isOn: volume.muted) { volume.toggleMute() }
            ToggleChip(symbol: "camera.viewfinder", label: "Screenshot", isOn: false) {
                vm.collapse()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { toggles.screenshot() }
            }
            ToggleChip(symbol: "lock.fill", label: "Sleep Display", isOn: false) { toggles.sleepDisplay() }
        }
    }
}

struct ToggleChip: View {
    let symbol: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(isOn ? Color.white : Color.white.opacity(0.1)))
                .foregroundStyle(isOn ? Color.black : Color.white)
        }
        .buttonStyle(PressableStyle())
        .help(label)
    }
}

struct AppShelfRow: View {
    @ObservedObject var shelf: AppShelf
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shelf.apps) { app in
                    Button {
                        shelf.open(app)
                        vm.collapse()
                    } label: {
                        VStack(spacing: 2) {
                            Image(nsImage: app.icon).resizable().frame(width: 30, height: 30)
                            Circle().fill(shelf.running.contains(app.id) ? Color.white.opacity(0.7) : .clear)
                                .frame(width: 3, height: 3)
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .help(app.name)
                    .contextMenu {
                        Button("Remove \(app.name) from Shelf") { shelf.remove(app) }
                    }
                }
                Button {
                    vm.collapse()
                    shelf.addApps()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.1)))
                        .padding(.bottom, 5)
                }
                .buttonStyle(PressableStyle())
                .help("Add apps")
            }
        }
    }
}

// MARK: - Calendar

struct CalendarTab: View {
    @ObservedObject var calendar: CalendarService
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        if !calendar.authorized {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 26))
                Text(calendar.denied ? "Calendar access was denied" : "Notchy needs calendar access")
                    .font(.system(size: 13, weight: .semibold))
                PillButton(title: calendar.denied ? "Open System Settings" : "Allow Access") { calendar.requestAccess() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 18) {
                dateBlock.frame(width: 118, alignment: .leading)
                agendaList
            }
        }
    }

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            TimelineView(.everyMinute) { ctx in
                VStack(alignment: .leading, spacing: 0) {
                    Text(ctx.date.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
                    Text(ctx.date.formatted(.dateTime.day()))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                    Text(ctx.date.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer(minLength: 6)
            calendarsMenu
            if !calendar.hasGoogle {
                Button { calendar.openInternetAccounts() } label: {
                    Label("Add Google", systemImage: "plus.circle.fill").font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }

    private var calendarsMenu: some View {
        let groups = Dictionary(grouping: calendar.calendars, by: \.source)
        return Menu {
            ForEach(groups.keys.sorted(), id: \.self) { source in
                Section(source) {
                    ForEach(groups[source] ?? []) { c in
                        Toggle(c.title, isOn: Binding(get: { !calendar.excluded.contains(c.id) },
                                                      set: { calendar.setCalendar(c.id, included: $0) }))
                    }
                }
            }
            Divider()
            Button("Add Google / Other Account…") { calendar.openInternetAccounts() }
        } label: {
            Label("Calendars", systemImage: "line.3.horizontal.decrease.circle")
                .font(.system(size: 10.5, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(0.75)
    }

    private var agendaList: some View {
        let today = calendar.agenda.filter { $0.start < Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400) }
        let tomorrow = calendar.agenda.filter { !today.contains($0) }
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                if calendar.agenda.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nothing scheduled").font(.system(size: 13, weight: .semibold))
                        Text("No events for the rest of today or tomorrow.")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.top, 8)
                }
                if !today.isEmpty { section("Today", today) }
                if !tomorrow.isEmpty { section("Tomorrow", tomorrow) }
            }
        }
    }

    private func section(_ title: String, _ events: [CalendarService.EventInfo]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.4))
                .padding(.top, 2)
            ForEach(events) { AgendaRow(event: $0) }
        }
    }
}

struct AgendaRow: View {
    let event: CalendarService.EventInfo
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        let ongoing = event.start <= Date() && event.end > Date()
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.color ?? .systemBlue))
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL {
                PillButton(title: "Join", symbol: "video.fill", tint: ongoing ? .green.opacity(0.85) : .white.opacity(0.14)) {
                    NSWorkspace.shared.open(url)
                    vm.collapse()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(ongoing ? 0.1 : 0.04)))
    }

    private var detail: String {
        let time = event.isAllDay ? "All day"
            : "\(EventFormat.time(event.start)) – \(EventFormat.time(event.end))"
        return [time, event.location].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Timer

struct TimerTab: View {
    @ObservedObject var timer: TimerService
    @State private var customMinutes = 20
    @AppStorage("timerMode") private var pomodoroMode = false
    private let presets = [1, 3, 5, 10, 15, 25, 30, 45]

    var body: some View {
        if timer.isActive { running } else { pomodoroMode ? AnyView(pomodoroPicker) : AnyView(picker) }
    }

    private var accent: Color { timer.phase?.color ?? .orange }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach([false, true], id: \.self) { pomo in
                Button { pomodoroMode = pomo } label: {
                    Text(pomo ? "Pomodoro" : "Timer")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 22)
                        .background(Capsule().fill(pomodoroMode == pomo ? Color.white.opacity(0.16) : .clear))
                        .foregroundStyle(pomodoroMode == pomo ? Color.white : Color.white.opacity(0.5))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.06)))
    }

    private var pomodoroPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Focus sessions").font(.system(size: 13, weight: .semibold))
                Spacer()
                modePicker
            }
            HStack(spacing: 10) {
                phaseCard("Focus", minutes: $timer.focusMinutes, color: PomodoroPhase.focus.color, symbol: "brain.head.profile")
                phaseCard("Short break", minutes: $timer.shortBreakMinutes, color: .green, symbol: "cup.and.saucer.fill")
                phaseCard("Long break", minutes: $timer.longBreakMinutes, color: .teal, symbol: "figure.walk")
                VStack(spacing: 8) {
                    PillButton(title: "Start", symbol: "play.fill", tint: PomodoroPhase.focus.color, foreground: .black) {
                        timer.startPomodoro()
                    }
                    Text("Long break every \(timer.cyclesBeforeLongBreak)")
                        .font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func phaseCard(_ title: String, minutes: Binding<Int>, color: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.system(size: 10.5, weight: .medium)).foregroundStyle(color)
            HStack(spacing: 6) {
                IconButton(symbol: "minus", size: 10) { minutes.wrappedValue = max(1, minutes.wrappedValue - 1) }
                Text("\(minutes.wrappedValue)")
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .frame(minWidth: 30)
                IconButton(symbol: "plus", size: 10) { minutes.wrappedValue = min(120, minutes.wrappedValue + 1) }
            }
            Text("minutes").font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.45))
        }
        .padding(10)
        .frame(width: 128, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
    }

    private var running: some View {
        HStack(spacing: 28) {
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                let remaining = timer.remaining(at: ctx.date)
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: timer.progress(at: ctx.date))
                        .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: remaining)
                    Text(TimerService.format(remaining))
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .frame(width: 112, height: 112)
            }
            VStack(alignment: .leading, spacing: 12) {
                if let phase = timer.phase {
                    HStack(spacing: 8) {
                        Label(phase.title, systemImage: phase.symbol)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(phase.color)
                        if !timer.isRunning { Text("Paused").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
                    }
                    HStack(spacing: 5) {
                        let cycles = max(1, timer.cyclesBeforeLongBreak)
                        let done = timer.completedFocus % cycles
                        ForEach(0..<cycles, id: \.self) { i in
                            Circle().fill(i < done ? PomodoroPhase.focus.color : .white.opacity(0.18)).frame(width: 7, height: 7)
                        }
                        Text("\(timer.completedFocus) session\(timer.completedFocus == 1 ? "" : "s") done")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).padding(.leading, 4)
                    }
                } else {
                    Text(timer.isRunning ? "Timer running" : "Paused")
                        .font(.system(size: 15, weight: .semibold))
                    Text("It'll show in the notch while it runs.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                }
                HStack(spacing: 8) {
                    PillButton(title: timer.isRunning ? "Pause" : "Resume",
                               symbol: timer.isRunning ? "pause.fill" : "play.fill",
                               tint: accent.opacity(0.9), foreground: .black) {
                        timer.isRunning ? timer.pause() : timer.resume()
                    }
                    if timer.phase != nil {
                        PillButton(title: "Skip", symbol: "forward.end.fill") { timer.skipPhase() }
                        PillButton(title: "Stop", symbol: "stop.fill") { timer.cancel() }
                    } else {
                        PillButton(title: "+1 min", symbol: "plus") { timer.addMinute() }
                        PillButton(title: "Cancel", symbol: "xmark") { timer.cancel() }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Start a timer").font(.system(size: 13, weight: .semibold))
                Spacer()
                modePicker
            }
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { m in
                    Button { timer.start(seconds: Double(m) * 60) } label: {
                        VStack(spacing: 0) {
                            Text("\(m)").font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text("min").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(width: 54, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            HStack(spacing: 10) {
                Text("Custom").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                IconButton(symbol: "minus.circle.fill", size: 16) { customMinutes = max(1, customMinutes - 1) }
                Text("\(customMinutes) min")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .frame(width: 62)
                IconButton(symbol: "plus.circle.fill", size: 16) { customMinutes = min(600, customMinutes + 1) }
                PillButton(title: "Start", symbol: "play.fill", tint: .orange.opacity(0.9), foreground: .black) {
                    timer.start(seconds: Double(customMinutes) * 60)
                }
            }
        }
    }
}

// MARK: - File shelf

struct ShelfTab: View {
    @ObservedObject var files: FileShelf
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("File Shelf").font(.system(size: 13, weight: .semibold))
                if !files.items.isEmpty {
                    Text("\(files.items.count) item\(files.items.count == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                if !files.items.isEmpty {
                    PillButton(title: "AirDrop All", symbol: "airplayaudio") { files.airDrop(files.items) }
                    PillButton(title: "Clear", symbol: "trash") { files.clear() }
                }
            }
            if files.items.isEmpty {
                dropZone
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(files.items) { FileTile(item: $0, files: files) }
                    }
                    .padding(6)
                }
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(vm.isDropTargeted ? Color.blue : .clear, lineWidth: 1.5)
                )
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(vm.isDropTargeted ? Color.blue : Color.white.opacity(0.25))
            .background(RoundedRectangle(cornerRadius: 14).fill(vm.isDropTargeted ? Color.blue.opacity(0.12) : .clear))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 22))
                    Text("Drop files on the notch to hold them here")
                        .font(.system(size: 12, weight: .medium))
                    Text("Then drag them out anywhere — or AirDrop them")
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5))
                }
                .foregroundStyle(vm.isDropTargeted ? Color.blue : Color.white.opacity(0.8))
            }
    }
}

struct FileTile: View {
    let item: FileShelf.Item
    @ObservedObject var files: FileShelf

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon).resizable().frame(width: 48, height: 48)
            Text(item.name)
                .font(.system(size: 10))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76, height: 26, alignment: .top)
        }
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { files.open(item) }
        .help(item.url.path)
        .contextMenu {
            Button("Open") { files.open(item) }
            Button("Show in Finder") { files.reveal(item) }
            Button("AirDrop") { files.airDrop([item]) }
            Divider()
            Button("Remove from Shelf") { files.remove(item) }
        }
    }
}
