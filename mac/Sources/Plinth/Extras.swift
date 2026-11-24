import Foundation

/// Bluesky posts from chosen accounts (public AppView API, no sign-in) and the user's Steam wishlist
/// (public wishlist + Steam store item data: release dates and discounts).
final class ExtraFeeds {
    static let shared = ExtraFeeds()

    private let lock = NSLock()
    private var bluesky: [[String: Any]] = []
    private var steamUpcoming: [[String: Any]] = []
    private var steamDeals: [[String: Any]] = []
    private var steamInfo: [String: Any] = [:]
    private var errors: [String: String] = [:]
    private(set) var version = 0
    private var timers: [Timer] = []
    private var pending: DispatchWorkItem?
    private var steamIdCache: [String: (id: String, name: String)] = [:]

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": "MatchboxDashboard/1.0 (macOS info display)", "Accept-Language": "en-US"]
        return URLSession(configuration: c)
    }()

    func start() {
        refreshAll()
        let b = Timer(timeInterval: 180, repeats: true) { [weak self] _ in self?.refreshBluesky() }
        let s = Timer(timeInterval: 1800, repeats: true) { [weak self] _ in self?.refreshSteam() }
        for t in [b, s] { RunLoop.main.add(t, forMode: .common); timers.append(t) }
        NotificationCenter.default.addObserver(forName: .plinthConfigChanged, object: nil, queue: .main) { [weak self] _ in
            self?.pending?.cancel()
            let w = DispatchWorkItem { self?.refreshAll() }
            self?.pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
        }
    }

    func refreshAll() { refreshBluesky(); refreshSteam() }

    var snapshot: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["bluesky": bluesky, "steamUpcoming": steamUpcoming, "steamDeals": steamDeals, "steam": steamInfo, "errors": errors]
    }

    private func setError(_ k: String, _ v: String?) { lock.lock(); errors[k] = v; lock.unlock() }
    private func bump() { lock.lock(); version += 1; lock.unlock() }

    private func getJSON(_ url: URL) -> (Any?, String?) {
        let sem = DispatchSemaphore(value: 0)
        var out: (Any?, String?) = (nil, nil)
        session.dataTask(with: url) { d, r, e in
            let code = (r as? HTTPURLResponse)?.statusCode ?? 0
            if let e { out = (nil, e.localizedDescription) }
            else if code >= 400 { out = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) }, "HTTP \(code)") }
            else { out = (d.flatMap { try? JSONSerialization.jsonObject(with: $0) }, nil) }
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }
    private func getText(_ url: URL) -> String? {
        let sem = DispatchSemaphore(value: 0)
        var out: String?
        session.dataTask(with: url) { d, _, _ in out = d.map { String(decoding: $0, as: UTF8.self) }; sem.signal() }.resume()
        sem.wait()
        return out
    }

    // MARK: - Bluesky

    private static let bskyAPI = "https://public.api.bsky.app/xrpc/"

    /// Look up an account for the manager: accepts @handle, handle, did:plc:…, or a bsky.app profile URL.
    func resolveBluesky(_ input: String) -> [String: Any] {
        var q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = q.range(of: "bsky.app/profile/") { q = String(q[r.upperBound...]).components(separatedBy: "/").first ?? q }
        if q.hasPrefix("@") { q.removeFirst() }
        if !q.contains(".") && !q.hasPrefix("did:") { q += ".bsky.social" }
        guard !q.isEmpty, var c = URLComponents(string: Self.bskyAPI + "app.bsky.actor.getProfile") else { return ["error": "Enter a Bluesky handle"] }
        c.queryItems = [.init(name: "actor", value: q)]
        let (j, err) = getJSON(c.url!)
        guard let p = j as? [String: Any], let did = p["did"] as? String else {
            return ["error": ((j as? [String: Any])?["message"] as? String) ?? err ?? "Account not found"]
        }
        return ["did": did, "handle": p["handle"] ?? q, "name": (p["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (p["handle"] ?? q),
                "avatar": p["avatar"] ?? ""]
    }

    func refreshBluesky() {
        let cfg = ConfigStore.shared
        let accounts = (cfg.value("bluesky.accounts") as? [[String: Any]] ?? []).compactMap { ($0["did"] as? String) ?? ($0["handle"] as? String) }
        let reposts = cfg.bool("bluesky.includeReposts", false)
        if accounts.isEmpty { lock.lock(); bluesky = []; lock.unlock(); bump(); setError("bluesky", nil); return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var posts: [[String: Any]] = []
            var failed = 0
            let collect = NSLock()
            DispatchQueue.concurrentPerform(iterations: accounts.count) { i in
                var c = URLComponents(string: Self.bskyAPI + "app.bsky.feed.getAuthorFeed")!
                c.queryItems = [.init(name: "actor", value: accounts[i]), .init(name: "limit", value: "15"),
                                .init(name: "filter", value: "posts_no_replies")]
                let (j, _) = self.getJSON(c.url!)
                guard let feed = (j as? [String: Any])?["feed"] as? [[String: Any]] else { collect.lock(); failed += 1; collect.unlock(); return }
                var mine: [[String: Any]] = []
                for item in feed {
                    let reason = item["reason"] as? [String: Any]
                    let isRepost = (reason?["$type"] as? String)?.contains("reasonRepost") == true
                    if isRepost && !reposts { continue }
                    if let p = ExtraFeeds.parsePost(item, repost: isRepost ? reason : nil) { mine.append(p) }
                }
                collect.lock(); posts.append(contentsOf: mine); collect.unlock()
            }
            var seen = Set<String>()
            posts = posts.filter { seen.insert($0["uri"] as? String ?? UUID().uuidString).inserted }
            posts.sort { ($0["sort"] as? Double ?? 0) > ($1["sort"] as? Double ?? 0) }
            self.lock.lock(); self.bluesky = Array(posts.prefix(30)); self.lock.unlock(); self.bump()
            self.setError("bluesky", failed == accounts.count ? "Couldn’t reach Bluesky" : failed > 0 ? "\(failed) account(s) failed to load" : nil)
        }
    }

    static func parsePost(_ item: [String: Any], repost: [String: Any]?) -> [String: Any]? {
        guard let post = item["post"] as? [String: Any], let author = post["author"] as? [String: Any],
              let record = post["record"] as? [String: Any] else { return nil }
        let created = (record["createdAt"] as? String).flatMap { FeedParser.parseDate($0) } ?? 0
        var out: [String: Any] = [
            "uri": post["uri"] ?? "",
            "text": (record["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "date": created,
            "handle": author["handle"] ?? "",
            "name": (author["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (author["handle"] ?? ""),
            "avatar": author["avatar"] ?? "",
            "likes": post["likeCount"] ?? 0, "reposts": post["repostCount"] ?? 0, "replies": post["replyCount"] ?? 0,
        ]
        if let r = repost {
            let by = r["by"] as? [String: Any]
            out["repostBy"] = (by?["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? by?["handle"] ?? ""
            out["sort"] = (r["indexedAt"] as? String).flatMap { FeedParser.parseDate($0) } ?? created
        } else {
            out["sort"] = created
        }
        // First picture: image post, link card, video thumbnail, or the media part of a quote post.
        func image(from e: [String: Any]?) -> String? {
            guard let e else { return nil }
            if let imgs = e["images"] as? [[String: Any]], let t = imgs.first?["thumb"] as? String { return t }
            if let ext = e["external"] as? [String: Any], let t = ext["thumb"] as? String { return t }
            if let t = e["thumbnail"] as? String { return t }
            return image(from: e["media"] as? [String: Any])
        }
        if let img = image(from: post["embed"] as? [String: Any]) { out["image"] = img }
        if (out["text"] as? String ?? "").isEmpty, out["image"] == nil { return nil }
        return out
    }

    // MARK: - Steam wishlist

    /// Accepts a 17-digit SteamID64, a profile URL (/id/name or /profiles/7656…), or a custom URL name.
    func resolveSteam(_ input: String) -> [String: Any] {
        let q = input.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock(); if let hit = steamIdCache[q] { lock.unlock(); return ["steamid": hit.id, "name": hit.name] }; lock.unlock()
        var profileURL: String
        if let r = q.range(of: #"7656119\d{10}"#, options: .regularExpression) {
            profileURL = "https://steamcommunity.com/profiles/\(q[r])/?xml=1"
        } else if let r = q.range(of: #"steamcommunity\.com/id/([^/?#]+)"#, options: .regularExpression) {
            let vanity = q[r].components(separatedBy: "/id/").last ?? ""
            profileURL = "https://steamcommunity.com/id/\(vanity)/?xml=1"
        } else if !q.isEmpty, !q.contains("/") {
            profileURL = "https://steamcommunity.com/id/\(q.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? q)/?xml=1"
        } else {
            return ["error": "Paste your Steam profile link, e.g. steamcommunity.com/id/yourname"]
        }
        guard let url = URL(string: profileURL), let xml = getText(url) else { return ["error": "Couldn’t reach Steam"] }
        func tag(_ t: String) -> String? {
            guard let r = xml.range(of: "<\(t)>(.*?)</\(t)>", options: .regularExpression) else { return nil }
            return String(xml[r]).replacingOccurrences(of: "<\(t)>", with: "").replacingOccurrences(of: "</\(t)>", with: "")
                .replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
        }
        guard let id = tag("steamID64") else { return ["error": "No Steam profile found there"] }
        let name = tag("steamID") ?? id
        lock.lock(); steamIdCache[q] = (id, name); lock.unlock()
        return ["steamid": id, "name": name]
    }

    func refreshSteam() {
        let profile = ConfigStore.shared.string("steam.profile", "")
        if profile.isEmpty {
            lock.lock(); steamUpcoming = []; steamDeals = []; steamInfo = [:]; lock.unlock(); bump(); setError("steam", nil); return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let who = self.resolveSteam(profile)
            guard let sid = who["steamid"] as? String else { self.setError("steam", who["error"] as? String); return }
            let (j, err) = self.getJSON(URL(string: "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=\(sid)")!)
            guard let resp = (j as? [String: Any])?["response"] as? [String: Any] else { self.setError("steam", err ?? "Steam unavailable"); return }
            // Wishlist order is the user's priority; look up at most 1,500 games so huge wishlists stay quick.
            let allIds = ((resp["items"] as? [[String: Any]]) ?? [])
                .sorted { (($0["priority"] as? NSNumber)?.intValue ?? 0) < (($1["priority"] as? NSNumber)?.intValue ?? 0) }
                .compactMap { ($0["appid"] as? NSNumber)?.intValue }
            let appids = Array(allIds.prefix(1500))
            if appids.isEmpty {
                self.lock.lock(); self.steamUpcoming = []; self.steamDeals = []; self.steamInfo = ["name": who["name"] ?? "", "count": 0]; self.lock.unlock()
                self.bump()
                self.setError("steam", "Your wishlist looks empty or private. In Steam, set Privacy › Game details to Public.")
                return
            }
            var items: [[String: Any]] = []
            for chunk in stride(from: 0, to: appids.count, by: 100).map({ Array(appids[$0..<min($0 + 100, appids.count)]) }) {
                let input: [String: Any] = [
                    "ids": chunk.map { ["appid": $0] },
                    "context": ["language": "english", "country_code": Locale.current.region?.identifier ?? "US"],
                    "data_request": ["include_basic_info": true, "include_release": true, "include_assets": true],
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: input), var c = URLComponents(string: "https://api.steampowered.com/IStoreBrowseService/GetItems/v1/") else { continue }
                c.queryItems = [.init(name: "input_json", value: String(decoding: data, as: UTF8.self))]
                let (r, _) = self.getJSON(c.url!)
                items += (((r as? [String: Any])?["response"] as? [String: Any])?["store_items"] as? [[String: Any]]) ?? []
            }
            let (up, deals) = ExtraFeeds.buildSteam(items)
            self.lock.lock()
            self.steamUpcoming = up; self.steamDeals = deals
            self.steamInfo = ["name": who["name"] ?? "", "count": allIds.count]
            self.lock.unlock()
            self.bump()
            self.setError("steam", nil)
        }
    }

    static func capsule(_ it: [String: Any]) -> String {
        guard let a = it["assets"] as? [String: Any], let fmt = a["asset_url_format"] as? String,
              let file = (a["header"] as? String) ?? (a["main_capsule"] as? String) ?? (a["small_capsule"] as? String) else {
            let id = (it["appid"] as? NSNumber)?.intValue ?? 0
            return "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(id)/header.jpg"
        }
        return "https://shared.akamai.steamstatic.com/store_item_assets/" + fmt.replacingOccurrences(of: "${FILENAME}", with: file)
    }

    static func buildSteam(_ items: [[String: Any]]) -> ([[String: Any]], [[String: Any]]) {
        let now = Date().timeIntervalSince1970
        var upcoming: [[String: Any]] = [], deals: [[String: Any]] = []
        for it in items {
            guard (it["visible"] as? Bool) != false, let name = it["name"] as? String else { continue }
            let appid = (it["appid"] as? NSNumber)?.intValue ?? 0
            let rel = it["release"] as? [String: Any] ?? [:]
            let img = capsule(it)
            let soon = (it["is_coming_soon"] as? Bool) == true || (rel["is_coming_soon"] as? Bool) == true
            let date = (rel["steam_release_date"] as? NSNumber)?.doubleValue
            let eaDate = (rel["release_from_early_access_date"] as? NSNumber)?.doubleValue
            let display = rel["coming_soon_display"] as? String ?? ""
            if soon {
                // date_full = exact day; date_month / date_quarter / date_year are rough; text_* is a custom message.
                var e: [String: Any] = ["appid": appid, "name": name, "img": img, "precision": display]
                if let date { e["date"] = date * 1000 }
                if let msg = rel["custom_release_date_message"] as? String { e["label"] = msg }
                upcoming.append(e)
            } else if let date, now - date < 3 * 86400, date <= now {
                upcoming.append(["appid": appid, "name": name, "img": img, "precision": "date_full", "date": date * 1000, "out": true])
            } else if let ea = eaDate, ea > now - 3 * 86400 {
                upcoming.append(["appid": appid, "name": name, "img": img, "precision": "date_full", "date": ea * 1000, "earlyAccessExit": true])
            }
            if let po = it["best_purchase_option"] as? [String: Any], let pct = (po["discount_pct"] as? NSNumber)?.intValue, pct > 0,
               (po["hide_discount_pct_for_compliance"] as? Bool) != true {
                var d: [String: Any] = ["appid": appid, "name": name, "img": img, "pct": pct,
                                        "final": po["formatted_final_price"] ?? "", "orig": po["formatted_original_price"] ?? ""]
                let ends = ((po["active_discounts"] as? [[String: Any]]) ?? []).compactMap { ($0["discount_end_date"] as? NSNumber)?.doubleValue }.min()
                if let ends { d["ends"] = ends * 1000 }
                deals.append(d)
            }
        }
        let rank: ([String: Any]) -> Int = { e in
            if e["out"] as? Bool == true { return 0 }
            switch e["precision"] as? String ?? "" {
            case "date_full": return 1
            case "date_month": return 2
            case "date_quarter": return 3
            case "date_year": return 4
            default: return 5
            }
        }
        upcoming.sort { a, b in
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return (a["date"] as? Double ?? .greatestFiniteMagnitude) < (b["date"] as? Double ?? .greatestFiniteMagnitude)
        }
        deals.sort { ($0["pct"] as? Int ?? 0) != ($1["pct"] as? Int ?? 0) ? ($0["pct"] as? Int ?? 0) > ($1["pct"] as? Int ?? 0)
                                                                         : ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        return (Array(upcoming.prefix(24)), Array(deals.prefix(24)))
    }
}
