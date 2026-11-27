import Foundation

/// Stock ticker card: quotes and today's intraday line for up to 8 symbols (stocks, ETFs, indexes, crypto) from
/// Yahoo Finance's public chart data. Every 30 seconds while any of them is trading, every 15 minutes otherwise.
final class Stocks {
    static let shared = Stocks()

    private let lock = NSLock()
    private var quotes: [[String: Any]] = []
    private var error: String?
    private(set) var version = 0
    private var timer: Timer?
    private var lastFetch = Date.distantPast
    private var anyOpen = false
    private var busy = false
    static let maxSymbols = 8

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) MatchboxDashboard/1.0", "Accept-Language": "en-US"]
        return URLSession(configuration: c)
    }()

    func start() {
        let t = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common); timer = t
        NotificationCenter.default.addObserver(forName: .plinthConfigChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let want = Self.symbols().map { $0.symbol }
            let have = self.snapshotQuotes.compactMap { $0["symbol"] as? String }
            if want != have { self.refresh() }
        }
        refresh()
    }

    private func tick() {
        let age = Date().timeIntervalSince(lastFetch)
        lock.lock(); let open = anyOpen; lock.unlock()
        if age >= (open ? 30 : 900) { refresh() }
    }

    static func symbols() -> [(symbol: String, name: String)] {
        let list = (ConfigStore.shared.value("stocks.symbols") as? [Any]) ?? []
        return list.compactMap { v -> (String, String)? in
            guard let d = v as? [String: Any], let s = d["symbol"] as? String, !s.isEmpty else { return nil }
            return (s, d["name"] as? String ?? s)
        }.prefix(maxSymbols).map { $0 }
    }

    private var snapshotQuotes: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return quotes }

    var snapshot: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["stocks": quotes, "error": error ?? NSNull()]
    }
    var lastError: String? { lock.lock(); defer { lock.unlock() }; return error }

    func refresh() {
        lastFetch = Date()
        let syms = Self.symbols()
        guard ConfigStore.shared.bool("cards.stocks", true), !syms.isEmpty else {
            lock.lock(); let changed = !quotes.isEmpty || error != nil; quotes = []; error = nil; anyOpen = false
            if changed { version += 1 }; lock.unlock()
            return
        }
        lock.lock(); if busy { lock.unlock(); return }; busy = true; lock.unlock()
        let group = DispatchGroup()
        var results = [[String: Any]?](repeating: nil, count: syms.count)
        var failures = 0
        let rl = NSLock()
        for (i, s) in syms.enumerated() {
            group.enter()
            fetch(s.symbol) { q in
                rl.lock()
                if var q { if (q["name"] as? String ?? "").isEmpty { q["name"] = s.name }; results[i] = q } else { failures += 1 }
                rl.unlock()
                group.leave()
            }
        }
        group.notify(queue: .global(qos: .utility)) { [weak self] in
            guard let self else { return }
            let got = results.compactMap { $0 }
            self.lock.lock()
            self.busy = false
            if !got.isEmpty || failures == syms.count {
                // Keep the last good quote for any symbol that failed this time.
                let old = Dictionary(self.quotes.compactMap { q in (q["symbol"] as? String).map { ($0, q) } }, uniquingKeysWith: { a, _ in a })
                self.quotes = syms.enumerated().compactMap { i, s in results[i] ?? old[s.symbol] }
            }
            self.error = failures == syms.count ? "Couldn’t reach Yahoo Finance" : failures > 0 ? "\(failures) symbol\(failures == 1 ? "" : "s") didn’t load" : nil
            self.anyOpen = self.quotes.contains { ($0["state"] as? String) == "open" }
            self.version += 1
            self.lock.unlock()
        }
    }

    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?&=+#"))) ?? s }

    private func fetch(_ symbol: String, _ done: @escaping ([String: Any]?) -> Void) {
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc(symbol))?range=1d&interval=5m&includePrePost=false") else { return done(nil) }
        session.dataTask(with: url) { d, r, e in
            guard e == nil, (r as? HTTPURLResponse)?.statusCode == 200, let d,
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let res = ((j["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
                  let meta = res["meta"] as? [String: Any],
                  let price = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue else { return done(nil) }
            let prev = (meta["chartPreviousClose"] as? NSNumber)?.doubleValue ?? (meta["previousClose"] as? NSNumber)?.doubleValue ?? price
            let closes = ((((res["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first)?["close"] as? [Any] ?? [])
                .compactMap { ($0 as? NSNumber)?.doubleValue }
            // At most ~80 points is plenty for a sparkline.
            let step = max(1, Int(ceil(Double(closes.count) / 80)))
            var pts = stride(from: 0, to: closes.count, by: step).map { (closes[$0] * 1e4).rounded() / 1e4 }
            if let last = closes.last, pts.last != last { pts.append(last) }
            let now = Date().timeIntervalSince1970
            var state = "closed"
            if let tp = meta["currentTradingPeriod"] as? [String: Any] {
                func inside(_ k: String) -> Bool {
                    guard let p = tp[k] as? [String: Any], let s = (p["start"] as? NSNumber)?.doubleValue,
                          let e = (p["end"] as? NSNumber)?.doubleValue else { return false }
                    return now >= s && now < e
                }
                state = inside("regular") ? "open" : inside("pre") ? "pre" : inside("post") ? "post" : "closed"
            }
            // Quotes that haven't moved in hours while "open" (holidays) count as closed.
            let t = (meta["regularMarketTime"] as? NSNumber)?.doubleValue ?? 0
            if state == "open", now - t > 3 * 3600 { state = "closed" }
            done([
                "symbol": meta["symbol"] as? String ?? symbol,
                "name": meta["shortName"] as? String ?? meta["longName"] as? String ?? "",
                "price": price, "prev": prev, "change": price - prev, "pct": prev != 0 ? (price - prev) / prev * 100 : 0,
                "currency": meta["currency"] as? String ?? "", "exchange": meta["fullExchangeName"] as? String ?? meta["exchangeName"] as? String ?? "",
                "time": t * 1000, "state": state, "points": pts,
                "url": "https://finance.yahoo.com/quote/\(symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol)",
            ])
        }.resume()
    }

    /// For the manager's search box.
    func search(_ q: String, _ done: @escaping ([String: Any]) -> Void) {
        let s = q.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, let e = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))),
              let url = URL(string: "https://query1.finance.yahoo.com/v1/finance/search?q=\(e)&quotesCount=8&newsCount=0&listsCount=0") else {
            return done(["results": []])
        }
        session.dataTask(with: url) { d, _, err in
            guard err == nil, let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                return done(["error": "Couldn’t reach Yahoo Finance", "results": []])
            }
            let ok: Set<String> = ["EQUITY", "ETF", "INDEX", "MUTUALFUND", "CRYPTOCURRENCY", "CURRENCY", "FUTURE"]
            let out = (j["quotes"] as? [[String: Any]] ?? []).compactMap { q -> [String: Any]? in
                guard let sym = q["symbol"] as? String, ok.contains(q["quoteType"] as? String ?? "") else { return nil }
                return ["symbol": sym, "name": q["shortname"] as? String ?? q["longname"] as? String ?? sym,
                        "type": (q["typeDisp"] as? String) ?? (q["quoteType"] as? String ?? ""), "exchange": q["exchDisp"] as? String ?? ""]
            }
            done(["results": out])
        }.resume()
    }
}
