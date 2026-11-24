import AppKit

@main
enum NotchIslandMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // no Dock icon, no menu bar
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Efficiency.shared // start CPU self-monitoring and sleep/wake tracking
        controller = NotchWindowController()
        controller?.show()
        // `--demo --snapshots <folder>`: render the website's screenshots of the new screens, then quit.
        if isDemoMode, let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count,
           let vm = controller?.viewModel {
            let dir = CommandLine.arguments[i + 1]
            let shots = ["claude", "drop-claude", "claude-live", "claude-done", "approval", "question", "approval-live"]
            for (n, state) in shots.enumerated() {
                let t = 3.5 + Double(n) * 2.5
                DispatchQueue.main.asyncAfter(deadline: .now() + t) { DemoData.showState(state, on: vm) }
                DispatchQueue.main.asyncAfter(deadline: .now() + t + 1.8) { [weak self] in self?.controller?.snapshot(to: "\(dir)/\(state).png") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5 + Double(shots.count) * 2.5 + 0.5) { NSApp.terminate(nil) }
        }
        // First launch: let people choose what their notch shows.
        if !isDemoMode && !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.controller?.viewModel.openSettings(welcome: true)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { controller?.viewModel.handle(url) }
    }
}
