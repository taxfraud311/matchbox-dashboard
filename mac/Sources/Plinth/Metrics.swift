import Foundation
import IOKit
import SystemConfiguration
import Darwin

/// Samples system metrics once per second and keeps a short history for sparklines.
final class MetricsCollector {
    static let shared = MetricsCollector()
    static let historyLength = 90

    private let queue = DispatchQueue(label: "plinth.metrics")
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()

    // previous counters for deltas
    private var prevCPU: [(busy: UInt64, total: UInt64)] = []
    private var prevNet: (rx: UInt64, tx: UInt64, t: TimeInterval)?
    private var prevDisk: (r: UInt64, w: UInt64, t: TimeInterval)?
    private var volumes: [[String: Any]] = []
    private var volumesAt: TimeInterval = 0

    private var latest: [String: Any] = [:]
    private var history: [String: [Double]] = ["cpu": [], "gpu": [], "mem": [], "rx": [], "tx": [], "dr": [], "dw": []]

    private var primaryIface = "en0"
    private var primaryIfaceName = "Ethernet"
    private var ifaceCheckedAt: TimeInterval = 0

    // speed test
    private var speedTest: [String: Any] = [:]
    private var speedTestRunning = false
    private var lastSpeedTestStart: Date?
    private var firstSpeedTestAfter = Date.distantFuture

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 1.0, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.sample() }
        t.resume()
        timer = t
        // First speed test a minute after launch so it doesn't compete with startup.
        firstSpeedTestAfter = Date().addingTimeInterval(60)
    }

    var snapshot: (latest: [String: Any], history: [String: [Double]]) {
        lock.lock(); defer { lock.unlock() }
        return (latest, history)
    }

    // MARK: - Sampling

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        var m: [String: Any] = [:]

        let (cpuTotal, cores) = sampleCPU()
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        m["cpu"] = ["usage": cpuTotal, "cores": cores, "load": load[0], "coreCount": cores.count]

        let mem = sampleMemory()
        m["mem"] = mem

        let gpu = sampleGPU()
        m["gpu"] = gpu

        var disk = sampleDiskCapacity()
        let (dr, dw) = sampleDiskIO()
        var drRate = 0.0, dwRate = 0.0
        if let p = prevDisk, now > p.t {
            drRate = Double(dr &- p.r) / (now - p.t)
            dwRate = Double(dw &- p.w) / (now - p.t)
            if dr < p.r { drRate = 0 }
            if dw < p.w { dwRate = 0 }
        }
        prevDisk = (dr, dw, now)
        disk["readBps"] = drRate
        disk["writeBps"] = dwRate
        if now - volumesAt > 10 { volumes = DiskScanner.capacities(); volumesAt = now }
        disk["volumes"] = volumes
        m["disk"] = disk

        if now - ifaceCheckedAt > 15 { refreshPrimaryInterface(); ifaceCheckedAt = now }
        let (rx, tx) = sampleNet(iface: primaryIface)
        var rxRate = 0.0, txRate = 0.0
        if let p = prevNet, now > p.t, rx >= p.rx, tx >= p.tx {
            rxRate = Double(rx - p.rx) * 8 / (now - p.t)   // bits/s
            txRate = Double(tx - p.tx) * 8 / (now - p.t)
        }
        prevNet = (rx, tx, now)

        lock.lock()
        let st = speedTest
        let running = speedTestRunning
        lock.unlock()
        m["net"] = ["iface": primaryIface, "ifaceName": primaryIfaceName,
                    "rxBps": rxRate, "txBps": txRate,
                    "speedTest": st, "speedTestRunning": running]

        m["uptime"] = ProcessInfo.processInfo.systemUptime
        m["thermal"] = ["nominal", "fair", "serious", "critical"][min(3, ProcessInfo.processInfo.thermalState.rawValue)]
        m["t"] = Date().timeIntervalSince1970 * 1000

        lock.lock()
        latest = m
        push("cpu", cpuTotal)
        push("gpu", (gpu["usage"] as? Double) ?? 0)
        push("mem", (mem["percent"] as? Double) ?? 0)
        push("rx", rxRate)
        push("tx", txRate)
        push("dr", drRate)
        push("dw", dwRate)
        lock.unlock()

        maybeRunSpeedTest()
    }

    private func push(_ key: String, _ v: Double) {
        var arr = history[key] ?? []
        arr.append(v.isFinite ? v : 0)
        if arr.count > Self.historyLength { arr.removeFirst(arr.count - Self.historyLength) }
        history[key] = arr
    }

    // MARK: CPU

    private func sampleCPU() -> (Double, [Double]) {
        var numCPU: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &info, &count) == KERN_SUCCESS,
              let info else { return (0, []) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(Int(count) * MemoryLayout<integer_t>.stride))
        }
        var cur: [(UInt64, UInt64)] = []
        for i in 0..<Int(numCPU) {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let sys = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            cur.append((user + sys + nice, user + sys + nice + idle))
        }
        var cores: [Double] = []
        var busySum: UInt64 = 0, totalSum: UInt64 = 0
        if prevCPU.count == cur.count {
            for (i, c) in cur.enumerated() {
                let db = c.0 &- prevCPU[i].busy, dt = c.1 &- prevCPU[i].total
                cores.append(dt > 0 && dt < UInt64(UInt32.max) ? Double(db) / Double(dt) * 100 : 0)
                if dt < UInt64(UInt32.max) { busySum += db; totalSum += dt }
            }
        } else {
            cores = Array(repeating: 0, count: cur.count)
        }
        prevCPU = cur.map { (busy: $0.0, total: $0.1) }
        let total = totalSum > 0 ? Double(busySum) / Double(totalSum) * 100 : 0
        return (total, cores)
    }

    // MARK: Memory

    private func sampleMemory() -> [String: Any] {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard r == KERN_SUCCESS else { return ["total": total, "used": 0, "percent": 0] }
        let page = Double(vm_kernel_page_size)
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let wired = Double(stats.wire_count)
        let compressed = Double(stats.compressor_page_count)
        let used = (app + wired + compressed) * page
        let cached = (Double(stats.external_page_count) + Double(stats.purgeable_count)) * page

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &size, nil, 0)

        var pressure: Int32 = 1
        var psize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &psize, nil, 0)

        return ["total": total, "used": used, "percent": min(100, used / total * 100),
                "wired": wired * page, "compressed": compressed * page, "cached": cached,
                "swapUsed": Double(swap.xsu_used),
                "pressure": pressure >= 4 ? "critical" : (pressure >= 2 ? "warn" : "normal")]
    }

    // MARK: GPU

    private func sampleGPU() -> [String: Any] {
        var util = 0.0, memUsed = 0.0, renderer = 0.0
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS
        else { return ["usage": 0] }
        defer { IOObjectRelease(iter) }
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            if let cf = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0),
               let perf = cf.takeRetainedValue() as? [String: Any] {
                if let u = perf["Device Utilization %"] as? NSNumber { util = max(util, u.doubleValue) }
                if let r = perf["Renderer Utilization %"] as? NSNumber { renderer = max(renderer, r.doubleValue) }
                if let m = perf["In use system memory"] as? NSNumber { memUsed = max(memUsed, m.doubleValue) }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return ["usage": util, "renderer": renderer, "memUsed": memUsed]
    }

    // MARK: Disk

    private func sampleDiskCapacity() -> [String: Any] {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeNameKey]
        guard let v = try? url.resourceValues(forKeys: keys), let total = v.volumeTotalCapacity else {
            return ["total": 0, "free": 0, "percent": 0]
        }
        let free = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
        let t = Double(total)
        return ["name": v.volumeName ?? "Macintosh HD", "total": t, "free": free,
                "used": t - free, "percent": t > 0 ? (t - free) / t * 100 : 0]
    }

    private func sampleDiskIO() -> (UInt64, UInt64) {
        var r: UInt64 = 0, w: UInt64 = 0
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS
        else { return (0, 0) }
        defer { IOObjectRelease(iter) }
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            if let cf = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0),
               let st = cf.takeRetainedValue() as? [String: Any] {
                r += (st["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                w += (st["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return (r, w)
    }

    // MARK: Network

    private func refreshPrimaryInterface() {
        guard let store = SCDynamicStoreCreate(nil, "Plinth" as CFString, nil, nil),
              let v = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let iface = v["PrimaryInterface"] as? String else { return }
        primaryIface = iface
        primaryIfaceName = iface
        if let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] {
            for i in all where (SCNetworkInterfaceGetBSDName(i) as String?) == iface {
                if let n = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? { primaryIfaceName = n }
            }
        }
    }

    private func sampleNet(iface: String) -> (UInt64, UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return (0, 0) }
        let want = if_nametoindex(iface)
        var rx: UInt64 = 0, tx: UInt64 = 0
        buf.withUnsafeBytes { raw in
            var off = 0
            while off + MemoryLayout<if_msghdr>.size <= len {
                let hdr = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr.self)
                if hdr.ifm_msglen == 0 { break }
                if Int32(hdr.ifm_type) == RTM_IFINFO2, off + MemoryLayout<if_msghdr2>.size <= len {
                    let h2 = raw.loadUnaligned(fromByteOffset: off, as: if_msghdr2.self)
                    if UInt32(h2.ifm_index) == want {
                        rx = h2.ifm_data.ifi_ibytes
                        tx = h2.ifm_data.ifi_obytes
                    }
                }
                off += Int(hdr.ifm_msglen)
            }
        }
        return (rx, tx)
    }

    // MARK: Speed test (macOS networkQuality)

    private func maybeRunSpeedTest() {
        let cfg = ConfigStore.shared
        guard cfg.bool("speedTest.enabled", true) else { return }
        let interval = TimeInterval(max(15, cfg.int("speedTest.intervalMinutes", 60)) * 60)
        lock.lock(); let running = speedTestRunning; lock.unlock()
        if running || Date() < firstSpeedTestAfter { return }
        if let last = lastSpeedTestStart, Date().timeIntervalSince(last) < interval { return }
        runSpeedTest()
    }

    func runSpeedTest() {
        lock.lock()
        if speedTestRunning { lock.unlock(); return }
        speedTestRunning = true
        lock.unlock()
        lastSpeedTestStart = Date()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let out = Shell.run("/usr/bin/networkQuality", ["-c"], timeout: 90)
            var result: [String: Any] = [:]
            if let data = out.stdout.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                result["down"] = (j["dl_throughput"] as? NSNumber)?.doubleValue ?? 0
                result["up"] = (j["ul_throughput"] as? NSNumber)?.doubleValue ?? 0
                result["rpm"] = (j["responsiveness"] as? NSNumber)?.doubleValue
                    ?? (j["dl_responsiveness"] as? NSNumber)?.doubleValue ?? 0
                result["rtt"] = (j["base_rtt"] as? NSNumber)?.doubleValue ?? 0
                result["iface"] = j["interface_name"] as? String ?? ""
                result["at"] = Date().timeIntervalSince1970 * 1000
            } else {
                result["error"] = out.stderr.isEmpty ? "networkQuality failed" : out.stderr
                result["at"] = Date().timeIntervalSince1970 * 1000
            }
            guard let self else { return }
            self.lock.lock()
            // keep the last good numbers if this run failed
            if result["error"] != nil, self.speedTest["down"] != nil {
                self.speedTest["error"] = result["error"]
            } else {
                self.speedTest = result
            }
            self.speedTestRunning = false
            self.lock.unlock()
        }
    }
}

/// Minimal process runner with timeout.
enum Shell {
    struct Result { var status: Int32; var stdout: String; var stderr: String }

    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 15) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return Result(status: -1, stdout: "", stderr: error.localizedDescription) }
        // Drain pipes concurrently to avoid deadlock on large output.
        var outData = Data(), errData = Data()
        let g = DispatchGroup()
        g.enter(); DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        g.enter(); DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); g.leave() }
        let deadline = DispatchTime.now() + timeout
        if g.wait(timeout: deadline) == .timedOut {
            p.terminate()
            _ = g.wait(timeout: .now() + 2)
        }
        p.waitUntilExit()
        return Result(status: p.terminationStatus,
                      stdout: String(decoding: outData, as: UTF8.self),
                      stderr: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
