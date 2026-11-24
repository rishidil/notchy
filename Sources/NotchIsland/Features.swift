import SwiftUI

/// Every tab the expanded island can show. Which ones appear (and in what order) is chosen in Settings.
enum NotchTab: String, CaseIterable, Identifiable, Codable {
    case home, claude, calendar, timer, weather, todo, lyrics, agents, shelf, bluetooth, system, screenTime, notifications

    var id: String { rawValue }

    static let defaultTabs: [NotchTab] = [.home, .claude, .calendar, .timer, .weather, .shelf]

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .claude: "sparkle"
        case .calendar: "calendar"
        case .timer: "timer"
        case .weather: "cloud.sun.fill"
        case .todo: "checklist"
        case .lyrics: "quote.bubble.fill"
        case .agents: "sparkles"
        case .shelf: "tray.full.fill"
        case .bluetooth: "headphones"
        case .system: "gauge.with.dots.needle.67percent"
        case .screenTime: "hourglass"
        case .notifications: "bell.fill"
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .claude: "Claude"
        case .calendar: "Calendar"
        case .timer: "Timer & Pomodoro"
        case .weather: "Weather"
        case .todo: "To-Do"
        case .lyrics: "Lyrics"
        case .agents: "Agents (T3 Code)"
        case .shelf: "File Shelf"
        case .bluetooth: "Bluetooth"
        case .system: "System Monitor"
        case .screenTime: "Screen Time"
        case .notifications: "Notifications"
        }
    }

    var blurb: String {
        switch self {
        case .home: "Now playing, volume & brightness, quick toggles and your favorite apps"
        case .claude: "Ask Claude anything, or drop files on the notch to ask about them"
        case .calendar: "Today and tomorrow, with one-click Join for video calls"
        case .timer: "Timers and Pomodoro focus sessions that count down in the notch"
        case .weather: "Current conditions and the forecast for where you are"
        case .todo: "A quick to-do list, always one hover away"
        case .lyrics: "Synced lyrics for whatever's playing in Spotify or Music"
        case .agents: "See, prompt and start your T3 Code agents"
        case .shelf: "Drop files on the notch to hold them, drag them out later"
        case .bluetooth: "Connected devices, battery levels and one-click connect"
        case .system: "CPU, memory, network and disk at a glance"
        case .screenTime: "How long you've spent in each app today, tracked on your Mac"
        case .notifications: "Your recent notifications in one place"
        }
    }

    var tint: Color {
        switch self {
        case .home: .blue
        case .claude: .claude
        case .calendar: .red
        case .timer: .orange
        case .weather: .cyan
        case .todo: .green
        case .lyrics: .pink
        case .agents: .purple
        case .shelf: .indigo
        case .bluetooth: .blue
        case .system: .mint
        case .screenTime: .purple
        case .notifications: .red
        }
    }
}

/// Things you can do with files dragged onto the notch.
enum DropAction: String, CaseIterable, Identifiable {
    case askClaude, shelf, airDrop, compress, copyPath, mail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askClaude: "Ask Claude"
        case .shelf: "Keep on Shelf"
        case .airDrop: "AirDrop"
        case .compress: "Compress"
        case .copyPath: "Copy Path"
        case .mail: "Email"
        }
    }

    var symbol: String {
        switch self {
        case .askClaude: "sparkle"
        case .shelf: "tray.and.arrow.down.fill"
        case .airDrop: "dot.radiowaves.left.and.right"
        case .compress: "doc.zipper"
        case .copyPath: "doc.on.doc.fill"
        case .mail: "envelope.fill"
        }
    }

    var tint: Color {
        switch self {
        case .askClaude: .claude
        case .shelf: .indigo
        case .airDrop: .blue
        case .compress: .orange
        case .copyPath: .mint
        case .mail: .cyan
        }
    }
}

extension Color {
    /// Claude's warm clay orange.
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
}

/// True when launched with `--demo` (sample data for screenshots; nothing is saved).
let isDemoMode = CommandLine.arguments.contains("--demo")
