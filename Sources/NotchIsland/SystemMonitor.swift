import Darwin
import Foundation

/// CPU, memory, network and disk stats. Samples once a second, but only while the System tab is on screen.
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memoryUsed: UInt64 = 0
    @Published private(set) var memoryHistory: [Double] = []
    @Published private(set) var netIn: Double = 0
    @Published private(set) var netOut: Double = 0
    @Published private(set) var netHistory: [Double] = []
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0
    @Published private(set) var thermal: ProcessInfo.ThermalState = .nominal
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    let cpuCores = ProcessInfo.processInfo.activeProcessorCount

    private var timer: Timer?
    private var prevTicks: (busy: UInt64, total: UInt64)?
    private var prevNet: (rx: UInt64, tx: UInt64, at: Date)?
    private let historyLength = 40

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    var diskFraction: Double { diskTotal > 0 ? 1 - Double(diskFree) / Double(diskTotal) : 0 }

    func start() {
        guard timer == nil, !isDemoMode else { return }
        sample()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        prevNet = nil
    }

    private func sample() {
        if let c = Self.cpuTicks() {
            if let p = prevTicks, c.total > p.total {
                cpu = Double(c.busy - p.busy) / Double(c.total - p.total)
                push(&cpuHistory, cpu)
            }
            prevTicks = c
        }
        memoryUsed = Self.memoryUsed()
        push(&memoryHistory, memoryFraction)

        let n = Self.networkBytes()
        let now = Date()
        if let p = prevNet {
            let dt = max(now.timeIntervalSince(p.at), 0.1)
            netIn = n.rx >= p.rx ? Double(n.rx - p.rx) / dt : 0
            netOut = n.tx >= p.tx ? Double(n.tx - p.tx) / dt : 0
            push(&netHistory, netIn + netOut)
        }
        prevNet = (n.rx, n.tx, now)

        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        }
        thermal = ProcessInfo.processInfo.thermalState
    }

    private func push(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > historyLength { arr.removeFirst(arr.count - historyLength) }
    }

    // MARK: Readers

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + sys + nice, user + sys + nice + idle)
    }

    /// Matches Activity Monitor's "Memory Used": app memory + wired + compressed.
    private static func memoryUsed() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.purgeable_count), UInt64(stats.internal_page_count))
        return (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private static func networkBytes() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let name = String(cString: ifa.ifa_name)
                if name.hasPrefix("en") || name.hasPrefix("pdp_ip") { // Wi-Fi, Ethernet, tethering
                    let d = data.assumingMemoryBound(to: if_data.self).pointee
                    rx += UInt64(d.ifi_ibytes)
                    tx += UInt64(d.ifi_obytes)
                }
            }
            ptr = ifa.ifa_next
        }
        return (rx, tx)
    }

    // MARK: Formatting

    static func bytes(_ b: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .memory)
    }

    static func rate(_ b: Double) -> String {
        if b < 1024 { return "\(Int(b)) B/s" }
        if b < 1024 * 1024 { return String(format: "%.0f KB/s", b / 1024) }
        return String(format: "%.1f MB/s", b / 1024 / 1024)
    }

    func applyDemo() {
        cpuHistory = (0..<40).map { (i: Int) -> Double in
            let x = Double(i)
            let wave: Double = 0.1 * sin(x / 3)
            let jitter: Double = Double(i % 7) / 60
            return 0.12 + wave + jitter
        }
        cpu = 0.18
        memoryUsed = UInt64(Double(memoryTotal) * 0.62)
        memoryHistory = (0..<40).map { (i: Int) -> Double in 0.6 + 0.02 * sin(Double(i) / 5) }
        netHistory = (0..<40).map { (i: Int) -> Double in 200_000 + 900_000 * max(0, sin(Double(i) / 4)) }
        netIn = 1_420_000
        netOut = 86_000
        diskTotal = 494_000_000_000
        diskFree = 212_000_000_000
    }
}
