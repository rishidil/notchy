import AppKit
import Security

/// In-app updates from GitHub Releases. Checks the latest release, downloads Notchy.zip, verifies that the new app
/// is signed by the same certificate as this one, then swaps it in place and relaunches.
final class UpdateService: ObservableObject {
    struct Release: Equatable {
        let version: String
        let notes: String
        let zipURL: URL
        let pageURL: URL
    }

    enum State: Equatable {
        case idle, checking, upToDate, available, downloading(Double), installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var latest: Release?
    @Published private(set) var lastChecked: Date?
    @Published var autoCheck = UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCheck, forKey: "autoCheckUpdates"); schedule() }
    }

    /// Fired once per newly found version (to show a pop-up in the notch).
    var onUpdateAvailable: ((Release) -> Void)?

    static let repo = "rishidil/notchy"
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private var timer: Timer?
    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    init() {
        guard !isDemoMode else { return }
        schedule()
        // First check shortly after launch, without slowing startup.
        if autoCheck {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.check(userInitiated: false) }
        }
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard autoCheck else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 12 * 3600, repeats: true) { [weak self] _ in self?.check(userInitiated: false) }
    }

    // MARK: Check

    func check(userInitiated: Bool) {
        if case .downloading = state { return }
        if state == .installing || state == .checking { return }
        state = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Notchy/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            let release = data.flatMap(Self.parse)
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastChecked = Date()
                guard let release else {
                    self.state = userInitiated ? .failed(error == nil ? "Couldn't read the latest release" : "You're offline") : .idle
                    return
                }
                if Self.compare(release.version, self.currentVersion) > 0 {
                    let isNew = self.latest?.version != release.version
                    self.latest = release
                    self.state = .available
                    if self.installWhenFound { self.installWhenFound = false; self.installUpdate(); return }
                    let announced = UserDefaults.standard.string(forKey: "announcedUpdateVersion")
                    if isNew && (userInitiated || announced != release.version) {
                        UserDefaults.standard.set(release.version, forKey: "announcedUpdateVersion")
                        if !userInitiated { self.onUpdateAvailable?(release) }
                    }
                } else {
                    self.latest = nil
                    self.state = .upToDate
                }
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> Release? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let page = (obj["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = obj["assets"] as? [[String: Any]],
              let zip = assets.first(where: { ($0["name"] as? String) == "Notchy.zip" }),
              let zipURL = (zip["browser_download_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, notes: obj["body"] as? String ?? "", zipURL: zipURL, pageURL: page)
    }

    /// Numeric version comparison ("1.10" > "1.9"). Returns >0 if a is newer.
    static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x - y }
        }
        return 0
    }

    // MARK: Install

    func installUpdate() {
        guard let release = latest else { return }
        let appURL = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            state = .failed("Can't write to \(appURL.deletingLastPathComponent().path). Download it from GitHub instead.")
            return
        }
        state = .downloading(0)
        let task = URLSession.shared.downloadTask(with: release.zipURL) { [weak self] tmp, response, error in
            guard let self else { return }
            guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                DispatchQueue.main.async { self.state = .failed(error == nil ? "Download failed" : "You're offline") }
                return
            }
            self.unpackAndInstall(zip: tmp, replacing: appURL)
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async {
                if case .downloading = self?.state { self?.state = .downloading(p.fractionCompleted) }
            }
        }
        downloadTask = task
        task.resume()
    }

    private func unpackAndInstall(zip tmp: URL, replacing appURL: URL) {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("NotchyUpdate-\(UUID().uuidString)", isDirectory: true)
        func fail(_ msg: String) {
            try? fm.removeItem(at: work)
            DispatchQueue.main.async { self.state = .failed(msg) }
        }
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("Notchy.zip")
            try fm.moveItem(at: tmp, to: zip)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zip.path, work.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else { return fail("Couldn't unpack the update") }
        } catch {
            return fail("Couldn't prepare the update")
        }
        guard let newApp = (try? fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil))?
            .first(where: { $0.pathExtension == "app" }) else { return fail("The update didn't contain an app") }

        // Only install an app signed by the same certificate as this one.
        guard Self.isSignedLikeMe(newApp) else { return fail("The update's signature didn't match. Not installed.") }

        DispatchQueue.main.async {
            self.state = .installing
            Self.swapAndRelaunch(newApp: newApp, replacing: appURL, cleanup: work)
        }
    }

    /// True if `url` satisfies this running app's designated requirement (same bundle id and signing certificate).
    static func isSignedLikeMe(_ url: URL) -> Bool {
        var me: SecCode?
        var meStatic: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &requirement) == errSecSuccess, let requirement else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement) == errSecSuccess
    }

    /// Waits for this process to quit, swaps the bundles, and opens the new version.
    private static func swapAndRelaunch(newApp: URL, replacing appURL: URL, cleanup: URL) {
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        OLD="$1.old-$$"
        mv "$1" "$OLD" && mv "$2" "$1" && rm -rf "$OLD"
        [ -d "$1" ] || mv "$OLD" "$1"
        xattr -dr com.apple.quarantine "$1" 2>/dev/null
        rm -rf "$3"
        open "$1"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "notchy-update", appURL.path, newApp.path, cleanup.path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            NSWorkspace.shared.activateFileViewerSelecting([newApp])
            return
        }
        NSApp.terminate(nil)
    }

    /// Checks, and installs straight away if there's a newer version (notchy://update?install=1).
    func checkAndInstall() {
        installWhenFound = true
        check(userInitiated: true)
    }
    private var installWhenFound = false

    func openReleasePage() {
        NSWorkspace.shared.open(latest?.pageURL ?? URL(string: "https://github.com/\(Self.repo)/releases/latest")!)
    }
}
