import Foundation

/// Fetches and caches external info (weather, sports, headlines) so the tablet only ever talks to the Mac.
final class FeedService {
    static let shared = FeedService()

    private let lock = NSLock()
    private var weather: Any = NSNull()
    private var weatherAt: Date?
    private var sports: [[String: Any]] = []
    private var sportsAt: Date?
    private var news: [[String: Any]] = []
    private var newsAt: Date?
    private(set) var errors: [String: String] = [:]
    private var version = 0

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpAdditionalHeaders = ["User-Agent": "MatchboxDashboard/1.0 (macOS info display)"]
        return URLSession(configuration: c)
    }()

    private var timers: [Timer] = []

    func start() {
        refreshAll()
        // Sports refresh faster when something is live.
        schedule(every: 30) { [weak self] in
            guard let self else { return }
            let live = self.snapshot["sportsLive"] as? Bool ?? false
            if live || (self.sportsAt.map { Date().timeIntervalSince($0) > 180 } ?? true) { self.refreshSports() }
        }
        schedule(every: 600) { [weak self] in self?.refreshWeather() }
        schedule(every: 600) { [weak self] in self?.refreshNews() }
        NotificationCenter.default.addObserver(forName: .plinthConfigChanged, object: nil, queue: .main) { [weak self] _ in
            // Debounce: the manager may save several times quickly.
            self?.pendingRefresh?.cancel()
            let w = DispatchWorkItem { self?.refreshAll() }
            self?.pendingRefresh = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: w)
        }
    }

    private var pendingRefresh: DispatchWorkItem?

    func refreshAll() { refreshWeather(); refreshSports(); refreshNews() }

    private func schedule(every s: TimeInterval, _ block: @escaping () -> Void) {
        let t = Timer(timeInterval: s, repeats: true) { _ in block() }
        RunLoop.main.add(t, forMode: .common)
        timers.append(t)
    }

    var snapshot: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        let live = sports.contains { ($0["state"] as? String) == "in" }
        return [
            "version": version,
            "weather": weather,
            "weatherAt": weatherAt.map { $0.timeIntervalSince1970 * 1000 } ?? NSNull(),
            "sports": sports,
            "sportsLive": live,
            "news": news,
            "errors": errors,
        ]
    }

    private func setError(_ key: String, _ msg: String?) {
        lock.lock(); errors[key] = msg; lock.unlock()
    }

    private func fetch(_ url: URL, _ done: @escaping (Data?, String?) -> Void) {
        session.dataTask(with: url) { data, resp, err in
            if let err { return done(nil, err.localizedDescription) }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code >= 400 { return done(nil, "HTTP \(code)") }
            done(data, nil)
        }.resume()
    }

    // MARK: Weather (Open-Meteo, no key needed)

    func refreshWeather() {
        let cfg = ConfigStore.shared
        let lat = cfg.double("location.lat", 37.7749), lon = cfg.double("location.lon", -122.4194)
        let metric = cfg.string("units", "imperial") == "metric"
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day,precipitation,pressure_msl,uv_index,visibility,dew_point_2m"),
            .init(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,uv_index_max,precipitation_sum,wind_speed_10m_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "7"),
            .init(name: "forecast_hours", value: "24"),
            .init(name: "temperature_unit", value: metric ? "celsius" : "fahrenheit"),
            .init(name: "wind_speed_unit", value: metric ? "kmh" : "mph"),
        ]
        fetch(c.url!) { [weak self] data, err in
            guard let self else { return }
            if let data, let j = try? JSONSerialization.jsonObject(with: data) {
                self.lock.lock(); self.weather = j; self.weatherAt = Date(); self.version += 1; self.lock.unlock()
                self.setError("weather", nil)
            } else {
                self.setError("weather", err ?? "Bad weather response")
            }
        }
    }

    // MARK: Sports (ESPN public scoreboard JSON)

    static let leagueNames: [String: String] = [
        "football/nfl": "NFL", "basketball/nba": "NBA", "baseball/mlb": "MLB", "hockey/nhl": "NHL",
        "basketball/wnba": "WNBA", "football/college-football": "NCAAF",
        "basketball/mens-college-basketball": "NCAAM", "basketball/womens-college-basketball": "NCAAW",
        "soccer/usa.1": "MLS", "soccer/eng.1": "Premier League", "soccer/esp.1": "La Liga",
        "soccer/uefa.champions": "Champions League", "soccer/usa.nwsl": "NWSL",
    ]

    func refreshSports() {
        let cfg = ConfigStore.shared
        let leagues = cfg.strings("sports.leagues")
        let favs = Set(cfg.strings("sports.favorites").map { $0.uppercased().trimmingCharacters(in: .whitespaces) })
        if leagues.isEmpty {
            lock.lock(); sports = []; sportsAt = Date(); version += 1; lock.unlock()
            return
        }
        let group = DispatchGroup()
        var all: [[String: Any]] = []
        var errs: [String] = []
        let collect = NSLock()
        for league in leagues {
            guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league)/scoreboard") else { continue }
            group.enter()
            fetch(url) { data, err in
                defer { group.leave() }
                guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    collect.lock(); errs.append("\(league): \(err ?? "bad response")"); collect.unlock(); return
                }
                let parsed = FeedService.parseScoreboard(j, league: league, favorites: favs)
                collect.lock(); all.append(contentsOf: parsed); collect.unlock()
            }
        }
        group.notify(queue: .global()) { [weak self] in
            guard let self else { return }
            let rank: ([String: Any]) -> Int = { g in
                switch g["state"] as? String { case "in": return 0; case "pre": return 1; default: return 2 }
            }
            all.sort { a, b in
                let fa = (a["favorite"] as? Bool) == true, fb = (b["favorite"] as? Bool) == true
                if rank(a) != rank(b) { return rank(a) < rank(b) }
                if fa != fb { return fa }
                let da = a["date"] as? String ?? "", db = b["date"] as? String ?? ""
                return rank(a) == 2 ? da > db : da < db
            }
            self.lock.lock(); self.sports = all; self.sportsAt = Date(); self.version += 1; self.lock.unlock()
            self.setError("sports", errs.isEmpty ? nil : errs.joined(separator: "; "))
        }
    }

    static func parseScoreboard(_ j: [String: Any], league: String, favorites: Set<String>) -> [[String: Any]] {
        let leagueAbbr = leagueNames[league]
            ?? ((j["leagues"] as? [[String: Any]])?.first?["abbreviation"] as? String) ?? league.uppercased()
        var out: [[String: Any]] = []
        for ev in (j["events"] as? [[String: Any]]) ?? [] {
            guard let comp = (ev["competitions"] as? [[String: Any]])?.first,
                  let competitors = comp["competitors"] as? [[String: Any]] else { continue }
            let statusType = ((ev["status"] as? [String: Any])?["type"] as? [String: Any]) ?? [:]
            var teams: [String: [String: Any]] = [:]
            var isFav = false
            for c in competitors {
                let team = c["team"] as? [String: Any] ?? [:]
                let abbr = (team["abbreviation"] as? String) ?? "?"
                let short = (team["shortDisplayName"] as? String) ?? (team["name"] as? String) ?? abbr
                let display = (team["displayName"] as? String) ?? short
                let fav = favorites.contains(abbr.uppercased()) || favorites.contains(short.uppercased())
                    || favorites.contains(display.uppercased())
                isFav = isFav || fav
                let record = ((c["records"] as? [[String: Any]])?.first?["summary"] as? String) ?? ""
                teams[(c["homeAway"] as? String) ?? "home"] = [
                    "abbr": abbr, "name": short, "color": (team["color"] as? String) ?? "888888",
                    "alt": (team["alternateColor"] as? String) ?? "ffffff",
                    "score": (c["score"] as? String) ?? "", "record": record, "favorite": fav,
                    "winner": (c["winner"] as? Bool) ?? false,
                ]
            }
            var nets: [String] = []
            for b in (comp["broadcasts"] as? [[String: Any]]) ?? [] {
                for n in (b["names"] as? [String]) ?? [] where !nets.contains(n) { nets.append(n) }
            }
            if nets.isEmpty {
                for g in (comp["geoBroadcasts"] as? [[String: Any]]) ?? [] {
                    if let n = (g["media"] as? [String: Any])?["shortName"] as? String, !nets.contains(n) { nets.append(n) }
                }
            }
            let situation = comp["situation"] as? [String: Any]
            out.append([
                "id": ev["id"] as? String ?? UUID().uuidString,
                "league": leagueAbbr,
                "leagueKey": league,
                "date": ev["date"] as? String ?? "",
                "state": statusType["state"] as? String ?? "pre",
                "detail": statusType["shortDetail"] as? String ?? "",
                "home": teams["home"] ?? [:],
                "away": teams["away"] ?? [:],
                "broadcasts": nets,
                "situation": (situation?["downDistanceText"] as? String) ?? (situation?["shortDownDistanceText"] as? String) ?? "",
                "favorite": isFav,
            ])
        }
        return out
    }

    // MARK: News (RSS 2.0 / Atom)

    func refreshNews() {
        let cfg = ConfigStore.shared
        let feeds = ((cfg.value("feeds") as? [[String: Any]]) ?? []).filter { ($0["enabled"] as? Bool) ?? true }
        let group = DispatchGroup()
        var results: [(Int, [String: Any])] = []
        var errs: [String] = []
        let collect = NSLock()
        for (i, f) in feeds.enumerated() {
            guard let s = f["url"] as? String, let url = URL(string: s) else { continue }
            let name = (f["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            group.enter()
            fetch(url) { data, err in
                defer { group.leave() }
                guard let data else { collect.lock(); errs.append("\(name ?? s): \(err ?? "?")"); collect.unlock(); return }
                let p = FeedParser(data: data)
                let items = p.parse()
                if items.isEmpty { collect.lock(); errs.append("\(name ?? s): no items"); collect.unlock(); return }
                let feed: [String: Any] = ["name": name ?? p.channelTitle ?? url.host ?? s, "items": Array(items.prefix(12))]
                collect.lock(); results.append((i, feed)); collect.unlock()
            }
        }
        group.notify(queue: .global()) { [weak self] in
            guard let self else { return }
            let sorted = results.sorted { $0.0 < $1.0 }.map { $0.1 }
            self.lock.lock(); self.news = sorted; self.newsAt = Date(); self.version += 1; self.lock.unlock()
            self.setError("news", errs.isEmpty ? nil : errs.joined(separator: "; "))
        }
    }
}

final class FeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [[String: Any]] = []
    private var current: [String: String]?
    private var text = ""
    private var depthInItem = false
    private(set) var channelTitle: String?
    private var sawChannelTitle = false

    init(data: Data) { self.data = data }

    func parse() -> [[String: Any]] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.shouldResolveExternalEntities = false
        p.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        if name == "item" || name == "entry" { current = [:]; depthInItem = true }
        if depthInItem, name == "link", let href = attributes["href"], current?["link"] == nil { current?["link"] = href }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if depthInItem {
            switch name {
            case "title": current?["title"] = FeedParser.clean(t)
            case "link": if !t.isEmpty { current?["link"] = t }
            case "pubDate", "published", "updated", "dc:date":
                if current?["date"] == nil { current?["date"] = t }
            case "item", "entry":
                if var c = current, let title = c["title"], !title.isEmpty {
                    var item: [String: Any] = ["title": title, "link": c["link"] ?? ""]
                    if let d = c.removeValue(forKey: "date"), let ms = FeedParser.parseDate(d) { item["date"] = ms }
                    items.append(item)
                }
                current = nil; depthInItem = false
            default: break
            }
        } else if name == "title", !sawChannelTitle {
            channelTitle = FeedParser.clean(t); sawChannelTitle = true
        }
        text = ""
    }

    static func clean(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (k, v) in ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
                       "&#8217;": "’", "&#8216;": "‘", "&#8220;": "“", "&#8221;": "”", "&#8211;": "–", "&#8212;": "—"] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static let rfc822: [DateFormatter] = ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz",
                                                  "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm Z"].map {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = $0; return f
    }
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); return f }()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    static func parseDate(_ s: String) -> Double? {
        if let d = iso.date(from: s) ?? isoFrac.date(from: s) { return d.timeIntervalSince1970 * 1000 }
        for f in rfc822 { if let d = f.date(from: s) { return d.timeIntervalSince1970 * 1000 } }
        return nil
    }
}
