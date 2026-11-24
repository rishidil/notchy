import AppKit
import CoreBluetooth
import IOBluetooth

/// Paired Bluetooth devices, their battery levels, and connect/disconnect.
/// Battery levels come from IOKit (Apple keyboards/mice/trackpads) and system_profiler (AirPods & headphones).
final class BluetoothService: NSObject, ObservableObject {
    enum Kind: Equatable {
        case airpods, airpodsPro, airpodsMax, headphones, speaker, keyboard, mouse, trackpad, phone, controller, computer, other

        var symbol: String {
            switch self {
            case .airpods: "airpods"
            case .airpodsPro: "airpodspro"
            case .airpodsMax: "airpodsmax"
            case .headphones: "headphones"
            case .speaker: "hifispeaker.fill"
            case .keyboard: "keyboard.fill"
            case .mouse: "magicmouse.fill"
            case .trackpad: "hand.point.up.left.fill"
            case .phone: "iphone"
            case .controller: "gamecontroller.fill"
            case .computer: "laptopcomputer"
            case .other: "dot.radiowaves.left.and.right"
            }
        }
    }

    struct Battery: Equatable {
        var main: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        var lowest: Int? { [main, left, right].compactMap { $0 }.min() }
        var isEmpty: Bool { main == nil && left == nil && right == nil && caseLevel == nil }
    }

    struct Device: Identifiable, Equatable {
        let id: String // address, "aa-bb-cc-dd-ee-ff"
        var name: String
        var isConnected: Bool
        var kind: Kind
        var battery: Battery?
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var powerOn = true
    @Published private(set) var busy: Set<String> = []
    /// Fired when a device connects (after its battery level has been read).
    var onConnect: ((Device) -> Void)?

    private var connectNote: IOBluetoothUserNotification?
    private var batteries: [String: Battery] = [:]
    private var timer: Timer?
    private var startedAt = Date.distantFuture
    private(set) var isRunning = false
    private let queue = DispatchQueue(label: "notchisland.bluetooth")

    static var authorization: CBManagerAuthorization { CBManager.authorization }

    func start() {
        guard !isRunning, !isDemoMode else { return }
        isRunning = true
        startedAt = Date()
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        reload()
        refreshBatteries(full: true)
        timer = Timer.every(120) { [weak self] _ in self?.refreshBatteries(full: false) }
    }

    func stop() {
        isRunning = false
        connectNote?.unregister()
        connectNote = nil
        timer?.invalidate()
        timer = nil
    }

    /// Call when the Bluetooth tab is shown, to pick up AirPods battery levels.
    func refreshDetails() {
        guard isRunning else { return }
        reload()
        refreshBatteries(full: true)
    }

    func toggleConnection(_ device: Device) {
        guard !busy.contains(device.id) else { return }
        busy.insert(device.id)
        queue.async { [weak self] in
            if let d = IOBluetoothDevice(addressString: device.id) {
                if d.isConnected() { d.closeConnection() } else { d.openConnection() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self?.busy.remove(device.id)
                self?.reload()
                self?.refreshBatteries(full: true)
            }
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Notifications

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        reload()
        // Registration reports already-connected devices too; only announce genuinely new connections.
        guard Date().timeIntervalSince(startedAt) > 4, let address = device.addressString else { return }
        let id = Self.normalize(address)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.refreshBatteries(full: true) {
                guard let self, let d = self.devices.first(where: { $0.id == id }) else { return }
                self.onConnect?(d)
            }
        }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        reload()
    }

    // MARK: Reading state

    private func reload() {
        powerOn = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        devices = paired.compactMap { d -> Device? in
            guard let address = d.addressString else { return nil }
            let id = Self.normalize(address)
            let name = d.name ?? d.nameOrAddress ?? "Unknown"
            return Device(id: id, name: name, isConnected: d.isConnected(), kind: Self.kind(of: d, name: name),
                          battery: batteries[id])
        }
        .sorted { ($0.isConnected ? 0 : 1, $0.name.lowercased()) < ($1.isConnected ? 0 : 1, $1.name.lowercased()) }
    }

    private func refreshBatteries(full: Bool, then: (() -> Void)? = nil) {
        queue.async { [weak self] in
            var found = Self.ioregBatteries()
            if full {
                for (k, v) in Self.profilerBatteries() { found[k] = v }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (k, v) in found { self.batteries[k] = v }
                self.devices = self.devices.map { var d = $0; d.battery = self.batteries[d.id]; return d }
                then?()
            }
        }
    }

    /// Apple HID devices (Magic Keyboard / Mouse / Trackpad) report BatteryPercent in the IORegistry.
    private static func ioregBatteries() -> [String: Battery] {
        guard let out = Shell.output("/usr/sbin/ioreg", ["-r", "-a", "-k", "BatteryPercent"]),
              let data = out.data(using: .utf8),
              let list = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [[String: Any]]
        else { return [:] }
        var result: [String: Battery] = [:]
        for item in list {
            guard let address = item["DeviceAddress"] as? String, let pct = item["BatteryPercent"] as? Int else { continue }
            result[normalize(address)] = Battery(main: pct)
        }
        return result
    }

    /// AirPods and other headphones only expose battery levels through system_profiler.
    private static func profilerBatteries() -> [String: Battery] {
        guard let out = Shell.output("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
              let data = out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]] else { return [:] }
        func pct(_ v: Any?) -> Int? {
            (v as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) }
        }
        var result: [String: Battery] = [:]
        for section in sections {
            for group in (section["device_connected"] as? [[String: Any]]) ?? [] {
                for (_, value) in group {
                    guard let info = value as? [String: Any], let address = info["device_address"] as? String else { continue }
                    let b = Battery(main: pct(info["device_batteryLevelMain"]), left: pct(info["device_batteryLevelLeft"]),
                                    right: pct(info["device_batteryLevelRight"]), caseLevel: pct(info["device_batteryLevelCase"]))
                    if !b.isEmpty { result[normalize(address)] = b }
                }
            }
        }
        return result
    }

    private static func normalize(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: ":", with: "-")
    }

    private static func kind(of d: IOBluetoothDevice, name: String) -> Kind {
        let n = name.lowercased()
        if n.contains("airpods max") { return .airpodsMax }
        if n.contains("airpods pro") { return .airpodsPro }
        if n.contains("airpods") { return .airpods }
        if n.contains("trackpad") { return .trackpad }
        if n.contains("mouse") { return .mouse }
        if n.contains("keyboard") { return .keyboard }
        if n.contains("controller") || n.contains("dualsense") || n.contains("xbox") { return .controller }
        switch d.deviceClassMajor {
        case 0x01: return .computer
        case 0x02: return .phone
        case 0x04: return d.deviceClassMinor == 0x05 || d.deviceClassMinor == 0x07 ? .speaker : .headphones
        case 0x05:
            let minor = d.deviceClassMinor
            if minor & 0x10 != 0 { return .keyboard }
            if minor & 0x20 != 0 { return .mouse }
            if minor & 0x0F == 0x01 || minor & 0x0F == 0x02 { return .controller }
            return .other
        default: return .other
        }
    }

    func applyDemo() {
        devices = [
            Device(id: "demo-1", name: "AirPods Pro", isConnected: true, kind: .airpodsPro,
                   battery: Battery(left: 84, right: 86, caseLevel: 62)),
            Device(id: "demo-2", name: "Magic Keyboard", isConnected: true, kind: .keyboard, battery: Battery(main: 71)),
            Device(id: "demo-3", name: "Magic Mouse", isConnected: true, kind: .mouse, battery: Battery(main: 38)),
            Device(id: "demo-4", name: "Studio Speaker", isConnected: false, kind: .speaker),
            Device(id: "demo-5", name: "Game Controller", isConnected: false, kind: .controller),
        ]
    }
}
