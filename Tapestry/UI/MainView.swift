import SwiftUI
import UniformTypeIdentifiers

/// Every gesture as a card. Click one to edit what it is and what it does.
struct MainView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var expanded: Mapping.ID?

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Gestures")
                        .display(32)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    IconButton(symbol: "plus", help: "Add a gesture", size: 30) {
                        let mapping = store.add()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded = mapping.id }
                    }
                    IconButton(symbol: "gearshape", help: "Settings", size: 30) {
                        openWindow(id: WindowID.settings)
                        NSApp.activate()
                    }
                }

                if !store.trusted {
                    AccessibilityTile()
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if store.mappings.isEmpty {
                    Text("Add a gesture with the + button.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }

                ForEach($store.mappings) { $mapping in
                    MappingCard(mapping: $mapping, expanded: expanded == mapping.id) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            expanded = expanded == mapping.id ? nil : mapping.id
                        }
                    }
                }

                if let fired = store.lastFired {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("Last gesture: \(fired.trigger.title), \(Format.ago(fired.date, now: context.date))")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .frame(width: 560)
        .frame(minHeight: 420)
        .background(Theme.canvas)
        .onAppear {
            store.refreshTrust()
            expanded = store.focus ?? expanded
        }
        .onChange(of: store.focus) { _, focus in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded = focus }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshTrust()
        }
    }
}

struct MappingCard: View {
    @Environment(Store.self) private var store
    @Binding var mapping: Mapping
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 14) {
                    GestureGlyph(trigger: mapping.trigger, size: 44, dimmed: !mapping.enabled)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mapping.trigger.title)
                            .display(17)
                            .foregroundStyle(mapping.enabled ? Theme.ink : Theme.muted)
                        Text(mapping.summary)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Toggle("On", isOn: $mapping.enabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Theme.accent)
                        .labelsHidden()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.horizontal, 16)
                MappingEditor(mapping: $mapping)
                    .padding(16)
                    .transition(.opacity)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Fingers, gesture, and action, in rows of segmented controls.
struct MappingEditor: View {
    @Environment(Store.self) private var store
    @Binding var mapping: Mapping
    @State private var shortcuts: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Teach") { TeachButton(id: mapping.id) }
            row("Fingers") {
                Picker("Fingers", selection: $mapping.trigger.fingers) {
                    ForEach(Trigger.fingerChoices, id: \.self) { Text("\($0)").tag($0) }
                }
                .fixedSize()
            }
            row("Gesture") {
                Picker("Gesture", selection: style) {
                    Text("Tap").tag(Motion.tap)
                    Text("Hold").tag(Motion.hold)
                    Text("Swipe").tag(Motion.upRight)
                }
                .fixedSize()
            }
            if mapping.trigger.motion.isSwipe {
                row("Direction") {
                    Picker("Direction", selection: $mapping.trigger.motion) {
                        ForEach(Motion.directions) { Text($0.short).tag($0) }
                    }
                    .fixedSize()
                }
            }
            row("Action") {
                Picker("Action", selection: kind) {
                    ForEach(Action.Kind.allCases) { Text($0.label).tag($0) }
                }
                .fixedSize()
            }
            row("") { value }

            ForEach(notes, id: \.self) { note in
                Label(note, systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Remove Gesture", role: .destructive) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { store.remove(mapping.id) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.warn)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onDisappear { if store.teaching == mapping.id { store.teaching = nil } }
        .task(id: mapping.action.kind) {
            if mapping.action.kind == .shortcut, shortcuts.isEmpty { shortcuts = await Shortcuts.names() }
        }
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(width: 64, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var value: some View {
        switch mapping.action {
        case .key(let combo):
            KeyRecorder(combo: Binding(get: { combo }, set: { mapping.action = .key($0) }))
        case .shortcut(let name):
            Picker("Shortcut", selection: Binding(get: { name }, set: { mapping.action = .shortcut($0) })) {
                if name.isEmpty { Text("Choose a shortcut").tag("") }
                ForEach(shortcuts.contains(name) || name.isEmpty ? shortcuts : [name] + shortcuts, id: \.self) {
                    Text($0).tag($0)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 260)
        case .open(let target):
            OpenField(target: Binding(get: { target }, set: { mapping.action = .open($0) }))
        }
    }

    /// Tap, hold, or swipe. Every direction shows as Swipe, tagged with the default direction.
    private var style: Binding<Motion> {
        Binding(
            get: { mapping.trigger.motion.isSwipe ? .upRight : mapping.trigger.motion },
            set: { motion in
                guard !(motion.isSwipe && mapping.trigger.motion.isSwipe) else { return }
                mapping.trigger.motion = motion
            }
        )
    }

    private var kind: Binding<Action.Kind> {
        Binding(
            get: { mapping.action.kind },
            set: { kind in
                guard kind != mapping.action.kind else { return }
                switch kind {
                case .key: mapping.action = .key(.returnKey)
                case .shortcut: mapping.action = .shortcut("")
                case .open: mapping.action = .open("")
                }
            }
        )
    }

    /// Clashes with other gestures and with what macOS already does with the same fingers.
    private var notes: [String] {
        var notes: [String] = []
        let trigger = mapping.trigger
        if store.isShared(mapping) {
            notes.append("Another gesture uses this too. The one higher in the list runs.")
        }
        if trigger == Trigger(fingers: 3, motion: .tap) {
            notes.append("If a three-finger tap also looks things up, turn off Look up & data detectors in System Settings > Trackpad.")
        }
        if trigger.motion.isSwipe, trigger.fingers < 5, [.up, .down, .left, .right].contains(trigger.motion) {
            notes.append("macOS may use \(trigger.fingers)-finger straight swipes for Spaces, Mission Control, and App Exposé, and both will run. Turn those off or move them to the other finger count in System Settings > Trackpad > More Gestures.")
        } else if trigger.motion.isSwipe, trigger.fingers < 5 {
            notes.append("macOS may use \(trigger.fingers)-finger swipes for Spaces and Mission Control, and both will run. Diagonals mostly avoid them; if not, move those to the other finger count in System Settings > Trackpad > More Gestures.")
        }
        if trigger.fingers == 3, trigger.motion != .tap {
            notes.append("If three-finger drag is on in Accessibility > Pointer Control, it will also drag.")
        }
        if trigger.motion == .hold, mapping.action.kind != .key {
            notes.append("Holds keep keys down. Other actions run once when the hold starts.")
        }
        return notes
    }
}

/// Sets a gesture by doing it. Click, then tap, hold, or swipe on the trackpad.
struct TeachButton: View {
    @Environment(Store.self) private var store
    let id: Mapping.ID

    var body: some View {
        let teaching = store.teaching == id
        HStack(spacing: 10) {
            Button {
                store.teaching = teaching ? nil : id
            } label: {
                Text(teaching ? "Do the gesture…" : "Record Gesture")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(teaching ? Theme.accent : Theme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(minWidth: 120)
                    .background(Theme.quietWash, in: Capsule())
                    .overlay(Capsule().strokeBorder(teaching ? Theme.accent : .clear, lineWidth: 1.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(teaching ? "Click to cancel" : "Click, then do the gesture on the trackpad")

            if teaching {
                Text(store.teachHint ?? "Tap, hold, or swipe with 3 to 5 fingers. Click to cancel.")
                    .font(.system(size: 11))
                    .foregroundStyle(store.teachHint == nil ? Theme.muted : Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A key or shortcut. Click, then press the keys. A modifier on its own, like Option, counts.
struct KeyRecorder: View {
    @Binding var combo: KeyCombo
    @State private var recording = false
    @State private var monitor: Any?
    @State private var pendingModifier: UInt16?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Type a key…" : combo.label)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(recording ? Theme.accent : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(minWidth: 120)
                .background(Theme.quietWash, in: Capsule())
                .overlay(Capsule().strokeBorder(recording ? Theme.accent : .clear, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Click, then press the key or shortcut")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        pendingModifier = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            MainActor.assumeIsolated {
                let modifiers = event.modifierFlags.intersection(KeyCombo.relevant)
                if event.type == .keyDown {
                    finish(KeyCombo(
                        keyCode: event.keyCode, modifiers: modifiers.rawValue,
                        key: KeyCombo.name(for: event.keyCode, characters: event.charactersIgnoringModifiers)
                    ))
                } else if !modifiers.isEmpty || event.keyCode == 63 && pendingModifier == nil {
                    pendingModifier = event.keyCode
                } else if let code = pendingModifier {
                    // A modifier went down and came back up with no other key: record the modifier itself.
                    finish(KeyCombo(keyCode: code, modifiers: 0, key: KeyCombo.name(for: code, characters: nil)))
                }
            }
            return nil
        }
    }

    private func finish(_ new: KeyCombo) {
        combo = new
        stop()
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// An app, chosen from a panel, or a link typed in.
struct OpenField: View {
    @Binding var target: String

    var body: some View {
        HStack(spacing: 8) {
            if target.hasPrefix("/") {
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: target))
                        .resizable()
                        .frame(width: 18, height: 18)
                    Text(Action.displayName(target))
                        .font(.system(size: 13, weight: .medium))
                    Button {
                        target = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.quietWash, in: Capsule())
            } else {
                TextField("https://… or choose an app", text: $target)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 230)
            }
            Button("Choose App…") { choose() }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url { target = url.path }
    }
}
