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
    }
}
