import Foundation

/// Claude Code usage from its own local logs (~/.claude/projects/**/*.jsonl): context left in the most recent
/// session, tokens per day / week / 5-hour window, and the time to the weekly reset the user sets in the manager.
/// Only the usage numbers, model, session id and folder are read from each line, never the conversation itself.
/// Plan limits (the 5-hour and weekly "% used") aren't in the logs. They come from Claude Code's status line, which
/// Matchbox Dashboard can be connected to (ClaudeBridge below); failing that, from the logs' "limit reached" events.
final class ClaudeUsage {
    static let shared = ClaudeUsage()

    private struct Rec {
        let t: Double            // seconds since 1970
        let model: String
        let input: Int, cacheW: Int, cacheR: Int, output: Int
        let session: String
        let side: Bool           // subagent (sidechain) call: doesn't fill the main context
        var tokens: Int { input + cacheW + output }
        var context: Int { input + cacheW + cacheR + output }
    }

    private let queue = DispatchQueue(label: "plinth.claude", qos: .utility)
    private let lock = NSLock()
    private var recs: [String: Rec] = [:]
    private var files: [String: (ino: UInt64, offset: UInt64)] = [:]
    private var cwds: [String: String] = [:]
    private var summaryCache: [String: Any]?
    private var timer: DispatchSourceTimer?
    private var scanning = false

    static let root = ProcessInfo.processInfo.environment["PLINTH_CLAUDE_DIR"] ?? NSHomeDirectory() + "/.claude"
    /// "Limit reached" events seen in the logs: limit type → when it resets (seconds).
    private var hits: [String: Double] = [:]
    private static let keepDays = 9.0

    func start() {
        if ClaudeBridge.isConnected { ClaudeBridge.installScript() }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 20)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private func tick() {
        guard ConfigStore.shared.bool("claude.enabled", false) else { return }
        scan()
        let s = buildSummary()
        lock.lock(); summaryCache = s; lock.unlock()
    }

    /// Small payload for the tile, sent with every metrics poll (nil while the tile is off).
    var summary: [String: Any]? {
        guard ConfigStore.shared.bool("claude.enabled", false) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if summaryCache == nil { queue.async { [weak self] in self?.tick() } }
        return summaryCache ?? ["loading": true]
    }

    // MARK: Reading the logs

    private func scan() {
        let fm = FileManager.default
        let base = ClaudeUsage.root + "/projects"
        guard let e = fm.enumerator(atPath: base) else { return }
        let cutoff = Date().addingTimeInterval(-ClaudeUsage.keepDays * 86400)
        var seen = Set<String>()
        while let rel = e.nextObject() as? String {
            guard rel.hasSuffix(".jsonl") else { continue }
            let path = base + "/" + rel
            guard let a = try? fm.attributesOfItem(atPath: path),
                  let size = (a[.size] as? NSNumber)?.uint64Value,
                  let mod = a[.modificationDate] as? Date, mod > cutoff else { continue }
            seen.insert(path)
            let ino = (a[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            var start: UInt64 = 0
            if let f = files[path], f.ino == ino, f.offset <= size { start = f.offset }
            if start == size { continue }
            files[path] = (ino, read(path, from: start))
        }
        for k in files.keys where !seen.contains(k) { files[k] = nil }
        let old = Date().timeIntervalSince1970 - ClaudeUsage.keepDays * 86400
        recs = recs.filter { $0.value.t >= old }
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    /// Reads whole lines from `offset`; returns where the next read should start (before any partial last line).
    private func read(_ path: String, from offset: UInt64) -> UInt64 {
        guard let h = FileHandle(forReadingAtPath: path) else { return offset }
        defer { try? h.close() }
        try? h.seek(toOffset: offset)
        var pos = offset
        var carry = Data()
        let usageKey = Data(#""usage":{"#.utf8)
        while true {
            guard let chunk = try? h.read(upToCount: 4 << 20), !chunk.isEmpty else { break }
            var buf = carry; buf.append(chunk); carry = Data()
            var lineStart = buf.startIndex
            while let nl = buf[lineStart...].firstIndex(of: 0x0A) {
                let line = buf[lineStart..<nl]
                if line.range(of: usageKey) != nil { parse(Data(line)) }
                pos += UInt64(nl - lineStart + 1)
                lineStart = buf.index(after: nl)
            }
            carry = Data(buf[lineStart...])
        }
        return pos
    }

    private func parse(_ line: Data) {
        guard let j = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              j["type"] as? String == "assistant",
              let m = j["message"] as? [String: Any], let u = m["usage"] as? [String: Any],
              let ts = j["timestamp"] as? String,
              let d = ClaudeUsage.iso.date(from: ts) ?? ClaudeUsage.isoPlain.date(from: ts) else { return }
        let model = m["model"] as? String ?? ""
        if model.hasPrefix("<") {                   // "<synthetic>" placeholder messages, incl. "limit reached"
            if let info = (j["apiErrorParams"] as? [String: Any])?["rate_limit_info"] as? [String: Any],
               info["status"] as? String == "rejected", let type = info["rateLimitType"] as? String,
               let r = (info["resetsAt"] as? NSNumber)?.doubleValue { hits[type] = max(hits[type] ?? 0, r) }
            return
        }
        func n(_ k: String) -> Int { (u[k] as? NSNumber)?.intValue ?? 0 }
        let session = j["sessionId"] as? String ?? ""
        if let c = j["cwd"] as? String, !session.isEmpty { cwds[session] = c }
        // A reply is written as one line per content block, each repeating the usage: keep one per message.
        let key = (m["id"] as? String ?? UUID().uuidString) + "|" + (j["requestId"] as? String ?? "")
        recs[key] = Rec(t: d.timeIntervalSince1970, model: model, input: n("input_tokens"), cacheW: n("cache_creation_input_tokens"),
                        cacheR: n("cache_read_input_tokens"), output: n("output_tokens"), session: session,
                        side: (j["isSidechain"] as? Bool) ?? false)
    }

    // MARK: Lookups

    /// Context window and display name per model id, from Claude Code's cached model list.
    private func catalog() -> [String: (window: Int, name: String)] {
        var out: [String: (Int, String)] = [:]
        let dir = ClaudeUsage.root + "/cache/model-catalog"
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where f.hasSuffix(".json") {
            guard let d = FileManager.default.contents(atPath: dir + "/" + f),
                  let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let models = ((j["catalog"] as? [String: Any])?["config"] as? [String: Any])?["models"] as? [[String: Any]] else { continue }
            for m in models {
                guard let id = m["id"] as? String else { continue }
                let w = ((m["runtime"] as? [String: Any])?["max_input_tokens"] as? NSNumber)?.intValue ?? 0
                out[id] = (w, m["name"] as? String ?? id)
            }
        }
        return out
    }

    private func sessionNames() -> [String: String] {
        var out: [String: String] = [:]
        let dir = ClaudeUsage.root + "/sessions"
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where f.hasSuffix(".json") {
            guard let d = FileManager.default.contents(atPath: dir + "/" + f),
                  let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let id = j["sessionId"] as? String, let name = j["name"] as? String, !name.isEmpty else { continue }
            out[id] = name
        }
        return out
    }

    private func modelName(_ id: String, _ cat: [String: (window: Int, name: String)]) -> String {
        if let c = cat[id] { return c.name }
        // claude-opus-5-5 → Opus 5.5
        let parts = id.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        guard let fam = parts.first else { return id }
        let ver = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) && $0.count <= 2 }.joined(separator: ".")
        return fam.capitalized + (ver.isEmpty ? "" : " " + ver)
    }

    /// The 5-hour and weekly limits: % used and reset time, from the status line bridge when it has fresh numbers,
    /// else 100% while a "limit reached" from the logs is still in force.
    private func limits(now: Double) -> [String: Any] {
        var out: [String: Any] = [:]
        let st = ClaudeBridge.latest()
        for (key, type) in [("five", "five_hour"), ("week", "seven_day")] {
            if let s = st?.limits[type], s.reset > now {
                out[key] = ["used": s.used, "reset": s.reset * 1000, "src": "statusline", "at": (st?.at ?? 0) * 1000]
            } else if let r = hits[type], r > now {
                out[key] = ["used": 100, "reset": r * 1000, "src": "limit"]
            }
        }
        return out
    }

    /// Next weekly reset: from Claude Code when known, else the day/time set in the manager (nil when neither).
    private func nextReset(now: Date) -> Date? {
        if let w = limits(now: now.timeIntervalSince1970)["week"] as? [String: Any], let r = w["reset"] as? Double {
            return Date(timeIntervalSince1970: r / 1000)
        }
        let day = ConfigStore.shared.int("claude.resetDay", -1)
        guard (0...6).contains(day) else { return nil }
        let hm = ConfigStore.shared.string("claude.resetTime", "09:00").split(separator: ":").compactMap { Int($0) }
        var c = DateComponents(); c.weekday = day + 1; c.hour = hm.first ?? 9; c.minute = hm.count > 1 ? hm[1] : 0
        return Calendar.current.nextDate(after: now, matching: c, matchingPolicy: .nextTime)
    }

    /// Claude's usage limits run in 5-hour windows that start with your first message. This follows the usual
    /// estimate: a window opens at the hour of the first message after the last one ended.
    private func block(_ sorted: [Rec], now: Double) -> (start: Double, end: Double, tokens: Int, msgs: Int)? {
        var start = 0.0, end = 0.0, tokens = 0, msgs = 0
        for r in sorted {
            if r.t >= end {
                start = floor(r.t / 3600) * 3600; end = start + 5 * 3600; tokens = 0; msgs = 0
            }
            tokens += r.tokens; msgs += 1
        }
        return end > now ? (start, end, tokens, msgs) : nil
    }

    private struct Totals { var tokens = 0, input = 0, cacheW = 0, cacheR = 0, output = 0, msgs = 0
        mutating func add(_ r: Rec) { tokens += r.tokens; input += r.input; cacheW += r.cacheW; cacheR += r.cacheR; output += r.output; msgs += 1 }
        var dict: [String: Any] { ["tokens": tokens, "input": input, "cacheWrite": cacheW, "cacheRead": cacheR, "output": output, "messages": msgs] }
    }

    private func currentContext(_ all: [Rec], _ cat: [String: (window: Int, name: String)], _ names: [String: String]) -> [String: Any]? {
        guard let last = all.filter({ !$0.side }).max(by: { $0.t < $1.t }) else { return nil }
        let known = cat[last.model]?.window ?? 0
        let window = known > 0 ? known : 200_000
        let used = min(last.context, window)
        let folder = cwds[last.session].map { ($0 as NSString).lastPathComponent } ?? ""
        return ["used": used, "window": window, "left": Double(window - used) / Double(window) * 100,
                "model": modelName(last.model, cat), "session": names[last.session] ?? folder, "folder": folder,
                "at": last.t * 1000]
    }

    private func buildSummary() -> [String: Any] {
        let now = Date(), t = now.timeIntervalSince1970
        let all = Array(recs.values).sorted { $0.t < $1.t }
        let cat = catalog(), names = sessionNames()
        let dayStart = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        let reset = nextReset(now: now)
        let weekStart = reset.map { $0.timeIntervalSince1970 - 7 * 86400 } ?? t - 7 * 86400
        var today = 0, week = 0
        for r in all { if r.t >= dayStart { today += r.tokens }; if r.t >= weekStart { week += r.tokens } }
        var out: [String: Any] = ["today": today, "week": week, "any": !all.isEmpty,
                                  "tile": ConfigStore.shared.string("claude.tile", "context"), "limits": limits(now: t),
                                  "bridge": ClaudeBridge.isConnected]
        if let c = currentContext(all, cat, names) { out["ctx"] = c }
        if let r = reset { out["reset"] = r.timeIntervalSince1970 * 1000 }
        if let b = block(all, now: t) { out["block"] = ["end": b.end * 1000, "tokens": b.tokens] }
        return out
    }

    /// Everything for the tap-to-expand sheet.
    func detail() -> [String: Any] {
        return queue.sync { () -> [String: Any] in
            if ConfigStore.shared.bool("claude.enabled", false) { scan() }
            let now = Date(), t = now.timeIntervalSince1970
            let all = Array(recs.values).sorted { $0.t < $1.t }
            let cat = catalog(), names = sessionNames()
            let cal = Calendar.current
            let dayStart = cal.startOfDay(for: now).timeIntervalSince1970
            let reset = nextReset(now: now)
            let weekStart = reset.map { $0.timeIntervalSince1970 - 7 * 86400 } ?? t - 7 * 86400
            var todayT = Totals(), weekT = Totals(), blockT = Totals()
            let blk = block(all, now: t)
            var models: [String: Int] = [:], sessions: [String: (tokens: Int, last: Double)] = [:]
            var days = [Int](repeating: 0, count: 7)
            for r in all {
                if r.t >= dayStart { todayT.add(r) }
                if let b = blk, r.t >= b.start { blockT.add(r) }
                if r.t >= weekStart {
                    weekT.add(r)
                    models[modelName(r.model, cat), default: 0] += r.tokens
                    let s = sessions[r.session] ?? (0, 0)
                    sessions[r.session] = (s.tokens + r.tokens, max(s.last, r.t))
                }
                let ago = cal.dateComponents([.day], from: cal.startOfDay(for: Date(timeIntervalSince1970: r.t)), to: cal.startOfDay(for: now)).day ?? 99
                if (0..<7).contains(ago) { days[6 - ago] += r.tokens }
            }
            var out: [String: Any] = [
                "today": todayT.dict, "week": weekT.dict, "weekFromReset": reset != nil,
                "days": days.enumerated().map { i, v in
                    ["t": cal.date(byAdding: .day, value: i - 6, to: cal.startOfDay(for: now))!.timeIntervalSince1970 * 1000, "tokens": v] },
                "models": models.sorted { $0.value > $1.value }.map { ["name": $0.key, "tokens": $0.value] },
                "sessions": sessions.sorted { $0.value.tokens > $1.value.tokens }.prefix(6).map { k, v in
                    ["name": names[k] ?? cwds[k].map { ($0 as NSString).lastPathComponent } ?? "Session", "tokens": v.tokens, "at": v.last * 1000] },
                "any": !all.isEmpty,
            ]
            if let b = blk { var d = blockT.dict; d["end"] = b.end * 1000; d["start"] = b.start * 1000; out["block"] = d }
            if let c = currentContext(all, cat, names) { out["ctx"] = c }
            if let r = reset { out["reset"] = r.timeIntervalSince1970 * 1000 }
            out["limits"] = limits(now: t); out["bridge"] = ClaudeBridge.isConnected
            return out
        }
    }
}

/// Connects Claude Code's status line to the dashboard. Claude Code hands its status line command the plan's
/// 5-hour and weekly "% used" (Pro and Max plans); a small script saves those numbers and the context window for
/// the dashboard, then runs the status line you had before. Off until you click Connect in the manager, and
/// Disconnect puts your settings back as they were.
enum ClaudeBridge {
    static let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Plinth")
    static var script: URL { dir.appendingPathComponent("claude-statusline.sh") }
    static var previous: URL { dir.appendingPathComponent("claude-statusline-previous.json") }
    static var data: URL { dir.appendingPathComponent("claude-status.json") }
    /// Plan limits on their own, only rewritten when Claude Code reports them (a new session has none until its
    /// first reply, which mustn't wipe what's known).
    static var limitsFile: URL { dir.appendingPathComponent("claude-limits.json") }
    static var settings: URL { URL(fileURLWithPath: ClaudeUsage.root + "/settings.json") }

    struct Status { var limits: [String: (used: Double, reset: Double)]; var at: Double }

    /// The numbers the status line last saved.
    static func latest() -> Status? {
        guard let d = FileManager.default.contents(atPath: limitsFile.path),
              let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        let at = ((try? FileManager.default.attributesOfItem(atPath: limitsFile.path))?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        var l: [String: (Double, Double)] = [:]
        for (k, v) in j {
            guard let o = v as? [String: Any], let u = (o["used_percentage"] as? NSNumber)?.doubleValue,
                  let r = (o["resets_at"] as? NSNumber)?.doubleValue else { continue }
            l[k] = (u, r)
        }
        return Status(limits: l, at: at)
    }

    private static func readSettings() -> [String: Any]? {
        guard let d = FileManager.default.contents(atPath: settings.path) else { return [:] }   // no file yet: start one
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]                     // nil: unreadable, leave it alone
    }

    static var isConnected: Bool {
        guard let s = readSettings(), let sl = s["statusLine"] as? [String: Any], let c = sl["command"] as? String else { return false }
        return c.contains("claude-statusline.sh")
    }

    static var status: [String: Any] {
        var out: [String: Any] = ["connected": isConnected]
        let seen = ((try? FileManager.default.attributesOfItem(atPath: data.path))?[.modificationDate] as? Date)?.timeIntervalSince1970
        if let seen { out["lastData"] = seen * 1000 }
        if let st = latest(), !st.limits.isEmpty { out["hasLimits"] = true; out["lastData"] = max(seen ?? 0, st.at) * 1000 }
        return out
    }

    private static func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// Writes the script (also on every launch, so it stays current after updates).
    static func installScript() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = """
        #!/bin/sh
        # Matchbox Dashboard: keeps the usage numbers Claude Code gives its status line (plan limits and context
        # window) for the dashboard's Claude tile, then runs the status line you had before, if any.
        # Disconnect in Matchbox Dashboard's manager to put your previous status line back.
        dir=\(q(dir.path))
        in=$(cat)
        pick() { printf '%s' "$in" | /usr/bin/plutil -extract "$1" json -o - - 2>/dev/null || printf null; }
        printf '{"context_window":%s}' "$(pick context_window)" > "$dir/.claude-status.$$" && mv -f "$dir/.claude-status.$$" "$dir/claude-status.json"
        lim=$(pick rate_limits)
        [ "$lim" != null ] && printf '%s' "$lim" > "$dir/.claude-limits.$$" && mv -f "$dir/.claude-limits.$$" "$dir/claude-limits.json"
        prev=$(/usr/bin/plutil -extract command raw -o - "$dir/claude-statusline-previous.json" 2>/dev/null)
        if [ -n "$prev" ]; then printf '%s' "$in" | /bin/sh -c "$prev"; exit; fi
        val() { printf '%s' "$in" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null; }
        ctx=$(val context_window.remaining_percentage); five=$(val rate_limits.five_hour.used_percentage); week=$(val rate_limits.seven_day.used_percentage)
        line=""
        [ -n "$ctx" ] && line="Context ${ctx%.*}% left"
        [ -n "$five" ] && line="$line${line:+ · }5h ${five%.*}% used"
        [ -n "$week" ] && line="$line${line:+ · }Week ${week%.*}% used"
        printf '%s\n' "$line"
        """
        try? s.write(to: script, atomically: true, encoding: .utf8)
        chmod(script.path, 0o755)
    }

    private static func writeSettings(_ s: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let d = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try d.write(to: settings, options: .atomic)
    }

    /// Points Claude Code's status line at the script, keeping the one you had so the script can run it.
    static func connect() -> String? {
        guard var s = readSettings() else { return "Claude Code’s settings.json couldn’t be read, so it was left alone." }
        if isConnected { return nil }
        installScript()
        let fm = FileManager.default
        if fm.fileExists(atPath: settings.path) {
            let backup = settings.path + ".matchbox-backup"
            try? fm.removeItem(atPath: backup); try? fm.copyItem(atPath: settings.path, toPath: backup)
        }
        let prev = s["statusLine"] as? [String: Any] ?? [:]
        if let d = try? JSONSerialization.data(withJSONObject: prev) { try? d.write(to: previous, options: .atomic) }
        var sl: [String: Any] = ["type": "command", "command": q(script.path)]
        for k in ["padding", "refreshInterval", "hideVimModeIndicator"] { if let v = prev[k] { sl[k] = v } }
        s["statusLine"] = sl
        do { try writeSettings(s) } catch { return "Couldn’t save Claude Code’s settings: \(error.localizedDescription)" }
        return nil
    }

    /// Puts the previous status line back (or removes ours if there wasn't one).
    static func disconnect() -> String? {
        guard var s = readSettings() else { return "Claude Code’s settings.json couldn’t be read, so it was left alone." }
        guard isConnected else { return nil }
        if let d = FileManager.default.contents(atPath: previous.path),
           let p = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], !p.isEmpty { s["statusLine"] = p }
        else { s.removeValue(forKey: "statusLine") }
        do { try writeSettings(s) } catch { return "Couldn’t save Claude Code’s settings: \(error.localizedDescription)" }
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.removeItem(at: data)
        try? FileManager.default.removeItem(at: limitsFile)
        return nil
    }
}
