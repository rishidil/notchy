import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shape

/// Notch silhouette: flared top corners that blend into the bezel, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius, b = min(bottomRadius, rect.height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t), control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY), control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b), control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Root

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        let shape = NotchShape(topRadius: vm.topRadius, bottomRadius: vm.bottomRadius)
        let raised = vm.isExpanded || vm.collapsedSize.height > vm.notchSize.height
        ZStack(alignment: .top) {
            shape.fill(Color.black)
            if vm.isExpanded {
                ExpandedView()
                    .frame(width: vm.expandedSize.width, height: vm.expandedSize.height)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .top))
                            .animation(.easeOut(duration: 0.25).delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.12))))
            } else {
                CollapsedView()
                    .frame(width: vm.collapsedSize.width, height: vm.collapsedSize.height, alignment: .top)
                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
            }
        }
        .frame(width: vm.shapeSize.width, height: vm.shapeSize.height)
        .clipShape(shape)
        .contentShape(shape)
        .shadow(color: .black.opacity(raised ? 0.5 : 0), radius: 16, y: 6)
        .onTapGesture { vm.handleTap() }
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { vm.isDropTargeted }, set: { vm.dropTargetChanged($0) })) {
            vm.files.handleDrop($0)
        }
        .contextMenu {
            if case .notification(let n) = vm.transient {
                Button("Mute Previews from \(n.appName)") { vm.muteNotifications(from: n) }
                Divider()
            }
            SettingsMenuItems()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchViewModel.spring, value: vm.activity)
        .environmentObject(vm)
        .environment(\.colorScheme, .dark)
    }
}

struct SettingsMenuItems: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        if vm.notifications.hasAccess {
            Toggle("Notification Previews", isOn: Binding(get: { vm.notifications.enabled },
                                                          set: { vm.notifications.setEnabled($0) }))
        } else {
            Button("Enable Notification Previews (Full Disk Access)…") { vm.notifications.openFullDiskAccessSettings() }
        }
        Toggle("Replace System Volume & Brightness HUD", isOn: Binding(get: { vm.replaceSystemHUD },
                                                                       set: { vm.setReplaceSystemHUD($0) }))
        Toggle("Launch at Login", isOn: Binding(get: { vm.launchAtLogin }, set: { _ in vm.toggleLaunchAtLogin() }))
        Divider()
        Button("Add Google / Other Calendar Account…") { vm.calendar.openInternetAccounts() }
        Button("Reset App Shelf") { vm.shelf.reset() }
        if !vm.notifications.mutedApps.isEmpty {
            Button("Unmute All Notification Previews") { vm.notifications.unmuteAll() }
        }
        Divider()
        Button("Quit Notch Island") { NSApp.terminate(nil) }
    }
}

// MARK: - Collapsed (live activities)

struct CollapsedView: View {
    @EnvironmentObject var vm: NotchViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading.frame(width: vm.sideWidth)
                Spacer(minLength: 0)
                trailing.frame(width: vm.sideWidth)
            }
            .frame(height: vm.notchSize.height)
            bottom
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var leading: some View {
        switch vm.activity {
        case .music:
            ArtworkView(image: vm.music.artwork, size: 22, radius: 6)
        case .battery(_, let onAC):
            Image(systemName: onAC ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(onAC ? .green : .white.opacity(0.8))
        case .event:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: vm.calendar.nextEvent?.color ?? .systemOrange))
        case .timer, .timerDone:
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
        case .hud(let kind):
            Image(systemName: hudSymbol(kind))
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        case .notification, .none:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch vm.activity {
        case .music:
            EqualizerView(color: vm.music.accent).frame(width: 18, height: 14)
        case .battery(let level, let onAC):
            Text("\(level)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(onAC ? .green : .white)
        case .event(let minutes):
            Text(minutes == 0 ? "now" : "\(minutes)m")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(nsColor: vm.calendar.nextEvent?.color ?? .systemOrange))
        case .timer:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(TimerService.shortFormat(vm.timer.remaining(at: ctx.date)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.orange.opacity(vm.timer.isRunning ? 1 : 0.5))
            }
        case .timerDone:
            Text("0:00").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.orange)
        case .hud(let kind):
            Text("\(Int((hudLevel(kind) * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
        case .notification, .none:
            EmptyView()
        }
    }

    @ViewBuilder private var bottom: some View {
        switch vm.activity {
        case .hud(let kind):
            LevelBar(level: hudLevel(kind))
                .frame(height: 6)
                .padding(.horizontal, 20)
                .frame(height: 22)
        case .notification(let n):
            NotificationBanner(item: n)
        case .timerDone:
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                Text("Timer finished").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                PillButton(title: "Restart") { vm.timer.restart(); vm.dismissTransient() }
                PillButton(title: "Done") { vm.dismissTransient() }
            }
            .padding(.horizontal, 18)
            .frame(height: 38)
        default:
            EmptyView()
        }
    }

    private func hudLevel(_ kind: HUDKind) -> Double {
        switch kind {
        case .volume: return vm.volume.muted ? 0 : Double(vm.volume.volume)
        case .brightness: return Double(vm.brightness.level)
        }
    }

    private func hudSymbol(_ kind: HUDKind) -> String {
        switch kind {
        case .brightness: return vm.brightness.level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            let v = vm.volume.volume
            if vm.volume.muted || v == 0 { return "speaker.slash.fill" }
            return v < 0.33 ? "speaker.wave.1.fill" : (v < 0.66 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
        }
    }
}

struct NotificationBanner: View {
    let item: NotificationItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "bell.fill").resizable().scaledToFit().padding(6)
                }
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title.isEmpty ? item.appName : item.title)
                        .font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(item.appName).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
                Text(item.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(item.subtitle.isEmpty ? 2 : 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }
}

struct EqualizerView: View {
    var color: Color = .white

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { ctx in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(color).frame(width: 2.5, height: .random(in: 4...14))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: ctx.date)
        }
    }
}

// MARK: - Shared components

struct LevelBar: View {
    let level: Double
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(color).frame(width: max(0, min(1, level)) * geo.size.width)
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color.purple.opacity(0.7), Color.blue.opacity(0.6)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct IconButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = .white.opacity(0.14)
    var foreground: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(tint))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}
