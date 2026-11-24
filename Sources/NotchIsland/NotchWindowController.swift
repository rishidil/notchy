import AppKit
import Combine
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar.
extension Notification.Name {
    static let notchySnapshot = Notification.Name("notchy.snapshot")
}

final class NotchPanel: NSPanel {
    /// Only true while a tab with a text field (To-Do) is open, so clicking the island
    /// doesn't steal keyboard focus from the app you're using.
    var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }
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
    private var bag = Set<AnyCancellable>()
    var viewModel: NotchViewModel { vm }

    /// Fixed canvas size; SwiftUI draws the island at its top-center.
    private let canvas = CGSize(width: 780, height: 370)

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
        NotificationCenter.default.addObserver(forName: .notchySnapshot, object: nil, queue: .main) { [weak self] n in
            if let path = n.object as? String { self?.snapshot(to: path) }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.vm.panelIsKey = true
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            self?.vm.panelResignedKey()
        }

        // Let the panel take keyboard focus only for the To-Do tab; hand focus back when the island closes.
        vm.$isExpanded.combineLatest(vm.$tab)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] expanded, tab in
                guard let self else { return }
                let wantsKey = expanded && (tab == .todo || tab == .agents || tab == .claude)
                self.panel.allowsKey = wantsKey
                if !wantsKey && self.panel.isKeyWindow {
                    self.panel.resignKey()
                    NSWorkspace.shared.frontmostApplication?.activate()
                }
            }
            .store(in: &bag)

        // Files dropped on "Ask Claude" (or notchy://ask): give the panel keyboard focus so you can type right away.
        vm.claude.$focusRequest.dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard let self, self.panel.allowsKey else { return }
                    self.panel.makeKey()
                }
            }
            .store(in: &bag)
    }

    func show() {
        panel.orderFrontRegardless()
    }

    /// Demo mode only (`notchy://demo?state=snap&path=…`): renders the island over a wallpaper-like backdrop into a PNG,
    /// for the website's screenshots. Draws Notchy's own window, so it needs no screen-recording permission.
    func snapshot(to path: String) {
        guard isDemoMode, let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let island = vm.shapeSize
        let size = CGSize(width: view.bounds.width, height: max(260, min(view.bounds.height, island.height + 70)))
        let out = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.16, green: 0.30, blue: 0.58, alpha: 1), NSColor(red: 0.30, green: 0.22, blue: 0.55, alpha: 1),
                                NSColor(red: 0.50, green: 0.20, blue: 0.45, alpha: 1)])?.draw(in: rect, angle: -20)
            NSColor(white: 1, alpha: 0.10).setFill()
            NSRect(x: 0, y: rect.maxY - self.vm.notchSize.height, width: rect.width, height: self.vm.notchSize.height).fill()
            let img = NSImage(size: view.bounds.size)
            img.addRepresentation(rep)
            img.draw(in: NSRect(x: 0, y: rect.maxY - view.bounds.height, width: view.bounds.width, height: view.bounds.height))
            return true
        }
        guard let cg = out.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        bitmap.size = size
        try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func layout() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        screenFrame = screen.frame

        // `defaults write dev.notchisland.app simulateNoNotch -bool true` previews the notch-less layout.
        let simulateNoNotch = UserDefaults.standard.bool(forKey: "simulateNoNotch")
        if !simulateNoNotch, screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            vm.hasNotch = true
            vm.notchSize = CGSize(width: screen.frame.width - left.width - right.width,
                                  height: screen.safeAreaInsets.top)
        } else {
            // No notch (M1 Air/13" Pro, iMac, external display): the island is invisible until it has
            // something to show, then appears as a slim pill inside the menu bar.
            vm.hasNotch = false
            let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
            vm.notchSize = CGSize(width: 36, height: min(menuBar, 32))
        }

        panel.setFrame(CGRect(x: screenFrame.midX - canvas.width / 2, y: screenFrame.maxY - canvas.height,
                              width: canvas.width, height: canvas.height), display: true)
    }

    // MARK: Mouse

    /// The pointer is sampled on a light timer (10×/s idle, 25×/s near the island) instead of observing every
    /// mouse event: high-rate mice deliver up to 1,000 events a second, which would wake Notchy constantly.
    private func installMouseMonitors() {
        // Clicks are rare: remember the drag pasteboard at mouse-down to tell file drags from window drags.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.dragBaseline = NSPasteboard(name: .drag).changeCount
        }) {
            monitors.append(m)
        }
        Efficiency.shared.$isAwake
            .receive(on: DispatchQueue.main)
            .sink { [weak self] awake in
                guard let self else { return }
                if awake { self.schedulePoll(engaged: false) } else { self.pollTimer?.invalidate(); self.pollTimer = nil; self.pollInterval = 0 }
            }
            .store(in: &bag)
    }

    private var dragBaseline = NSPasteboard(name: .drag).changeCount
    private var pollInterval: TimeInterval = 0

    private func schedulePoll(engaged: Bool) {
        let interval: TimeInterval = engaged ? 0.04 : (Efficiency.shared.isActive ? 0.2 : 0.1)
        guard interval != pollInterval || pollTimer == nil else { return }
        pollTimer?.invalidate()
        pollInterval = interval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.updateMouse() }
        t.tolerance = interval * 0.25
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }

    /// Drag pasteboard generation we've already classified, and whether it holds files.
    private var classifiedDrag = -1
    private var dragHasFiles = false
    private var fileDragInside = false
    private var lastIslandPoint = CGPoint.zero

    private func updateMouse() {
        let location = NSEvent.mouseLocation
        var inside = vm.interactiveRect(screenFrame: screenFrame).contains(location)
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0

        // Is a *file* being dragged? (The drag pasteboard changes when a drag starts; check its types once per drag.)
        var fileDrag = false
        if buttonDown {
            let pb = NSPasteboard(name: .drag)
            if pb.changeCount != dragBaseline {
                if pb.changeCount != classifiedDrag {
                    classifiedDrag = pb.changeCount
                    dragHasFiles = pb.types?.contains(.fileURL) ?? false
                }
                fileDrag = dragHasFiles
            }
            // Window moves / text selections passing over the collapsed island shouldn't open it.
            if inside && !fileDrag && !vm.isExpanded { inside = false }
        }

        // File drags work from any tab: open the drop UI and track which tile is under the pointer.
        if fileDrag && inside {
            let s = vm.shapeSize
            let originX = screenFrame.midX + vm.bodyOffsetX - s.width / 2
            lastIslandPoint = CGPoint(x: location.x - originX, y: screenFrame.maxY - location.y)
            fileDragInside = true
            vm.fileDragMoved(to: lastIslandPoint)
        } else if fileDragInside {
            fileDragInside = false
            if !buttonDown { vm.fileDragReleased(at: lastIslandPoint) } else { vm.fileDragLeft() }
        }

        // Only capture the mouse over the island; everywhere else clicks pass through to the menu bar.
        // While hidden (no notch, idle) never capture it, so menu-bar clicks still work.
        let capture = inside && !vm.isHiddenIdle
        if panel.ignoresMouseEvents == capture { panel.ignoresMouseEvents = !capture }
        vm.setHovering(inside)
        schedulePoll(engaged: inside || vm.isExpanded || fileDrag)
    }
}
