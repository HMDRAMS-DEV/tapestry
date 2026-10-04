import AppKit
import ApplicationServices
import ServiceManagement
import simd

// Optap: a trackpad gesture that presses Option. Menu bar only.

enum Gesture: String, CaseIterable {
    case threeFingerTap, fourFingerTap, threeFingerHold

    var title: String {
        switch self {
        case .threeFingerTap: "Three-finger tap"
        case .fourFingerTap: "Four-finger tap"
        case .threeFingerHold: "Three-finger hold (Option held while touching)"
        }
    }

    var fingers: Int { self == .fourFingerTap ? 4 : 3 }
    var isHold: Bool { self == .threeFingerHold }
}

// MARK: - Option key

enum OptionKey {
    private static let keyCode: CGKeyCode = 58  // left Option

    static func set(down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down) else { return }
        event.type = .flagsChanged
        event.flags = down ? .maskAlternate : []
        event.post(tap: .cghidEventTap)
    }

    static func tap() {
        set(down: true)
        set(down: false)
    }
}

// MARK: - Gesture detection

@MainActor
final class Detector {
    static let shared = Detector()

    var gesture: Gesture = .threeFingerTap

    private let maxTapDuration = 0.3   // seconds from first touch to last lift
    private let holdDelay = 0.18       // seconds of resting fingers before Option goes down
    private let moveTolerance: Float = 0.03  // normalized trackpad units

    private var sessionStart: Double?
    private var maxFingers = 0
    private var anchor: SIMD2<Float>?
    private var reachedTargetAt: Double?
    private var moved = false
    private var holding = false

    func frame(fingers n: Int, centroid: SIMD2<Float>, time t: Double) {
        let target = gesture.fingers

        if n > 0, sessionStart == nil {
            sessionStart = t
        }
        if n > maxFingers {
            maxFingers = n
            anchor = centroid
            if n == target { reachedTargetAt = t }
        }
        if n == maxFingers, let anchor, simd_distance(centroid, anchor) > moveTolerance {
            moved = true
        }

        if gesture.isHold {
            if !holding, n == target, maxFingers == target, !moved,
               let reached = reachedTargetAt, t - reached >= holdDelay {
                holding = true
                OptionKey.set(down: true)
            } else if holding, n < target {
                holding = false
                OptionKey.set(down: false)
            }
        }

        guard n == 0, let start = sessionStart else { return }
        if !gesture.isHold, maxFingers == target, !moved, t - start <= maxTapDuration {
            OptionKey.tap()
        }
        reset()
    }

    func reset() {
        if holding { OptionKey.set(down: false) }
        sessionStart = nil
        maxFingers = 0
        anchor = nil
        reachedTargetAt = nil
        moved = false
        holding = false
    }
}

// MARK: - MultitouchSupport (private framework, the same one BetterTouchTool uses)

@MainActor
enum Multitouch {
    typealias Callback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>
    private typealias Register = @convention(c) (UnsafeMutableRawPointer, Callback) -> Void
    private typealias Start = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias Stop = @convention(c) (UnsafeMutableRawPointer) -> Void

    private static let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
    private static func sym<T>(_ name: String, _: T.Type) -> T? {
        guard let lib, let p = dlsym(lib, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    private static var devices: CFArray?

    // One touch record is 96 bytes. state is at offset 20, normalized x/y at 32/36.
    private static let callback: Callback = { _, data, count, timestamp, _ in
        var touching = 0
        var sum = SIMD2<Float>(0, 0)
        if let data {
            for i in 0..<Int(count) {
                let touch = data + i * 96
                let state = touch.load(fromByteOffset: 20, as: Int32.self)
                guard state == 4 || state == 5 else { continue }  // make-touch, touching
                touching += 1
                sum += SIMD2(touch.load(fromByteOffset: 32, as: Float.self),
                             touch.load(fromByteOffset: 36, as: Float.self))
            }
        }
        let centroid = touching > 0 ? sum / Float(touching) : sum
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Detector.shared.frame(fingers: touching, centroid: centroid, time: timestamp)
            }
        }
        return 0
    }

    static func start() -> Bool {
        stop()
        guard let createList = sym("MTDeviceCreateList", CreateList.self),
              let register = sym("MTRegisterContactFrameCallback", Register.self),
              let startDevice = sym("MTDeviceStart", Start.self) else { return false }
        let list = createList().takeRetainedValue()
        devices = list
        for i in 0..<CFArrayGetCount(list) {
            guard let device = CFArrayGetValueAtIndex(list, i) else { continue }
            let ptr = UnsafeMutableRawPointer(mutating: device)
            register(ptr, callback)
            startDevice(ptr, 0)
        }
        return CFArrayGetCount(list) > 0
    }

    static func stop() {
        guard let list = devices, let stopDevice = sym("MTDeviceStop", Stop.self) else { return }
        for i in 0..<CFArrayGetCount(list) {
            if let device = CFArrayGetValueAtIndex(list, i) {
                stopDevice(UnsafeMutableRawPointer(mutating: device))
            }
        }
        devices = nil
        Detector.shared.reset()
    }
}

// MARK: - App

@main
@MainActor
final class OptapApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let defaults = UserDefaults.standard

    static func main() {
        let app = NSApplication.shared
        let delegate = OptapApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Detector.shared.gesture = Gesture(rawValue: defaults.string(forKey: "gesture") ?? "") ?? .threeFingerTap

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "option", accessibilityDescription: "Optap")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Posting key events needs Accessibility. This shows the system prompt once.
        let prompt = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)

        _ = Multitouch.start()

        // Trackpads stop reporting after sleep, and a Magic Trackpad can connect later.
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { _ = Multitouch.start() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Multitouch.stop()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        for gesture in Gesture.allCases {
            let item = NSMenuItem(title: gesture.title, action: #selector(pickGesture(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = gesture.rawValue
            item.state = Detector.shared.gesture == gesture ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if !AXIsProcessTrusted() {
            let item = NSMenuItem(title: "Grant Accessibility…", action: #selector(openAccessibility), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        let rescan = NSMenuItem(title: "Reconnect Trackpads", action: #selector(rescan), keyEquivalent: "")
        rescan.target = self
        menu.addItem(rescan)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Optap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func pickGesture(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let gesture = Gesture(rawValue: raw) else { return }
        Detector.shared.reset()
        Detector.shared.gesture = gesture
        defaults.set(raw, forKey: "gesture")
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        try? service.status == .enabled ? service.unregister() : service.register()
    }

    @objc private func rescan() {
        _ = Multitouch.start()
    }
}
