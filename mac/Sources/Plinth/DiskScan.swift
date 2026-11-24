import Foundation
import Darwin

/// What's taking up space: a background walk of a volume (fts, allocated sizes) kept as a pruned tree,
/// served a few levels at a time to the tablet's list + treemap view.
final class DiskScanner {
    static let shared = DiskScanner()

    final class Node {
        let name: String
        var size: Int64 = 0
        var files: Int = 0
        var isDir: Bool
        var children: [Node] = []
        var otherSize: Int64 = 0       // children too small to keep, summed
        var otherCount: Int = 0
        init(name: String, isDir: Bool) { self.name = name; self.isDir = isDir }
    }

    struct Volume { let id: String; let name: String; let mount: String; let scanRoot: String; let total: Int64; let free: Int64; let root: Bool }

    private final class Scan {
        var running = true
        var scanned: Int64 = 0
        var files = 0
        var started = Date()
        var finished: Date?
        var tree: Node?
        var used: Int64 = 0
        var cancelled = false
        var denied = 0
    }

    private let lock = NSLock()
    private var scans: [String: Scan] = [:]
    private let queue = DispatchQueue(label: "plinth.diskscan", qos: .utility)

    // MARK: Volumes

    static func volumes() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeIsRootFileSystemKey, .volumeIsReadOnlyKey, .volumeIsBrowsableKey]
        var out: [Volume] = []
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? [] {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), let total = v.volumeTotalCapacity, total > 0 else { continue }
            let root = v.volumeIsRootFileSystem ?? (url.path == "/")
            if !root && (v.volumeIsReadOnly ?? false) { continue }       // mounted installers / disk images
            if v.volumeIsBrowsable == false { continue }
            let free = max(v.volumeAvailableCapacityForImportantUsage ?? 0, Int64(v.volumeAvailableCapacity ?? 0))
            // On the boot disk everything you own lives on the Data volume (the system volume is sealed).
            let scanRoot = root && FileManager.default.fileExists(atPath: "/System/Volumes/Data/Users") ? "/System/Volumes/Data" : url.path
            out.append(Volume(id: url.path, name: v.volumeName ?? url.lastPathComponent, mount: url.path, scanRoot: scanRoot,
                              total: Int64(total), free: free, root: root))
        }
        return out.sorted { ($0.root ? 0 : 1, $0.name) < ($1.root ? 0 : 1, $1.name) }
    }

    /// Capacity of every volume for the rotating Disk tile.
    static func capacities() -> [[String: Any]] {
        volumes().map { v in
            let used = Double(max(0, v.total - v.free)), t = Double(v.total)
            return ["name": v.name, "total": t, "free": Double(v.free), "used": used, "percent": t > 0 ? used / t * 100 : 0, "root": v.root]
        }
    }

    // MARK: API

    func status(volume id: String?, path: String, rescan: Bool) -> [String: Any] {
        let vols = DiskScanner.volumes()
        guard let vol = vols.first(where: { $0.id == id }) ?? vols.first else { return ["error": "No volumes"] }
        lock.lock()
        var scan = scans[vol.id]
        let stale = scan.map { !$0.running && Date().timeIntervalSince($0.finished ?? .distantPast) > 6 * 3600 } ?? true
        if scan == nil || (rescan && scan?.running == false) || (stale && scan?.running == false) {
            let s = Scan(); s.used = max(1, vol.total - vol.free)
            s.tree = (scan?.tree)            // keep showing the previous result while rescanning
            if let old = scan { s.finished = old.finished }
            scans[vol.id] = s; scan = s
            lock.unlock()
            start(s, vol)
        } else { lock.unlock() }
        guard let s = scan else { return [:] }

        lock.lock()
        var out: [String: Any] = [
            "volumes": vols.map { ["id": $0.id, "name": $0.name, "total": Double($0.total), "used": Double(max(0, $0.total - $0.free)), "root": $0.root] },
            "volume": vol.id, "running": s.running, "scanned": Double(s.scanned), "files": s.files,
            "used": Double(s.used), "fullDiskAccess": DiskScanner.hasFullDiskAccess(), "denied": s.denied,
        ]
        if let f = s.finished { out["at"] = f.timeIntervalSince1970 * 1000 }
        let tree = s.tree
        lock.unlock()

        if let tree {
            // Walk to the requested sub-path.
            var node = tree, trail: [String] = []
            for part in path.split(separator: "/").map(String.init) where !part.isEmpty {
                guard let next = node.children.first(where: { $0.name == part && $0.isDir }) else { break }
                node = next; trail.append(part)
            }
            out["path"] = trail
            out["node"] = DiskScanner.export(node, depth: 3, minFrac: 0.0025, top: node.size)
            if trail.isEmpty {
                // Space the walk couldn't see: snapshots, purgeable caches, system files, protected folders.
                out["unseen"] = Double(max(0, s.used - tree.size))
            }
        }
        return out
    }

    private static func export(_ n: Node, depth: Int, minFrac: Double, top: Int64) -> [String: Any] {
        var o: [String: Any] = ["n": n.name, "s": Double(n.size), "d": n.isDir]
        if n.isDir { o["f"] = n.files }
        guard depth > 0, n.isDir else { return o }
        let cut = Int64(Double(top) * minFrac)
        var kids: [[String: Any]] = []
        var restSize = n.otherSize, restCount = n.otherCount
        for (i, c) in n.children.enumerated() {
            if c.size >= cut && i < 80 { kids.append(export(c, depth: depth - 1, minFrac: minFrac, top: top)) }
            else { restSize += c.size; restCount += 1 }
        }
        if restSize > 0 { kids.append(["n": "\(restCount) smaller item\(restCount == 1 ? "" : "s")", "s": Double(restSize), "d": false, "o": true]) }
        o["c"] = kids
        return o
    }

    // MARK: Scanning

    /// Without Full Disk Access, walking other apps' containers makes macOS ask once per app, so leave those out.
    private static let tccSensitive = ["/Library/Containers", "/Library/Group Containers", "/Library/Daemon Containers",
                                       "/Library/Mail", "/Library/Messages", "/Library/Safari", "/Library/Metadata/CoreSpotlight",
                                       "/Library/Application Support/AddressBook", "/Library/Calendars", "/Library/Reminders",
                                       "/Library/HomeKit", "/Library/IdentityServices", "/Library/Suggestions", "/Library/Cookies",
                                       "/Library/Application Support/CallHistoryDB", "/Library/Application Support/com.apple.TCC",
                                       "/Library/Biome", "/Library/Accounts", "/Library/Sharing", "/Library/Trial",
                                       "/Library/Application Support/FileProvider", "/Library/CloudStorage", "/Library/Mobile Documents",
                                       "/Pictures/Photos Library.photoslibrary"]

    private static func name(_ ent: UnsafeMutablePointer<FTSENT>) -> String {
        let p = String(cString: ent.pointee.fts_path)
        return p.split(separator: "/").last.map(String.init) ?? p
    }

    static func hasFullDiskAccess() -> Bool {
        let probe = NSHomeDirectory() + "/Library/Safari"
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    private func start(_ s: Scan, _ vol: Volume) {
        queue.async {
            let fda = DiskScanner.hasFullDiskAccess()
            let root = Node(name: vol.name, isDir: true)
            var stack: [Node] = [root]
            let keepMin = max(Int64(1 << 20), s.used / 40000)      // nodes smaller than this are summed into their parent
            var seenInodes = Set<UInt64>()
            func fold() {
                let done = stack.removeLast(), parent = stack[stack.count - 1]
                done.children.sort { $0.size > $1.size }
                parent.size += done.size; parent.files += done.files
                if done.size >= keepMin { parent.children.append(done) }
                else { parent.otherSize += done.size; parent.otherCount += 1 }
            }

            vol.scanRoot.withCString { cpath in
                var paths: [UnsafeMutablePointer<CChar>?] = [strdup(cpath), nil]
                defer { free(paths[0]) }
                guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, nil) else { return }
                defer { fts_close(fts) }
                while let ent = fts_read(fts) {
                    let info = Int32(ent.pointee.fts_info)
                    let level = Int(ent.pointee.fts_level)
                    switch info {
                    case FTS_D:
                        if level == 0 { continue }
                        let path = String(cString: ent.pointee.fts_path)
                        if !fda, DiskScanner.tccSensitive.contains(where: { path.hasSuffix($0) }) {
                            fts_set(fts, ent, FTS_SKIP); s.denied += 1; continue
                        }
                        if path == vol.scanRoot + "/System/Volumes" || path == vol.scanRoot + "/Volumes" || path == "/dev" {
                            fts_set(fts, ent, FTS_SKIP); continue
                        }
                        while stack.count > level { fold() }
                        stack.append(Node(name: DiskScanner.name(ent), isDir: true))
                    case FTS_DP, FTS_DNR:
                        // An unreadable folder arrives as FTS_D then FTS_DNR (no FTS_DP), so both close it.
                        // Only folders in someone's home count: those are what Full Disk Access unlocks.
                        if info == FTS_DNR, String(cString: ent.pointee.fts_path).contains("/Users/") { s.denied += 1 }
                        if level == 0 { continue }
                        while stack.count > level + 1 { fold() }     // never let a missed close strand a branch
                        if stack.count == level + 1 { fold() }
                    case FTS_F, FTS_SL, FTS_DEFAULT:
                        guard let st = ent.pointee.fts_statp else { continue }
                        if st.pointee.st_nlink > 1 && info == FTS_F {
                            if !seenInodes.insert(UInt64(st.pointee.st_ino)).inserted { continue }
                        }
                        let bytes = Int64(st.pointee.st_blocks) * 512
                        while stack.count > max(1, level) { fold() }
                        let parent = stack[stack.count - 1]
                        parent.size += bytes; parent.files += 1
                        if bytes >= keepMin { let n = Node(name: DiskScanner.name(ent), isDir: false); n.size = bytes; parent.children.append(n) }
                        else { parent.otherSize += bytes; parent.otherCount += 1 }
                        s.scanned += bytes; s.files += 1
                    default: break
                    }
                }
            }
            while stack.count > 1 { fold() }
            root.children.sort { $0.size > $1.size }
            self.lock.lock()
            s.tree = root; s.running = false; s.finished = Date()
            self.lock.unlock()
        }
    }
}
