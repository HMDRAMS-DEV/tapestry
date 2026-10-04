<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/banner-dark.png">
  <img src="docs/banner-light.png" alt="Tapestry: five fingers, press Return. A macOS menu bar app that turns trackpad taps, holds, and diagonal swipes into keys, Shortcuts, and apps.">
</picture>

Tapestry turns trackpad gestures into actions, without BetterTouchTool. Tap five fingers to press Return, hold three to keep Option down for push-to-talk, or swipe four fingers up-right to run a Shortcut.

## Gestures

Each gesture is a finger count and a motion:

- **Fingers:** three, four, or five.
- **Tap:** touch and lift within 0.3 seconds without moving.
- **Hold:** rest the fingers for a moment. A key stays down until you lift.
- **Diagonal swipe:** up-right, up-left, down-right, or down-left, within a second. Straight swipes are left to macOS.

## Actions

- **Key:** any key or shortcut, like Return, ⌘↩, or Option on its own. Click the key field and press it.
- **Shortcut:** runs one of your Shortcuts.app shortcuts by name.
- **Open:** opens an app or a link.

## Setup

1. Build and open Tapestry (see below). The woven glyph appears in the menu bar, and the gestures window opens.
2. Grant Accessibility when macOS asks. Tapestry needs it to press keys. If you missed the prompt, use **Allow** in the menu bar popover.
3. Tapestry only listens to the trackpad. It can't stop macOS from also acting on the same gesture. If a three-finger tap also looks things up, turn off Look up & data detectors in System Settings > Trackpad. If your swipes also switch Spaces, move those system gestures to a finger count you don't use here.

**Open Tapestry at login** is in Settings.

## How it works

Tapestry reads raw touches from Apple's private `MultitouchSupport` framework, the same one BetterTouchTool uses. For each touch it tracks the most fingers down, how long they stayed, and how far their center moved. When that matches a gesture, it posts key events with `CGEvent`, runs `shortcuts run`, or opens the app or link with `NSWorkspace`. Tapestry has no network access and no analytics. It stores only your gestures.

Because the framework is private, a future macOS update could break it.

## Build

Requirements: macOS 15 or later on Apple silicon and the Xcode Command Line Tools. You don't need Xcode.

```sh
./build.sh
open build/Tapestry.app
```

macOS ties the Accessibility permission to the app's signature. `build.sh` signs with a code signing certificate named "Tapestry Local Signing" if your keychain has one, so the permission survives rebuilds. Without it the build is ad-hoc signed, and after each rebuild you need to remove Tapestry from System Settings > Privacy & Security > Accessibility and add it again.

To redraw the icon: `swift scripts/render-icon.swift`. To redraw the README banner: `scripts/render-banner.sh` (needs Google Chrome).

## License

MIT
