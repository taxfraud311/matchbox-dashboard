import Foundation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Steam activity (recent achievements, closest achievements, news for your games — needs a Steam Web API key),
/// exchange rates (Frankfurter / ECB), hourly kanji (kanjiapi.dev + KanjiVG strokes), rain radar (RainViewer)
/// and Slickdeals RSS.
final class MoreFeeds {
    static let shared = MoreFeeds()

    private let lock = NSLock()
    private var data: [String: Any] = [:]
    private var errors: [String: String] = [:]
    private(set) var version = 0
    private var timers: [Timer] = []
    private var pending: DispatchWorkItem?
    private var kanjiLists: [String: [String]] = [:]
    private var kanjiHour = -1, kanjiLevel = ""
    private var schemaCache: [Int: [String: [String: Any]]] = [:]

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) MatchboxDashboard/1.0", "Accept-Language": "en-US"]
        return URLSession(configuration: c)
    }()

    func start() {
        refreshAll()
        let every: [(TimeInterval, () -> Void)] = [
            (1200, { [weak self] in self?.refreshSteam() }),
            (3600, { [weak self] in self?.refreshFX() }),
            (60, { [weak self] in self?.refreshKanji(force: false) }),
            (300, { [weak self] in self?.refreshRadar() }),
            (600, { [weak self] in self?.refreshSlickdeals() }),
        ]
        for (iv, f) in every {
            let t = Timer(timeInterval: iv, repeats: true) { _ in f() }
            RunLoop.main.add(t, forMode: .common); timers.append(t)
        }
        NotificationCenter.default.addObserver(forName: .plinthConfigChanged, object: nil, queue: .main) { [weak self] _ in
            self?.pending?.cancel()
            let w = DispatchWorkItem { self?.refreshAll() }
            self?.pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
        }
    }

    func refreshAll() { refreshSteam(); refreshFX(); refreshKanji(force: true); refreshRadar(); refreshSlickdeals() }

    var snapshot: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var d = data; d["errors"] = errors; return d
    }

    private func put(_ k: String, _ v: Any?, error: String? = nil) {
        lock.lock(); data[k] = v; errors[k] = error; version += 1; lock.unlock()
    }
    private func setError(_ k: String, _ e: String?) { lock.lock(); errors[k] = e; version += 1; lock.unlock() }

    private func get(_ url: URL) -> (Data?, Int, String?) {
        let sem = DispatchSemaphore(value: 0)
        var out: (Data?, Int, String?) = (nil, 0, nil)
        session.dataTask(with: url) { d, r, e in
            out = (d, (r as? HTTPURLResponse)?.statusCode ?? 0, e?.localizedDescription); sem.signal()
        }.resume()
        sem.wait()
        return out
    }
    private func json(_ url: URL) -> Any? {
        let (d, code, _) = get(url)
        guard code < 400, let d else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
    private func bg(_ f: @escaping () -> Void) { DispatchQueue.global(qos: .utility).async(execute: f) }
    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))) ?? s }

    // MARK: - Steam activity

    // Where Steam serves achievement icons now (the old steamcommunity/public/images path misses newer games).
    static let steamCDN = "https://shared.fastly.steamstatic.com/community_assets/images/apps/"

    func refreshSteam() {
        let cfg = ConfigStore.shared
        let key = cfg.string("steam.apiKey", "").trimmingCharacters(in: .whitespaces), profile = cfg.string("steam.profile", "")
        let wantAch = cfg.bool("cards.steamAchievements", true) || cfg.bool("cards.steamClosest", true)
        let wantNews = cfg.bool("cards.steamNews", true)
        guard !profile.isEmpty, !key.isEmpty else {
            put("steamRecent", []); put("steamClosest", []); put("steamNews", [])
            setError("steamActivity", nil)
            return
        }
        bg { [self] in
            guard let sid = ExtraFeeds.shared.resolveSteam(profile)["steamid"] as? String else { return }
            let owned = json(URL(string: "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?key=\(enc(key))&steamid=\(sid)&include_appinfo=1&include_played_free_games=1")!)
            guard let resp = (owned as? [String: Any])?["response"] as? [String: Any] else {
                setError("steamActivity", "Steam didn’t accept the API key, or the profile is private."); return
            }
            let games = ((resp["games"] as? [[String: Any]]) ?? [])
                .filter { (($0["playtime_forever"] as? NSNumber)?.intValue ?? 0) > 0 }
                .sorted { (($0["rtime_last_played"] as? NSNumber)?.doubleValue ?? 0) > (($1["rtime_last_played"] as? NSNumber)?.doubleValue ?? 0) }
            if games.isEmpty && resp["game_count"] == nil {
                setError("steamActivity", "Your game list is private. In Steam, set Privacy › Game details to Public."); return
            }
            setError("steamActivity", nil)
            if wantAch { buildAchievements(Array(games.prefix(25)), key: key, sid: sid) }
            if wantNews { buildNews(Array(games.prefix(18))) }
        }
    }

    private func schema(_ appid: Int, key: String) -> [String: [String: Any]] {
        lock.lock(); if let s = schemaCache[appid] { lock.unlock(); return s }; lock.unlock()
        var out: [String: [String: Any]] = [:]
        // Global unlock rates (no key needed)…
        if let r = (json(URL(string: "https://api.steampowered.com/IPlayerService/GetGameAchievements/v1/?appid=\(appid)&language=english")!) as? [String: Any])?["response"] as? [String: Any] {
            for a in (r["achievements"] as? [[String: Any]]) ?? [] { if let n = a["internal_name"] as? String { out[n] = a } }
        }
        lock.lock(); schemaCache[appid] = out; lock.unlock()
        return out
    }

    private func buildAchievements(_ games: [[String: Any]], key: String, sid: String) {
        var recent: [[String: Any]] = [], closest: [[String: Any]] = []
        for g in games {
            guard let appid = (g["appid"] as? NSNumber)?.intValue else { continue }
            let gname = g["name"] as? String ?? ""
            guard let ps = (json(URL(string: "https://api.steampowered.com/ISteamUserStats/GetPlayerAchievements/v1/?key=\(enc(key))&steamid=\(sid)&appid=\(appid)&l=english")!) as? [String: Any])?["playerstats"] as? [String: Any],
                  let list = ps["achievements"] as? [[String: Any]], !list.isEmpty else { continue }
            let sch = schema(appid, key: key)
            let unlocked = list.filter { ($0["achieved"] as? NSNumber)?.intValue == 1 }
            let page = "https://steamcommunity.com/profiles/\(sid)/stats/\(appid)/achievements/"
            func item(_ a: [String: Any]) -> [String: Any] {
                let api = a["apiname"] as? String ?? "", s = sch[api] ?? [:]
                let icon = (s["icon"] as? String).flatMap { $0.isEmpty ? nil : MoreFeeds.steamCDN + "\(appid)/" + $0 } ?? ""
                return ["game": gname, "appid": appid, "name": (a["name"] as? String) ?? (s["localized_name"] as? String) ?? api,
                        "desc": (a["description"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (s["localized_desc"] as? String) ?? "",
                        "hidden": (s["hidden"] as? Bool) ?? false, "icon": icon,
                        "pct": Double(s["player_percent_unlocked"] as? String ?? "") ?? (s["player_percent_unlocked"] as? NSNumber)?.doubleValue ?? 0,
                        "got": unlocked.count, "total": list.count, "url": page]
            }
            for a in unlocked {
                var it = item(a); it["at"] = ((a["unlocktime"] as? NSNumber)?.doubleValue ?? 0) * 1000
                recent.append(it)
            }
            if unlocked.count < list.count {
                let locked = list.filter { ($0["achieved"] as? NSNumber)?.intValue != 1 }.map(item)
                    .sorted { ($0["pct"] as? Double ?? 0) > ($1["pct"] as? Double ?? 0) }
                closest += locked.prefix(2)
            }
        }
        recent.sort { ($0["at"] as? Double ?? 0) > ($1["at"] as? Double ?? 0) }
        // Most-earned achievements you're still missing, favoring games you're furthest through.
        closest.sort {
            let a = ($0["pct"] as? Double ?? 0) + 30 * Double($0["got"] as? Int ?? 0) / Double(max(1, $0["total"] as? Int ?? 1))
            let b = ($1["pct"] as? Double ?? 0) + 30 * Double($1["got"] as? Int ?? 0) / Double(max(1, $1["total"] as? Int ?? 1))
            return a > b
        }
        put("steamRecent", Array(recent.prefix(12)))
        put("steamClosest", Array(closest.prefix(12)))
    }

    private func buildNews(_ games: [[String: Any]]) {
        var out: [[String: Any]] = []
        let cutoff = Date().timeIntervalSince1970 - 60 * 86400
        for g in games {
            guard let appid = (g["appid"] as? NSNumber)?.intValue else { continue }
            guard let items = ((json(URL(string: "https://api.steampowered.com/ISteamNews/GetNewsForApp/v2/?appid=\(appid)&count=3&maxlength=0&feeds=steam_community_announcements")!) as? [String: Any])?["appnews"] as? [String: Any])?["newsitems"] as? [[String: Any]] else { continue }
            for n in items {
                let date = (n["date"] as? NSNumber)?.doubleValue ?? 0
                guard date > cutoff, let title = n["title"] as? String, let gid = n["gid"] as? String else { continue }
                let body = n["contents"] as? String ?? ""
                out.append(["game": g["name"] ?? "", "appid": appid, "title": title, "date": date * 1000,
                            "text": MoreFeeds.plain(body, limit: 220),
                            "img": MoreFeeds.firstImage(body) ?? "", "noImg": MoreFeeds.firstImage(body) == nil,
                            "url": "https://store.steampowered.com/news/app/\(appid)/view/\(gid)"])
            }
        }
        out.sort { ($0["date"] as? Double ?? 0) > ($1["date"] as? Double ?? 0) }
        out = Array(out.prefix(16))
        let need = Set(out.filter { ($0["noImg"] as? Bool) == true }.compactMap { $0["appid"] as? Int })
        if !need.isEmpty {
            let input: [String: Any] = ["ids": need.map { ["appid": $0] }, "context": ["language": "english", "country_code": "US"],
                                        "data_request": ["include_assets": true]]
            if let data = try? JSONSerialization.data(withJSONObject: input), var c = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/") {
                c.queryItems = [.init(name: "input_json", value: String(decoding: data, as: UTF8.self))]
                let items = (((json(c.url!) as? [String: Any])?["response"] as? [String: Any])?["store_items"] as? [[String: Any]]) ?? []
                var art: [Int: String] = [:]
                for it in items { if let id = (it["appid"] as? NSNumber)?.intValue { art[id] = ExtraFeeds.capsule(it) } }
                out = out.map { var n = $0; if (n["noImg"] as? Bool) == true, let id = n["appid"] as? Int, let a = art[id] { n["img"] = a }; return n }
            }
        }
        put("steamNews", out)
    }

    static func firstImage(_ s: String) -> String? {
        if let r = s.range(of: #"\{STEAM_CLAN_IMAGE\}/[^\s\[\]"<>]+"#, options: .regularExpression) {
            return "https://clan.akamai.steamstatic.com/images/" + s[r].dropFirst("{STEAM_CLAN_IMAGE}/".count)
        }
        for pat in [#"\[img(?: [^\]]*)?\](https://[^\[]+)\[/img\]"#, #"<img[^>]+src="(https://[^"]+)""#, #"\[img src="(https://[^"]+)""#] {
            if let re = try? NSRegularExpression(pattern: pat), let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
               let r = Range(m.range(at: 1), in: s) { return String(s[r]) }
        }
        return nil
    }

    static func plain(_ s: String, limit: Int) -> String {
        var t = s.replacingOccurrences(of: #"\{STEAM_CLAN_IMAGE\}\S*"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[(img|previewyoutube|video)[^\]]*\].*?\[/\1\]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[/?(p|h\d|list|olist|\*|tr|td|th|table)[^\]]*\]"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[[^\]]{0,200}\]"#, with: "", options: .regularExpression)
        t = FeedParser.clean(t).trimmingCharacters(in: .whitespaces)
        return t.count > limit ? String(t.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : t
    }

    // MARK: - Exchange rates (ECB reference rates via Frankfurter, updated each business day)

    func refreshFX() {
        let pairs = (ConfigStore.shared.value("exchange.pairs") as? [[String: Any]] ?? []).compactMap { p -> (String, String)? in
            guard let f = p["from"] as? String, let t = p["to"] as? String, f != t else { return nil }; return (f, t)
        }
        guard !pairs.isEmpty else { put("fx", []); return }
        bg { [self] in
            let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd"; df.timeZone = TimeZone(identifier: "UTC")
            let start = df.string(from: Date().addingTimeInterval(-45 * 86400))
            var out: [[String: Any]] = [], err: String?
            for (f, t) in pairs.prefix(4) {
                guard let j = json(URL(string: "https://api.frankfurter.dev/v1/\(start)..?from=\(f)&to=\(t)")!) as? [String: Any],
                      let rates = j["rates"] as? [String: [String: Any]] else { err = "Couldn’t load rates for \(f)→\(t)"; continue }
                let days = rates.keys.sorted()
                let series = days.compactMap { (rates[$0]?[t] as? NSNumber)?.doubleValue }
                guard let last = series.last else { continue }
                let prev = series.count > 1 ? series[series.count - 2] : last
                out.append(["from": f, "to": t, "rate": last, "date": days.last ?? "", "series": series, "dates": days,
                            "d1": prev > 0 ? (last - prev) / prev * 100 : 0, "d30": series.first.map { $0 > 0 ? (last - $0) / $0 * 100 : 0 } ?? 0,
                            "url": "https://www.xe.com/currencyconverter/convert/?Amount=1&From=\(f)&To=\(t)"])
            }
            put("fx", out, error: out.isEmpty ? err : nil)
        }
    }

    // MARK: - Kanji of the hour

    func refreshKanji(force: Bool) {
        let level = ConfigStore.shared.string("kanji.level", "jlpt-4")
        let hour = Int(Date().timeIntervalSince1970 / 3600)
        lock.lock(); let same = hour == kanjiHour && level == kanjiLevel; lock.unlock()
        if same && !force { return }
        bg { [self] in
            lock.lock(); var list = kanjiLists[level]; lock.unlock()
            if list == nil {
                guard let l = json(URL(string: "https://kanjiapi.dev/v1/kanji/\(level)")!) as? [String], !l.isEmpty else { setError("kanji", "Couldn’t reach kanjiapi.dev"); return }
                // A fixed shuffle, so every kanji comes up once before any repeats.
                list = l.sorted { MoreFeeds.mix($0) < MoreFeeds.mix($1) }
                lock.lock(); kanjiLists[level] = list; lock.unlock()
            }
            guard let all = list else { return }
            func pick(_ h: Int) -> String { all[((h % all.count) + all.count) % all.count] }
            let k = pick(hour)
            guard let code = k.unicodeScalars.first?.value,
                  var info = json(URL(string: "https://kanjiapi.dev/v1/kanji/" + enc(k))!) as? [String: Any] else { setError("kanji", "Couldn’t reach kanjiapi.dev"); return }
            info["words"] = examples(k)
            info["strokes"] = strokes(code)
            info["hour"] = Double(hour) * 3600 * 1000
            info["next"] = pick(hour + 1)
            info["url"] = "https://jisho.org/search/" + enc(k) + "%20%23kanji"
            info["level"] = level
            lock.lock(); kanjiHour = hour; kanjiLevel = level; lock.unlock()
            put("kanji", info)
        }
    }

    private static func mix(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return h
    }

    private func examples(_ k: String) -> [[String: Any]] {
        guard let words = json(URL(string: "https://kanjiapi.dev/v1/words/" + enc(k))!) as? [[String: Any]] else { return [] }
        var scored: [(Double, [String: Any])] = []
        var seen = Set<String>()
        for w in words {
            guard let v = (w["variants"] as? [[String: Any]])?.first, let written = v["written"] as? String, written.contains(k),
                  written.count >= 2, written.count <= 4, !seen.contains(written) else { continue }
            let pri = (v["priorities"] as? [String]) ?? []
            if pri.isEmpty { continue }
            var score = 0.0
            for p in pri {
                if p == "ichi1" || p == "news1" || p == "spec1" { score += 3 } else if p.hasSuffix("2") { score += 1 }
                if p.hasPrefix("nf"), let n = Double(p.dropFirst(2)) { score += (48 - n) / 8 }
            }
            score -= Double(written.count) * 0.4
            let gloss = ((w["meanings"] as? [[String: Any]])?.first?["glosses"] as? [String] ?? []).prefix(2).joined(separator: "; ")
            seen.insert(written)
            scored.append((score, ["w": written, "r": v["pronounced"] ?? "", "m": gloss]))
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(3).map { $0.1 }
    }

    private func strokes(_ code: UInt32) -> [String] {
        let hex = String(format: "%05x", code)
        guard let d = get(URL(string: "https://raw.githubusercontent.com/KanjiVG/kanjivg/master/kanji/\(hex).svg")!).0 else { return [] }
        let s = String(decoding: d, as: UTF8.self)
        guard let re = try? NSRegularExpression(pattern: #"<path id="kvg:[0-9a-f]+-s\d+"[^>]*? d="([^"]+)""#) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range(at: 1), in: s).map { String(s[$0]) } }
    }

    // MARK: - Rain radar (RainViewer — free tiles up to zoom 7)

    func refreshRadar() {
        let cfg = ConfigStore.shared
        let useWx = cfg.bool("radar.useWeatherLocation", true)
        let lat = cfg.double(useWx ? "location.lat" : "radar.lat", cfg.double("location.lat", 0))
        let lon = cfg.double(useWx ? "location.lon" : "radar.lon", cfg.double("location.lon", 0))
        let name = cfg.string(useWx ? "location.name" : "radar.name", "")
        let zoom = max(3, min(7, cfg.int("radar.zoom", 6)))
        bg { [self] in
            guard let j = json(URL(string: "https://api.rainviewer.com/public/weather-maps.json")!) as? [String: Any],
                  let host = j["host"] as? String, let radar = j["radar"] as? [String: Any] else { setError("radar", "Couldn’t reach RainViewer"); return }
            let frames = ((radar["past"] as? [[String: Any]]) ?? []) + ((radar["nowcast"] as? [[String: Any]]) ?? [])
            put("radar", ["host": host, "lat": lat, "lon": lon, "zoom": zoom, "name": name,
                          "frames": frames.suffix(10).map { ["t": (($0["time"] as? NSNumber)?.doubleValue ?? 0) * 1000, "path": $0["path"] ?? ""] },
                          "url": "https://www.rainviewer.com/map.html?loc=\(lat),\(lon),\(zoom)&layer=radar"])
        }
    }

    // MARK: - Slickdeals

    func refreshSlickdeals() {
        let cfg = ConfigStore.shared
        var sources: [(String, String)] = []
        if cfg.bool("slickdeals.frontpage", true) { sources.append(("Frontpage", "https://slickdeals.net/newsearch.php?mode=frontpage&searcharea=deals&searchin=first&rss=1")) }
        if cfg.bool("slickdeals.popular", false) { sources.append(("Popular", "https://slickdeals.net/newsearch.php?mode=popdeals&searcharea=deals&searchin=first&rss=1")) }
        for q in cfg.strings("slickdeals.searches").prefix(8) where !q.trimmingCharacters(in: .whitespaces).isEmpty {
            sources.append((q, "https://slickdeals.net/newsearch.php?searcharea=deals&searchin=first&rss=1&q=" + enc(q)))
        }
        guard !sources.isEmpty else { put("slickdeals", []); return }
        bg { [self] in
            var out: [[String: Any]] = [], seen = Set<String>(), ok = false
            for (label, u) in sources {
                guard let d = get(URL(string: u)!).0 else { continue }
                ok = true
                for var it in SlickParser(data: d).parse().prefix(15) {
                    let id = it["id"] as? String ?? it["link"] as? String ?? ""
                    if seen.contains(id) { continue }
                    seen.insert(id); it["source"] = label; out.append(it)
                }
            }
            out.sort { ($0["date"] as? Double ?? 0) > ($1["date"] as? Double ?? 0) }
            put("slickdeals", Array(out.prefix(24)), error: ok ? nil : "Couldn’t reach Slickdeals")
        }
    }

    // MARK: - QR codes for the tablet's "open on your phone" sheet

    private let qrCache = NSCache<NSString, NSData>()
    func qrPNG(_ text: String) -> Data? {
        guard text.count < 1500, let u = URL(string: text), ["http", "https"].contains(u.scheme ?? "") else { return nil }
        if let d = qrCache.object(forKey: text as NSString) { return d as Data }
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8); f.correctionLevel = "M"
        guard let img = f.outputImage else { return nil }
        let scaled = img.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let ctx = CIContext(options: [.useSoftwareRenderer: true])
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        qrCache.setObject(png as NSData, forKey: text as NSString)
        return png
    }
}

/// Slickdeals RSS: title, link, image and thumbs-up score from content:encoded.
final class SlickParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [[String: Any]] = []
    private var cur: [String: String]?
    private var text = ""
    init(data: Data) { self.data = data }

    func parse() -> [[String: Any]] { let p = XMLParser(data: data); p.delegate = self; p.parse(); return items }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""; if el == "item" { cur = [:] }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ parser: XMLParser, foundCDATA b: Data) { text += String(decoding: b, as: UTF8.self) }
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        guard cur != nil else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "title", "link", "pubDate", "guid", "content:encoded": cur?[el] = t
        case "item":
            if let c = cur, let title = c["title"], !title.isEmpty {
                var link = c["link"] ?? ""
                if let q = link.firstIndex(of: "?") { link = String(link[..<q]) }
                let html = c["content:encoded"] ?? ""
                var it: [String: Any] = ["title": FeedParser.clean(title), "link": link, "id": c["guid"] ?? link]
                if let d = c["pubDate"], let ms = FeedParser.parseDate(d) { it["date"] = ms }
                if let r = html.range(of: #"<img src="(https://[^"]+)""#, options: .regularExpression) {
                    it["img"] = String(html[r]).replacingOccurrences(of: "<img src=\"", with: "").replacingOccurrences(of: "\"", with: "")
                }
                if let r = html.range(of: #"Thumb Score: [+-]?\d+"#, options: .regularExpression) {
                    it["score"] = Int(html[r].replacingOccurrences(of: "Thumb Score: ", with: "").replacingOccurrences(of: "+", with: "")) ?? 0
                }
                if let re = try? NSRegularExpression(pattern: #"<a [^>]*data-cta="outclick"[^>]*>([^<]{1,60})</a>"#),
                   let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let r = Range(m.range(at: 1), in: html) {
                    it["store"] = FeedParser.clean(String(html[r]))
                }
                if let r = title.range(of: #"\$[0-9][0-9,]*(\.[0-9]{2})?"#, options: .regularExpression) { it["price"] = String(title[r]) }
                else if title.localizedCaseInsensitiveContains("free") { it["price"] = "Free" }
                items.append(it)
            }
            cur = nil
        default: break
        }
        text = ""
    }
}
