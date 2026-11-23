import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets clicks register even though our app is never the active app.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchWindowController {
    private let panel: NotchPanel
    private let vm = NotchViewModel()
    private var screenFrame: CGRect = .zero
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?

    /// Fixed canvas size; SwiftUI draws the island at its top-center.
    private let canvas = CGSize(width: 780, height: 280)

    init() {
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)

        let host = NotchHostingView(rootView: NotchRootView(vm: vm))
        host.sizingOptions = []
        panel.contentView = host

        layout()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.layout() }
        installMouseMonitors()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    private func layout() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        screenFrame = screen.frame

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            vm.notchSize = CGSize(width: screen.frame.width - left.width - right.width,
                                  height: screen.safeAreaInsets.top)
        } else {
            // No notch (external display): draw a fake one the height of the menu bar.
            let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
            vm.notchSize = CGSize(width: 190, height: menuBar)
        }

        panel.setFrame(CGRect(x: screenFrame.midX - canvas.width / 2, y: screenFrame.maxY - canvas.height,
                              width: canvas.width, height: canvas.height), display: true)
    }

    // MARK: Mouse

    private func installMouseMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] e in self?.updateMouse(e) }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] e in self?.updateMouse(e); return e }) {
            monitors.append(m)
        }
        // Remember the drag pasteboard at mouse-down so we can tell file drags from window drags.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.dragBaseline = NSPasteboard(name: .drag).changeCount
        }) {
            monitors.append(m)
        }
    }

    private var dragBaseline = NSPasteboard(name: .drag).changeCount

    private func updateMouse(_ event: NSEvent? = nil) {
        var inside = vm.interactiveRect(screenFrame: screenFrame).contains(NSEvent.mouseLocation)

        // Something is being dragged over the collapsed notch: only react to file drags.
        if inside, !vm.isExpanded, event?.type == .leftMouseDragged {
            if NSPasteboard(name: .drag).changeCount != dragBaseline {
                vm.beginFileDrag()
            } else {
                inside = false // window move / text selection etc.
            }
        }

        // Only capture the mouse over the island; everywhere else clicks pass through to the menu bar.
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        vm.setHovering(inside)

        // Mouse-moved events don't always reach an inactive app, so poll while the island is engaged.
        if inside || vm.isExpanded {
            if pollTimer == nil {
                pollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.updateMouse() }
            }
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }
}
