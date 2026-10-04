// Renders Tapestry's app icon into Tapestry/AppIcon.iconset, plus light and dark copies for the README.
//
//     swift scripts/render-icon.swift
//
// The mark is a small weave: three ink warp threads and three warm weft threads, crossing over and
// under like cloth. It also reads as fingers on a pad. Same tile, grid, and shadow as Pacer and Keeper.

import AppKit

let output = URL(fileURLWithPath: "Tapestry/AppIcon.iconset")
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

    // A hairline inner edge, so the tile holds its shape on a desktop of the same shade.
    context.saveGState()
    context.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 183, cornerHeight: 183, transform: nil))
    context.setStrokeColor(dark ? color(0xFFFFFF, 0.08) : color(0x000000, 0.06))
    context.setLineWidth(3)
    context.strokePath()
    context.restoreGState()

    // The weave. Each thread is drawn once, clipped so it stops a little short of every thread
    // that crosses over it. Crossings alternate like a checkerboard.
    let pitch: CGFloat = 150, width: CGFloat = 88, reach: CGFloat = 230, gap: CGFloat = 12
    let offsets: [CGFloat] = [-pitch, 0, pitch]
    let ink = dark ? color(0xFFFFFF) : color(0x0D0D0D)
    // Sunset weft, top to bottom: magenta, coral, amber.
    let weft: [(CGColor, CGColor)] = [
        (color(0xD9367A), color(0xFF5FA2)),
        (color(0xF0443C), color(0xFF7A59)),
        (color(0xF58A1F), color(0xFFC14D)),
    ]
    func weftOver(_ row: Int, _ column: Int) -> Bool { (row + column) % 2 == 1 }

    /// Clips out the given gaps, then strokes one round-capped thread from `a` to `b`.
    func thread(from a: CGPoint, to b: CGPoint, gaps: [CGRect], fill: (CGPoint, CGPoint) -> Void) {
        context.saveGState()
        context.addRect(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        gaps.forEach { context.addRect($0) }
        context.clip(using: .evenOdd)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.move(to: a)
        context.addLine(to: b)
        context.replacePathWithStrokedPath()
        context.clip()
        fill(a, b)
        context.restoreGState()
    }

    for (row, dy) in offsets.enumerated() {
        let y = 512 - dy
        let gaps = offsets.indices.filter { !weftOver(row, $0) }.map { column in
            CGRect(x: 512 + offsets[column] - width / 2 - gap, y: y - width, width: width + gap * 2, height: width * 2)
        }
        thread(from: CGPoint(x: 512 - reach, y: y), to: CGPoint(x: 512 + reach, y: y), gaps: gaps) { a, b in
            context.drawLinearGradient(gradient([weft[row].0, weft[row].1]), start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }
    for (column, dx) in offsets.enumerated() {
        let x = 512 + dx
        let gaps = offsets.indices.filter { weftOver($0, column) }.map { row in
            CGRect(x: x - width, y: 512 - offsets[row] - width / 2 - gap, width: width * 2, height: width + gap * 2)
        }
        thread(from: CGPoint(x: x, y: 512 - reach), to: CGPoint(x: x, y: 512 + reach), gaps: gaps) { _, _ in
            context.setFillColor(ink)
            context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
    }
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
