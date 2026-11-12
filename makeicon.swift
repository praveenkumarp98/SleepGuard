// Renders SleepGuard's app icon (moon inside a timer ring on a night-sky squircle) into an .iconset.
// Usage: swift makeicon.swift <out.iconset>
import AppKit

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
}

/// Draws on a 1024×1024 canvas (Apple's macOS icon grid: 824 pt squircle, 100 pt margin).
func draw(_ ctx: CGContext) {
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 185, cornerHeight: 185, transform: nil)
    let c = CGPoint(x: 512, y: 512)

    // Tile with drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.35))
    ctx.addPath(tile); ctx.setFillColor(rgb(0x141A45)); ctx.fillPath()
    ctx.restoreGState()

    // Night-sky gradient + soft glow behind the moon
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0x34449E), rgb(0x1A2160), rgb(0x0B0F2E)]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.drawRadialGradient(gradient([rgb(0xFFB547, 0.22), rgb(0xFFB547, 0)]),
                           startCenter: c, startRadius: 0, endCenter: c, endRadius: 340, options: [])
    // faint top highlight
    ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0)]),
                           start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 700), options: [])
    ctx.restoreGState()

    // Timer ring: track, then a 3/4 amber arc from 12 o'clock clockwise
    let r: CGFloat = 288, w: CGFloat = 46
    ctx.setLineWidth(w); ctx.setLineCap(.round)
    ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.13)); ctx.strokePath()

    ctx.saveGState()
    ctx.setLineWidth(w); ctx.setLineCap(.round)
    ctx.addArc(center: c, radius: r, startAngle: .pi / 2, endAngle: -.pi, clockwise: true)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(0xFFD36B), rgb(0xFF8A3D)]),
                           start: CGPoint(x: 800, y: 800), end: CGPoint(x: 224, y: 224), options: [])
    ctx.restoreGState()

    // Crescent moon (full disc minus an offset disc), with a soft glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: rgb(0xFFE7A8, 0.55))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let moonR: CGFloat = 168
    ctx.addEllipse(in: CGRect(x: c.x - moonR - 12, y: c.y - moonR - 10, width: moonR * 2, height: moonR * 2))
    ctx.setFillColor(rgb(0xFFF3D2)); ctx.fillPath()
    ctx.setBlendMode(.destinationOut)
    let cutR: CGFloat = 150
    ctx.addEllipse(in: CGRect(x: c.x + 80 - cutR, y: c.y + 66 - cutR, width: cutR * 2, height: cutR * 2))
    ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Two small stars in the moon's hollow
    func sparkle(_ p: CGPoint, _ s: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: p.x, y: p.y + s))
        path.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: p)
        path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: p)
        ctx.addPath(path); ctx.setFillColor(rgb(0xFFF3D2)); ctx.fillPath()
    }
    sparkle(CGPoint(x: 640, y: 618), 34)
    sparkle(CGPoint(x: 572, y: 690), 16)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = pt * scale
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name)"))
}
print("wrote \(out)")
