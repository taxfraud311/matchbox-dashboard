import AppKit
import IOKit
import SystemConfiguration
import Darwin

/// On-demand detail for the tablet's expanded metric panels: top apps by CPU / memory / disk / network,
/// volumes, GPU info, network interface info. Apps are grouped like Activity Monitor's app view
/// (all helper processes of "Google Chrome.app" count as Google Chrome).
final class DetailService {
    static let shared = DetailService()

    private let lock = NSLock()
    private var iconPaths: [String: String] = [:]          // app name -> bundle path (for /api/appicon)
    private var iconCache: [String: Data] = [:]
    private var prevDisk: [Int32: (r: UInt64, w: UInt64)] = [:]
    private var prevDiskAt: TimeInterval = 0
    private var netApps: [[String: Any]] = []
    private var netLastRequest = Date.distantPast
    private var netRunning = false

    // MARK: Process list

    struct Proc { var pid: Int32; var cpu: Double; var rss: Double; var path: String }

    private func processes() -> [Proc] {
        let out = Shell.run("/bin/ps", ["-Ao", "pid=,pcpu=,rss=,comm="], timeout: 5).stdout
        var list: [Proc] = []
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]) else { continue }
            list.append(Proc(pid: pid, cpu: Double(parts[1]) ?? 0, rss: (Double(parts[2]) ?? 0) * 1024, path: String(parts[3])))
        }
        return list
    }

    /// "…/Google Chrome.app/Contents/…/Google Chrome Helper" → ("Google Chrome", "…/Google Chrome.app")
    private func appIdentity(_ path: String) -> (name: String, bundle: String?) {
        if let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app") : nil) {
            let bundle = String(path[..<r.upperBound]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let bundlePath = bundle.hasPrefix("/") ? bundle : "/" + bundle
            return ((bundlePath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: ""), bundlePath)
        }
        return ((path as NSString).lastPathComponent, nil)
    }

    private func group(_ items: [(path: String, value: Double)], top: Int) -> [[String: Any]] {
        var sums: [String: (v: Double, n: Int, bundle: String?)] = [:]
        for it in items where it.value > 0 {
            let id = appIdentity(it.path)
            var cur = sums[id.name] ?? (0, 0, id.bundle)
            cur.v += it.value; cur.n += 1
            if cur.bundle == nil { cur.bundle = id.bundle }
            sums[id.name] = cur
        }
        lock.lock()
        for (name, s) in sums { if let b = s.bundle { iconPaths[name] = b } }
        lock.unlock()
        return sums.sorted { $0.value.v > $1.value.v }.prefix(top).map { name, s in
            ["name": name, "value": s.v, "count": s.n, "icon": s.bundle != nil]
        }
    }

    // MARK: Detail by kind

    func detail(_ kind: String) -> [String: Any] {
        switch kind {
        case "cpu": return cpu()
        case "mem": return mem()
        case "gpu": return gpu()
        case "disk": return disk()
        case "net": return net()
        default: return ["error": "unknown"]
        }
    }

    private func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
    private func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : nil
    }

    private func cpu() -> [String: Any] {
        let procs = processes()
        var load = [Double](repeating: 0, count: 3)
        getloadavg(&load, 3)
        var levels: [[String: Any]] = []
        for i in 0..<4 {
            guard let n = sysctlInt("hw.perflevel\(i).logicalcpu") else { break }
            levels.append(["name": sysctlString("hw.perflevel\(i).name") ?? "Level \(i)", "cores": n])
        }
        return [
            "chip": sysctlString("machdep.cpu.brand_string") ?? "Apple silicon",
            "load": load, "levels": levels,
            "processCount": procs.count,
            "apps": group(procs.map { ($0.path, $0.cpu) }, top: 8),
        ]
    }

    private func mem() -> [String: Any] {
        let procs = processes()
        var byPid: [Int32: String] = [:]
        for p in procs { byPid[p.pid] = p.path }
        // `top` reports each process's memory footprint (what Activity Monitor calls "Memory").
        let out = Shell.run("/usr/bin/top", ["-l", "1", "-o", "mem", "-n", "60", "-stats", "pid,mem"], timeout: 8).stdout
        var items: [(String, Double)] = []
        var inTable = false
        for line in out.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true)
            if cols.first == "PID" { inTable = true; continue }
            guard inTable, cols.count >= 2, let pid = Int32(cols[0]), let path = byPid[pid] else { continue }
            items.append((path, Self.parseSize(String(cols[1]))))
        }
        if items.isEmpty { items = procs.map { ($0.path, $0.rss) } }
        return ["apps": group(items, top: 8), "processCount": procs.count]
    }

    static func parseSize(_ s: String) -> Double {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard let unit = t.last, let v = Double(t.dropLast()) else { return Double(t) ?? 0 }
        switch unit { case "K": return v * 1024; case "M": return v * 1_048_576; case "G": return v * 1_073_741_824; case "B": return v
        default: return Double(t) ?? 0 }
    }

    private lazy var gpuInfo: [String: Any] = {
        var info: [String: Any] = [:]
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS {
            let e = IOIteratorNext(iter)
            if e != 0 {
                if let c = IORegistryEntryCreateCFProperty(e, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
                    info["cores"] = c.intValue
                }
                if let m = IORegistryEntryCreateCFProperty(e, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                    if let s = m as? String { info["model"] = s }
                    else if let d = m as? Data { info["model"] = String(decoding: d, as: UTF8.self).trimmingCharacters(in: .controlCharacters) }
                }
                IOObjectRelease(e)
            }
            IOObjectRelease(iter)
        }
        return info
    }()

    private func gpu() -> [String: Any] {
        var out = gpuInfo
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS {
            var e = IOIteratorNext(iter)
            while e != 0 {
                if let perf = IORegistryEntryCreateCFProperty(e, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] {
                    out["renderer"] = perf["Renderer Utilization %"] ?? 0
                    out["tiler"] = perf["Tiler Utilization %"] ?? 0
                    out["device"] = perf["Device Utilization %"] ?? 0
                    out["memUsed"] = perf["In use system memory"] ?? 0
                    out["memAlloc"] = perf["Alloc system memory"] ?? 0
                }
                IOObjectRelease(e); e = IOIteratorNext(iter)
            }
            IOObjectRelease(iter)
        }
        out["chip"] = sysctlString("machdep.cpu.brand_string") ?? "Apple silicon"
        return out
    }

    private func disk() -> [String: Any] {
        // Volumes
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsRootFileSystemKey]
        var vols: [[String: Any]] = []
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [] {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), let total = v.volumeTotalCapacity, total > 0 else { continue }
            let free = Double(max(v.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v.volumeAvailableCapacity ?? 0)))
            vols.append(["name": v.volumeName ?? url.lastPathComponent, "total": Double(total), "free": free,
                         "internal": v.volumeIsInternal ?? false, "root": v.volumeIsRootFileSystem ?? false])
        }
        vols.sort { (($0["root"] as? Bool) == true ? 0 : 1) < (($1["root"] as? Bool) == true ? 0 : 1) }

        // Per-app disk activity since the previous request (only your own processes are readable).
        let procs = processes()
        let now = ProcessInfo.processInfo.systemUptime
        var cur: [Int32: (UInt64, UInt64)] = [:]
        var items: [(String, Double)] = []
        lock.lock(); let prev = prevDisk; let dt = now - prevDiskAt; lock.unlock()
        for p in procs {
            var info = rusage_info_v4()
            let ok = withUnsafeMutablePointer(to: &info) { ptr in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(p.pid, RUSAGE_INFO_V4, $0) }
            }
            guard ok == 0 else { continue }
            cur[p.pid] = (info.ri_diskio_bytesread, info.ri_diskio_byteswritten)
            if let old = prev[p.pid], dt > 0.3, dt < 30 {
                let bytes = Double(info.ri_diskio_bytesread &- old.r) + Double(info.ri_diskio_byteswritten &- old.w)
                if bytes > 0, bytes < 1e12 { items.append((p.path, bytes / dt)) }
            }
        }
        lock.lock(); prevDisk = cur.mapValues { (r: $0.0, w: $0.1) }; prevDiskAt = now; lock.unlock()
        return ["volumes": vols, "apps": group(items, top: 6), "ready": dt > 0.3 && dt < 30]
    }

    private func net() -> [String: Any] {
        lock.lock()
        netLastRequest = Date()
        let apps = netApps
        let start = !netRunning
        if start { netRunning = true }
        lock.unlock()
        if start { DispatchQueue.global(qos: .utility).async { [weak self] in self?.netLoop() } }

        var info: [String: Any] = ["apps": apps]
        if let store = SCDynamicStoreCreate(nil, "Plinth" as CFString, nil, nil),
           let g = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
            info["router"] = g["Router"] ?? NSNull()
            if let iface = g["PrimaryInterface"] as? String {
                info["iface"] = iface
                if let a = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(iface)/IPv4" as CFString) as? [String: Any] {
                    info["ip"] = (a["Addresses"] as? [String])?.first ?? NSNull()
                }
            }
            if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
                info["dns"] = (dns["ServerAddresses"] as? [String])?.prefix(2).joined(separator: ", ") ?? NSNull()
            }
        }
        return info
    }

    /// Samples per-app network traffic with `nettop` while a network panel is open (stops 15 s after the last request).
    private func netLoop() {
        while true {
            lock.lock()
            let idle = Date().timeIntervalSince(netLastRequest) > 15
            if idle { netRunning = false; netApps = []; lock.unlock(); return }
            lock.unlock()

            var byPid: [Int32: String] = [:]
            for p in processes() { byPid[p.pid] = p.path }
            let out = Shell.run("/usr/bin/nettop", ["-P", "-d", "-L", "2", "-s", "1", "-J", "bytes_in,bytes_out", "-x"], timeout: 10).stdout
            let lines = out.split(separator: "\n").map(String.init)
            // Second sample (deltas) follows the last header line.
            let lastHeader = lines.lastIndex { $0.contains("bytes_in") } ?? -1
            var down: [(String, Double)] = [], up: [(String, Double)] = []
            var rx: [String: Double] = [:], tx: [String: Double] = [:]
            for line in lines.dropFirst(lastHeader + 1) {
                let c = line.split(separator: ",", omittingEmptySubsequences: false)
                guard c.count >= 3, let dot = c[0].lastIndex(of: "."), let pid = Int32(c[0][c[0].index(after: dot)...]) else { continue }
                let path = byPid[pid] ?? String(c[0][..<dot])
                down.append((path, Double(c[1]) ?? 0)); up.append((path, Double(c[2]) ?? 0))
            }
            for g in group(down, top: 50) { rx[g["name"] as! String] = g["value"] as? Double }
            for g in group(up, top: 50) { tx[g["name"] as! String] = g["value"] as? Double }
            let names = Set(rx.keys).union(tx.keys)
            let combined: [[String: Any]] = names.map { n in
                ["name": n, "rx": (rx[n] ?? 0) * 8, "tx": (tx[n] ?? 0) * 8, "icon": iconPathFor(n) != nil] as [String: Any]
            }.sorted { (($0["rx"] as! Double) + ($0["tx"] as! Double)) > (($1["rx"] as! Double) + ($1["tx"] as! Double)) }
            lock.lock(); netApps = Array(combined.prefix(6)); lock.unlock()
        }
    }

    private func iconPathFor(_ name: String) -> String? { lock.lock(); defer { lock.unlock() }; return iconPaths[name] }

    // MARK: App icons

    /// 96 px PNG of an app's icon, only for apps that appeared in a detail list (no arbitrary file access).
    func iconPNG(for name: String) -> Data? {
        lock.lock()
        if let d = iconCache[name] { lock.unlock(); return d }
        let path = iconPaths[name]
        lock.unlock()
        guard let path else { return nil }
        var data: Data?
        DispatchQueue.main.sync {
            let img = NSWorkspace.shared.icon(forFile: path)
            let size = NSSize(width: 96, height: 96)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96, bitsPerSample: 8, samplesPerPixel: 4,
                                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(origin: .zero, size: size))
            NSGraphicsContext.restoreGraphicsState()
            data = rep.representation(using: .png, properties: [:])
        }
        if let data { lock.lock(); iconCache[name] = data; lock.unlock() }
        return data
    }
}
