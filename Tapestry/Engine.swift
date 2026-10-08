import AppKit
import ApplicationServices
import os
import simd

let log = Logger(subsystem: "dev.tapestry.Tapestry", category: "gesture")

// MARK: - Actions

@MainActor
enum Performer {
    /// Taps and swipes: run once.
    static func run(_ action: Action) {
        begin(action)
        end(action)
    }

    /// Holds: a key stays down until `end`. Other actions run once when the hold starts.
    static func begin(_ action: Action) {
        switch action {
        case .key(let combo): post(combo, down: true)
        case .shortcut(let name): runShortcut(name)
        case .open(let target): open(target)
        }
    }

    static func end(_ action: Action) {
        if case .key(let combo) = action { post(combo, down: false) }
    }

    private static func post(_ combo: KeyCombo, down: Bool) {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: combo.keyCode, keyDown: down) else { return }
        var flags = combo.eventFlags
        if let own = combo.modifierFlag {
            event.type = .flagsChanged
            if down { flags.insert(own) } else { flags = [] }
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private static func runShortcut(_ name: String) {
        guard !name.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        try? process.run()
    }

    private static func open(_ target: String) {
        if target.hasPrefix("/") {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: target), configuration: .init())
        } else if let url = URL(string: target), url.scheme != nil {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Gesture detection

@MainActor
final class Detector {
    static let shared = Detector()

    private let maxTapDuration = 0.6     // seconds from first touch to last lift
    /// Seconds of resting fingers before a hold starts. Above the minimum tap, so a tap still fits
    /// before a hold on the same finger count takes over.
    private var holdDelay: Double { Store.shared.minTapDuration + 0.15 }
    private let maxSwipeDuration = 1.0   // slower movements are drags, not swipes
    private let moveTolerance: Float = 0.03  // normalized trackpad units
    /// Normalized x spans the trackpad's width, which is about 1.5 times its height. Scaling x by
    /// this makes a 45° finger movement come out at 45°.
    private let aspect: Float = 1.5

    private var sessionStart: Double?
    private var maxFingers = 0
    private var anchor: SIMD2<Float>?
    private var last: SIMD2<Float>?
    private var reachedAt: Double?
    private var moved = false
    private var holding: Mapping?
    private var held = false

    func frame(fingers n: Int, centroid: SIMD2<Float>, time t: Double) {
        let store = Store.shared

        if n > 0, sessionStart == nil {
            sessionStart = t
        }
        if n > maxFingers {
            maxFingers = n
            anchor = centroid
            reachedAt = t
        }
        if n == maxFingers, let anchor {
            last = centroid
            if simd_distance(centroid, anchor) > moveTolerance { moved = true }
        }

        if store.teaching == nil, holding == nil, !held, n == maxFingers, !moved, let reachedAt, t - reachedAt >= holdDelay,
           let mapping = store.mapping(for: Trigger(fingers: n, motion: .hold)) {
            log.info("hold matched: \(mapping.trigger.title, privacy: .public)")
            holding = mapping
            held = true
            Performer.begin(mapping.action)
            store.didFire(mapping)
        } else if let mapping = holding, n < mapping.trigger.fingers {
            holding = nil
            Performer.end(mapping.action)
        }

        guard n == 0, let start = sessionStart else { return }
        defer { reset() }
        let duration = t - start
        let delta = (last ?? .zero) - (anchor ?? .zero)
        log.info("touch ended: fingers=\(self.maxFingers) duration=\(duration, format: .fixed(precision: 2)) dx=\(delta.x, format: .fixed(precision: 3)) dy=\(delta.y, format: .fixed(precision: 3))")
        if store.teaching != nil {
            teach(duration: duration, delta: delta)
            return
        }
        guard !held else { return }

        let motion: Motion?
        if !moved {
            motion = (store.minTapDuration...maxTapDuration).contains(duration) ? .tap : nil
        } else {
            motion = duration <= maxSwipeDuration ? Motion.swipe([delta.x * aspect, delta.y]) : nil
        }
        guard let motion, let mapping = store.mapping(for: Trigger(fingers: maxFingers, motion: motion)) else { return }
        log.info("matched: \(mapping.trigger.title, privacy: .public) (accessibility=\(AXIsProcessTrusted()))")
        Performer.run(mapping.action)
        store.didFire(mapping)
    }

    /// Turns the gesture just made into the taught mapping's trigger, or says why it did not count.
    /// A still rest past the longest tap teaches a hold.
    private func teach(duration: Double, delta: SIMD2<Float>) {
        let store = Store.shared
        guard Trigger.fingerChoices.contains(maxFingers) else { return }  // clicks and scrolls
        let motion: Motion?
        if !moved {
            motion = duration > maxTapDuration ? .hold : duration >= store.minTapDuration ? .tap : nil
            if motion == nil { store.teachHint = "Too quick for a tap. Rest the fingers a moment, then lift." }
        } else if duration > maxSwipeDuration {
            motion = nil
            store.teachHint = "Too slow for a swipe. Finish within a second."
        } else {
            motion = Motion.swipe([delta.x * aspect, delta.y])
            if motion == nil { store.teachHint = "Swipe farther, about a third of the trackpad, straight or on a true diagonal." }
        }
        guard let motion else { return }
        let trigger = Trigger(fingers: maxFingers, motion: motion)
        log.info("taught: \(trigger.title, privacy: .public)")
        store.learn(trigger)
    }

    func reset() {
        if let holding { Performer.end(holding.action) }
        sessionStart = nil
        maxFingers = 0
        anchor = nil
        last = nil
        reachedAt = nil
        moved = false
        holding = nil
        held = false
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

    @discardableResult
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
        log.info("multitouch started: devices=\(CFArrayGetCount(list))")
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

// MARK: - Shortcuts.app

enum Shortcuts {
    /// The user's shortcut names, from the `shortcuts` command line tool.
    static func names() async -> [String] {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["list"]
            let pipe = Pipe()
            process.standardOutput = pipe
            guard (try? process.run()) != nil else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).sorted()
        }.value
    }
}
