import ServiceManagement
import SwiftUI

/// One page, in the native grouped style.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open Tapestry at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }

            Section {
                @Bindable var store = store
                LabeledContent("Tap press time") {
                    HStack {
                        Slider(value: $store.minTapDuration, in: 0...0.4, step: 0.02)
                        Text("\(Int((store.minTapDuration * 1000).rounded())) ms")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            } header: {
                Text("Gestures")
            } footer: {
                Text("How long fingers must rest before a lift counts as a tap. Lower feels quicker; higher ignores more drags and swipes. Holds start 150 ms after this.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Accessibility") {
                    if store.trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Open System Settings") { openAccessibilitySettings() }
                    }
                }
                LabeledContent("Trackpads") {
                    Button("Reconnect") { Multitouch.start() }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Tapestry needs Accessibility to press keys. Reconnect if a trackpad you just paired doesn't respond.")
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .tint(Theme.accent)
        .frame(width: 440, height: 480)
        .onAppear { store.refreshTrust() }
    }
}
