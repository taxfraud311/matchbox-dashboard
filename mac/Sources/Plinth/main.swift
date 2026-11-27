import AppKit
import ServiceManagement

var appVersion: String { Updater.current }

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
    var versionItem = NSMenuItem()
    var updateItem = NSMenuItem()
    var currentPort: Int = 0
    var currentLocalOnly = false
    /// Keeps App Nap from throttling the server and metrics while no window is open. Idle system sleep stays allowed.
    var activity: NSObjectProtocol?
    var serverWatchdog: Timer?

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
        ClaudeUsage.shared.start()
        Stocks.shared.start()
        Updater.shared.onChange = { [weak self] in self?.refreshMenu() }
        Updater.shared.start()
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                          reason: "Serving the tablet display")
        Presence.shared.onIdleChange = { idle in
            // Screen-saver mode: over USB the Mac switches the tablet off itself (the tablet may not get another
            // poll in before the Mac sleeps), and wakes it again, since a tablet with its screen off has stopped listening.
            guard ConfigStore.shared.string("screen.mode", "always") == "screensaver" else { return }
            ADBBridge.shared.setScreen(on: !idle)
        }
        // Switched back to Always On while the screen is off: wake it.
        // (Only when the mode itself changes, so a tablet you switched off with its power button stays off.)
        var lastMode = ConfigStore.shared.string("screen.mode", "always")
        NotificationCenter.default.addObserver(forName: .plinthConfigChanged, object: nil, queue: .main) { _ in
            let mode = ConfigStore.shared.string("screen.mode", "always")
            if mode == "always", lastMode != "always" { ADBBridge.shared.setScreen(on: true, force: true) }
            lastMode = mode
        }

        server = HTTPServer { [weak self] req in self?.route(req) ?? .text("unavailable", status: 500) }
        server.asyncHandler = { req, reply in
            // Thumbnails and radar tiles download without tying up a server thread each.
            if req.method == "GET", req.path == "/api/stocks/search" {
                guard req.isLoopback else { reply(.text("The manager is only available on the Mac itself.", status: 403)); return true }
                Stocks.shared.search(req.query["q"] ?? "") { reply(.json($0)) }
                return true
            }
            guard req.method == "GET", req.path == "/img" else { return false }
            MediaFeeds.shared.imageAsync(req.query["u"] ?? "") { r in
                guard let (data, type) = r else { return reply(.text("Not found", status: 404)) }
                reply(HTTPResponse(status: 200, headers: ["Content-Type": type, "Cache-Control": "max-age=86400"], body: data))
            }
            return true
        }
        server.onStateChange = { [weak self] in DispatchQueue.main.async { self?.refreshMenu() } }
        startServer()
        // A fresh listener after waking (network interfaces come back changed) and whenever it isn't listening.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.server.restart(after: 3)
        }
        serverWatchdog = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, !self.server.isReady else { return }
            NSLog("HTTP listener not ready (\(self.server.lastError ?? "no error")); restarting")
            self.server.restart()
        }
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
        updateItem = item("Check for Updates…", #selector(updateMenu), "")
        menu.addItem(updateItem)
        versionItem.isEnabled = false
        menu.addItem(versionItem)
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
        versionItem.title = "Version \(appVersion)"
        let u = Updater.shared.status
        if Updater.shared.busy {
            updateItem.title = u["phase"] as? String == "downloading" ? "Downloading Update… \(Int(((u["progress"] as? Double) ?? 0) * 100))%" : "Installing Update…"
        } else if let rel = Updater.shared.available {
            updateItem.title = "Install Update \(rel.version)…"
        } else { updateItem.title = (u["checking"] as? Bool) == true ? "Checking for Updates…" : "Check for Updates…" }
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

    @objc func updateMenu() {
        if Updater.shared.busy { return }
        if Updater.shared.available != nil { confirmUpdate(); return }
        Updater.shared.check { ok in
            DispatchQueue.main.async {
                if Updater.shared.available != nil { self.confirmUpdate(); return }
                let a = NSAlert()
                a.messageText = ok ? "You’re up to date" : "Couldn’t check for updates"
                a.informativeText = ok ? "Matchbox Dashboard \(appVersion) is the latest version."
                                       : (Updater.shared.status["error"] as? String ?? "Try again later.")
                NSApp.activate(ignoringOtherApps: true); a.runModal()
            }
        }
    }

    func confirmUpdate() {
        guard let rel = Updater.shared.available else { return }
        let a = NSAlert()
        a.messageText = "Matchbox Dashboard \(rel.version) is available"
        var notes = rel.notes.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "## ", with: "")
        if notes.count > 700 { notes = String(notes.prefix(700)) + "…" }
        a.informativeText = "You have \(appVersion). The app will download the update, check it and relaunch.\n\n" + notes
        a.addButton(withTitle: "Install and Relaunch"); a.addButton(withTitle: "Later"); a.addButton(withTitle: "Release Notes")
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn:
            if let err = Updater.shared.install() {
                let e = NSAlert(); e.messageText = "Couldn’t install the update"; e.informativeText = err; e.runModal()
            }
        case .alertThirdButtonReturn: if let u = URL(string: rel.page) { NSWorkspace.shared.open(u) }
        default: break
        }
    }

    /// Give the tablet a moment to hear that Plinth is going away (logout, shutdown or Quit).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if [.awake, .locked].contains(Presence.shared.state) { Presence.shared.set(.quitting) }
        // A run-loop timer rather than GCD: terminate() can be called from inside a main-queue block, which would
        // keep a queued reply from ever running.
        let t = Timer(timeInterval: Presence.announceDelay, repeats: false) { _ in NSApp.reply(toApplicationShouldTerminate: true) }
        RunLoop.main.add(t, forMode: .common)
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

    func feedsPayload() -> [String: Any] {
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
        f["stocks"] = Stocks.shared.snapshot["stocks"]
        if let e = Stocks.shared.lastError { errs["stocks"] = e }
        f["errors"] = errs
        return f
    }

    /// Links the tablet may ask this Mac to open: web links that appear in the current feeds, or on the few
    /// sites whose links the display builds itself (scores, anime, Bluesky posts, Steam store pages).
    func openableURL(_ s: String) -> URL? {
        guard s.count < 4096, let u = URL(string: s), let scheme = u.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = u.host?.lowercased() else { return nil }
        if ["www.espn.com", "anilist.co", "bsky.app", "store.steampowered.com"].contains(host) { return u }
        var found = false
        func walk(_ v: Any) {
            if found { return }
            if let x = v as? String { if x == s { found = true } }
            else if let d = v as? [String: Any] { for x in d.values { walk(x) } }
            else if let a = v as? [Any] { for x in a { walk(x) } }
        }
        walk(feedsPayload())
        return found ? u : nil
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
                "fv": "\((FeedService.shared.snapshot["version"] as? Int) ?? 0).\(MediaFeeds.shared.version).\(ExtraFeeds.shared.version).\(MoreFeeds.shared.version).\(Stocks.shared.version)",
                "reload": reloadToken, "brightness": bright,
                "host": Host.current().localizedName ?? "Mac",
                "tz": TimeZone.current.identifier,
                "presence": Presence.shared.state.rawValue,
                "screen": ["mode": ConfigStore.shared.string("screen.mode", "always"),
                           "timeout": max(1, ConfigStore.shared.int("screen.timeoutMinutes", 10)) * 60,
                           "saver": Presence.shared.macIdle] as [String: Any],
                "day": [
                    "mode": ConfigStore.shared.string("dayColors.mode", "wallpaper"),
                    "custom": ConfigStore.shared.string("dayColors.custom", "#3a82f7"),
                    "wallpaper": WallpaperSampler.shared.snapshot,
                ] as [String: Any],
            ]
            if r.query["h"] != nil { body["h"] = s.history }
            if let c = ClaudeUsage.shared.summary { body["claude"] = c }
            // Lets the tablet show its "update available" note.
            var ver: [String: Any] = ["mac": appVersion]
            if let rel = Updater.shared.available { ver["update"] = rel.version }
            if let t = Updater.bundledTabletVersion { ver["tablet"] = t }
            body["version"] = ver
            return .json(body)

        case ("GET", "/api/feeds"):
            return .json(feedsPayload())

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
            case "screen":
                // The tablet switched its screen off (timeout or screen saver) or back on.
                ADBBridge.shared.setScreen(on: (j["on"] as? Bool) ?? true, fromTablet: true); return .json(["ok": true])
            case "open":
                // "Open on Mac" in the QR sheet. Only links the dashboard itself is showing, so nothing else on the
                // network can make this Mac open arbitrary pages.
                guard let u = openableURL(j["url"] as? String ?? "") else { return .json(["error": "That link can’t be opened"], status: 403) }
                DispatchQueue.main.async { NSWorkspace.shared.open(u) }
                return .json(["ok": true, "presence": Presence.shared.state.rawValue])
            case "cycle":
                // Long-press menu on the carousel: time between cards.
                guard let n = (j["seconds"] as? NSNumber)?.intValue, (4...600).contains(n) else { return .json(["error": "bad value"], status: 400) }
                ConfigStore.shared.update(with: ["cycleSeconds": n]); return .json(["ok": true])
            default: return .json(["error": "not allowed"], status: 403)
            }

        case ("POST", "/api/claude/bridge"):
            return managerOnly {
                let j = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
                let err = (j["action"] as? String) == "connect" ? ClaudeBridge.connect() : ClaudeBridge.disconnect()
                if let err { return .json(["error": err], status: 500) }
                return .json(ClaudeBridge.status)
            }

        case ("GET", "/api/update"):
            return managerOnly { .json(Updater.shared.status) }

        case ("POST", "/api/update"):
            return managerOnly {
                let j = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
                switch j["action"] as? String ?? "" {
                case "check": Updater.shared.check()
                case "install": if let err = Updater.shared.install() { return .json(["error": err], status: 409) }
                default: return .json(["error": "unknown action"], status: 400)
                }
                return .json(Updater.shared.status)
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
                        if let s = Stocks.shared.lastError { e["stocks"] = s }
                        return e
                    }(),
                    "theme": effectiveTheme,
                    "macDark": Appearance.shared.isDark,
                    "lastAction": lastActionMessage,
                    "apkBundled": Bundle.main.url(forResource: "MatchboxDashboard", withExtension: "apk") != nil || AppPaths.devAPK != nil,
                    "configPath": ConfigStore.shared.fileURL.path,
                    "claudeBridge": ClaudeBridge.status,
                ])
            }

        case ("POST", "/api/action"):
            return managerOnly {
                let j = (try? JSONSerialization.jsonObject(with: r.body)) as? [String: Any] ?? [:]
                switch j["action"] as? String ?? "" {
                case "speedtest": MetricsCollector.shared.runSpeedTest()
                case "refresh": FeedService.shared.refreshAll(); MediaFeeds.shared.refreshAll(); ExtraFeeds.shared.refreshAll(); MoreFeeds.shared.refreshAll(); Stocks.shared.refresh()
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
