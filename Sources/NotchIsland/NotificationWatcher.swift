import AppKit
import SQLite3

struct NotificationItem: Equatable, Identifiable {
    let id: Int64
    let bundleID: String
    let title: String
    let subtitle: String
    let body: String

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var appName: String {
        appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID
    }
    var icon: NSImage? { appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } }
}

/// Mirrors new macOS notifications by watching Notification Center's local database.
/// There's no public API for this; it requires Full Disk Access. Nothing leaves the Mac.
final class NotificationWatcher: ObservableObject {
    @Published private(set) var hasAccess = false
    @Published private(set) var enabled: Bool
    @Published private(set) var mutedApps: Set<String>
    var onNotification: ((NotificationItem) -> Void)?

    private static let dbPath = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    private let queue = DispatchQueue(label: "notchisland.notifications")
    private var db: OpaquePointer? // only touched on `queue`
    private var lastID: Int64 = -1
    private var timer: Timer?
    private var tick = 0

    init() {
        enabled = UserDefaults.standard.object(forKey: "notificationPreviews") as? Bool ?? true
        mutedApps = Set(UserDefaults.standard.stringArray(forKey: "mutedNotificationApps") ?? [])
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "notificationPreviews")
        if on { lastID = -1; poll() }
    }

    func mute(_ bundleID: String) {
        mutedApps.insert(bundleID)
        UserDefaults.standard.set(Array(mutedApps), forKey: "mutedNotificationApps")
    }

    func unmuteAll() {
        mutedApps = []
        UserDefaults.standard.removeObject(forKey: "mutedNotificationApps")
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func poll() {
        guard enabled else { return }
        tick += 1
        if !hasAccess && tick % 6 != 1 { return } // back off to ~9s while we lack permission
        let last = lastID
        queue.async { [weak self] in
            guard let self else { return }
            let result = self.fetch(after: last)
            DispatchQueue.main.async {
                if self.hasAccess != result.ok { self.hasAccess = result.ok }
                guard result.ok else { return }
                if self.lastID < 0 { self.lastID = result.maxID; return } // first read: skip history
                self.lastID = max(self.lastID, result.maxID)
                if let item = result.items.last(where: { !self.mutedApps.contains($0.bundleID) }) {
                    self.onNotification?(item)
                }
            }
        }
    }

    private func fetch(after last: Int64) -> (ok: Bool, items: [NotificationItem], maxID: Int64) {
        let fail = (ok: false, items: [NotificationItem](), maxID: last)
        if db == nil {
            var handle: OpaquePointer?
            guard sqlite3_open_v2(Self.dbPath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                sqlite3_close(handle)
                return fail
            }
            db = handle
        }
        let sql = last < 0
            ? "SELECT IFNULL(MAX(rec_id), 0) FROM record"
            : "SELECT r.rec_id, a.identifier, r.data FROM record r JOIN app a ON a.app_id = r.app_id WHERE r.rec_id > ? ORDER BY r.rec_id LIMIT 20"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            return fail
        }
        defer { sqlite3_finalize(stmt) }

        if last < 0 {
            guard sqlite3_step(stmt) == SQLITE_ROW else { return fail }
            return (true, [], sqlite3_column_int64(stmt, 0))
        }

        sqlite3_bind_int64(stmt, 1, last)
        var items: [NotificationItem] = []
        var maxID = last
        let now = Date().timeIntervalSinceReferenceDate
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { sqlite3_close(db); db = nil; return fail }
            let id = sqlite3_column_int64(stmt, 0)
            maxID = max(maxID, id)
            let bundle = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            guard let bytes = sqlite3_column_blob(stmt, 2) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 2)))
            guard let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
                  let req = plist["req"] as? [String: Any] else { continue }
            if let date = plist["date"] as? Double, now - date > 60 { continue } // stale
            let title = req["titl"] as? String ?? ""
            let subtitle = req["subt"] as? String ?? ""
            let body = req["body"] as? String ?? ""
            if title.isEmpty && body.isEmpty { continue }
            if bundle.caseInsensitiveCompare(Bundle.main.bundleIdentifier ?? "") == .orderedSame { continue }
            items.append(NotificationItem(id: id, bundleID: bundle, title: title, subtitle: subtitle, body: body))
        }
        return (true, items, maxID)
    }
}
