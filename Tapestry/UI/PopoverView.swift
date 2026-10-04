import SwiftUI

struct MenuBarLabel: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Keys.welcomed) private var welcomed = false
    @State private var active = false

    var body: some View {
        Image(nsImage: MenuBarIcon.image(active: active))
            .task {
                if !welcomed {
                    welcomed = true
                    openWindow(id: WindowID.main)
                    NSApp.activate()
                }
            }
            .task(id: store.lastFired) {
                guard store.lastFired != nil else { return }
                active = true
                try? await Task.sleep(for: .milliseconds(600))
                active = false
            }
    }
}

/// Sits on the system menu material, so it reads like part of macOS.
struct PopoverView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Wordmark(size: 20)
                Spacer()
                Text("\(store.mappings.filter(\.enabled).count) gestures")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if !store.trusted {
                AccessibilityTile()
            }

            if store.mappings.isEmpty {
                Text("No gestures yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tile()
            } else {
                VStack(spacing: 8) {
                    ForEach(store.mappings) { mapping in
                        MappingTile(mapping: mapping) {
                            store.focus = mapping.id
                            open(WindowID.main)
                        }
                    }
                }
            }

            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { store.refreshTrust() }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if let fired = store.lastFired {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("\(fired.trigger.title), \(Format.ago(fired.date, now: context.date))")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            IconButton(symbol: "plus", help: "Add a gesture") {
                store.focus = store.add().id
                open(WindowID.main)
            }
            IconButton(symbol: "gearshape", help: "Settings") { open(WindowID.settings) }
            Menu {
                Button("Open Tapestry") { open(WindowID.main) }
                Button("Settings…") { open(WindowID.settings) }
                Button("Reconnect Trackpads") { Multitouch.start() }
                Divider()
                Button("Quit Tapestry") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("More")
        }
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}

/// Tapestry can't press keys until it has Accessibility.
struct AccessibilityTile: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Needs Accessibility")
                    .font(.system(size: 13, weight: .semibold))
                Text("Gestures can't press keys until you allow it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Allow") { openAccessibilitySettings() }
                .buttonStyle(PillButtonStyle())
        }
        .padding(12)
        .tile()
    }
}

/// One gesture in the popover. Clicking it opens the main window on that gesture.
struct MappingTile: View {
    let mapping: Mapping
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                GestureGlyph(trigger: mapping.trigger, size: 32, dimmed: !mapping.enabled)
                VStack(alignment: .leading, spacing: 1) {
                    Text(mapping.trigger.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(mapping.summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if !mapping.enabled {
                    Text("Off")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile()
            .contentShape(Rectangle())
            .scaleEffect(hovering ? 1.015 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

@MainActor
func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}
