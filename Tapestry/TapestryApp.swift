import AppKit
import SwiftUI

// Tapestry: trackpad gestures that press keys, run Shortcuts, and open apps. Lives in the menu bar.

@main
struct TapestryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
        } label: {
            MenuBarLabel()
                .environment(store)
        }
        .menuBarExtraStyle(.window)

        Window("Tapestry", id: WindowID.main) {
            MainView()
                .environment(store)
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 560, height: 640)
        .defaultPosition(.center)

        Window("Tapestry Settings", id: WindowID.settings) {
            SettingsView()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Posting key events needs Accessibility. This shows the system prompt once.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            log.info("launch: accessibility=\(AXIsProcessTrusted()) mappings=\(Store.shared.mappings.count)")
            Multitouch.start()

            // Trackpads stop reporting after sleep, and a Magic Trackpad can connect later.
            _ = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { _ = Multitouch.start() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Multitouch.stop() }
    }
}
