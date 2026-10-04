// Renders Optap's app icon into Optap/AppIcon.iconset, plus light and dark copies for the README.
//
//     swift scripts/render-icon.swift
//
// The mark is the gesture itself: a trackpad with three fingertips tapping it, and the Option
// glyph underneath. Same tile, grid, and shadow as Pacer and Keeper.

import AppKit

let output = URL(fileURLWithPath: "Optap/AppIcon.iconset")
let docs = URL(fileURLWithPath: "docs")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: nil)!
}

func draw(in context: CGContext, size: CGFloat, dark: Bool) {
    context.scaleBy(x: size / 1024, y: size / 1024)

    // The macOS icon grid: an 824pt rounded square centered on a 1024pt canvas, with a soft shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
    context.addPath(shape)
    context.setFillColor(color(dark ? 0x161618 : 0xF7F5F3))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.drawLinearGradient(dark ? gradient([color(0x2A2A2E), color(0x0E0E10)]) : gradient([color(0xFFFFFF), color(0xEEEAE5)]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    context.restoreGState()

    context.saveGState()
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183, cornerHeight: 183, transform: nil))
    context.setStrokeColor(dark ? color(0xFFFFFF, 0.08) : color(0x000000, 0.06))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    // The trackpad: a wide outlined rounded rectangle.
    let pad = CGRect(x: 232, y: 290, width: 560, height: 444)
    context.addPath(CGPath(roundedRect: pad, cornerWidth: 64, cornerHeight: 64, transform: nil))
    context.setStrokeColor(dark ? color(0xFFFFFF, 0.2) : color(0x0D0D0D, 0.16))
    context.setLineWidth(13)
    context.strokePath()

    // Three fingertips in the upper half, each with a faint tap ripple.
    let diameter: CGFloat = 88, pitch: CGFloat = 152
    for i in -1...1 {
        let center = CGPoint(x: 512 + pitch * CGFloat(i), y: 610)
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        context.setStrokeColor(color(0x7A5CFF, 0.22))
        context.setLineWidth(8)
        context.strokeEllipse(in: rect.insetBy(dx: -15, dy: -15))
        context.saveGState()
        context.addEllipse(in: rect)
        context.clip()
        context.drawLinearGradient(gradient([color(0x6A48FF), color(0xA98CFF)]), start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
        context.restoreGState()
    }

    // The Option glyph, drawn as strokes in the lower half.
    context.setStrokeColor(dark ? color(0xFFFFFF) : color(0x0D0D0D))
    context.setLineWidth(26)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let top: CGFloat = 462, bottom: CGFloat = 362
    context.move(to: CGPoint(x: 396, y: top))
    context.addLine(to: CGPoint(x: 466, y: top))
    context.addLine(to: CGPoint(x: 558, y: bottom))
    context.addLine(to: CGPoint(x: 628, y: bottom))
    context.move(to: CGPoint(x: 552, y: top))
    context.addLine(to: CGPoint(x: 628, y: top))
    context.strokePath()
}

func png(pixels: Int, dark: Bool = false) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    draw(in: context.cgContext, size: CGFloat(pixels), dark: dark)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        try png(pixels: points * scale).write(to: output.appending(path: "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"))
    }
}
try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
try png(pixels: 512).write(to: docs.appending(path: "icon.png"))
try png(pixels: 512, dark: true).write(to: docs.appending(path: "icon-dark.png"))
print("Wrote \(output.path) and docs/icon.png, docs/icon-dark.png")
