import AppKit

/// Temporary holding area for files: drop onto the notch, drag back out anywhere.
/// Stores references (not copies), so moving/deleting the original removes it from the shelf.
final class FileShelf: ObservableObject {
    struct Item: Identifiable, Equatable {
        let url: URL
        var id: URL { url }
        var name: String { url.lastPathComponent }
        var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
    }

    @Published private(set) var items: [Item] = []
    private let key = "fileShelfPaths"

    init() {
        items = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { Item(url: URL(fileURLWithPath: $0)) }
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !items.contains(where: { $0.url == url }) {
            items.append(Item(url: url))
        }
        save()
    }

    func remove(_ item: Item) {
        items.removeAll { $0 == item }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    func open(_ item: Item) { NSWorkspace.shared.open(item.url) }
    func reveal(_ item: Item) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }

    func airDrop(_ selection: [Item]) {
        NSApp.activate(ignoringOtherApps: true)
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: selection.map(\.url))
    }

    /// Handles a SwiftUI drop. Returns true if any file URLs were offered.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = p.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url, url.isFileURL else { return }
                DispatchQueue.main.async { self?.add([url]) }
            }
        }
        return accepted
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: key)
    }
}
