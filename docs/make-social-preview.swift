// Renders docs/social-preview.png (1280×640), the image GitHub shows when the repo link is shared.
// Usage (from the repo root): swift docs/make-social-preview.swift
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let W: CGFloat = 1280, H: CGFloat = 640
let icon = NSImage(contentsOfFile: "docs/icon.png")!
let window = NSImage(contentsOfFile: "docs/window-dark.png")!

let image = NSImage(size: NSSize(width: W, height: H), flipped: true) { _ in
    let ctx = NSGraphicsContext.current!.cgContext

    // Night-sky background, as in the app icon, with a soft accent glow behind the window.
    NSGradient(colors: [rgb(0x2B3A8F), rgb(0x151B4D), rgb(0x090C26)])!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)
    NSGradient(colors: [rgb(0x3D7BFF, 0.35), rgb(0x3D7BFF, 0)])!
        .draw(fromCenter: NSPoint(x: 1010, y: 300), radius: 0, toCenter: NSPoint(x: 1010, y: 300), radius: 420, options: [])

    // Left: icon, name, pitch, facts.
    let x: CGFloat = 84
    icon.draw(in: NSRect(x: x - 14, y: 96, width: 150, height: 150))
    func text(_ s: String, _ font: NSFont, _ color: NSColor, at p: NSPoint, width: CGFloat = 640, spacing: CGFloat = 0) {
        let para = NSMutableParagraphStyle(); para.lineSpacing = spacing
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
            .draw(with: NSRect(x: p.x, y: p.y, width: width, height: 400), options: [.usesLineFragmentOrigin])
    }
    text("SleepGuard", .systemFont(ofSize: 76, weight: .bold), .white, at: NSPoint(x: x, y: 258))
    text("Keep your Mac awake, lid closed too,\nfor exactly as long as you choose.",
         .systemFont(ofSize: 34, weight: .regular), rgb(0xD9DEFF), at: NSPoint(x: x, y: 362), spacing: 6)

    // Fact chips.
    var cx = x
    for fact in ["macOS 14+", "Apple silicon & Intel", "Open source · MIT"] {
        let font = NSFont.monospacedSystemFont(ofSize: 17, weight: .medium)
        let s = NSAttributedString(string: fact, attributes: [.font: font, .foregroundColor: rgb(0xE8EBFF)])
        let size = s.size()
        let chip = NSRect(x: cx, y: 488, width: size.width + 32, height: 40)
        rgb(0xFFFFFF, 0.10).setFill()
        NSBezierPath(roundedRect: chip, xRadius: 20, yRadius: 20).fill()
        rgb(0xFFFFFF, 0.18).setStroke()
        let border = NSBezierPath(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), xRadius: 20, yRadius: 20)
        border.lineWidth = 1; border.stroke()
        s.draw(at: NSPoint(x: chip.minX + 16, y: chip.midY - size.height / 2))
        cx = chip.maxX + 10
    }

    // Right: the real window (dark mode), 1:1 pixels so it stays sharp, running off the bottom edge.
    let shown: CGFloat = H - 64
    let src = NSRect(x: 0, y: window.size.height - shown, width: window.size.width, height: shown) // top part (image coords are bottom-up)
    let dst = NSRect(x: W - window.size.width - 84, y: 64, width: window.size.width, height: shown)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 48, color: NSColor.black.withAlphaComponent(0.55).cgColor)
    rgb(0x1E1E1E).setFill()
    NSBezierPath(roundedRect: dst, xRadius: 14, yRadius: 14).fill()
    ctx.restoreGState()
    ctx.saveGState()
    NSBezierPath(roundedRect: dst, xRadius: 14, yRadius: 14).addClip()
    window.draw(in: dst, from: src, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    ctx.restoreGState()
    rgb(0xFFFFFF, 0.14).setStroke()
    let edge = NSBezierPath(roundedRect: dst.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
    edge.lineWidth = 1; edge.stroke()
    return true
}

// Write exactly 1280×640 pixels (not the screen's 2× scale).
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/social-preview.png"))
print("wrote docs/social-preview.png")
