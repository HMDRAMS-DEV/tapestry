import AppKit
import ApplicationServices
import Observation
import simd

// MARK: - Gestures

enum Motion: String, Codable, CaseIterable, Identifiable {
    case tap, hold, upRight, upLeft, downRight, downLeft

    var id: String { rawValue }

    var isSwipe: Bool { direction != nil }

    /// Short label for the gesture picker.
    var short: String {
        switch self {
        case .tap: "Tap"
        case .hold: "Hold"
        case .upRight: "↗"
        case .upLeft: "↖"
        case .downRight: "↘"
        case .downLeft: "↙"
        }
    }

    var phrase: String {
        switch self {
        case .tap: "tap"
        case .hold: "hold"
        case .upRight: "swipe up-right"
        case .upLeft: "swipe up-left"
        case .downRight: "swipe down-right"
        case .downLeft: "swipe down-left"
        }
    }

    /// Unit direction on the trackpad, y up.
    var direction: SIMD2<Float>? {
        let d: Float = 0.7071
        switch self {
        case .tap, .hold: return nil
        case .upRight: return [d, d]
        case .upLeft: return [-d, d]
        case .downRight: return [d, -d]
        case .downLeft: return [-d, -d]
        }
    }

    /// The diagonal swipe a movement matches. Straight swipes are left to macOS.
    static func swipe(_ delta: SIMD2<Float>) -> Motion? {
        guard simd_length(delta) >= 0.12 else { return nil }
        let degrees = atan2(delta.y, delta.x) * 180 / .pi
        switch Int((degrees / 45).rounded()) {
        case 1: return .upRight
        case 3: return .upLeft
        case -1: return .downRight
        case -3: return .downLeft
        default: return nil
        }
    }
}

struct Trigger: Codable, Hashable {
    var fingers: Int
    var motion: Motion

    static let fingerChoices = [3, 4, 5]

    var title: String {
        let count = [3: "Three", 4: "Four", 5: "Five"][fingers] ?? "\(fingers)"
        return "\(count)-finger \(motion.phrase)"
    }
}

// MARK: - Actions

struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags` raw value, limited to Command, Option, Control, and Shift.
    var modifiers: UInt
    var key: String

    static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let returnKey = KeyCombo(keyCode: 36, modifiers: 0, key: "Return")
    static let option = KeyCombo(keyCode: 58, modifiers: 0, key: "Option")

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var label: String {
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        if let symbol = Self.modifierSymbols[keyCode] { symbols += symbol }
        if symbols.isEmpty { return key }
        return key.count > 1 ? "\(symbols) \(key)" : symbols + key
    }

    /// Set for Command, Shift, Option, Control, and fn. These post as modifier changes, not key presses.
    var modifierFlag: CGEventFlags? {
        switch keyCode {
        case 54, 55: .maskCommand
        case 56, 60: .maskShift
        case 58, 61: .maskAlternate
        case 59, 62: .maskControl
        case 63: .maskSecondaryFn
        default: nil
        }
    }

    var eventFlags: CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        return result
    }

    private static let modifierSymbols: [UInt16: String] = [54: "⌘", 55: "⌘", 56: "⇧", 60: "⇧", 58: "⌥", 61: "⌥", 59: "⌃", 62: "⌃"]

    private static let names: [UInt16: String] = [
        36: "Return", 76: "Enter", 48: "Tab", 49: "Space", 51: "Delete", 117: "Forward Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12",
        54: "Right Command", 55: "Command", 56: "Shift", 60: "Right Shift", 58: "Option", 61: "Right Option",
        59: "Control", 62: "Right Control", 63: "fn",
    ]

    static func name(for keyCode: UInt16, characters: String?) -> String {
        names[keyCode] ?? characters?.uppercased() ?? "Key \(keyCode)"
    }
}

enum Action: Codable, Hashable {
    case key(KeyCombo)
    case shortcut(String)
    /// An app's path, or a URL.
    case open(String)

    enum Kind: String, CaseIterable, Identifiable {
        case key, shortcut, open
        var id: String { rawValue }
        var label: String {
            switch self {
            case .key: "Key"
            case .shortcut: "Shortcut"
            case .open: "Open"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .key: .key
        case .shortcut: .shortcut
        case .open: .open
        }
    }

    func summary(holding: Bool) -> String {
        switch self {
        case .key(let combo): "\(holding ? "Hold" : "Press") \(combo.label)"
        case .shortcut(let name): name.isEmpty ? "Run a shortcut" : "Run “\(name)”"
        case .open(let target): target.isEmpty ? "Open an app or link" : "Open \(Self.displayName(target))"
        }
    }

    static func displayName(_ target: String) -> String {
        if target.hasPrefix("/") {
            return FileManager.default.displayName(atPath: target).replacingOccurrences(of: ".app", with: "")
        }
        return URL(string: target)?.host() ?? target
    }
}

struct Mapping: Codable, Identifiable, Hashable {
    var id = UUID()
    var trigger: Trigger
    var action: Action
    var enabled = true

    var summary: String { action.summary(holding: trigger.motion == .hold) }
}

// MARK: - Store

enum WindowID {
    static let main = "main"
    static let settings = "settings"
}

enum Keys {
    static let mappings = "mappings"
    static let welcomed = "welcomed"
}

@MainActor
@Observable
final class Store {
    static let shared = Store()

    struct Fired: Equatable {
        var trigger: Trigger
        var date: Date
    }

    var mappings: [Mapping] {
        didSet { save() }
    }

    /// The last gesture that ran an action. The menu bar glyph lights up when it changes.
    private(set) var lastFired: Fired?
    private(set) var trusted = AXIsProcessTrusted()
    /// The card the main window opens on.
    var focus: Mapping.ID?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Keys.mappings),
           let saved = try? JSONDecoder().decode([Mapping].self, from: data) {
            mappings = saved
        } else {
            mappings = [
                Mapping(trigger: Trigger(fingers: 5, motion: .tap), action: .key(.returnKey)),
                Mapping(trigger: Trigger(fingers: 3, motion: .tap), action: .key(.option)),
            ]
        }
    }

    /// The first enabled mapping for a gesture.
    func mapping(for trigger: Trigger) -> Mapping? {
        mappings.first { $0.enabled && $0.trigger == trigger }
    }

    func isShared(_ mapping: Mapping) -> Bool {
        mappings.contains { $0.id != mapping.id && $0.enabled && $0.trigger == mapping.trigger }
    }

    /// A new mapping on the first gesture nothing uses yet.
    @discardableResult
    func add() -> Mapping {
        let used = Set(mappings.map(\.trigger))
        let trigger = Motion.allCases.lazy
            .flatMap { motion in Trigger.fingerChoices.map { Trigger(fingers: $0, motion: motion) } }
            .first { !used.contains($0) } ?? Trigger(fingers: 4, motion: .tap)
        let mapping = Mapping(trigger: trigger, action: .key(.returnKey))
        mappings.append(mapping)
        return mapping
    }

    func remove(_ id: Mapping.ID) {
        mappings.removeAll { $0.id == id }
    }

    func didFire(_ mapping: Mapping) {
        lastFired = Fired(trigger: mapping.trigger, date: .now)
    }

    func refreshTrust() {
        trusted = AXIsProcessTrusted()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(data, forKey: Keys.mappings)
        }
    }
}
