import Foundation

/// Claude Code usage from its own local logs (~/.claude/projects/**/*.jsonl): context left in the most recent
/// session, tokens per day / week / 5-hour window, and the time to the weekly reset the user sets in the manager.
/// Only the usage numbers, model, session id and folder are read from each line, never the conversation itself.
/// Plan limits (the "% used" Claude shows) aren't stored on the Mac, so they aren't shown.
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

    private static let root = NSHomeDirectory() + "/.claude"
    private static let keepDays = 9.0

    func start() {
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
        if model.hasPrefix("<") { return }          // "<synthetic>" placeholder messages
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

    /// Next weekly reset from the day/time set in the manager (nil when not set).
    private func nextReset(now: Date) -> Date? {
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
        var out: [String: Any] = ["today": today, "week": week, "any": !all.isEmpty]
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
            return out
        }
    }
}
