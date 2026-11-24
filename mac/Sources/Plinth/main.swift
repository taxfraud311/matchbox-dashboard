import AppKit
import ServiceManagement

let appVersion = "1.0"

enum AppPaths {
    /// Bundled web assets, or the repo's web/ folder when running from `swift run`.
    static var webRoot: URL {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("web"),
           FileManager.default.fileExists(atPath: r.appendingPathComponent("display/index.html").path) { return r }
        if let env = ProcessInfo.processInfo.environment["PLINTH_WEB"] { return URL(fileURLWithPath: env) }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("web")
    }
    static var devAPK: String? {
        let p = webRoot.deletingLastPathComponent().appendingPathComponent("build/MatchboxDashboard.apk").path
        return FileManager.default.fileExists(atPath: p) ? p : nil
    }
}

/// Tracks the Mac's Light/Dark appearance (including Auto switching at sunset).
final class Appearance {
    static let shared = Appearance()
    private let lock = NSLock()
    private var _dark = false
    private var observation: NSKeyValueObservation?
    var isDark: Bool { lock.lock(); defer { lock.unlock() }; return _dark }
    var onChange: (() -> Void)?

    func start() {
        update()
        observation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.update() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.update() }
        }
    }

    private func update() {
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        lock.lock(); let changed = dark != _dark; _dark = dark; lock.unlock()
        if changed { onChange?() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var server: HTTPServer!
    var reloadToken = Int(Date().timeIntervalSince1970)
    var lastActionMessage = ""
    let menu = NSMenu()
    var serverInfoItem = NSMenuItem()
    var tabletItem = NSMenuItem()
    var themeItem = NSMenuItem()
    var loginItem = NSMenuItem()
    var currentPort: Int = 0
    var currentLocalOnly = false

    func applicationDidFinishLaunching(_ n: Notification) {
        Appearance.shared.start()
        Presence.shared.start()
        MetricsCollector.shared.start()
        FeedService.shared.start()
        WallpaperSampler.shared.start()
        MediaFeeds.shared.start()
        ExtraFeeds.shared.start()
        MoreFeeds.shared.start()
        ADBBridge.shared.onChange = { [weak self] in DispatchQueue.main.async { self?.refreshMenu() } }
        ADBBridge.shared.start()

        server = HTTPServer { [weak self] req in self?.route(req) ?? .text("unavailable", status: 500) }
        server.onStateChange = { [weak self] in DispatchQueue.main.async { self?.refreshMenu() } }
        startServer()
        NotificationCenter.default.addObserver(forName: .plinthConfigChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let port = ConfigStore.shared.int("port", 8787)
            let localOnly = !ConfigStore.shared.bool("allowNetwork", true)
            if port != self.currentPort || localOnly != self.currentLocalOnly { self.startServer() }
            self.refreshMenu()
        }
        Appearance.shared.onChange = { [weak self] in DispatchQueue.main.async { self?.refreshMenu() } }

        migrateLoginItem()
        buildMenu()
        if CommandLine.arguments.contains("--open-manager") { openManager() }
    }

    func startServer() {
        currentPort = ConfigStore.shared.int("port", 8787)
        currentLocalOnly = !ConfigStore.shared.bool("allowNetwork", true)
        server.start(port: UInt16(currentPort), localOnly: currentLocalOnly, bonjourName: "Matchbox Dashboard on \(Host.current().localizedName ?? "Mac")")
    }

    // MARK: Menu bar

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "flame", accessibilityDescription: "Matchbox Dashboard")
                ?? NSImage(systemSymbolName: "display", accessibilityDescription: "Matchbox Dashboard")
        }
        menu.delegate = self
        for i in [serverInfoItem, tabletItem, themeItem] { i.isEnabled = false; menu.addItem(i) }
        menu.addItem(.separator())
        menu.addItem(item("Open Manager…", #selector(openManager), "m"))
        menu.addItem(item("Preview Display in Browser", #selector(openDisplay), "p"))
        menu.addItem(.separator())
        menu.addItem(item("Install App on Tablet (USB)", #selector(installApp), ""))
        menu.addItem(item("Relaunch Tablet Display", #selector(launchTablet), ""))
        menu.addItem(item("Run Network Speed Test", #selector(runSpeedTest), ""))
        menu.addItem(item("Refresh Weather, Scores & News", #selector(refreshFeeds), "r"))
        menu.addItem(.separator())
        loginItem = item("Open at Login", #selector(toggleLogin), "")
        menu.addItem(loginItem)
        menu.addItem(item("Quit Matchbox Dashboard", #selector(quit), "q"))
        statusItem.menu = menu
        refreshMenu()
    }

    func item(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    func menuWillOpen(_ menu: NSMenu) { refreshMenu() }

    func refreshMenu() {
        guard statusItem != nil else { return }
        if let e = server.lastError {
            serverInfoItem.title = "Server error on :\(currentPort) — \(e)"
        } else {
            serverInfoItem.title = "Serving on port \(currentPort)" + (currentLocalOnly ? " (USB only)" : " (USB + Wi-Fi)")
        }
        tabletItem.title = ADBBridge.shared.connectedSummary
        themeItem.title = "Display mode: " + (effectiveTheme == "night" ? "Night" : "Day")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    var effectiveTheme: String {
        switch ConfigStore.shared.string("theme", "auto") {
        case "day": return "day"
        case "night": return "night"
        default: return Appearance.shared.isDark ? "night" : "day"
        }
    }

    @objc func openManager() { NSWorkspace.shared.open(URL(string: "http://localhost:\(currentPort)/manager/")!) }
    @objc func openDisplay() { NSWorkspace.shared.open(URL(string: "http://localhost:\(currentPort)/display/")!) }
    @objc func runSpeedTest() { MetricsCollector.shared.runSpeedTest() }
    @objc func refreshFeeds() { FeedService.shared.refreshAll() }
    @objc func launchTablet() { ADBBridge.shared.launchApp() }
    @objc func quit() { NSApp.terminate(nil) }

    /// Give the tablet a moment to hear that Plinth is going away (logout, shutdown or Quit).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if [.awake, .locked].contains(Presence.shared.state) { Presence.shared.set(.quitting) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Presence.announceDelay) { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    @objc func installApp() {
        ADBBridge.shared.installApp { msg in
            DispatchQueue.main.async {
                self.lastActionMessage = msg
                let a = NSAlert()
                a.messageText = "Install on Tablet"
                a.informativeText = msg
                NSApp.activate(ignoringOtherApps: true)
                a.runModal()
            }
        }
    }

    /// The app was renamed (Plinth.app → Matchbox Dashboard.app). A login item still points at the old path,
    /// so re-register it once from wherever this copy lives.
    func migrateLoginItem() {
        let key = "loginItemPath", here = Bundle.main.bundlePath
        guard here.hasSuffix(".app"), UserDefaults.standard.string(forKey: key) != here else { return }
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            try? SMAppService.mainApp.register()
        }
        UserDefaults.standard.set(here, forKey: key)
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert(); a.messageText = "Couldn’t change login item"
            a.informativeText = "\(error.localizedDescription)\nMove Matchbox Dashboard.app to /Applications and try again."
            a.runModal()
        }
        refreshMenu()
    }

    // MARK: Routes

    func route(_ r: HTTPRequest) -> HTTPResponse {
        let path = r.path
        let managerOnly = { (resp: () -> HTTPResponse) -> HTTPResponse in
            r.isLoopback ? resp() : .text("The manager is only available on the Mac itself.", status: 403)
        }

        switch (r.method, path) {
        case (_, "/"):
            return .redirect("/display/")
        case (_, "/manager"):
            return .redirect("/manager/")
        case (_, "/display"):
            return .redirect("/display/")

        case ("GET", "/api/metrics"):
            if (r.headers["user-agent"] ?? "").contains("; wv)") { ADBBridge.shared.tabletPolled() }
            let s = MetricsCollector.shared.snapshot
            let theme = effectiveTheme
            let bright = ConfigStore.shared.double(theme == "night" ? "brightness.night" : "brightness.day", -1)
            var body: [String: Any] = [
                "m": s.latest, "theme": theme, "macDark": Appearance.shared.isDark,
                "rev": ConfigStore.shared.revision,
                "fv": "\((FeedService.shared.snapshot["version"] as? Int) ?? 0).\(MediaFeeds.shared.version).\(ExtraFeeds.shared.version).\(MoreFeeds.shared.version)",
                "reload": reloadToken, "brightness": bright,
                "host": Host.current().localizedName ?? "Mac",
                "tz": TimeZone.current.identifier,
                "presence": Presence.shared.state.rawValue,
                "day": [
                    "mode": ConfigStore.shared.string("dayColors.mode", "wallpaper"),
                    "custom": ConfigStore.shared.string("dayColors.custom", "#3a82f7"),
                    "wallpaper": WallpaperSampler.shared.snapshot,
                ] as [String: Any],
            ]
            if r.query["h"] != nil { body["h"] = s.history }
            return .json(body)

        case ("GET", "/api/feeds"):
            var f = FeedService.shared.snapshot
            let media = MediaFeeds.shared.snapshot
            f["youtube"] = media["youtube"]; f["anime"] = media["anime"]
            let extra = ExtraFeeds.shared.snapshot
            for k in ["bluesky", "steamUpcoming", "steamDeals", "steam"] { f[k] = extra[k] }
            var errs = f["errors"] as? [String: Any] ?? [:]
            for (k, v) in media["errors"] as? [String: Any] ?? [:] { errs[k] = v }
            for (k, v) in extra["errors"] as? [String: Any] ?? [:] { errs[k] = v }
            let more = MoreFeeds.shared.snapshot
            for k in ["steamRecent", "steamClosest", "steamNews", "fx", "kanji", "radar", "slickdeals"] { f[k] = more[k] }
            for (k, v) in more["errors"] as? [String: Any] ?? [:] { errs[k] = v }
            f["errors"] = errs
            return .json(f)

        case ("GET", "/img"):
            // Thumbnails/cover art fetched by the Mac (allow-listed hosts only) so a USB-only tablet can show them.
            guard let u = r.query["u"], let (data, type) = MediaFeeds.shared.image(u) else { return .text("Not found", status: 404) }
            return HTTPResponse(status: 200, headers: ["Content-Type": type, "Cache-Control": "max-age=86400"], body: data)

        case ("GET", "/api/detail"):
            // Expanded metric panels on the tablet.
            return .json(DetailService.shared.detail(r.query["kind"] ?? ""))

        case ("GET", "/api/appicon"):
            guard let png = DetailService.shared.iconPNG(for: r.query["name"] ?? "") else { return .text("Not found", status: 404) }
            return HTTPResponse(status: 200, headers: ["Content-Type": "image/png", "Cache-Control": "max-age=86400"], body: png)

        case ("POST", "/api/tablet"):
            // The few actions the tablet itself may trigger.
            let j = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
            switch j["action"] as? String ?? "" {
            case "speedtest": MetricsCollector.shared.runSpeedTest(); return .json(["ok": true])
            case "cycle":
                // Long-press menu on the carousel: time between cards.
                guard let n = (j["seconds"] as? NSNumber)?.intValue, (4...600).contains(n) else { return .json(["error": "bad value"], status: 400) }
                ConfigStore.shared.update(with: ["cycleSeconds": n]); return .json(["ok": true])
            default: return .json(["error": "not allowed"], status: 403)
            }

        case ("GET", "/api/diskscan"):
            // What's using space on a volume: list + treemap on the tablet's Disk sheet.
            return .json(DiskScanner.shared.status(volume: r.query["vol"], path: r.query["path"] ?? "", rescan: r.query["rescan"] == "1"))

        case ("GET", "/api/qr"):
            guard let png = MoreFeeds.shared.qrPNG(r.query["u"] ?? "") else { return .text("Not found", status: 404) }
            return HTTPResponse(status: 200, headers: ["Content-Type": "image/png", "Cache-Control": "max-age=86400"], body: png)

        case ("GET", "/api/bluesky/resolve"):
            return managerOnly { .json(ExtraFeeds.shared.resolveBluesky(r.query["q"] ?? "")) }

        case ("GET", "/api/steam/resolve"):
            return managerOnly { .json(ExtraFeeds.shared.resolveSteam(r.query["q"] ?? "")) }

        case ("GET", "/api/youtube/resolve"):
            return managerOnly { .json(MediaFeeds.shared.resolveChannel(r.query["q"] ?? "")) }

        case ("GET", "/api/config"):
            var c = ConfigStore.shared.snapshot
            if (c["deviceName"] as? String ?? "").isEmpty { c["deviceName"] = Host.current().localizedName ?? "Mac mini" }
            c["_rev"] = ConfigStore.shared.revision
            // The Steam Web API key never leaves the Mac; the manager only learns whether one is saved.
            if var st = c["steam"] as? [String: Any] {
                st["apiKeySet"] = !((st["apiKey"] as? String) ?? "").isEmpty; st["apiKey"] = ""; c["steam"] = st
            }
            return .json(c)

        case ("POST", "/api/config"):
            return managerOnly {
                guard var patch = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] else {
                    return .json(["error": "Invalid JSON"], status: 400)
                }
                patch.removeValue(forKey: "_rev")
                ConfigStore.shared.update(with: patch)
                return .json(["ok": true, "rev": ConfigStore.shared.revision])
            }

        case ("POST", "/api/config/reset"):
            return managerOnly { ConfigStore.shared.reset(); return .json(["ok": true]) }

        case ("GET", "/api/status"):
            return managerOnly {
                .json([
                    "version": appVersion,
                    "port": currentPort,
                    "localOnly": currentLocalOnly,
                    "serverError": server.lastError ?? NSNull(),
                    "addresses": NetUtil.localIPv4Addresses(),
                    "adb": ADBBridge.shared.status,
                    "feedErrors": {
                        var e = FeedService.shared.snapshot["errors"] as? [String: Any] ?? [:]
                        for (k, v) in MediaFeeds.shared.snapshot["errors"] as? [String: Any] ?? [:] { e[k] = v }
                        for (k, v) in ExtraFeeds.shared.snapshot["errors"] as? [String: Any] ?? [:] { e[k] = v }
                        for (k, v) in MoreFeeds.shared.snapshot["errors"] as? [String: Any] ?? [:] { e[k] = v }
                        return e
                    }(),
                    "theme": effectiveTheme,
                    "macDark": Appearance.shared.isDark,
                    "lastAction": lastActionMessage,
                    "apkBundled": Bundle.main.url(forResource: "MatchboxDashboard", withExtension: "apk") != nil || AppPaths.devAPK != nil,
                    "configPath": ConfigStore.shared.fileURL.path,
                ])
            }

        case ("POST", "/api/action"):
            return managerOnly {
                let j = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
                switch j["action"] as? String ?? "" {
                case "speedtest": MetricsCollector.shared.runSpeedTest()
                case "refresh": FeedService.shared.refreshAll(); MediaFeeds.shared.refreshAll(); ExtraFeeds.shared.refreshAll(); MoreFeeds.shared.refreshAll()
                case "wallpaper": WallpaperSampler.shared.refreshNow()
                case "presence":
                    // Test hook: pretend the Mac is asleep / logged out for a while.
                    let s = Presence.State(rawValue: j["state"] as? String ?? "") ?? .sleeping
                    Presence.shared.simulate(s, seconds: (j["seconds"] as? NSNumber)?.doubleValue ?? 30)
                case "reload": reloadToken += 1
                case "launch": ADBBridge.shared.launchApp()
                case "install":
                    lastActionMessage = "Installing…"
                    ADBBridge.shared.installApp { [weak self] msg in self?.lastActionMessage = msg }
                default: return .json(["error": "unknown action"], status: 400)
                }
                return .json(["ok": true])
            }

        case ("GET", "/api/wallpaper.png"):
            return managerOnly {
                guard let png = WallpaperSampler.shared.thumbnailPNG else { return .text("No wallpaper sampled yet", status: 404) }
                return HTTPResponse(status: 200, headers: ["Content-Type": "image/png", "Cache-Control": "no-store"], body: png)
            }

        case ("GET", "/download/MatchboxDashboard.apk"), ("GET", "/download/Plinth.apk"):
            let apk = Bundle.main.url(forResource: "MatchboxDashboard", withExtension: "apk")?.path ?? AppPaths.devAPK
            guard let apk, let data = FileManager.default.contents(atPath: apk) else { return .text("Not bundled", status: 404) }
            return HTTPResponse(status: 200, headers: ["Content-Type": MIME.type(for: "apk"),
                                                       "Content-Disposition": "attachment; filename=MatchboxDashboard.apk"], body: data)

        default:
            break
        }

        if r.method == "GET" || r.method == "HEAD" {
            if path.hasPrefix("/fonts/") { return serveFont(String(path.dropFirst(7))) }
            if path.hasPrefix("/manager/") && !r.isLoopback {
                return .text("The manager is only available on the Mac itself.", status: 403)
            }
            return serveStatic(path)
        }
        return .text("Not found", status: 404)
    }

    /// Streams the Mac's own system font to the tablet so the type matches macOS exactly.
    func serveFont(_ name: String) -> HTTPResponse {
        let allowed = ["SFNS.ttf", "SFNSRounded.ttf", "SFNSMono.ttf"]
        guard allowed.contains(name), ConfigStore.shared.bool("useMacFont", true),
              let data = FileManager.default.contents(atPath: "/System/Library/Fonts/\(name)") else {
            return .text("Not found", status: 404)
        }
        return HTTPResponse(status: 200, headers: ["Content-Type": "font/ttf", "Cache-Control": "max-age=604800"], body: data)
    }

    func serveStatic(_ path: String) -> HTTPResponse {
        let root = AppPaths.webRoot.standardizedFileURL
        var rel = path
        if rel.hasSuffix("/") { rel += "index.html" }
        let url = root.appendingPathComponent(rel).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), let data = FileManager.default.contents(atPath: url.path) else {
            return .text("Not found", status: 404)
        }
        return HTTPResponse(status: 200, headers: ["Content-Type": MIME.type(for: url.pathExtension)], body: data)
    }
}

enum NetUtil {
    static func localIPv4Addresses() -> [[String: String]] {
        var out: [[String: String]] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let a = p {
            let name = String(cString: a.pointee.ifa_name)
            if let sa = a.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), name.hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                out.append(["iface": name, "ip": String(cString: host)])
            }
            p = a.pointee.ifa_next
        }
        return out
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
