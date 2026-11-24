import Foundation

/// YouTube uploads from followed channels (public RSS, no sign-in) and anime episode schedules (AniList's public API).
final class MediaFeeds {
    static let shared = MediaFeeds()

    private let lock = NSLock()
    private var youtube: [[String: Any]] = []
    private var anime: [[String: Any]] = []
    private var errors: [String: String] = [:]
    private(set) var version = 0
    private var timers: [Timer] = []
    private var pending: DispatchWorkItem?

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                                   "Accept-Language": "en-US,en;q=0.9"]
        c.httpCookieStorage = nil
        return URLSession(configuration: c)
    }()

    func start() {
        refreshAll()
        for (interval, block) in [(900.0, { [weak self] in self?.refreshYouTube() }),
                                  (900.0, { [weak self] in self?.refreshAnime() })] as [(TimeInterval, () -> Void)] {
            let t = Timer(timeInterval: interval, repeats: true) { _ in block() }
            RunLoop.main.add(t, forMode: .common)
            timers.append(t)
        }
        NotificationCenter.default.addObserver(forName: .plinthConfigChanged, object: nil, queue: .main) { [weak self] _ in
            self?.pending?.cancel()
            let w = DispatchWorkItem { self?.refreshAll() }
            self?.pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
        }
    }

    func refreshAll() { refreshYouTube(); refreshAnime() }

    var snapshot: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["youtube": youtube, "anime": anime, "errors": errors, "version": version]
    }

    private func setError(_ k: String, _ v: String?) { lock.lock(); errors[k] = v; lock.unlock() }

    private func get(_ url: URL) -> (Data?, String?) {
        let sem = DispatchSemaphore(value: 0)
        var out: (Data?, String?) = (nil, nil)
        var req = URLRequest(url: url)
        // OpenStreetMap's tile policy asks apps to identify themselves honestly.
        if url.host == "tile.openstreetmap.org" { req.setValue("MatchboxDashboard/1.0 (personal home info display; macOS)", forHTTPHeaderField: "User-Agent") }
        session.dataTask(with: req) { d, r, e in
            let code = (r as? HTTPURLResponse)?.statusCode ?? 0
            out = e != nil ? (nil, e!.localizedDescription) : code >= 400 ? (nil, "HTTP \(code)") : (d, nil)
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    // MARK: - YouTube

    func refreshYouTube() {
        let cfg = ConfigStore.shared
        let channels = (cfg.value("youtube.channels") as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let maxAge = TimeInterval(max(1, cfg.int("youtube.maxAgeDays", 7))) * 86400
        let hideShorts = cfg.bool("youtube.hideShorts", true)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var videos: [[String: Any]] = []
            var failed = 0
            let collect = NSLock()
            // Fetch feeds in parallel (one per CPU core) — people often follow hundreds of channels.
            DispatchQueue.concurrentPerform(iterations: channels.count) { i in
                guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channels[i])") else { return }
                let (data, _) = self.get(url)
                guard let data else { collect.lock(); failed += 1; collect.unlock(); return }
                let items = YouTubeFeedParser(data: data).parse()
                collect.lock(); videos.append(contentsOf: items); collect.unlock()
            }
            let cutoff = Date().timeIntervalSince1970 * 1000 - maxAge * 1000
            videos = videos.filter { ($0["date"] as? Double ?? 0) >= cutoff }
            if hideShorts { videos = videos.filter { ($0["short"] as? Bool) != true } }
            videos.sort { ($0["date"] as? Double ?? 0) > ($1["date"] as? Double ?? 0) }
            self.lock.lock()
            self.youtube = Array(videos.prefix(30))
            self.version += 1
            self.lock.unlock()
            self.setError("youtube", failed > 0 && failed == channels.count ? "Couldn’t reach YouTube" :
                                     failed > 0 ? "\(failed) of \(channels.count) channel feeds failed to load" : nil)
        }
    }

    /// Turns a channel URL, @handle or channel ID into { id, title }.
    func resolveChannel(_ input: String) -> [String: Any] {
        var q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = q.range(of: #"UC[A-Za-z0-9_-]{22}"#, options: .regularExpression) {
            let id = String(q[r])
            return ["id": id, "title": channelTitle(id) ?? id]
        }
        if q.hasPrefix("@") { q = "https://www.youtube.com/" + q }
        if !q.lowercased().hasPrefix("http") { q = "https://www.youtube.com/@" + q }
        guard let url = URL(string: q) else { return ["error": "That doesn’t look like a YouTube channel"] }
        let (data, err) = get(url)
        guard let data else { return ["error": err ?? "Couldn’t load that page"] }
        let html = String(decoding: data, as: UTF8.self)
        func first(_ p: String) -> String? {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let r = Range(m.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }
        // Only markers that describe the page's own channel. A loose "channelId" also matches featured and
        // linked channels (the @DSPTriesItMemology101 page links Memology 101 before its own id appears).
        let patterns = [#"<link rel="canonical" href="https://www\.youtube\.com/channel/(UC[A-Za-z0-9_-]{22})""#,
                        #"<meta property="og:url" content="https://www\.youtube\.com/channel/(UC[A-Za-z0-9_-]{22})""#,
                        #""channelMetadataRenderer":\{[^{}]*?"externalId":"(UC[A-Za-z0-9_-]{22})""#,
                        #""externalId":"(UC[A-Za-z0-9_-]{22})""#]
        guard let id = patterns.lazy.compactMap(first).first else { return ["error": "Couldn’t find a channel at that address"] }
        var out: [String: Any] = ["id": id, "title": channelTitle(id) ?? q]
        if let h = first(#""vanityChannelUrl":"https?://www\.youtube\.com/(@[^"/?]+)""#) {
            out["handle"] = h.removingPercentEncoding ?? h
            // Asked for a handle but landed on a different channel's page (a redirect): don't guess.
            if let asked = q.range(of: #"/(@[^/?#]+)"#, options: .regularExpression).map({ String(q[$0].dropFirst()) }),
               (asked.removingPercentEncoding ?? asked).lowercased() != (out["handle"] as! String).lowercased() {
                return ["error": "YouTube sent a different channel (\(out["handle"]!)) for \(asked)"]
            }
        }
        return out
    }

    private func channelTitle(_ id: String) -> String? {
        guard let url = URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(id)"),
              let data = get(url).0 else { return nil }
        let p = YouTubeFeedParser(data: data); _ = p.parse()
        return p.channelTitle
    }

    // MARK: - Anime (AniList)

    private static let fragment = """
    fragment F on Media { id siteUrl status episodes title { english romaji } coverImage { large color }
      nextAiringEpisode { airingAt episode } externalLinks { site url } }
    """

    private func anilist(_ query: String, _ vars: [String: Any]) -> ([String: Any]?, String?) {
        var req = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": vars])
        let sem = DispatchSemaphore(value: 0)
        var out: ([String: Any]?, String?) = (nil, nil)
        session.dataTask(with: req) { d, _, e in
            if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                let msg = ((j["errors"] as? [[String: Any]])?.first?["message"] as? String)
                out = (j["data"] as? [String: Any], msg)
            } else { out = (nil, e?.localizedDescription ?? "AniList unavailable") }
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    func refreshAnime() {
        let cfg = ConfigStore.shared
        let ids = (cfg.value("anime.shows") as? [[String: Any]] ?? []).compactMap { ($0["id"] as? NSNumber)?.intValue }
        let user = cfg.string("anime.anilistUser", "").trimmingCharacters(in: .whitespaces)
        if ids.isEmpty && user.isEmpty {
            lock.lock(); anime = []; version += 1; lock.unlock(); setError("anime", nil); return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var media: [Int: [String: Any]] = [:]
            var errs: [String] = []

            if !ids.isEmpty {
                let q = "query ($ids: [Int]) { Page(perPage: 50) { media(id_in: $ids, type: ANIME) { ...F } } }\n" + Self.fragment
                let (d, e) = self.anilist(q, ["ids": ids])
                for m in ((d?["Page"] as? [String: Any])?["media"] as? [[String: Any]]) ?? [] {
                    if let id = (m["id"] as? NSNumber)?.intValue { media[id] = m }
                }
                if let e { errs.append(e) }
            }
            if !user.isEmpty {
                let q = """
                query ($u: String) { MediaListCollection(userName: $u, type: ANIME, status_in: [CURRENT, PLANNING, REPEATING]) {
                  lists { entries { media { ...F } } } } }
                """ + "\n" + Self.fragment
                let (d, e) = self.anilist(q, ["u": user])
                for l in (((d?["MediaListCollection"] as? [String: Any])?["lists"] as? [[String: Any]]) ?? []) {
                    for entry in (l["entries"] as? [[String: Any]]) ?? [] {
                        if let m = entry["media"] as? [String: Any], let id = (m["id"] as? NSNumber)?.intValue,
                           ["RELEASING", "NOT_YET_RELEASED"].contains(m["status"] as? String ?? "") { media[id] = m }
                    }
                }
                if let e { errs.append("AniList user “\(user)”: \(e)") }
            }

            // Upcoming (and just-aired) episodes for every show, so the tablet can roll over to the next
            // countdown on its own without waiting for a refresh.
            var schedule: [Int: [[String: Any]]] = [:]
            let now = Int(Date().timeIntervalSince1970)
            let allIds = Array(media.keys)
            if !allIds.isEmpty {
                let q = """
                query ($ids: [Int], $from: Int, $to: Int) { Page(perPage: 100) {
                  airingSchedules(mediaId_in: $ids, airingAt_greater: $from, airingAt_lesser: $to, sort: TIME) { mediaId episode airingAt } } }
                """
                let (d, e) = self.anilist(q, ["ids": allIds, "from": now - 2 * 86400, "to": now + 21 * 86400])
                for s in ((d?["Page"] as? [String: Any])?["airingSchedules"] as? [[String: Any]]) ?? [] {
                    if let id = (s["mediaId"] as? NSNumber)?.intValue {
                        schedule[id, default: []].append(["ep": s["episode"] ?? 0, "at": s["airingAt"] ?? 0])
                    }
                }
                if let e { errs.append(e) }
            }

            var shows: [[String: Any]] = []
            for (id, m) in media {
                let title = (m["title"] as? [String: Any]).flatMap { ($0["english"] as? String) ?? ($0["romaji"] as? String) } ?? "Untitled"
                let cover = (m["coverImage"] as? [String: Any])?["large"] as? String ?? ""
                let links = (m["externalLinks"] as? [[String: Any]]) ?? []
                var eps = schedule[id] ?? []
                if eps.isEmpty, let n = m["nextAiringEpisode"] as? [String: Any] {
                    eps = [["ep": n["episode"] ?? 0, "at": n["airingAt"] ?? 0]]
                }
                shows.append([
                    "id": id, "title": title, "cover": cover,
                    "color": (m["coverImage"] as? [String: Any])?["color"] as? String ?? "#888888",
                    "episodes": m["episodes"] ?? NSNull(), "status": m["status"] ?? "",
                    "crunchyroll": links.contains { ($0["site"] as? String) == "Crunchyroll" },
                    "schedule": eps,
                ])
            }
            self.lock.lock(); self.anime = shows; self.version += 1; self.lock.unlock()
            self.setError("anime", errs.isEmpty ? nil : errs.joined(separator: "; "))
        }
    }

    // MARK: - Image proxy (the tablet may only have the USB link)

    private let imageCache = NSCache<NSString, NSData>()
    private static let imageHosts = ["i.ytimg.com", "i1.ytimg.com", "i2.ytimg.com", "i3.ytimg.com", "i4.ytimg.com",
                                     "s4.anilist.co", "img.anili.st",
                                     "cdn.bsky.app", "video.bsky.app", "video.cdn.bsky.app",
                                     "shared.akamai.steamstatic.com", "shared.fastly.steamstatic.com",
                                     "shared.cloudflare.steamstatic.com", "cdn.akamai.steamstatic.com", "cdn.cloudflare.steamstatic.com",
                                     "cdn.fastly.steamstatic.com", "clan.akamai.steamstatic.com", "clan.fastly.steamstatic.com",
                                     "tilecache.rainviewer.com", "static.slickdealscdn.com", "tile.openstreetmap.org"]

    func image(_ s: String) -> (Data, String)? {
        guard let url = URL(string: s), url.scheme == "https", let host = url.host, Self.imageHosts.contains(host) else { return nil }
        if let d = imageCache.object(forKey: s as NSString) { return (d as Data, url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg") }
        guard let d = get(url).0, d.count < 2_000_000 else { return nil }
        imageCache.setObject(d as NSData, forKey: s as NSString, cost: d.count)
        return (d, url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg")
    }
}

final class YouTubeFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [[String: Any]] = []
    private var cur: [String: Any]?
    private var text = ""
    private(set) var channelTitle: String?

    init(data: Data) { self.data = data }

    func parse() -> [[String: Any]] {
        let p = XMLParser(data: data); p.delegate = self; p.parse(); return items
    }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch el {
        case "entry": cur = [:]
        case "link": if cur != nil, let h = a["href"] { cur?["link"] = h; if h.contains("/shorts/") { cur?["short"] = true } }
        case "media:statistics": if let v = a["views"], let n = Double(v) { cur?["views"] = n }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters s: String) { text += s }
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cur == nil {
            if el == "title", channelTitle == nil { channelTitle = t }
        } else {
            switch el {
            case "yt:videoId": cur?["id"] = t; cur?["thumb"] = "https://i.ytimg.com/vi/\(t)/mqdefault.jpg"
            case "title": cur?["title"] = t
            case "name": cur?["channel"] = t
            case "published": if let ms = FeedParser.parseDate(t) { cur?["date"] = ms }
            case "entry":
                if let c = cur, c["id"] != nil { items.append(c) }
                cur = nil
            default: break
            }
        }
        text = ""
    }
}
