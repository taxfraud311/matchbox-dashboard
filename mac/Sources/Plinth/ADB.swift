import Foundation

/// Watches for USB-connected Android/Fire devices and sets up `adb reverse` so the tablet
/// can reach this Mac at http://127.0.0.1:<port> over the cable — no Wi-Fi involved.
final class ADBBridge {
    static let shared = ADBBridge()
    static let package = "com.plinth.display"
    static let activity = "com.plinth.display/.MainActivity"

    struct Device {
        var serial: String
        var state: String
        var model: String
        var reversed: Bool
        var appInstalled: Bool?
        var lastMessage: String?
        /// adb transport the forward was created on. A new id means the adb server restarted or the
        /// cable was replugged, and any forward the tablet still lists is dead.
        var forwardedOn: String = ""
    }

    private let queue = DispatchQueue(label: "plinth.adb")
    private let lock = NSLock()
    private var devices: [String: Device] = [:]
    private var timer: DispatchSourceTimer?
    private(set) var adbPath: String?
    var onChange: (() -> Void)?

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.5, repeating: 4.0)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func locateADB() -> String? {
        var candidates: [String] = []
        let custom = ConfigStore.shared.string("adb.path", "")
        if !custom.isEmpty { candidates.append((custom as NSString).expandingTildeInPath) }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates += ["/opt/homebrew/bin/adb", "/usr/local/bin/adb",
                       "\(home)/Library/Android/sdk/platform-tools/adb",
                       Bundle.main.resourceURL?.appendingPathComponent("adb").path ?? ""]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }

    var status: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return [
            "tabletSeenAgo": everPolled ? Date().timeIntervalSince(lastTabletPoll) : NSNull(),
            "adbPath": adbPath ?? NSNull(),
            "devices": devices.values.sorted { $0.serial < $1.serial }.map {
                ["serial": $0.serial, "state": $0.state, "model": $0.model, "reversed": $0.reversed, "fire": ADBBridge.isFire($0), "eligible": ADBBridge.eligible($0),
                 "appInstalled": $0.appInstalled ?? NSNull(), "message": $0.lastMessage ?? NSNull()] as [String: Any]
            },
        ]
    }

    /// Amazon Fire tablets report model codes starting with "KF" (12th-gen Fire 7 = KFQUWI).
    static func isFire(_ d: Device) -> Bool { d.model.uppercased().hasPrefix("KF") }

    /// Only Fire tablets are touched unless "adb.anyDevice" is on — other Android gear on this Mac
    /// (TV boxes, phones) is left alone.
    static func eligible(_ d: Device) -> Bool { isFire(d) || ConfigStore.shared.bool("adb.anyDevice", false) }

    private func targets() -> [Device] {
        lock.lock(); defer { lock.unlock() }
        return devices.values.filter { $0.state == "device" && ADBBridge.eligible($0) }
    }

    var connectedSummary: String {
        lock.lock(); defer { lock.unlock() }
        let ready = devices.values.filter { $0.state == "device" && $0.reversed && ADBBridge.eligible($0) }
        if let d = ready.first { return "USB: \(ADBBridge.friendlyModel(d.model)) connected" }
        if devices.values.contains(where: { $0.state == "unauthorized" }) { return "USB: tap “Allow” on the tablet" }
        if adbPath == nil { return "USB: adb not installed" }
        return "USB: no tablet"
    }

    static func friendlyModel(_ m: String) -> String {
        switch m {
        case "KFQUWI": return "Fire 7 (12th gen)"
        case "KFMUWI": return "Fire 7 (9th gen)"
        default: return m.isEmpty ? "Tablet" : m.replacingOccurrences(of: "_", with: " ")
        }
    }

    @discardableResult
    private func adb(_ args: [String], timeout: TimeInterval = 10) -> Shell.Result {
        guard let p = adbPath else { return Shell.Result(status: -1, stdout: "", stderr: "adb not found") }
        return Shell.run(p, args, timeout: timeout)
    }

    private var pollCount = 0
    private var lastTabletPoll = Date()
    private var lastRepair = Date.distantPast
    private var everPolled = false
    func tabletPolled() { lock.lock(); lastTabletPoll = Date(); everPolled = true; lock.unlock() }
    /// Seconds since the tablet app last fetched data (nil if never since launch).
    var tabletSeenAgo: Double? { lock.lock(); defer { lock.unlock() }; return everPolled ? Date().timeIntervalSince(lastTabletPoll) : nil }

    private func poll() {
        pollCount += 1
        adbPath = locateADB()
        guard adbPath != nil, ConfigStore.shared.bool("adb.autoReverse", true) else {
            lock.lock(); let changed = !devices.isEmpty; devices = [:]; lock.unlock()
            if changed { onChange?() }
            return
        }
        let port = ConfigStore.shared.int("port", 8787)
        let out = adb(["devices", "-l"]).stdout
        var seen: [String: Device] = [:]
        for line in out.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { continue }
            let serial = String(parts[0]), state = String(parts[1])
            let model = parts.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)) } ?? ""
            let transport = parts.first { $0.hasPrefix("transport_id:") }.map { String($0.dropFirst(13)) } ?? "?"
            lock.lock(); let prev = devices[serial]; lock.unlock()
            var d = prev ?? Device(serial: serial, state: state, model: model, reversed: false)
            d.state = state
            if !model.isEmpty { d.model = model }
            if state == "device" && !ADBBridge.eligible(d) {
                d.reversed = false
                d.lastMessage = "Ignored (not a Fire tablet)"
            } else if state == "device" {
                let list = adb(["-s", serial, "reverse", "--list"]).stdout
                let want = "tcp:\(port) tcp:\(port)"
                if list.contains(want) && d.forwardedOn == transport {
                    d.reversed = true
                } else {
                    // (Re)create the forward: either it's missing, or it's left over from an earlier adb
                    // server and silently goes nowhere.
                    adb(["-s", serial, "reverse", "--remove", "tcp:\(port)"])
                    let r = adb(["-s", serial, "reverse", "tcp:\(port)", "tcp:\(port)"])
                    d.reversed = r.status == 0
                    d.forwardedOn = r.status == 0 ? transport : ""
                    d.lastMessage = r.status == 0 ? "Port \(port) forwarded over USB" : r.stderr
                }
                if d.appInstalled == nil || prev?.state != "device" {
                    let pm = adb(["-s", serial, "shell", "pm", "path", ADBBridge.package]).stdout
                    d.appInstalled = pm.contains("package:")
                    // Just plugged in (or just authorized) — bring the display up.
                    if d.appInstalled == true, ConfigStore.shared.bool("adb.autoLaunch", true) {
                        adb(["-s", serial, "shell", "am", "start", "-n", ADBBridge.activity])
                    }
                }
                // Every ~12 s: if the display process was killed (crash, low memory, WebView update), bring it back.
                // Pressing Home doesn't kill the process, so you can still leave the display on purpose.
                if pollCount % 3 == 0, d.appInstalled == true, prev?.state == "device",
                   ConfigStore.shared.bool("adb.autoLaunch", true) {
                    let pid = adb(["-s", serial, "shell", "pidof", ADBBridge.package]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    lock.lock(); let silent = Date().timeIntervalSince(lastTabletPoll); lock.unlock()
                    if pid.isEmpty {
                        adb(["-s", serial, "shell", "am", "start", "-n", ADBBridge.activity])
                        d.lastMessage = "Relaunched the display"
                    } else if silent > 60, Date().timeIntervalSince(lastRepair) > 180,
                              adb(["-s", serial, "shell", "dumpsys", "activity", "activities"]).stdout
                                .split(separator: "\n").contains(where: { $0.contains("ResumedActivity") && $0.contains(ADBBridge.package) }) {
                        // (Only when the display is in front — if you pressed Home, it's left alone.)
                        // Running but hasn't fetched data for a minute: the USB forward or the page is wedged.
                        // Rebuild the forward and restart the display cleanly.
                        lastRepair = Date()
                        adb(["-s", serial, "reverse", "--remove", "tcp:\(port)"])
                        adb(["-s", serial, "reverse", "tcp:\(port)", "tcp:\(port)"])
                        d.forwardedOn = transport
                        adb(["-s", serial, "shell", "am", "force-stop", ADBBridge.package])
                        adb(["-s", serial, "shell", "am", "start", "-n", ADBBridge.activity])
                        d.lastMessage = "Restarted the display (it had stopped updating)"
                        lock.lock(); lastTabletPoll = Date(); lock.unlock()   // give it a minute before trying again
                    }
                }
            } else {
                d.reversed = false
            }
            seen[serial] = d
        }
        lock.lock()
        let changed = Set(seen.keys) != Set(devices.keys)
            || seen.contains { devices[$0.key]?.state != $0.value.state || devices[$0.key]?.reversed != $0.value.reversed }
        devices = seen
        lock.unlock()
        if changed { onChange?() }
    }

    /// Installs the bundled tablet APK on every connected device.
    func installApp(completion: @escaping (String) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let apk = Bundle.main.url(forResource: "MatchboxDashboard", withExtension: "apk")?.path
                    ?? AppPaths.devAPK else { return completion("Tablet APK not bundled with this build.") }
            self.adbPath = self.locateADB()
            guard self.adbPath != nil else { return completion("adb not found — install with: brew install android-platform-tools") }
            let targets = self.targets()
            if targets.isEmpty { return completion("No authorized tablet connected over USB.") }
            var msgs: [String] = []
            for d in targets {
                let r = self.adb(["-s", d.serial, "install", "-r", apk], timeout: 120)
                let ok = r.stdout.contains("Success")
                msgs.append("\(ADBBridge.friendlyModel(d.model)): \(ok ? "installed" : (r.stderr.isEmpty ? r.stdout : r.stderr))")
                if ok {
                    self.lock.lock(); self.devices[d.serial]?.appInstalled = true; self.lock.unlock()
                    // Lets the display relaunch itself after a reboot (background activity start).
                    self.adb(["-s", d.serial, "shell", "appops", "set", ADBBridge.package, "SYSTEM_ALERT_WINDOW", "allow"])
                    self.adb(["-s", d.serial, "shell", "am", "start", "-n", ADBBridge.activity])
                }
            }
            completion(msgs.joined(separator: "\n"))
        }
    }

    func launchApp() {
        queue.async { [weak self] in
            guard let self else { return }
            for d in self.targets() { self.adb(["-s", d.serial, "shell", "am", "start", "-n", ADBBridge.activity]) }
        }
    }
}
