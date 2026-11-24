import AppKit
import SwiftUI

/// Sample content for screenshots (launch with `--demo`). Nothing here is saved, and no personal data is shown.
enum DemoData {
    static func apply(to vm: NotchViewModel) {
        vm.demoEnableAllTabs()
        vm.music.applyDemo(title: "Midnight Drive", artist: "Neon Coast", album: "Afterglow", duration: 214, position: 62,
                           artwork: artwork())
        let cal = Calendar.current
        let now = Date()
        let soon = cal.date(byAdding: .minute, value: 25, to: now)!
        let today: (Int, Int) -> Date = { h, m in cal.date(bySettingHour: h, minute: m, second: 0, of: now)! }
        let tomorrow: (Int, Int) -> Date = { h, m in cal.date(byAdding: .day, value: 1, to: today(h, m))! }
        vm.calendar.applyDemo([
            .init(id: "1", title: "Design Review", start: soon, end: soon.addingTimeInterval(1800), isAllDay: false,
                  color: .systemBlue, location: "Google Meet", meetingURL: URL(string: "https://meet.google.com/abc-defg-hij")),
            .init(id: "2", title: "Lunch with Sam", start: max(today(12, 30), soon.addingTimeInterval(3600)),
                  end: max(today(13, 30), soon.addingTimeInterval(7200)), isAllDay: false, color: .systemGreen,
                  location: "Tartine", meetingURL: nil),
            .init(id: "3", title: "Sprint Planning", start: tomorrow(10, 0), end: tomorrow(11, 0), isAllDay: false,
                  color: .systemPurple, location: nil, meetingURL: URL(string: "https://zoom.us/j/123456789")),
            .init(id: "4", title: "Gym", start: tomorrow(18, 0), end: tomorrow(19, 0), isAllDay: false,
                  color: .systemOrange, location: nil, meetingURL: nil),
        ])
        vm.weather.applyDemo()
        vm.todos.applyDemo()
        vm.lyrics.applyDemo()
        vm.bluetooth.applyDemo()
        vm.system.applyDemo()
        vm.screenTime.applyDemo()
        vm.agents.applyDemo()
        vm.notifications.applyDemo([
            NotificationItem(id: 1, bundleID: "com.apple.MobileSMS", title: "Sam", subtitle: "",
                             body: "Running 5 min late, grab us a table? 🙏", date: now.addingTimeInterval(-120)),
            NotificationItem(id: 2, bundleID: "com.tinyspeck.slackmacgap", title: "#design", subtitle: "",
                             body: "Maya: New mocks are up — take a look before review", date: now.addingTimeInterval(-900)),
            NotificationItem(id: 3, bundleID: "com.apple.iCal", title: "Design Review", subtitle: "",
                             body: "Starts in 25 minutes · Google Meet", date: now.addingTimeInterval(-1500)),
            NotificationItem(id: 4, bundleID: "com.apple.mail", title: "Alex Chen", subtitle: "Offsite plans",
                             body: "Here's the agenda for next week", date: now.addingTimeInterval(-3600)),
            NotificationItem(id: 5, bundleID: "com.apple.reminders", title: "Reminders", subtitle: "",
                             body: "Water the plants", date: now.addingTimeInterval(-7200)),
            NotificationItem(id: 6, bundleID: "com.spotify.client", title: "New release", subtitle: "",
                             body: "Neon Coast just dropped Afterglow", date: now.addingTimeInterval(-10800)),
        ])
        vm.files.applyDemo(demoFiles())
        vm.claude.applyDemo(files: demoFiles().filter { $0.pathExtension == "png" })
    }

    static let messageItem = NotificationItem(id: 99, bundleID: "com.apple.MobileSMS", title: "Sam", subtitle: "",
                                              body: "Running 5 min late, grab us a table? 🙏")

    /// notchy://demo?state=… : puts the island into a specific state for a screenshot.
    static func showState(_ state: String, on vm: NotchViewModel, path: String? = nil) {
        guard isDemoMode else { return }
        vm.dropPreview = false
        switch state {
        case "hud": vm.collapse(); vm.show(.hud(.volume), for: 60)
        case "brightness": vm.collapse(); vm.show(.hud(.brightness), for: 60)
        case "notification": vm.collapse(); vm.show(.notification(messageItem), for: 60)
        case "device":
            vm.collapse()
            if let d = vm.bluetooth.devices.first { vm.show(.device(d), for: 60) }
        case "music": vm.timer.cancel(); vm.dismissTransient(); vm.collapse()
        case "agents-live": vm.timer.cancel(); vm.dismissTransient(); vm.collapse()
        case "agent-done":
            vm.collapse()
            vm.show(.toast(symbol: "checkmark.circle.fill", text: "Agent finished · Add rate limiting to /login", tint: .green), for: 60, tab: .agents)
        case "idle":
            vm.timer.cancel()
            vm.dismissTransient()
            vm.collapse()
            vm.setDemoTabs([.home, .calendar, .timer, .weather, .shelf])
            vm.music.applyDemo(title: "Midnight Drive", artist: "Neon Coast", album: "Afterglow", duration: 214, position: 62,
                               artwork: nil, playing: false)
        case "filedrag":
            // Simulates the pointer sampler seeing a file dragged over the island.
            vm.fileDragMoved(to: CGPoint(x: 60, y: 60))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if let f = vm.dropTileFrames[.shelf] { vm.fileDragMoved(to: CGPoint(x: f.midX, y: f.midY)) }
            }
        case "filedrop":
            let p = vm.dropTileFrames[.shelf].map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: 60, y: 60)
            vm.fileDragReleased(at: p)
        case "hud-open":
            vm.tab = .lyrics
            vm.expand()
            vm.show(.hud(.volume), for: 60)
        case "drop": vm.demoDrop(hover: .airDrop)
        case "drop-claude": vm.demoDrop(hover: .askClaude)
        case "snap":
            NotificationCenter.default.post(name: .notchySnapshot, object: path)
        case "claude":
            vm.dropPreview = false
            vm.tab = .claude
            vm.expand()
        case "claude-live":
            vm.collapse()
            vm.claude.demoStreaming()
        case "claude-done":
            vm.collapse()
            vm.show(.toast(symbol: "sparkle", text: "Claude · Q3 plan in one line: ship onboarding by Aug 15", tint: .claude), for: 60, tab: .claude)
        case "approval", "question":
            vm.agents.applyDemoWaiting(question: state == "question")
            vm.tab = .agents
            vm.expand()
        case "approval-live":
            vm.agents.applyDemoWaiting(question: false)
            vm.dismissTransient()
            vm.collapse()
        case "pomodoro":
            vm.timer.startPomodoro()
            vm.tab = .timer
            vm.expand()
        case "lyrics":
            vm.music.applyDemo(title: "Midnight Drive", artist: "Neon Coast", album: "Afterglow", duration: 214,
                               position: 69, artwork: nil)
            vm.tab = .lyrics
            vm.expand()
        default: break
        }
    }

    private static func demoFiles() -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("NotchIslandDemo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ["Q4 Roadmap.pdf", "Launch Video.mov", "Hero Shot.png", "Brand Assets.zip", "Meeting Notes.txt"].map {
            let url = dir.appendingPathComponent($0)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: Data()) }
            return url
        }
    }

    /// Generated album art: a sunset gradient with a sun and horizon lines.
    static func artwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.98, green: 0.36, blue: 0.55, alpha: 1),
                                NSColor(red: 0.55, green: 0.25, blue: 0.95, alpha: 1),
                                NSColor(red: 0.12, green: 0.08, blue: 0.35, alpha: 1)])?
                .draw(in: rect, angle: -90)
            NSColor(red: 1, green: 0.8, blue: 0.35, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 90, y: 110, width: 120, height: 120)).fill()
            NSColor(red: 0.12, green: 0.08, blue: 0.35, alpha: 1).setFill()
            for i in 0..<6 {
                NSRect(x: 0, y: 110 + CGFloat(i) * 14, width: 300, height: CGFloat(6 - i)).fill()
            }
            NSRect(x: 0, y: 0, width: 300, height: 110).fill()
            return true
        }
    }
}

extension NotchViewModel {
    func demoEnableAllTabs() {
        // Same as the user-facing order, but don't persist anything.
        setDemoTabs([.home, .claude, .calendar, .timer, .weather, .todo, .lyrics, .agents, .shelf, .bluetooth, .system, .screenTime, .notifications])
    }
}
