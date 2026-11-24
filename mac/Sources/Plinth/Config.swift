import Foundation

/// Config is kept as a JSON dictionary deep-merged over defaults, so new keys
/// appear automatically for old config files and the web manager can edit it freely.
final class ConfigStore {
    static let shared = ConfigStore()

    private let lock = NSLock()
    private var dict: [String: Any]
    private(set) var revision = 1
    let fileURL: URL

    static let defaultsJSON = """
    {
      "port": 8787,
      "allowNetwork": true,
      "deviceName": "",
      "units": "imperial",
      "clock24h": false,
      "theme": "auto",
      "compact": false,
      "cycleSeconds": 12,
      "useMacFont": true,
      "dayColors": { "mode": "wallpaper", "custom": "#3a82f7" },
      "worldClocks": [
        { "name": "New York", "tz": "America/New_York" },
        { "name": "London", "tz": "Europe/London" },
        { "name": "Tokyo", "tz": "Asia/Tokyo" },
        { "name": "Sydney", "tz": "Australia/Sydney" }
      ],
      "location": { "name": "San Francisco", "lat": 37.7749, "lon": -122.4194 },
      "cards": { "weather": true, "sports": true, "news": true, "youtube": true, "anime": true, "bluesky": true, "steamUpcoming": true, "steamDeals": true,
                 "steamAchievements": true, "steamClosest": true, "steamNews": true, "fx": true, "kanji": true, "radar": true, "slickdeals": true },
      "exchange": { "pairs": [ { "from": "USD", "to": "JPY" } ] },
      "kanji": { "level": "jlpt-4" },
      "radar": { "useWeatherLocation": true, "name": "", "lat": 0, "lon": 0, "zoom": 6 },
      "slickdeals": { "frontpage": true, "popular": false, "searches": [] },
      "bluesky": { "accounts": [], "includeReposts": false },
      "steam": { "profile": "", "minDiscount": 10, "apiKey": "" },
      "youtube": { "channels": [], "maxAgeDays": 7, "hideShorts": true },
      "anime": { "shows": [], "anilistUser": "", "delayMinutes": 0 },
      "sports": {
        "leagues": ["football/nfl", "basketball/nba"],
        "favorites": [],
        "onlyFavorites": false,
        "includeFinals": true,
        "maxPerCard": 4
      },
      "feeds": [
        { "name": "BBC News", "url": "https://feeds.bbci.co.uk/news/rss.xml", "enabled": true },
        { "name": "NPR", "url": "https://feeds.npr.org/1001/rss.xml", "enabled": true },
        { "name": "The Verge", "url": "https://www.theverge.com/rss/index.xml", "enabled": true }
      ],
      "headlinesPerCard": 3,
      "speedTest": { "enabled": true, "intervalMinutes": 60 },
      "brightness": { "day": -1, "night": 0.2 },
      "adb": { "autoReverse": true, "autoLaunch": true, "anyDevice": false, "path": "" }
    }
    """

    static var defaults: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(defaultsJSON.utf8))) as? [String: Any] ?? [:]
    }

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plinth", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")
        var d = ConfigStore.defaults
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            d = ConfigStore.merge(d, saved)
        }
        dict = d
    }

    static func merge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            if let bv = base[k] as? [String: Any], let ov = v as? [String: Any] {
                out[k] = merge(bv, ov)
            } else {
                out[k] = v
            }
        }
        return out
    }

    var snapshot: [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return dict
    }

    func update(with patch: [String: Any]) {
        lock.lock()
        dict = ConfigStore.merge(dict, patch)
        revision += 1
        let d = dict
        lock.unlock()
        if let data = try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: fileURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .plinthConfigChanged, object: nil)
    }

    func reset() {
        lock.lock(); dict = ConfigStore.defaults; revision += 1; lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
        NotificationCenter.default.post(name: .plinthConfigChanged, object: nil)
    }

    // Typed accessors (dotted key paths)
    func value(_ path: String) -> Any? {
        var cur: Any? = snapshot
        for part in path.split(separator: ".") {
            cur = (cur as? [String: Any])?[String(part)]
        }
        return cur
    }
    func int(_ p: String, _ d: Int) -> Int { (value(p) as? NSNumber)?.intValue ?? d }
    func double(_ p: String, _ d: Double) -> Double { (value(p) as? NSNumber)?.doubleValue ?? d }
    func bool(_ p: String, _ d: Bool) -> Bool { (value(p) as? Bool) ?? (value(p) as? NSNumber)?.boolValue ?? d }
    func string(_ p: String, _ d: String) -> String { (value(p) as? String) ?? d }
    func strings(_ p: String) -> [String] { (value(p) as? [Any])?.compactMap { $0 as? String } ?? [] }
}

extension Notification.Name {
    static let plinthConfigChanged = Notification.Name("PlinthConfigChanged")
}
