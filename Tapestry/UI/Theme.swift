import AppKit
import SwiftUI

/// Pacer's look: the popover sits on the system menu material with translucent tiles, and the main
/// window is warm paper with white cards. Dark mode is neutral gray. Type is big and tightly
/// tracked. The accent is the coral from the icon's middle thread.
enum Theme {
    static let canvas = Color(light: 0xF7F5F3, dark: 0x141414)
    static let card = Color(light: 0xFFFFFF, dark: 0x212020)
    static let ink = Color(light: 0x0D0D0D, dark: 0xFFFFFF)
    static let muted = Color(light: 0x85807B, dark: 0xA39E99)
    static let hairline = Color(light: 0xE4E1DD, dark: 0x323131)
    static let warn = Color(light: 0xC2410C, dark: 0xFB923C)
    static let accent = Color(light: 0xEC4436, dark: 0xFF6A55)
    static let accentNS = NSColor(name: nil) { appearance in
        NSColor(hex: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? 0xFF6A55 : 0xEC4436)
    }
    /// A neutral fill that works on any background, including the menu material.
    static let quietWash = Color.primary.opacity(0.07)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

/// "Tapestry" with a fingertip dot after it, the way Pacer ends with its "you are here" dot.
struct Wordmark: View {
    var size: CGFloat = 20

    var body: some View {
        let dot = size * 0.3
        HStack(alignment: .firstTextBaseline, spacing: size * 0.3) {
            Text("Tapestry").display(size).foregroundStyle(.primary)
            Circle().fill(Theme.accent)
                .frame(width: dot, height: dot)
                .background(Circle().fill(Theme.accent.opacity(0.28)).frame(width: dot * 1.9, height: dot * 1.9))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tapestry")
    }
}

extension View {
    /// Display type: semibold and tightly tracked, after Cosmos.
    func display(_ size: CGFloat) -> some View {
        font(Theme.display(size)).tracking(-size * 0.035)
    }

    /// A translucent rounded tile that lets the menu material show through.
    func tile() -> some View {
        background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Format {
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}

/// Primary and secondary buttons in the calm style.
struct PillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? .white : Theme.ink)
            .background(prominent ? Theme.accent : Theme.quietWash, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// A quiet round icon button, like the ones along the bottom of system menus.
struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 24
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(hovering ? .primary : .secondary)
                .frame(width: size, height: size)
                .background(hovering ? Theme.quietWash : .clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The gesture drawn small: one dot per finger, in a slight arc like fingertips. Holds sit in a
/// pressed capsule, and swipes trail streaks behind them.
struct GestureGlyph: View {
    let trigger: Trigger
    var size: CGFloat = 40
    var dimmed = false

    var body: some View {
        Canvas { context, canvas in
            let n = trigger.fingers
            let dot = size * 0.135
            let pitch = size * 0.16
            let direction = trigger.motion.direction.map { CGVector(dx: CGFloat($0.x), dy: -CGFloat($0.y)) }
            var center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            if let direction {
                center.x += direction.dx * size * 0.1
                center.y += direction.dy * size * 0.1
            }
            let points = (0..<n).map { i in
                let t = n > 1 ? CGFloat(i) / CGFloat(n - 1) * 2 - 1 : 0
                return CGPoint(x: center.x + (CGFloat(i) - CGFloat(n - 1) / 2) * pitch, y: center.y + size * 0.05 * (t * t - 0.5))
            }

            if trigger.motion == .hold, let first = points.first, let last = points.last {
                let rect = CGRect(x: first.x - dot, y: center.y - dot * 1.05, width: last.x - first.x + dot * 2, height: dot * 2.1)
                context.fill(Path(roundedRect: rect, cornerRadius: dot * 1.05), with: .color(Theme.accent.opacity(0.22)))
            }
            for point in points {
                if let direction {
                    var trail = Path()
                    let length = size * 0.26
                    let tail = CGPoint(x: point.x - direction.dx * length, y: point.y - direction.dy * length)
                    trail.move(to: point)
                    trail.addLine(to: tail)
                    context.stroke(trail, with: .linearGradient(Gradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0)]), startPoint: point, endPoint: tail), style: StrokeStyle(lineWidth: dot * 0.7, lineCap: .round))
                }
                context.fill(Path(ellipseIn: CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)), with: .color(Theme.accent))
            }
        }
        .frame(width: size, height: size)
        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
        .saturation(dimmed ? 0 : 1)
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityHidden(true)
    }
}
