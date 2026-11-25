import AppKit
import CryptoKit

/// Checks GitHub for a newer release, then downloads it, checks it and swaps it in place of this copy.
///
/// The download is only accepted if its SHA-256 matches the digest GitHub publishes for the release asset, it
/// unpacks to an app with this app's bundle ID and the release's version number, and its code signature is intact.
final class Updater {
    static let shared = Updater()

    static let repo = "taxfraud311/matchbox-dashboard"
    /// For testing only: a URL that answers like GitHub's "latest release" API.
    private let apiURL = ProcessInfo.processInfo.environment["PLINTH_UPDATE_API"]
        ?? "https://api.github.com/repos/\(Updater.repo)/releases/latest"

    struct Release {
        let version: String, page: String, notes: String, published: String
        let zipURL: URL?, zipSHA: String?, zipSize: Int
    }

    private let lock = NSLock()
    private var latest: Release?
    private var checking = false
    private var checkedAt: Date?
    private var checkError: String?
    private var phase = "idle"            // idle, downloading, verifying, installing, failed
    private var phaseError: String?
    private var download: URLSessionDownloadTask?
    private var timer: Timer?
    /// Called on the main queue whenever something the menu shows changes.
    var onChange: (() -> Void)?

    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    /// The tablet app version bundled with this build (set by scripts/build.sh).
    static var bundledTabletVersion: String? { Bundle.main.object(forInfoDictionaryKey: "PlinthTabletVersion") as? String }

    var autoCheck: Bool { ConfigStore.shared.bool("updates.check", true) }

    func start() {
        // First look shortly after launch, then every 6 hours. GitHub allows 60 unauthenticated calls an hour.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in if self?.autoCheck == true { self?.check() } }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            if self?.autoCheck == true { self?.check() }
        }
        afterUpdate()
    }

    // MARK: State

    var available: Release? {
        lock.lock(); defer { lock.unlock() }
        guard let l = latest, Updater.isNewer(l.version, than: Updater.current) else { return nil }
        return l
    }
    var busy: Bool { lock.lock(); defer { lock.unlock() }; return ["downloading", "verifying", "installing"].contains(phase) }

    /// Why this copy can't replace itself, if it can't.
    var cantInstallReason: String? {
        let path = Bundle.main.bundlePath
        guard path.hasSuffix(".app") else { return "This copy isn’t running from an app bundle." }
        if (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true {
            return "The app is on a read-only disk. Move it to Applications first."
        }
        if path.contains("/AppTranslocation/") { return "macOS is running this copy from a temporary location. Move it to Applications and open it again." }
        let parent = (path as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent) else { return "You don’t have permission to replace the app in \(parent)." }
        return nil
    }

    /// For /api/update and the manager.
    var status: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var s: [String: Any] = [
            "current": Updater.current, "checking": checking, "auto": autoCheck, "phase": phase,
            "checkedAt": checkedAt.map { Int($0.timeIntervalSince1970 * 1000) } ?? NSNull(),
            "error": checkError ?? NSNull(), "installError": phaseError ?? NSNull(),
            "progress": download.map { $0.progress.fractionCompleted } ?? 0,
        ]
        if let l = latest {
            s["latest"] = ["version": l.version, "url": l.page, "notes": l.notes, "published": l.published, "size": l.zipSize] as [String: Any]
            s["available"] = Updater.isNewer(l.version, than: Updater.current)
        } else { s["available"] = false }
        s["cantInstall"] = cantInstallReason ?? NSNull()
        return s
    }

    private func changed() { DispatchQueue.main.async { self.onChange?() } }

    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: "-")[0]
                .split(separator: ".").map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: Check

    func check(completion: ((Bool) -> Void)? = nil) {
        lock.lock()
        if checking { lock.unlock(); completion?(false); return }
        checking = true; lock.unlock(); changed()
        var req = URLRequest(url: URL(string: apiURL)!, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MatchboxDashboard/\(Updater.current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            var rel: Release?, problem: String?
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let err { problem = err.localizedDescription }
            else if code == 404 { problem = "No releases found" }
            else if code == 403 || code == 429 { problem = "GitHub is limiting requests; trying again later" }
            else if let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let tag = j["tag_name"] as? String {
                let assets = j["assets"] as? [[String: Any]] ?? []
                let zip = assets.first { ($0["name"] as? String ?? "").hasSuffix("-macOS.zip") }
                let sha = (zip?["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
                rel = Release(version: String(tag.drop { $0 == "v" || $0 == "V" }), page: j["html_url"] as? String ?? "",
                              notes: j["body"] as? String ?? "", published: j["published_at"] as? String ?? "",
                              zipURL: (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)),
                              zipSHA: sha, zipSize: (zip?["size"] as? NSNumber)?.intValue ?? 0)
            } else { problem = "Unexpected reply from GitHub (\(code))" }
            self.lock.lock()
            self.checking = false; self.checkedAt = Date(); self.checkError = problem
            if let rel { self.latest = rel }
            self.lock.unlock()
            self.changed()
            completion?(problem == nil)
        }.resume()
    }

    // MARK: Install

    private var workDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Plinth/update")
    }

    private func fail(_ msg: String) {
        lock.lock(); phase = "failed"; phaseError = msg; download = nil; lock.unlock(); changed()
        NSLog("Update failed: \(msg)")
    }

    /// Downloads the available release and relaunches into it. Returns an error message if it can't start.
    @discardableResult
    func install() -> String? {
        guard let rel = available else { return "No update available." }
        if let why = cantInstallReason { return why }
        guard let zip = rel.zipURL, let sha = rel.zipSHA else { return "This release has no Mac download with a published checksum." }
        lock.lock()
        if ["downloading", "verifying", "installing"].contains(phase) { lock.unlock(); return nil }
        phase = "downloading"; phaseError = nil
        let task = URLSession.shared.downloadTask(with: zip) { [weak self] tmp, resp, err in
            guard let self else { return }
            guard let tmp, err == nil, (resp as? HTTPURLResponse)?.statusCode == 200 else {
                return self.fail(err?.localizedDescription ?? "Download failed (\((resp as? HTTPURLResponse)?.statusCode ?? 0))")
            }
            // The downloaded file is deleted when this block returns, so move it first.
            let fm = FileManager.default, dir = self.workDir
            try? fm.removeItem(at: dir)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("update.zip")
            do { try fm.moveItem(at: tmp, to: file) } catch { return self.fail("Couldn’t save the download: \(error.localizedDescription)") }
            DispatchQueue.global(qos: .userInitiated).async { self.verifyAndSwap(file, rel, sha) }
        }
        download = task
        lock.unlock(); changed()
        task.resume()
        return nil
    }

    private func setPhase(_ p: String) { lock.lock(); phase = p; lock.unlock(); changed() }

    private func verifyAndSwap(_ file: URL, _ rel: Release, _ sha: String) {
        setPhase("verifying")
        guard let digest = Self.sha256(file), digest == sha else { return fail("The download doesn’t match GitHub’s checksum, so it wasn’t installed.") }
        let fm = FileManager.default, out = workDir.appendingPathComponent("unpacked")
        guard Self.run("/usr/bin/ditto", ["-x", "-k", file.path, out.path]).0 == 0 else { return fail("Couldn’t unpack the download.") }
        let apps = ((try? fm.contentsOfDirectory(atPath: out.path)) ?? []).filter { $0.hasSuffix(".app") && !$0.hasPrefix("._") }
        guard apps.count == 1 else { return fail("The download doesn’t contain the app.") }
        let newApp = out.appendingPathComponent(apps[0])
        let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else { return fail("The download isn’t Matchbox Dashboard.") }
        guard info["CFBundleShortVersionString"] as? String == rel.version else { return fail("The download’s version doesn’t match the release.") }
        // exFAT and some unzip paths leave AppleDouble files behind, which break the signature.
        Self.run("/usr/bin/find", [newApp.path, "-name", "._*", "-delete"])
        guard Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]).0 == 0 else { return fail("The downloaded app’s signature is damaged.") }
        Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        setPhase("installing")
        let dest = Bundle.main.bundlePath
        let staged = ((dest as NSString).deletingLastPathComponent as NSString).appendingPathComponent(".Matchbox Dashboard \(rel.version) update.app")
        try? fm.removeItem(atPath: staged)
        do { try fm.moveItem(atPath: newApp.path, toPath: staged) } catch { return fail("Couldn’t copy the new version next to the app: \(error.localizedDescription)") }

        // A small helper waits for this process to quit, swaps the bundles (putting the old one back if anything
        // goes wrong) and opens the new copy.
        let script = """
        pid="$1"; new="$2"; dest="$3"; old="$4"
        n=0; while kill -0 "$pid" 2>/dev/null; do sleep 0.2; n=$((n+1)); [ $n -gt 300 ] && { rm -rf "$new"; exit 1; }; done
        rm -rf "$old"
        if mv "$dest" "$old"; then
          if mv "$new" "$dest"; then rm -rf "$old"; else mv "$old" "$dest"; fi
        fi
        rm -rf "$new"
        open "$dest"
        """
        let helper = workDir.appendingPathComponent("swap.sh")
        do { try script.write(to: helper, atomically: true, encoding: .utf8) } catch { return fail("Couldn’t prepare the installer.") }
        UserDefaults.standard.set(Updater.current, forKey: "updatedFrom")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), staged, dest, workDir.appendingPathComponent("previous.app").path]
        p.standardOutput = FileHandle(forWritingAtPath: "/dev/null"); p.standardError = p.standardOutput
        do { try p.run() } catch { try? fm.removeItem(atPath: staged); return fail("Couldn’t start the installer.") }
        RunLoop.main.perform(inModes: [.common]) { NSApp.terminate(nil) }
    }

    /// The first launch after an update: bring USB tablets up to the tablet app bundled with this version.
    private func afterUpdate() {
        guard let from = UserDefaults.standard.string(forKey: "updatedFrom") else { return }
        UserDefaults.standard.removeObject(forKey: "updatedFrom")
        NSLog("Updated from \(from) to \(Updater.current)")
        try? FileManager.default.removeItem(at: workDir)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { ADBBridge.shared.updateOutdatedTablets() }
    }

    static func sha256(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    static func run(_ exe: String, _ args: [String]) -> (Int32, String) {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
