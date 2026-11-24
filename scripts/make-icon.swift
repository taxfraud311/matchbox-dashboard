// Renders the Matchbox Dashboard app icon: an open box of matches (red sleeve with a flame label and a striker side,
// tray slid out showing red match heads) on a deep navy macOS squircle.
//   swift make-icon.swift <out.iconset>          writes every iconset size
//   swift make-icon.swift --png <out.png> <px>   writes one PNG (previews)
import AppKit

func C(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext

    // Squircle on the macOS icon grid.
    let inset = s * 0.1, r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
    g.saveGState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.shadowBlurRadius = s * 0.02
    sh.shadowOffset = NSSize(width: 0, height: -s * 0.01); sh.set()
    C(0x1b2540).setFill(); shape.fill()
    g.restoreGState()
    NSGradient(colors: [C(0x2c3c63), C(0x141c31)])!.draw(in: shape, angle: -90)

    // Unit helpers: u(x) maps 0…1 across the squircle.
    let W = r.width
    func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: r.minX + x * W, y: r.minY + y * W) }
    func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: r.minX + x * W, y: r.minY + y * W, width: w * W, height: h * W) }
    func rr(_ rect: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: rect, xRadius: rad * W, yRadius: rad * W) }

    shape.addClip()

    // Warm glow behind the match heads.
    NSGradient(colors: [C(0xff9a3c, 0.45), C(0xff9a3c, 0)])!.draw(fromCenter: P(0.80, 0.56), radius: 0, toCenter: P(0.80, 0.56), radius: 0.42 * W, options: [])

    // The whole box leans a little.
    g.saveGState()
    let pivot = P(0.5, 0.5)
    g.translateBy(x: pivot.x, y: pivot.y); g.rotate(by: 8 * .pi / 180); g.translateBy(x: -pivot.x, y: -pivot.y)

    let tx: CGFloat = 0.40, tw: CGFloat = 0.50, ty: CGFloat = 0.36, th: CGFloat = 0.32, side: CGFloat = 0.085
    let sx: CGFloat = 0.10, sw: CGFloat = 0.46, sy: CGFloat = 0.33, shh: CGFloat = 0.38

    // Shadow under the box: cast by the box's own outline, which the parts below then cover.
    g.saveGState()
    let bs = NSShadow(); bs.shadowColor = NSColor.black.withAlphaComponent(0.45); bs.shadowBlurRadius = 0.04 * W
    bs.shadowOffset = NSSize(width: 0, height: -0.025 * W); bs.set()
    C(0xb98b55).setFill(); rr(R(tx, ty - side, tw, th + side), 0.02).fill()
    C(0x8e1d18).setFill(); rr(R(sx, sy - side, sw, shh + side), 0.024).fill()
    g.restoreGState()

    // Tray (slid out to the right): front side, then the open top.
    C(0xb98b55).setFill(); rr(R(tx, ty - side, tw, side + 0.02), 0.018).fill()              // tray front face
    C(0x000000, 0.12).setFill(); rr(R(tx, ty - side, tw, 0.018), 0.009).fill()
    C(0xe2bf8a).setFill(); rr(R(tx, ty, tw, th), 0.02).fill()                                 // tray rim
    C(0xa8794a).setFill(); rr(R(tx + 0.025, ty + 0.025, tw - 0.05, th - 0.05), 0.012).fill() // tray floor

    // Matches: sticks running under the sleeve, red heads at the right.
    let n = 6
    let innerB = ty + 0.04, innerT = ty + th - 0.04, step = (innerT - innerB) / CGFloat(n)
    for i in 0..<n {
        let cy = innerB + step * (CGFloat(i) + 0.5)
        let stick = R(tx, cy - 0.014, tw - 0.10, 0.028)
        C(0xf3dcae).setFill(); NSBezierPath(rect: stick).fill()
        C(0x000000, 0.10).setFill(); NSBezierPath(rect: R(tx, cy - 0.014, tw - 0.10, 0.008)).fill()
        let head = R(tx + tw - 0.125, cy - 0.024, 0.085, 0.048)
        NSGradient(colors: [C(0xf0483a), C(0xb3191b)])!.draw(in: NSBezierPath(ovalIn: head), angle: -90)
        C(0xffffff, 0.35).setFill()
        NSBezierPath(ovalIn: R(tx + tw - 0.105, cy + 0.002, 0.03, 0.013)).fill()
    }

    // Sleeve: striker side (front face), then the labelled top.
    C(0x8e1d18).setFill(); rr(R(sx, sy - side, sw, side + 0.03), 0.022).fill()
    // Striker strip with grit.
    let strike = R(sx + 0.03, sy - side + 0.018, sw - 0.06, side - 0.03)
    C(0x4a2e22).setFill(); rr(strike, 0.008).fill()
    if px >= 64 {
        var seed: UInt32 = 7
        func rnd() -> CGFloat { seed = seed &* 1664525 &+ 1013904223; return CGFloat(seed >> 8) / CGFloat(1 << 24) }
        C(0x7a5644).setFill()
        for _ in 0..<70 {
            let d = (0.004 + rnd() * 0.005) * W
            NSBezierPath(ovalIn: NSRect(x: strike.minX + rnd() * (strike.width - d), y: strike.minY + rnd() * (strike.height - d), width: d, height: d)).fill()
        }
    }
    NSGradient(colors: [C(0xd8392c), C(0xb0241d)])!.draw(in: rr(R(sx, sy, sw, shh), 0.024), angle: -90)

    // Label: cream panel, red keyline, flame emblem.
    let lab = R(sx + 0.045, sy + 0.045, sw - 0.09, shh - 0.09)
    C(0xf6ead0).setFill(); rr(lab, 0.012).fill()
    let key = rr(lab.insetBy(dx: 0.018 * W, dy: 0.018 * W), 0.006)
    key.lineWidth = max(1, 0.008 * W); C(0xc72d23).setStroke(); key.stroke()

    let cx = lab.midX, b = lab.minY + 0.065 * W, hgt = lab.height - 0.13 * W
    func flame(_ cx: CGFloat, _ b: CGFloat, _ h: CGFloat, _ w: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx, y: b))
        p.curve(to: NSPoint(x: cx - w * 0.5, y: b + h * 0.38), controlPoint1: NSPoint(x: cx - w * 0.36, y: b), controlPoint2: NSPoint(x: cx - w * 0.5, y: b + h * 0.16))
        p.curve(to: NSPoint(x: cx + w * 0.06, y: b + h), controlPoint1: NSPoint(x: cx - w * 0.5, y: b + h * 0.66), controlPoint2: NSPoint(x: cx - w * 0.1, y: b + h * 0.8))
        p.curve(to: NSPoint(x: cx + w * 0.5, y: b + h * 0.36), controlPoint1: NSPoint(x: cx + w * 0.16, y: b + h * 0.72), controlPoint2: NSPoint(x: cx + w * 0.5, y: b + h * 0.66))
        p.curve(to: NSPoint(x: cx, y: b), controlPoint1: NSPoint(x: cx + w * 0.5, y: b + h * 0.14), controlPoint2: NSPoint(x: cx + w * 0.34, y: b))
        p.close(); return p
    }
    NSGradient(colors: [C(0xffc93d), C(0xf2621f)])!.draw(in: flame(cx, b, hgt, hgt * 0.68), angle: -90)
    C(0xd0281f).setFill(); flame(cx + 0.004 * W, b + 0.012 * W, hgt * 0.56, hgt * 0.4).fill()
    C(0xfff1b8).setFill(); flame(cx + 0.006 * W, b + 0.02 * W, hgt * 0.26, hgt * 0.2).fill()

    g.restoreGState()

    // Glass rim, like the other macOS icons.
    C(0xffffff, 0.18).setStroke()
    let rim = NSBezierPath(roundedRect: r.insetBy(dx: s * 0.004, dy: s * 0.004), xRadius: r.width * 0.22, yRadius: r.width * 0.22)
    rim.lineWidth = max(1, s * 0.006); rim.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let args = CommandLine.arguments
if args.count >= 4, args[1] == "--png" {
    try! render(Int(args[3]) ?? 1024).write(to: URL(fileURLWithPath: args[2]))
} else {
    let out = args[1]
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    let sizes: [(Int, String)] = [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),
                                  (256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")]
    for (px, name) in sizes { try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png")) }
}
