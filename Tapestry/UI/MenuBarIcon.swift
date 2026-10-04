import AppKit

/// Draws the menu bar glyph: the icon's weave at 18pt, two threads each way, crossing over and
/// under. It is a monochrome template image, and turns the accent color for a moment when a
/// gesture runs.
enum MenuBarIcon {
    static func image(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let lines: [CGFloat] = [6, 12]
            let width: CGFloat = 2.2, gap: CGFloat = 1.1, from: CGFloat = 2.5, to: CGFloat = 15.5
            let warp: NSColor = active ? .labelColor : .black
            let weft: NSColor = active ? Theme.accentNS : .black

            func stroke(_ a: NSPoint, _ b: NSPoint, color: NSColor, clear: Bool = false) {
                let path = NSBezierPath()
                path.move(to: a)
                path.line(to: b)
                path.lineWidth = clear ? width + gap * 2 : width
                path.lineCapStyle = clear ? .butt : .round
                NSGraphicsContext.current?.compositingOperation = clear ? .clear : .sourceOver
                color.setStroke()
                path.stroke()
            }

            for x in lines { stroke(NSPoint(x: x, y: from), NSPoint(x: x, y: to), color: warp) }
            for y in lines { stroke(NSPoint(x: from, y: y), NSPoint(x: to, y: y), color: weft) }

            // Checkerboard: at each crossing, cut a gap around the thread on top and redraw it.
            let half: CGFloat = 2
            for (row, y) in lines.enumerated() {
                for (column, x) in lines.enumerated() {
                    if (row + column) % 2 == 0 {
                        stroke(NSPoint(x: x, y: y - half), NSPoint(x: x, y: y + half), color: .black, clear: true)
                        stroke(NSPoint(x: x, y: y - half), NSPoint(x: x, y: y + half), color: warp)
                    } else {
                        stroke(NSPoint(x: x - half, y: y), NSPoint(x: x + half, y: y), color: .black, clear: true)
                        stroke(NSPoint(x: x - half, y: y), NSPoint(x: x + half, y: y), color: weft)
                    }
                }
            }
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = !active
        return image
    }
}
