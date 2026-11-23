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
        controller = NotchWindowController()
        controller?.show()
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
