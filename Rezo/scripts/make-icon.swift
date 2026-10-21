// Draws the Rezo app icon: the Tanit sign of Carthage broadcasting signal waves,
// on a Sidi Bou Said blue tile. Writes icon_1024.png into the given directory.
//
//   swift scripts/make-icon.swift <out-dir>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "."

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Work in top-left coordinates, like a design tool.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// Tile: Apple's macOS grid puts an 824 pt body inside the 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0x0B4F92))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let blue = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x2A8BDB), color(0x0E5AA8), color(0x083A70)] as CFArray,
    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(blue, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
// Soft light from the top, like whitewash catching the sun.
let glow = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(
    glow, startCenter: CGPoint(x: 512, y: 180), startRadius: 0,
    endCenter: CGPoint(x: 512, y: 180), endRadius: 560, options: [])
ctx.restoreGState()

// Tanit: disc head, bar arms raised at the hands, triangle body.
let white = color(0xFFFFFF)
let head = CGPoint(x: 512, y: 418)
let armY: CGFloat = 532

ctx.setFillColor(white)
ctx.fillEllipse(in: CGRect(x: head.x - 66, y: head.y - 66, width: 132, height: 132))

let body = CGMutablePath()
body.move(to: CGPoint(x: 512, y: armY))
body.addLine(to: CGPoint(x: 662, y: 806))
body.addLine(to: CGPoint(x: 362, y: 806))
body.closeSubpath()
ctx.addPath(body)
ctx.fillPath()
// Round the triangle's corners to match the rounded arms.
ctx.addPath(body)
ctx.setStrokeColor(white)
ctx.setLineJoin(.round)
ctx.setLineWidth(28)
ctx.strokePath()

ctx.setStrokeColor(white)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(42)
let arms = CGMutablePath()
arms.move(to: CGPoint(x: 318, y: armY - 64))
arms.addLine(to: CGPoint(x: 318, y: armY))
arms.addLine(to: CGPoint(x: 706, y: armY))
arms.addLine(to: CGPoint(x: 706, y: armY - 64))
ctx.addPath(arms)
ctx.strokePath()

// Signal waves from the head, sand gold fading to pale sand (solid colours:
// transparency over the blue turns gold into olive). Tilted up to clear the hands.
ctx.setLineWidth(34)
for (radius, hex) in [(CGFloat(126), UInt32(0xF6C445)), (196, 0xF8D47C), (266, 0xFAE3AE)] {
    ctx.setStrokeColor(color(hex))
    for side in [-1.0, 1.0] {
        // Angles in degrees, measured from the horizontal toward the top.
        let from = 18.0, to = 62.0
        let a0 = side < 0 ? (180 + from) : -from
        let a1 = side < 0 ? (180 + to) : -to
        let path = CGMutablePath()
        path.addArc(
            center: head, radius: radius,
            startAngle: CGFloat(a0 * .pi / 180), endAngle: CGFloat(a1 * .pi / 180),
            clockwise: side > 0)
        ctx.addPath(path)
        ctx.strokePath()
    }
}

NSGraphicsContext.current = nil
let png = rep.representation(using: .png, properties: [:])!
let url = URL(fileURLWithPath: out).appendingPathComponent("icon_1024.png")
try! png.write(to: url)
print("wrote \(url.path)")
