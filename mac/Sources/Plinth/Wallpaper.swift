import AppKit
import AVFoundation
import ImageIO

/// Finds the Mac's current wallpaper (including Aerial videos, which NSWorkspace doesn't report)
/// and samples representative colors from five regions so the tablet's day theme can match it.
final class WallpaperSampler {
    static let shared = WallpaperSampler()

    private let queue = DispatchQueue(label: "plinth.wallpaper", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var lastKey = ""
    private var info: [String: Any] = [:]
    private(set) var thumbnailPNG: Data?

    var snapshot: [String: Any] { lock.lock(); defer { lock.unlock() }; return info }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 15)
        t.setEventHandler { [weak self] in self?.refresh() }
        t.resume()
        timer = t
    }

    func refreshNow() { queue.async { [weak self] in self?.lastKey = ""; self?.refresh() } }

    // MARK: - Locate the wallpaper

    private struct Source { var url: URL; var kind: String; var name: String }

    private static let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper")

    private func resolveSource() -> Source? {
        if let s = fromWallpaperStore() { return s }
        if let screen = NSScreen.main ?? NSScreen.screens.first,
           let url = NSWorkspace.shared.desktopImageURL(for: screen) {
            return Source(url: url, kind: "image", name: url.deletingPathExtension().lastPathComponent)
        }
        return nil
    }

    /// macOS 14+ keeps the real choice (Aerial asset, photo, etc.) in the wallpaper store index.
    private func fromWallpaperStore() -> Source? {
        let indexURL = Self.store.appendingPathComponent("Store/Index.plist")
        guard let data = try? Data(contentsOf: indexURL),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }

        // Most specific first: a per-display choice, then "all spaces & displays", then the system default.
        var choice: [String: Any]?
        for key in ["Displays", "AllSpacesAndDisplays", "SystemDefault"] {
            if let node = root[key], let c = Self.firstChoice(in: node) { choice = c; break }
        }
        guard let choice else { return nil }
        let provider = choice["Provider"] as? String ?? ""

        if provider.contains("aerial") {
            var asset: String?
            if let cfg = choice["Configuration"] as? Data,
               let d = try? PropertyListSerialization.propertyList(from: cfg, format: nil) as? [String: Any] {
                asset = d["assetID"] as? String
            }
            let aerials = Self.store.appendingPathComponent("aerials")
            if let asset {
                let thumb = aerials.appendingPathComponent("thumbnails/\(asset).png")
                if FileManager.default.fileExists(atPath: thumb.path) { return Source(url: thumb, kind: "aerial", name: "Aerial") }
                let video = aerials.appendingPathComponent("videos/\(asset).mov")
                if FileManager.default.fileExists(atPath: video.path) { return Source(url: video, kind: "aerial", name: "Aerial") }
            }
            return nil
        }

        // Photos / custom images: Files = [{ relative: "file:///…" }]
        for f in (choice["Files"] as? [[String: Any]]) ?? [] {
            if let rel = f["relative"] as? String, let url = URL(string: rel), FileManager.default.fileExists(atPath: url.path) {
                return Source(url: url, kind: "image", name: url.deletingPathExtension().lastPathComponent)
            }
        }
        return nil
    }

    private static func firstChoice(in node: Any) -> [String: Any]? {
        if let d = node as? [String: Any] {
            if let choices = d["Choices"] as? [[String: Any]], let first = choices.first { return first }
            for key in d.keys.sorted() { if let c = firstChoice(in: d[key]!) { return c } }
        } else if let a = node as? [Any] {
            for v in a { if let c = firstChoice(in: v) { return c } }
        }
        return nil
    }

    // MARK: - Sample

    private func refresh() {
        guard let src = resolveSource() else { return }
        let mtime = (try? FileManager.default.attributesOfItem(atPath: src.url.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        let key = "\(src.url.path)|\(mtime)"
        if key == lastKey { return }
        guard let cg = loadImage(src) else { return }
        lastKey = key

        let colors = Self.sampleRegions(cg)
        let thumb = Self.pngThumbnail(cg, maxWidth: 320)
        lock.lock()
        info = ["key": String(key.hashValue, radix: 36), "source": src.kind, "name": src.name, "colors": colors]
        thumbnailPNG = thumb
        lock.unlock()
    }

    private func loadImage(_ src: Source) -> CGImage? {
        if ["mov", "mp4", "m4v"].contains(src.url.pathExtension.lowercased()) {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: src.url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 480, height: 480)
            return try? gen.copyCGImage(at: CMTime(seconds: 3, preferredTimescale: 600), actualTime: nil)
        }
        guard let isrc = CGImageSourceCreateWithURL(src.url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 480,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(isrc, 0, opts as CFDictionary)
    }

    /// Returns hex colors for top-left, top-right, bottom-left, bottom-right, center and overall.
    /// Pixels are weighted by saturation × brightness so the wallpaper's characteristic colors
    /// (neon, sky, foliage) win over large dull areas.
    static func sampleRegions(_ img: CGImage) -> [String: String] {
        let w = 48, h = 30
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [:] }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

        func region(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int) -> String {
            var r = 0.0, g = 0.0, b = 0.0, wsum = 0.0
            var pr = 0.0, pg = 0.0, pb = 0.0, n = 0.0
            for y in y0..<y1 { for x in x0..<x1 {
                // CGContext rows start at the bottom-left; flip so y0 = top of the picture.
                let i = ((h - 1 - y) * w + x) * 4
                let R = Double(px[i]) / 255, G = Double(px[i + 1]) / 255, B = Double(px[i + 2]) / 255
                let mx = max(R, G, B), mn = min(R, G, B)
                let sat = mx > 0 ? (mx - mn) / mx : 0
                let wt = 0.04 + sat * sat * mx
                r += R * wt; g += G * wt; b += B * wt; wsum += wt
                pr += R; pg += G; pb += B; n += 1
            }}
            guard wsum > 0 else { return "#888888" }
            // Blend 80% vivid-weighted, 20% plain average to stay faithful to the overall tone.
            let fr = 0.8 * r / wsum + 0.2 * pr / n, fg = 0.8 * g / wsum + 0.2 * pg / n, fb = 0.8 * b / wsum + 0.2 * pb / n
            return String(format: "#%02x%02x%02x", Int(fr * 255), Int(fg * 255), Int(fb * 255))
        }
        return ["tl": region(0, w / 2, 0, h / 2), "tr": region(w / 2, w, 0, h / 2),
                "bl": region(0, w / 2, h / 2, h), "br": region(w / 2, w, h / 2, h),
                "c": region(w / 4, w * 3 / 4, h / 4, h * 3 / 4), "all": region(0, w, 0, h)]
    }

    static func pngThumbnail(_ img: CGImage, maxWidth: Int) -> Data? {
        let scale = min(1, Double(maxWidth) / Double(img.width))
        let w = max(1, Int(Double(img.width) * scale)), h = max(1, Int(Double(img.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: out).representation(using: .png, properties: [:])
    }
}
