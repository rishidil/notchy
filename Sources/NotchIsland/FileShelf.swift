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

    /// Resolves dropped item providers to file URLs.
    static func loadURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }

    /// Zips the files next to the first one and reveals the archive in Finder.
    static func compress(_ urls: [URL]) {
        guard let first = urls.first else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let parent = first.deletingLastPathComponent()
            let base = urls.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
            var dest = parent.appendingPathComponent(base + ".zip")
            var n = 2
            while FileManager.default.fileExists(atPath: dest.path) {
                dest = parent.appendingPathComponent("\(base) \(n).zip")
                n += 1
            }
            let p = Process()
            if urls.count == 1 {
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, dest.path]
            } else {
                // zip relative names from the shared folder (or full paths if they live in different folders)
                p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                let sameFolder = urls.allSatisfy { $0.deletingLastPathComponent() == parent }
                p.currentDirectoryURL = parent
                p.arguments = ["-r", "-q", "-X", dest.path] + urls.map { sameFolder ? $0.lastPathComponent : $0.path }
            }
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async {
                if FileManager.default.fileExists(atPath: dest.path) {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            }
        }
    }

    func applyDemo(_ urls: [URL]) { items = urls.map { Item(url: $0) } }

    private func save() {
        guard !isDemoMode else { return }
        UserDefaults.standard.set(items.map(\.url.path), forKey: key)
    }
}
